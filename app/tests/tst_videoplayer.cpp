#include "resumepositions.h"
#include "videoplayer.h"

#include <QFile>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

#include <gst/gst.h>

// The player with real GStreamer, on videos the test makes: in CI with software decoders, on the board with the
// hardware decoder. The sound goes to a fakesink (RK3568_TV_AUDIO_SINK, set by CMake).
class TestVideoPlayer : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void plays();
    void tracks();
    void subtitles();
    void seeks();
    void pausesAndPlays();
    void ends();
    void failsOnAMissingFile();
    void findsASubtitleFileNextToTheVideo();
    void goesOnWhereItWasLeft();

private:
    bool make(const QString &description);
    static void waitUntilPlaying(VideoPlayer &player);

    QTemporaryDir m_dir;
    QString m_film; // 60 s of VP8 at 320x240, sound in English and in French, subtitles
    QString m_clip; // 3 s, no subtitles of its own but clip.srt next to it
};

bool TestVideoPlayer::make(const QString &description)
{
    GError *error = nullptr;
    GstElement *pipeline = gst_parse_launch(description.toUtf8().constData(), &error);
    if (!pipeline) {
        qWarning("%s", error ? error->message : "no pipeline");
        g_clear_error(&error);
        return false;
    }
    gst_element_set_state(pipeline, GST_STATE_PLAYING);
    GstBus *bus = gst_element_get_bus(pipeline);
    GstMessage *message
        = gst_bus_timed_pop_filtered(bus, 120 * GST_SECOND, GstMessageType(GST_MESSAGE_EOS | GST_MESSAGE_ERROR));
    const bool ok = message && GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS;
    if (message)
        gst_message_unref(message);
    gst_object_unref(bus);
    gst_element_set_state(pipeline, GST_STATE_NULL);
    gst_object_unref(pipeline);
    return ok;
}

void TestVideoPlayer::waitUntilPlaying(VideoPlayer &player)
{
    QTRY_COMPARE_WITH_TIMEOUT(player.status(), VideoPlayer::Playing, 15000);
}

void TestVideoPlayer::initTestCase()
{
    QStandardPaths::setTestModeEnabled(true);
    gst_init(nullptr, nullptr);
    QVERIFY(m_dir.isValid());
    m_film = m_dir.filePath("film.mkv");
    m_clip = m_dir.filePath("clip.mkv");

    const QString subtitles = m_dir.filePath("film-subtitles.srt");
    QFile srt(subtitles);
    QVERIFY(srt.open(QIODevice::WriteOnly));
    // GStreamer recognises a subtitle file by its first 129 bytes, so it must be longer than that
    srt.write("1\n00:00:01,000 --> 00:00:03,000\nHello\n\n"
              "2\n00:00:05,000 --> 00:00:06,000\nBye\n\n"
              "3\n00:00:40,000 --> 00:00:42,000\nStill here\n\n"
              "4\n00:00:50,000 --> 00:00:52,000\nThe end\n");
    srt.close();
    // the clip's own, within its 3 s: playing ends when the last stream does, subtitles too
    QFile clipSrt(m_dir.filePath("clip.srt"));
    QVERIFY(clipSrt.open(QIODevice::WriteOnly));
    clipSrt.write("1\n00:00:00,200 --> 00:00:00,900\nThe first line of the clip\n\n"
                  "2\n00:00:01,000 --> 00:00:01,900\nThe second line of the clip\n\n"
                  "3\n00:00:02,000 --> 00:00:02,800\nThe third line of the clip\n");
    clipSrt.close();

    const QString sound = QStringLiteral("audiotestsrc num-buffers=600 samplesperbuffer=2205 freq=%1 ! "
                                         "audio/x-raw,rate=22050 ! audioconvert ! vorbisenc ! "
                                         "taginject tags=\"language-code=%2\" ! queue ! mux. ");
    QVERIFY2(make(QStringLiteral("videotestsrc num-buffers=900 ! video/x-raw,width=320,height=240,framerate=15/1 ! "
                                 "vp8enc deadline=1 keyframe-max-dist=15 ! queue ! mux. ")
                  + sound.arg(440).arg("eng") + sound.arg(880).arg("fra")
                  + QStringLiteral("filesrc location=\"%1\" ! subparse ! queue ! mux. "
                                   "matroskamux name=mux ! filesink location=\"%2\"")
                        .arg(subtitles, m_film)),
             "making the test film");
    QVERIFY2(make(QStringLiteral("videotestsrc num-buffers=45 ! video/x-raw,width=320,height=240,framerate=15/1 ! "
                                 "vp8enc deadline=1 keyframe-max-dist=15 ! matroskamux ! filesink location=\"%1\"")
                      .arg(m_clip)),
             "making the test clip");
    ResumePositions::forget(m_film);
    ResumePositions::forget(m_clip);
}

void TestVideoPlayer::plays()
{
    VideoPlayer player;
    player.setResume(false);
    QCOMPARE(player.status(), VideoPlayer::NoMedia);
    player.setSource(m_film);
    QCOMPARE(player.status(), VideoPlayer::Loading);
    waitUntilPlaying(player);
    QVERIFY2(qAbs(player.duration() - 60'000) < 500, qPrintable(QString::number(player.duration())));
    QTRY_VERIFY_WITH_TIMEOUT(player.framesReceived() > 5, 5000);
    QTRY_VERIFY_WITH_TIMEOUT(player.position() > 200, 5000);
    qInfo("frames: %d, of them DMA-BUFs (hardware decoder): %d", player.framesReceived(),
          player.dmabufFramesReceived());
}

void TestVideoPlayer::tracks()
{
    VideoPlayer player;
    player.setResume(false);
    player.setSource(m_film);
    waitUntilPlaying(player);
    QTRY_COMPARE(player.audioTracks().size(), 2);
    QVERIFY2(player.audioTracks().at(0).contains("English") || player.audioTracks().at(0).contains("eng"),
             qPrintable(player.audioTracks().join(", ")));
    QVERIFY2(player.audioTracks().at(1).contains("French") || player.audioTracks().at(1).contains("fra"),
             qPrintable(player.audioTracks().join(", ")));
    QCOMPARE(player.audioTrack(), 0);
    player.setAudioTrack(1);
    QCOMPARE(player.audioTrack(), 1);
    player.setAudioTrack(5);
    QCOMPARE(player.audioTrack(), 1);
    QCOMPARE(player.subtitleTracks().size(), 1);
    QCOMPARE(player.subtitleTrack(), -1); // off until chosen
}

void TestVideoPlayer::subtitles()
{
    VideoPlayer player;
    player.setResume(false);
    player.setSource(m_film);
    QTRY_COMPARE_WITH_TIMEOUT(player.subtitleTracks().size(), 1, 15000);
    player.setSubtitleTrack(0);
    QCOMPARE(player.subtitleTrack(), 0);
    QTRY_COMPARE_WITH_TIMEOUT(player.subtitleText(), QStringLiteral("Hello"), 5000);
    QTRY_COMPARE_WITH_TIMEOUT(player.subtitleText(), QString(), 5000); // its time is up
    player.setSubtitleTrack(-1);
    QCOMPARE(player.subtitleTrack(), -1);
}

void TestVideoPlayer::seeks()
{
    VideoPlayer player;
    player.setResume(false);
    player.setSource(m_film);
    waitUntilPlaying(player);
    player.seek(30'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.position() >= 29'000 && player.status() == VideoPlayer::Playing, 5000);
    player.seekBy(-10'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.position() >= 19'000 && player.position() < 25'000, 5000);
    player.seek(-5'000);
    QTRY_VERIFY_WITH_TIMEOUT(player.position() < 2'000, 5000);
}

void TestVideoPlayer::pausesAndPlays()
{
    VideoPlayer player;
    player.setResume(false);
    player.setSource(m_film);
    waitUntilPlaying(player);
    player.togglePause();
    QTRY_COMPARE_WITH_TIMEOUT(player.status(), VideoPlayer::Paused, 5000);
    const qint64 at = player.position();
    QTest::qWait(500);
    QVERIFY(qAbs(player.position() - at) < 100);
    player.togglePause();
    waitUntilPlaying(player);
    QTRY_VERIFY_WITH_TIMEOUT(player.position() > at + 200, 5000);
}

void TestVideoPlayer::ends()
{
    VideoPlayer player;
    player.setSource(m_clip);
    QTRY_COMPARE_WITH_TIMEOUT(player.status(), VideoPlayer::Ended, 15000);
    QCOMPARE(player.position(), player.duration());
}

void TestVideoPlayer::failsOnAMissingFile()
{
    VideoPlayer player;
    player.setSource(m_dir.filePath("missing.mkv"));
    QTRY_COMPARE_WITH_TIMEOUT(player.status(), VideoPlayer::Failed, 15000);
    QVERIFY(!player.errorString().isEmpty());
}

void TestVideoPlayer::findsASubtitleFileNextToTheVideo()
{
    VideoPlayer player;
    player.setResume(false);
    player.setSource(m_clip);
    QTRY_COMPARE_WITH_TIMEOUT(player.subtitleTracks().size(), 1, 15000);
}

void TestVideoPlayer::goesOnWhereItWasLeft()
{
    {
        VideoPlayer player;
        player.setSource(m_film);
        waitUntilPlaying(player);
        player.seek(20'000);
        QTRY_VERIFY_WITH_TIMEOUT(player.position() >= 20'000 && player.status() == VideoPlayer::Playing, 5000);
        player.stop(); // remembers
    }
    QVERIFY(ResumePositions::position(m_film) >= 20'000);
    {
        VideoPlayer player;
        player.setSource(m_film);
        waitUntilPlaying(player);
        QVERIFY2(player.position() >= 19'000, qPrintable(QString::number(player.position())));
    }
    {
        VideoPlayer player;
        player.setResume(false);
        player.setSource(m_film);
        waitUntilPlaying(player);
        QVERIFY(player.position() < 5'000);
    }
    ResumePositions::forget(m_film);
}

QTEST_MAIN(TestVideoPlayer)
#include "tst_videoplayer.moc"
