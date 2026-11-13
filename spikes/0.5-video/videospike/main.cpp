// Step 0.5 video spike: throwaway measurement app for the three ways of showing hardware-decoded video in a
// Qt Quick UI (docs/01-plan.md, §4.3). Run it on EGLFS (no desktop).
//
//   videospike a CLIP FRAMES   Qt Multimedia: MediaPlayer + VideoOutput
//   videospike b CLIP FRAMES   own pipeline: mppvideodec -> appsink -> DMA-BUF -> EGLImage, drawn under the QML scene
//   videospike c CLIP FRAMES   own pipeline: mppvideodec -> kmssink on its own display plane, below the Qt UI's plane
//
// FRAMES is the clip's frame count (ffprobe). At the end of the clip it prints one tab-separated line:
//   candidate clip frames shown dropped video_fps ui_fps proc_cpu% sys_cpu% soc_C
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSurfaceFormat>
#include <QTimer>
#include <QUrl>
#include <QVideoFrame>
#include <QVideoSink>
#include <qpa/qplatformnativeinterface.h>

#include <gst/allocators/gstdmabuf.h>
#include <gst/app/gstappsink.h>
#include <gst/gst.h>
#include <gst/video/video.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#include <sys/resource.h>
#include <sys/stat.h>

#include <set>

#include <atomic>
#include <cstdio>
#include <map>
#include <mutex>
#include <string_view>
#include <tuple>

namespace {

struct CpuTimes {
    double total = 0;
    double idle = 0;
};

CpuTimes readCpu()
{
    QFile f("/proc/stat");
    f.open(QIODevice::ReadOnly);
    const auto fields = f.readLine().simplified().split(' ');
    CpuTimes c;
    for (int i = 1; i < fields.size() && i <= 8; ++i)
        c.total += fields[i].toDouble();
    c.idle = fields[4].toDouble() + fields[5].toDouble();
    return c;
}

double processCpuSeconds()
{
    rusage r{};
    getrusage(RUSAGE_SELF, &r);
    return r.ru_utime.tv_sec + r.ru_utime.tv_usec / 1e6 + r.ru_stime.tv_sec + r.ru_stime.tv_usec / 1e6;
}

int socTemperature()
{
    QFile f("/sys/class/thermal/thermal_zone0/temp");
    f.open(QIODevice::ReadOnly);
    return f.readAll().trimmed().toInt() / 1000;
}

QString demuxAndParse(const QString &clip)
{
    if (clip.endsWith(".webm"))
        return "matroskademux name=d d.video_0 ! queue ! vp9parse";
    if (clip.contains("h265"))
        return "qtdemux name=d d.video_0 ! queue ! h265parse";
    return "qtdemux name=d d.video_0 ! queue ! h264parse";
}

} // namespace

// Counts shown video frames and UI frames, and prints the result line once.
class Stats : public QObject
{
    Q_OBJECT
public:
    Stats(QString candidate, QString clip, int frames)
        : m_candidate(std::move(candidate)), m_clip(std::move(clip)), m_frames(frames)
    {
    }

    std::atomic<int> shown{0};
    std::atomic<int> uiFrames{0};
    std::atomic<int> lateAtSink{0};   // frames that reached the sink but were dropped there (candidate C)

    Q_INVOKABLE void start()
    {
        if (m_timer.isValid())
            return;
        m_cpu0 = readCpu();
        m_proc0 = processCpuSeconds();
        uiFrames = 0;
        m_timer.start();
    }

    Q_INVOKABLE void watchSink(QObject *sink)
    {
        auto *videoSink = qobject_cast<QVideoSink *>(sink);
        if (!videoSink) {
            std::fprintf(stderr, "no QVideoSink\n");
            return;
        }
        connect(videoSink, &QVideoSink::videoFrameChanged, this, [this](const QVideoFrame &f) {
            if (f.isValid())
                ++shown;
        });
    }

    Q_INVOKABLE void finish()
    {
        if (m_done)
            return;
        m_done = true;
        if (!m_timer.isValid()) {   // the run never started: say so and end anyway
            std::printf("%s\t%s\t%d\tNOT STARTED\n", qPrintable(m_candidate), qPrintable(QFileInfo(m_clip).fileName()),
                        m_frames);
            std::fflush(stdout);
            QTimer::singleShot(0, qApp, &QCoreApplication::quit);
            return;
        }
        const double wall = m_timer.nsecsElapsed() / 1e9;
        const CpuTimes c = readCpu();
        const double total = c.total - m_cpu0.total;
        const double busy = total - (c.idle - m_cpu0.idle);
        const int s = shown - lateAtSink;
        std::printf("%s\t%s\t%d\t%d\t%d\t%.1f\t%.1f\t%.0f\t%.0f\t%d\n", qPrintable(m_candidate),
                    qPrintable(QFileInfo(m_clip).fileName()), m_frames, s, m_frames - s, s / wall,
                    uiFrames / wall, 100 * (processCpuSeconds() - m_proc0) / wall,
                    total > 0 ? 100 * busy / total : 0, socTemperature());
        std::fflush(stdout);
        QTimer::singleShot(0, qApp, &QCoreApplication::quit);
    }

private:
    QString m_candidate;
    QString m_clip;
    int m_frames;
    QElapsedTimer m_timer;
    CpuTimes m_cpu0;
    double m_proc0 = 0;
    bool m_done = false;
};

// Ends the run on the pipeline's EOS or error (called on GStreamer's threads).
static GstBusSyncReply onBusMessage(GstBus *, GstMessage *msg, gpointer data)
{
    auto *stats = static_cast<Stats *>(data);
    switch (GST_MESSAGE_TYPE(msg)) {
    case GST_MESSAGE_EOS:
        QMetaObject::invokeMethod(stats, "finish", Qt::QueuedConnection);
        break;
    case GST_MESSAGE_ERROR: {
        GError *err = nullptr;
        gst_message_parse_error(msg, &err, nullptr);
        std::fprintf(stderr, "pipeline error: %s\n", err->message);
        g_error_free(err);
        QMetaObject::invokeMethod(stats, "finish", Qt::QueuedConnection);
        break;
    }
    case GST_MESSAGE_QOS:
        if (g_strcmp0(GST_OBJECT_NAME(GST_MESSAGE_SRC(msg)), "out") == 0) {
            guint64 processed = 0, dropped = 0;
            gst_message_parse_qos_stats(msg, nullptr, &processed, &dropped);
            stats->lateAtSink = int(dropped);
        }
        break;
    default:
        break;
    }
    return GST_BUS_PASS;
}

static GstElement *startPipeline(const QString &description, Stats *stats)
{
    GError *err = nullptr;
    GstElement *pipe = gst_parse_launch(description.toUtf8().constData(), &err);
    if (!pipe) {
        std::fprintf(stderr, "pipeline: %s\n", err ? err->message : "?");
        std::exit(1);
    }
    GstBus *bus = gst_element_get_bus(pipe);
    gst_bus_set_sync_handler(bus, onBusMessage, stats, nullptr);
    gst_object_unref(bus);
    gst_element_set_state(pipe, GST_STATE_PLAYING);
    stats->start();
    return pipe;
}

// Candidate B: the decoder's DMA-BUF frames are imported as EGLImages and drawn as an underlay, before the
// QML scene, in Qt's own render pass. No copies: the GPU samples the decoder's NV12 buffers directly.
class Underlay : public QObject
{
    Q_OBJECT
public:
    Underlay(QQuickWindow *window, Stats *stats, const QString &clip) : m_window(window), m_stats(stats)
    {
        connect(window, &QQuickWindow::beforeRenderPassRecording, this, &Underlay::render, Qt::DirectConnection);
        m_pipe = startPipeline(QString("filesrc location=\"%1\" ! %2 ! mppvideodec ! video/x-raw,format=NV12 ! queue max-size-buffers=4 ! "
                                       "appsink name=sink sync=true qos=true max-buffers=2 drop=true")
                                   .arg(clip, demuxAndParse(clip)),
                               stats);
        GstElement *sink = gst_bin_get_by_name(GST_BIN(m_pipe), "sink");
        GstAppSinkCallbacks callbacks{};
        callbacks.new_sample = &Underlay::onSample;
        gst_app_sink_set_callbacks(GST_APP_SINK(sink), &callbacks, this, nullptr);
        gst_object_unref(sink);
    }

private:
    static GstFlowReturn onSample(GstAppSink *sink, gpointer data)
    {
        auto *self = static_cast<Underlay *>(data);
        GstSample *sample = gst_app_sink_pull_sample(sink);
        {
            std::lock_guard lock(self->m_mutex);
            if (self->m_pending)
                gst_sample_unref(self->m_pending);   // replaced before it was drawn: that frame is not shown
            self->m_pending = sample;
        }
        QMetaObject::invokeMethod(self->m_window, "update", Qt::QueuedConnection);
        return GST_FLOW_OK;
    }

    // Runs on the render thread, with Qt's GL context current, inside the render pass.
    void render()
    {
        GstSample *sample = nullptr;
        {
            std::lock_guard lock(m_mutex);
            std::swap(sample, m_pending);
        }
        m_window->beginExternalCommands();
        // GL through Qt's resolved functions: Ubuntu's Qt is built for desktop GL, so the plain gl* symbols
        // would go to libOpenGL's dispatcher, which knows nothing of the Mali GLES context.
        auto *f = QOpenGLContext::currentContext()->extraFunctions();
        if (!m_program)
            initGl();
        if (sample) {
            if (bind(sample)) {
                if (m_current)
                    gst_sample_unref(m_current);   // the decoder may reuse that buffer now
                m_current = sample;
                ++m_stats->shown;
            } else {
                gst_sample_unref(sample);
            }
        }
        if (m_current) {
            const QSize size = m_window->size() * m_window->effectiveDevicePixelRatio();
            f->glViewport(0, 0, size.width(), size.height());
            f->glDisable(GL_BLEND);
            f->glDisable(GL_DEPTH_TEST);
            f->glDisable(GL_SCISSOR_TEST);
            f->glDisable(GL_CULL_FACE);
            f->glBindVertexArray(0);
            f->glUseProgram(m_program);
            f->glActiveTexture(GL_TEXTURE0);
            f->glBindTexture(GL_TEXTURE_EXTERNAL_OES, m_texture);
            f->glUniform1i(m_samplerLocation, 0);
            f->glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
            f->glEnableVertexAttribArray(0);
            f->glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
            f->glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            f->glDisableVertexAttribArray(0);
            f->glBindBuffer(GL_ARRAY_BUFFER, 0);
            f->glBindTexture(GL_TEXTURE_EXTERNAL_OES, 0);
            f->glUseProgram(0);
        }
        m_window->endExternalCommands();
    }

    void initGl()
    {
        auto *f = QOpenGLContext::currentContext()->extraFunctions();
        m_display = eglGetCurrentDisplay();
        m_createImage = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(eglGetProcAddress("eglCreateImageKHR"));
        m_destroyImage = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(eglGetProcAddress("eglDestroyImageKHR"));
        m_targetTexture = reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
            eglGetProcAddress("glEGLImageTargetTexture2DOES"));
        const char *vs = "attribute vec2 pos; varying vec2 uv;\n"
                         "void main() { uv = vec2(pos.x + 1.0, 1.0 - pos.y) * 0.5; gl_Position = vec4(pos, 0.0, 1.0); }\n";
        const char *fs = "#extension GL_OES_EGL_image_external : require\n"
                         "precision mediump float; varying vec2 uv; uniform samplerExternalOES tex;\n"
                         "void main() { gl_FragColor = texture2D(tex, uv); }\n";
        auto compile = [f](GLenum type, const char *src) {
            GLuint s = f->glCreateShader(type);
            f->glShaderSource(s, 1, &src, nullptr);
            f->glCompileShader(s);
            GLint ok = 0;
            f->glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
            if (!ok) {
                char log[512];
                f->glGetShaderInfoLog(s, sizeof log, nullptr, log);
                std::fprintf(stderr, "shader: %s\n", log);
            }
            return s;
        };
        m_program = f->glCreateProgram();
        f->glAttachShader(m_program, compile(GL_VERTEX_SHADER, vs));
        f->glAttachShader(m_program, compile(GL_FRAGMENT_SHADER, fs));
        f->glBindAttribLocation(m_program, 0, "pos");
        f->glLinkProgram(m_program);
        m_samplerLocation = f->glGetUniformLocation(m_program, "tex");
        const GLfloat quad[] = {-1, -1, 1, -1, -1, 1, 1, 1};
        f->glGenBuffers(1, &m_vbo);
        f->glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
        f->glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
        f->glBindBuffer(GL_ARRAY_BUFFER, 0);
    }

    // Points m_texture at the sample's buffer; EGLImages and textures are cached per buffer, since the
    // decoder cycles through a fixed pool.
    bool bind(GstSample *sample)
    {
        auto *f = QOpenGLContext::currentContext()->extraFunctions();
        GstBuffer *buffer = gst_sample_get_buffer(sample);
        GstMemory *memory = gst_buffer_peek_memory(buffer, 0);
        if (!gst_is_dmabuf_memory(memory)) {
            std::fprintf(stderr, "not a DMA-BUF buffer\n");
            return false;
        }
        const int fd = gst_dmabuf_memory_get_fd(memory);
        GstVideoInfo info;
        gst_video_info_from_caps(&info, gst_sample_get_caps(sample));
        int width = GST_VIDEO_INFO_WIDTH(&info), height = GST_VIDEO_INFO_HEIGHT(&info);
        gsize offset[2] = {GST_VIDEO_INFO_PLANE_OFFSET(&info, 0), GST_VIDEO_INFO_PLANE_OFFSET(&info, 1)};
        gint stride[2] = {GST_VIDEO_INFO_PLANE_STRIDE(&info, 0), GST_VIDEO_INFO_PLANE_STRIDE(&info, 1)};
        if (GstVideoMeta *meta = gst_buffer_get_video_meta(buffer)) {
            for (int i = 0; i < 2; ++i) {
                offset[i] = meta->offset[i];
                stride[i] = meta->stride[i];
            }
        }
        // Identify the buffer by its dma-buf inode, not by the fd number: GStreamer may hand out a new fd per
        // frame, and a closed fd's number gets reused for another buffer (that showed old frames).
        struct stat st {};
        fstat(fd, &st);
        m_fdNumbers.insert(fd);
        m_inodes.insert(st.st_ino);
        const auto key = std::make_tuple(st.st_ino, offset[1], stride[0]);
        auto it = m_textures.find(key);
        if (it == m_textures.end()) {
            if (m_textures.size() >= 64) {   // the decoder's pool changed: start over
                for (auto &[k, t] : m_textures) {
                    f->glDeleteTextures(1, &t.first);
                    m_destroyImage(m_display, t.second);
                }
                m_textures.clear();
            }
            const EGLint attrs[] = {EGL_WIDTH, width, EGL_HEIGHT, height, EGL_LINUX_DRM_FOURCC_EXT, DRM_FORMAT_NV12,
                                    EGL_DMA_BUF_PLANE0_FD_EXT, fd, EGL_DMA_BUF_PLANE0_OFFSET_EXT, EGLint(offset[0]),
                                    EGL_DMA_BUF_PLANE0_PITCH_EXT, stride[0], EGL_DMA_BUF_PLANE1_FD_EXT, fd,
                                    EGL_DMA_BUF_PLANE1_OFFSET_EXT, EGLint(offset[1]), EGL_DMA_BUF_PLANE1_PITCH_EXT,
                                    stride[1], EGL_NONE};
            EGLImageKHR image = m_createImage(m_display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attrs);
            if (image == EGL_NO_IMAGE_KHR) {
                std::fprintf(stderr, "eglCreateImageKHR failed: 0x%x\n", eglGetError());
                return false;
            }
            GLuint texture = 0;
            f->glGenTextures(1, &texture);
            f->glBindTexture(GL_TEXTURE_EXTERNAL_OES, texture);
            f->glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            f->glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            m_targetTexture(GL_TEXTURE_EXTERNAL_OES, image);
            f->glBindTexture(GL_TEXTURE_EXTERNAL_OES, 0);
            it = m_textures.emplace(key, std::make_pair(texture, image)).first;
        }
        m_texture = it->second.first;
        return true;
    }

public:
    ~Underlay() override
    {
        std::fprintf(stderr, "B: %zu distinct dma-bufs, %zu distinct fd numbers\n", m_inodes.size(), m_fdNumbers.size());
    }

private:
    std::set<int> m_fdNumbers;
    std::set<ino_t> m_inodes;
    PFNEGLDESTROYIMAGEKHRPROC m_destroyImage = nullptr;

    QQuickWindow *m_window;
    Stats *m_stats;
    GstElement *m_pipe = nullptr;
    std::mutex m_mutex;
    GstSample *m_pending = nullptr;
    GstSample *m_current = nullptr;
    EGLDisplay m_display = EGL_NO_DISPLAY;
    PFNEGLCREATEIMAGEKHRPROC m_createImage = nullptr;
    PFNGLEGLIMAGETARGETTEXTURE2DOESPROC m_targetTexture = nullptr;
    GLuint m_program = 0, m_vbo = 0, m_texture = 0;
    GLint m_samplerLocation = -1;
    std::map<std::tuple<ino_t, gsize, gint>, std::pair<GLuint, EGLImageKHR>> m_textures;
};

// Candidate C: kmssink shows the video on its own plane (Esmart0), using Qt's DRM device; the Qt UI's plane
// (the primary) is raised above it and is transparent where the video should show.
static void startPlaneVideo(Stats *stats, const QString &clip)
{
    auto *native = QGuiApplication::platformNativeInterface();
    const int fd = int(reinterpret_cast<intptr_t>(native->nativeResourceForIntegration("dri_fd")));
    if (fd <= 0) {
        std::fprintf(stderr, "no DRM fd from Qt (not on eglfs_kms?)\n");
        std::exit(1);
    }
    const uint32_t videoPlane = qEnvironmentVariableIntValue("SPIKE_VIDEO_PLANE") ?: 121;   // Esmart0-win0
    const uint32_t uiPlane = qEnvironmentVariableIntValue("SPIKE_UI_PLANE") ?: 57;          // Smart0-win0, primary
    // raise the UI's plane above the video's
    drmModeObjectProperties *props = drmModeObjectGetProperties(fd, uiPlane, DRM_MODE_OBJECT_PLANE);
    for (uint32_t i = 0; props && i < props->count_props; ++i) {
        drmModePropertyRes *p = drmModeGetProperty(fd, props->props[i]);
        if (p && std::string_view(p->name) == "zpos" &&
            drmModeObjectSetProperty(fd, uiPlane, DRM_MODE_OBJECT_PLANE, p->prop_id, 6) != 0)
            std::fprintf(stderr, "could not raise the UI plane\n");
        drmModeFreeProperty(p);
    }
    drmModeFreeObjectProperties(props);

    auto *pipe = startPipeline(QString("filesrc location=\"%1\" ! %2 ! mppvideodec ! identity name=count signal-handoffs=true ! queue max-size-buffers=4 ! "
                                       "kmssink name=out fd=%3 plane-id=%4 can-scale=true skip-vsync=true "
                                       "plane-properties=\"s,zpos=(int)1\"")
                                   .arg(clip, demuxAndParse(clip))
                                   .arg(fd)
                                   .arg(videoPlane),
                               stats);
    GstElement *count = gst_bin_get_by_name(GST_BIN(pipe), "count");
    g_signal_connect(count, "handoff",
                     G_CALLBACK(+[](GstElement *, GstBuffer *, gpointer s) { ++static_cast<Stats *>(s)->shown; }), stats);
    gst_object_unref(count);
}

int main(int argc, char *argv[])
{
    gst_init(&argc, &argv);
    if (argc < 4 || !QString("abc").contains(argv[1]) || QString(argv[1]).size() != 1) {
        std::fprintf(stderr, "usage: videospike a|b|c CLIP FRAMES\n");
        return 2;
    }
    const QString candidate = argv[1];
    const QString clip = QFileInfo(argv[2]).absoluteFilePath();

    if (candidate == "c") {   // C needs a transparent UI plane
        QSurfaceFormat format = QSurfaceFormat::defaultFormat();
        format.setAlphaBufferSize(8);
        QSurfaceFormat::setDefaultFormat(format);
    }
    QGuiApplication app(argc, argv);

    Stats stats(candidate, clip, QString(argv[3]).toInt());
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("candidate", candidate);
    engine.rootContext()->setContextProperty("clipUrl", QUrl::fromLocalFile(clip));
    engine.rootContext()->setContextProperty("clipName", QFileInfo(clip).fileName());
    engine.rootContext()->setContextProperty("stats", &stats);
    engine.load(QUrl("qrc:/main.qml"));
    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().value(0));
    if (!window)
        return 1;
    QObject::connect(window, &QQuickWindow::frameSwapped, &stats, [&stats] { ++stats.uiFrames; }, Qt::DirectConnection);

    Underlay *underlay = nullptr;
    if (candidate == "b")
        underlay = new Underlay(window, &stats, clip);
    else if (candidate == "c")
        QTimer::singleShot(500, [&stats, clip] { startPlaneVideo(&stats, clip); });   // after Qt has set the mode
    // a safety net: never run longer than the clip plus 30 s
    QTimer::singleShot((QString(argv[3]).toInt() / 24 + 30) * 1000, &stats, &Stats::finish);
    const int rc = app.exec();
    delete underlay;
    return rc;
}

#include "main.moc"
