#pragma once

#include <QQuickItem>
#include <QStringList>
#include <QTimer>
#include <QtQml/qqml.h> // in Qt 6.2, qqmlregistration.h alone lacks what QML_ELEMENT needs

#include <atomic>
#include <mutex>

typedef struct _GstElement GstElement;
typedef struct _GstSample GstSample;
typedef struct _GstMessage GstMessage;
class VideoRenderer;

// Plays a video file (step 1.4). GStreamer's playbin demuxes it and picks the decoders: on the board the hardware
// decoder mppvideodec, whose frames this item draws itself, without copies, under the QML scene and fitted into its
// own rectangle (docs/03-video-spike.md, candidate B). The sound goes to HDMI; subtitles, in the file or in a .srt
// file next to it, come out as text for QML to show. Setting `source` starts playing, from where the file was left
// the last time when `resume` is on.
class VideoPlayer : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(Status status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY statusChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(QStringList audioTracks READ audioTracks NOTIFY tracksChanged)
    Q_PROPERTY(int audioTrack READ audioTrack WRITE setAudioTrack NOTIFY tracksChanged)
    Q_PROPERTY(QStringList subtitleTracks READ subtitleTracks NOTIFY tracksChanged)
    Q_PROPERTY(int subtitleTrack READ subtitleTrack WRITE setSubtitleTrack NOTIFY tracksChanged)
    Q_PROPERTY(QString subtitleText READ subtitleText NOTIFY subtitleTextChanged)
    Q_PROPERTY(bool resume READ resume WRITE setResume NOTIFY resumeChanged)

public:
    enum Status { NoMedia, Loading, Playing, Paused, Ended, Failed };
    Q_ENUM(Status)

    explicit VideoPlayer(QQuickItem *parent = nullptr);
    ~VideoPlayer() override;

    QString source() const { return m_source; }
    void setSource(const QString &source);
    Status status() const { return m_status; }
    QString errorString() const { return m_error; }
    qint64 position() const { return m_position; }
    qint64 duration() const { return m_duration; }
    QStringList audioTracks() const { return m_audioTracks; }
    int audioTrack() const { return m_audioTrack; }
    void setAudioTrack(int index);
    QStringList subtitleTracks() const { return m_subtitleTracks; }
    // -1: no subtitles
    int subtitleTrack() const { return m_subtitleTrack; }
    void setSubtitleTrack(int index);
    QString subtitleText() const { return m_subtitleText; }
    bool resume() const { return m_resume; }
    void setResume(bool resume);

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void togglePause();
    // Stops, and remembers where (resume)
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(qint64 ms);
    Q_INVOKABLE void seekBy(qint64 ms);

    // Video frames that reached the item, and how many of them were DMA-BUFs (all, with the hardware decoder)
    int framesReceived() const { return m_framesReceived; }
    int dmabufFramesReceived() const { return m_dmabufFrames; }

    // The sound's GStreamer sink: RK3568_TV_AUDIO_SINK if set, otherwise the board's HDMI output
    static QString audioSinkDescription();

signals:
    void sourceChanged();
    void statusChanged();
    void positionChanged();
    void durationChanged();
    void tracksChanged();
    void subtitleTextChanged();
    void resumeChanged();

protected:
    void itemChange(ItemChange change, const ItemChangeData &value) override;
    void releaseResources() override;

private:
    void open();
    void close();
    void handleMessage(GstMessage *message);
    void loaded();
    void updatePosition();
    void updateTracks();
    void setStatus(Status status, const QString &error = {});
    void setSubtitle(const QString &text, qint64 durationMs);
    void rememberPosition();
    void sync(); // render thread, GUI thread blocked
    void cleanup(); // render thread
    void newFrame(GstSample *sample); // GStreamer's thread

    QString m_source;
    Status m_status = NoMedia;
    QString m_error;
    qint64 m_position = 0;
    qint64 m_duration = 0;
    qint64 m_pendingSeek = 0;
    bool m_loaded = false;
    bool m_wantPlaying = true;
    bool m_resume = true;
    int m_generation = 0; // which pipeline's messages count
    QStringList m_audioTracks;
    int m_audioTrack = -1;
    QStringList m_subtitleTracks;
    int m_subtitleTrack = -1;
    QString m_subtitleText;
    GstElement *m_pipeline = nullptr;
    QTimer m_positionTimer;
    QTimer m_subtitleTimer;

    std::mutex m_frameMutex;
    GstSample *m_pendingFrame = nullptr; // guarded by m_frameMutex
    bool m_resetFrames = false; // guarded by m_frameMutex
    std::atomic<int> m_framesReceived = 0;
    std::atomic<int> m_dmabufFrames = 0;
    VideoRenderer *m_renderer = nullptr; // render thread
};
