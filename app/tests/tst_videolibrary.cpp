#include "videolibrary.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>
#include <QVariantMap>

class TestVideoLibrary : public QObject
{
    Q_OBJECT

private slots:
    void isVideo_data();
    void isVideo();
    void folderFromTheEnvironment();
    void findsVideosInNaturalOrder();
    void aMissingFolderHasNone();

private:
    static void touch(const QString &path)
    {
        QDir().mkpath(QFileInfo(path).path());
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
    }
};

void TestVideoLibrary::isVideo_data()
{
    QTest::addColumn<QString>("name");
    QTest::addColumn<bool>("video");
    QTest::newRow("mkv") << "a.mkv" << true;
    QTest::newRow("mp4") << "a.mp4" << true;
    QTest::newRow("upper case") << "A.MKV" << true;
    QTest::newRow("ts") << "a.ts" << true;
    QTest::newRow("webm") << "a.webm" << true;
    QTest::newRow("subtitles") << "a.srt" << false;
    QTest::newRow("picture") << "a.jpg" << false;
    QTest::newRow("no suffix") << "mkv" << false;
}

void TestVideoLibrary::isVideo()
{
    QFETCH(QString, name);
    QFETCH(bool, video);
    QCOMPARE(VideoLibrary::isVideo(name), video);
}

void TestVideoLibrary::folderFromTheEnvironment()
{
    qputenv("RK3568_TV_MEDIA", "/srv/films");
    QCOMPARE(VideoLibrary().folder(), QStringLiteral("/srv/films"));
    qunsetenv("RK3568_TV_MEDIA");
    QCOMPARE(VideoLibrary().folder(), QStringLiteral("/userdata/media"));
}

void TestVideoLibrary::findsVideosInNaturalOrder()
{
    QTemporaryDir dir;
    touch(dir.filePath("a.mkv"));
    touch(dir.filePath("b/10.mp4"));
    touch(dir.filePath("b/2.mp4"));
    touch(dir.filePath("C.MKV"));
    touch(dir.filePath("notes.txt"));
    touch(dir.filePath("a.srt"));
    qputenv("RK3568_TV_MEDIA", dir.path().toUtf8());
    const QVariantList videos = VideoLibrary().videos();
    qunsetenv("RK3568_TV_MEDIA");

    QStringList names;
    for (const QVariant &video : videos)
        names << video.toMap().value("name").toString();
    QCOMPARE(names, QStringList({"2.mp4", "10.mp4", "a.mkv", "C.MKV"}));
    const QVariantMap first = videos.first().toMap();
    QCOMPARE(first.value("place").toString(), QStringLiteral("b"));
    QCOMPARE(first.value("path").toString(), dir.filePath("b/2.mp4"));
    QCOMPARE(videos.at(2).toMap().value("place").toString(), QString());
}

void TestVideoLibrary::aMissingFolderHasNone()
{
    qputenv("RK3568_TV_MEDIA", "/no/such/folder");
    QVERIFY(VideoLibrary().videos().isEmpty());
    qunsetenv("RK3568_TV_MEDIA");
}

QTEST_GUILESS_MAIN(TestVideoLibrary)
#include "tst_videolibrary.moc"
