#include "videoplayer.h"

#include "resumepositions.h"

#include <QFileInfo>
#include <QLoggingCategory>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QQuickWindow>
#include <QRunnable>
#include <QUrl>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <cstring>
#include <drm_fourcc.h>
#include <gst/allocators/gstdmabuf.h>
#include <gst/app/gstappsink.h>
#include <gst/gst.h>
#include <gst/tag/tag.h>
#include <gst/video/video.h>
#include <map>
#include <memory>
#include <sys/stat.h>
#include <tuple>
#include <vector>

Q_LOGGING_CATEGORY(lcPlayer, "rk3568tv.player")

// From GL ES's extensions (GLES2/gl2ext.h, which doesn't go together with Qt's desktop GL headers)
#define GL_TEXTURE_EXTERNAL_OES 0x8D65
using ImageTargetTexture2D = void (*)(GLenum target, void *image);
// DRM_FORMAT_NV15 (10-bit NV12, packed), which older drm_fourcc.h files lack
constexpr uint32_t DrmFormatNv15 = fourcc_code('N', 'V', '1', '5');

namespace {

// playbin's flags (GstPlayFlags, which no public header has). No deinterlacing or colour balance: they would add
// elements on the way from the decoder; video conversion stays possible, and passes the decoder's NV12 through.
enum PlayFlags { FlagVideo = 0x1, FlagAudio = 0x2, FlagText = 0x4, FlagSoftVolume = 0x10 };

// A track's name: its language; its title only without a language, since a stream's tags carry the file's title too
QString trackName(GstTagList *tags, int index)
{
    QString name;
    if (tags) {
        gchar *code = nullptr;
        if (gst_tag_list_get_string(tags, GST_TAG_LANGUAGE_CODE, &code) && g_strcmp0(code, "und") != 0) {
            const gchar *language = gst_tag_get_language_name(code); // "und": undetermined, no language
            name = QString::fromUtf8(language ? language : code);
        }
        g_free(code);
        gchar *title = nullptr;
        if (name.isEmpty() && gst_tag_list_get_string(tags, GST_TAG_TITLE, &title))
            name = QString::fromUtf8(title);
        g_free(title);
        gst_tag_list_unref(tags);
    }
    return name.isEmpty() ? VideoPlayer::tr("Track %1").arg(index + 1) : name;
}

// Tracks with the same name get their number: "English 1", "English 2"
QStringList numberTwins(QStringList names)
{
    const QStringList original = names;
    for (int i = 0; i < names.size(); ++i) {
        if (original.count(original.at(i)) > 1)
            names[i]
                = original.at(i) + QLatin1Char(' ') + QString::number(original.mid(0, i + 1).count(original.at(i)));
    }
    return names;
}

// A subtitle file next to the video: movie.srt (or .ass, .ssa, .sub, .vtt) for movie.mkv
QString subtitleFileFor(const QString &video)
{
    const QFileInfo info(video);
    for (const char *suffix : {"srt", "ass", "ssa", "vtt", "sub"}) {
        const QString candidate
            = info.path() + QLatin1Char('/') + info.completeBaseName() + QLatin1Char('.') + QLatin1String(suffix);
        if (QFileInfo::exists(candidate))
            return candidate;
    }
    return {};
}

} // namespace

// Draws the newest video frame on the render thread, with Qt's GL context current, inside Qt's render pass and
// before the QML scene: the decoder's DMA-BUF becomes an EGLImage that the GPU samples, with no copy. EGLImages and
// textures are kept per buffer, since the decoder cycles through a fixed pool.
//
// A frame goes back to the decoder only when the GPU is done with it: the GPU runs frames behind the commands, and
// a buffer the decoder writes again while the GPU still reads it shows half of the next frame (seen at 4K60). So
// every draw ends with a fence, and a frame that left the screen is kept until its last draw's fence has signalled.
class VideoRenderer : public QObject
{
public:
    explicit VideoRenderer(QQuickWindow *window) : m_window(window) { }

    ~VideoRenderer() override
    {
        reset();
        if (m_program && QOpenGLContext::currentContext()) {
            auto *f = QOpenGLContext::currentContext()->extraFunctions();
            f->glDeleteProgram(m_program);
            f->glDeleteBuffers(1, &m_vbo);
        }
    }

    // The newest frame (the renderer takes it over); one not drawn yet is dropped
    void setFrame(GstSample *sample)
    {
        if (m_next)
            gst_sample_unref(m_next);
        m_next = sample;
    }

    // A new file, or the end: every frame goes back, once the GPU is done with it
    void reset()
    {
        if (m_next)
            gst_sample_unref(m_next);
        m_next = nullptr;
        retire(m_current, m_currentFence);
        m_current = nullptr;
        m_currentFence = EGL_NO_SYNC_KHR;
        releaseRetired(true);
        releaseTextures();
    }

    // Where to draw, in window pixels from the top left
    void setTarget(const QRect &rect, int windowHeight, bool visible)
    {
        m_target = rect;
        m_windowHeight = windowHeight;
        m_visible = visible;
    }

    void render()
    {
        if (!m_visible || (!m_next && !m_current))
            return;
        m_window->beginExternalCommands();
        // GL through Qt's resolved functions: Ubuntu's Qt is built for desktop GL, so the plain gl* symbols would go
        // to libOpenGL's dispatcher, which knows nothing of the Mali GLES context (docs/03-video-spike.md)
        auto *f = QOpenGLContext::currentContext()->extraFunctions();
        if (!m_program)
            initGl(f);
        releaseRetired(false);
        if (m_next) {
            if (bind(f, m_next)) {
                retire(m_current, m_currentFence);
                m_current = m_next;
                m_currentFence = EGL_NO_SYNC_KHR;
            } else {
                gst_sample_unref(m_next);
            }
            m_next = nullptr;
        }
        if (m_current && m_texture) {
            draw(f);
            if (m_createSync) {
                if (m_currentFence != EGL_NO_SYNC_KHR)
                    m_destroySync(m_display, m_currentFence);
                m_currentFence = m_createSync(m_display, EGL_SYNC_FENCE_KHR, nullptr);
            }
        }
        m_window->endExternalCommands();
    }

private:
    // A frame left the screen: it goes back to the decoder when fence signals (at once if it was never drawn, or the
    // driver has no fences, in which case it waits for three newer frames)
    void retire(GstSample *sample, EGLSyncKHR fence)
    {
        if (!sample)
            return;
        if (fence == EGL_NO_SYNC_KHR && m_createSync) {
            gst_sample_unref(sample);
            return;
        }
        m_retired.push_back({sample, fence});
    }

    // Gives back the retired frames whose fences have signalled; all of them, waiting if need be, when all is true
    void releaseRetired(bool all)
    {
        for (auto it = m_retired.begin(); it != m_retired.end();) {
            bool done;
            if (it->fence == EGL_NO_SYNC_KHR)
                done = all || m_retired.size() > 3;
            else
                done = m_clientWaitSync(m_display, it->fence, 0, all ? 100'000'000 : 0) == EGL_CONDITION_SATISFIED_KHR
                    || all;
            if (!done) {
                ++it;
                continue;
            }
            if (it->fence != EGL_NO_SYNC_KHR)
                m_destroySync(m_display, it->fence);
            gst_sample_unref(it->sample);
            it = m_retired.erase(it);
        }
    }

    void initGl(QOpenGLExtraFunctions *f)
    {
        m_display = eglGetCurrentDisplay();
        m_createImage = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(eglGetProcAddress("eglCreateImageKHR"));
        m_destroyImage = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(eglGetProcAddress("eglDestroyImageKHR"));
        const char *extensions = eglQueryString(m_display, EGL_EXTENSIONS);
        if (extensions && strstr(extensions, "EGL_KHR_fence_sync")) {
            m_createSync = reinterpret_cast<PFNEGLCREATESYNCKHRPROC>(eglGetProcAddress("eglCreateSyncKHR"));
            m_destroySync = reinterpret_cast<PFNEGLDESTROYSYNCKHRPROC>(eglGetProcAddress("eglDestroySyncKHR"));
            m_clientWaitSync = reinterpret_cast<PFNEGLCLIENTWAITSYNCKHRPROC>(eglGetProcAddress("eglClientWaitSyncKHR"));
        }
        if (!m_createSync || !m_destroySync || !m_clientWaitSync) {
            qCWarning(lcPlayer, "no EGL fences: video frames go back to the decoder three frames late");
            m_createSync = nullptr;
        }
        m_targetTexture = reinterpret_cast<ImageTargetTexture2D>(eglGetProcAddress("glEGLImageTargetTexture2DOES"));
        const char *vertex
            = "attribute vec2 pos; varying vec2 uv;\n"
              "void main() { uv = vec2(pos.x + 1.0, 1.0 - pos.y) * 0.5; gl_Position = vec4(pos, 0.0, 1.0); }\n";
        const char *fragment = "#extension GL_OES_EGL_image_external : require\n"
                               "precision mediump float; varying vec2 uv; uniform samplerExternalOES tex;\n"
                               "void main() { gl_FragColor = texture2D(tex, uv); }\n";
        const auto compile = [f](GLenum type, const char *source) {
            const GLuint shader = f->glCreateShader(type);
            f->glShaderSource(shader, 1, &source, nullptr);
            f->glCompileShader(shader);
            GLint ok = 0;
            f->glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
            if (!ok) {
                char log[512] = {};
                f->glGetShaderInfoLog(shader, sizeof log, nullptr, log);
                qCWarning(lcPlayer, "video shader: %s", log);
            }
            return shader;
        };
        m_program = f->glCreateProgram();
        f->glAttachShader(m_program, compile(GL_VERTEX_SHADER, vertex));
        f->glAttachShader(m_program, compile(GL_FRAGMENT_SHADER, fragment));
        f->glBindAttribLocation(m_program, 0, "pos");
        f->glLinkProgram(m_program);
        m_samplerLocation = f->glGetUniformLocation(m_program, "tex");
        const GLfloat quad[] = {-1, -1, 1, -1, -1, 1, 1, 1};
        f->glGenBuffers(1, &m_vbo);
        f->glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
        f->glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
        f->glBindBuffer(GL_ARRAY_BUFFER, 0);
    }

    // Points m_texture at the sample's buffer; remembers the picture's size and pixel aspect
    bool bind(QOpenGLExtraFunctions *f, GstSample *sample)
    {
        GstBuffer *buffer = gst_sample_get_buffer(sample);
        GstMemory *memory = buffer ? gst_buffer_peek_memory(buffer, 0) : nullptr;
        if (!memory || !gst_is_dmabuf_memory(memory)) {
            if (!m_warnedNoDmabuf)
                qCWarning(lcPlayer, "a video frame that isn't a DMA-BUF: it can't be shown without a copy");
            m_warnedNoDmabuf = true;
            return false;
        }
        GstVideoInfo info;
        if (!gst_video_info_from_caps(&info, gst_sample_get_caps(sample)))
            return false;
        // 8-bit NV12, or the decoder's 10-bit NV12_10LE40, which DRM calls NV15: the Mali GPU samples both
        const uint32_t fourcc
            = GST_VIDEO_INFO_FORMAT(&info) == GST_VIDEO_FORMAT_NV12_10LE40 ? DrmFormatNv15 : uint32_t(DRM_FORMAT_NV12);
        const int fd = gst_dmabuf_memory_get_fd(memory);
        gsize offset[2] = {GST_VIDEO_INFO_PLANE_OFFSET(&info, 0), GST_VIDEO_INFO_PLANE_OFFSET(&info, 1)};
        gint stride[2] = {GST_VIDEO_INFO_PLANE_STRIDE(&info, 0), GST_VIDEO_INFO_PLANE_STRIDE(&info, 1)};
        if (const GstVideoMeta *meta = gst_buffer_get_video_meta(buffer)) {
            for (int i = 0; i < 2; ++i) {
                offset[i] = meta->offset[i];
                stride[i] = meta->stride[i];
            }
        }
        m_pictureWidth
            = GST_VIDEO_INFO_WIDTH(&info) * GST_VIDEO_INFO_PAR_N(&info) / qMax(1, GST_VIDEO_INFO_PAR_D(&info));
        m_pictureHeight = GST_VIDEO_INFO_HEIGHT(&info);

        // A buffer is known by its dma-buf's inode, not by the fd's number: GStreamer may hand out a new fd for each
        // frame, and a closed fd's number comes back for another buffer (docs/03-video-spike.md, finding 5)
        struct stat st = {};
        fstat(fd, &st);
        const auto key = std::make_tuple(st.st_ino, offset[1], stride[0], fourcc);
        auto it = m_textures.find(key);
        if (it == m_textures.end()) {
            if (m_textures.size() >= 64) // the decoder's pool changed: start over
                releaseTextures();
            const EGLint attributes[] = {EGL_WIDTH,
                                         GST_VIDEO_INFO_WIDTH(&info),
                                         EGL_HEIGHT,
                                         GST_VIDEO_INFO_HEIGHT(&info),
                                         EGL_LINUX_DRM_FOURCC_EXT,
                                         EGLint(fourcc),
                                         EGL_DMA_BUF_PLANE0_FD_EXT,
                                         fd,
                                         EGL_DMA_BUF_PLANE0_OFFSET_EXT,
                                         EGLint(offset[0]),
                                         EGL_DMA_BUF_PLANE0_PITCH_EXT,
                                         stride[0],
                                         EGL_DMA_BUF_PLANE1_FD_EXT,
                                         fd,
                                         EGL_DMA_BUF_PLANE1_OFFSET_EXT,
                                         EGLint(offset[1]),
                                         EGL_DMA_BUF_PLANE1_PITCH_EXT,
                                         stride[1],
                                         EGL_NONE};
            EGLImageKHR image = m_createImage(m_display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr, attributes);
            if (image == EGL_NO_IMAGE_KHR) {
                qCWarning(lcPlayer, "eglCreateImageKHR failed: 0x%x", eglGetError());
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

    // The picture, as large as fits into the target, centred (black bars from the window's colour)
    void draw(QOpenGLExtraFunctions *f)
    {
        if (m_target.isEmpty() || m_pictureWidth <= 0 || m_pictureHeight <= 0)
            return;
        const qreal scale = qMin(qreal(m_target.width()) / m_pictureWidth, qreal(m_target.height()) / m_pictureHeight);
        const int width = qRound(m_pictureWidth * scale), height = qRound(m_pictureHeight * scale);
        const int x = m_target.x() + (m_target.width() - width) / 2;
        const int y = m_target.y() + (m_target.height() - height) / 2;
        f->glViewport(x, m_windowHeight - y - height, width, height); // GL counts from the bottom
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

    void releaseTextures()
    {
        QOpenGLContext *context = QOpenGLContext::currentContext();
        if (context && m_destroyImage) {
            for (auto &[key, texture] : m_textures) {
                context->extraFunctions()->glDeleteTextures(1, &texture.first);
                m_destroyImage(m_display, texture.second);
            }
        }
        m_textures.clear();
        m_texture = 0;
    }

    QQuickWindow *m_window;
    struct Retired
    {
        GstSample *sample;
        EGLSyncKHR fence;
    };

    GstSample *m_next = nullptr;
    GstSample *m_current = nullptr;
    EGLSyncKHR m_currentFence = EGL_NO_SYNC_KHR; // after the current frame's last draw
    std::vector<Retired> m_retired;
    QRect m_target;
    int m_windowHeight = 0;
    bool m_visible = false;
    int m_pictureWidth = 0;
    int m_pictureHeight = 0;
    bool m_warnedNoDmabuf = false;
    EGLDisplay m_display = EGL_NO_DISPLAY;
    PFNEGLCREATEIMAGEKHRPROC m_createImage = nullptr;
    PFNEGLDESTROYIMAGEKHRPROC m_destroyImage = nullptr;
    PFNEGLCREATESYNCKHRPROC m_createSync = nullptr;
    PFNEGLDESTROYSYNCKHRPROC m_destroySync = nullptr;
    PFNEGLCLIENTWAITSYNCKHRPROC m_clientWaitSync = nullptr;
    ImageTargetTexture2D m_targetTexture = nullptr;
    GLuint m_program = 0;
    GLuint m_vbo = 0;
    GLuint m_texture = 0;
    GLint m_samplerLocation = -1;
    std::map<std::tuple<ino_t, gsize, gint, uint32_t>, std::pair<GLuint, EGLImageKHR>> m_textures;
};

namespace {

// Deletes the renderer on the render thread, where its GL objects live
class CleanupJob : public QRunnable
{
public:
    explicit CleanupJob(VideoRenderer *renderer) : m_renderer(renderer) { }
    void run() override { delete m_renderer; }

private:
    VideoRenderer *m_renderer;
};

} // namespace

VideoPlayer::VideoPlayer(QQuickItem *parent) : QQuickItem(parent)
{
    if (!gst_is_initialized())
        gst_init(nullptr, nullptr);
    m_positionTimer.setInterval(250);
    connect(&m_positionTimer, &QTimer::timeout, this, &VideoPlayer::updatePosition);
    m_subtitleTimer.setSingleShot(true);
    connect(&m_subtitleTimer, &QTimer::timeout, this, [this] { setSubtitle({}, 0); });
}

VideoPlayer::~VideoPlayer()
{
    rememberPosition();
    close();
    std::lock_guard lock(m_frameMutex);
    if (m_pendingFrame)
        gst_sample_unref(m_pendingFrame);
    m_pendingFrame = nullptr;
}

QString VideoPlayer::audioSinkDescription()
{
    const QString configured = qEnvironmentVariable("RK3568_TV_AUDIO_SINK");
    return configured.isEmpty() ? QStringLiteral("alsasink device=plughw:CARD=rockchiphdmi,DEV=0") : configured;
}

void VideoPlayer::setSource(const QString &source)
{
    if (source == m_source)
        return;
    rememberPosition();
    m_source = source;
    emit sourceChanged();
    open();
}

void VideoPlayer::setResume(bool resume)
{
    if (resume == m_resume)
        return;
    m_resume = resume;
    emit resumeChanged();
}

void VideoPlayer::open()
{
    close();
    if (m_source.isEmpty()) {
        setStatus(NoMedia);
        return;
    }
    const QString path = QFileInfo(m_source).absoluteFilePath();
    m_pipeline = gst_element_factory_make("playbin", "player");
    if (!m_pipeline) {
        setStatus(Failed, tr("GStreamer's playbin is missing"));
        return;
    }
    const int generation = ++m_generation;

    GstElement *videoSink = gst_element_factory_make("appsink", "video");
    GstCaps *videoCaps = gst_caps_from_string("video/x-raw,format=(string){NV12,NV12_10LE40}");
    g_object_set(videoSink, "caps", videoCaps, "sync", TRUE, "max-buffers", 2, "drop", TRUE, "qos", TRUE, nullptr);
    gst_caps_unref(videoCaps);
    GstAppSinkCallbacks videoCallbacks = {};
    videoCallbacks.new_sample = [](GstAppSink *sink, gpointer self) {
        static_cast<VideoPlayer *>(self)->newFrame(gst_app_sink_pull_sample(sink));
        return GST_FLOW_OK;
    };
    gst_app_sink_set_callbacks(GST_APP_SINK(videoSink), &videoCallbacks, this, nullptr);

    // Subtitles come as text at their time (sync); no waiting for them before playing starts (async off), since a
    // subtitle stream may have nothing for a long while
    GstElement *textSink = gst_element_factory_make("appsink", "text");
    GstCaps *textCaps = gst_caps_from_string("text/x-raw");
    g_object_set(textSink, "caps", textCaps, "sync", TRUE, "async", FALSE, nullptr);
    gst_caps_unref(textCaps);
    GstAppSinkCallbacks textCallbacks = {};
    textCallbacks.new_sample = [](GstAppSink *sink, gpointer self) {
        GstSample *sample = gst_app_sink_pull_sample(sink);
        GstBuffer *buffer = gst_sample_get_buffer(sample);
        QString text;
        qint64 durationMs = 0;
        GstMapInfo map;
        if (buffer && gst_buffer_map(buffer, &map, GST_MAP_READ)) {
            text = QString::fromUtf8(reinterpret_cast<const char *>(map.data), int(map.size)).trimmed();
            gst_buffer_unmap(buffer, &map);
        }
        if (buffer && GST_BUFFER_DURATION_IS_VALID(buffer))
            durationMs = qint64(GST_BUFFER_DURATION(buffer) / GST_MSECOND);
        gst_sample_unref(sample);
        auto *player = static_cast<VideoPlayer *>(self);
        QMetaObject::invokeMethod(
            player, [player, text, durationMs] { player->setSubtitle(text, durationMs); }, Qt::QueuedConnection);
        return GST_FLOW_OK;
    };
    gst_app_sink_set_callbacks(GST_APP_SINK(textSink), &textCallbacks, this, nullptr);

    GError *error = nullptr;
    GstElement *audioSink = gst_parse_bin_from_description(audioSinkDescription().toUtf8().constData(), TRUE, &error);
    if (!audioSink) {
        const QString message = error ? QString::fromUtf8(error->message) : QString();
        g_clear_error(&error);
        gst_object_unref(GST_OBJECT(gst_object_ref_sink(videoSink)));
        gst_object_unref(GST_OBJECT(gst_object_ref_sink(textSink)));
        gst_object_unref(m_pipeline);
        m_pipeline = nullptr;
        setStatus(Failed, tr("No sound output: %1").arg(message));
        return;
    }

    const QByteArray uri = QUrl::fromLocalFile(path).toEncoded();
    g_object_set(m_pipeline, "uri", uri.constData(), "video-sink", videoSink, "audio-sink", audioSink, "text-sink",
                 textSink, "flags", FlagVideo | FlagAudio | FlagText | FlagSoftVolume, nullptr);
    const QString subtitles = subtitleFileFor(path);
    if (!subtitles.isEmpty())
        g_object_set(m_pipeline, "suburi", QUrl::fromLocalFile(subtitles).toEncoded().constData(), nullptr);
    qCInfo(lcPlayer, "playing %s%s", qPrintable(path),
           subtitles.isEmpty() ? "" : qPrintable(QStringLiteral(", subtitles from ") + subtitles));

    // Messages come on GStreamer's threads; they are handled on this one, unless a newer file replaced theirs
    GstBus *bus = gst_element_get_bus(m_pipeline);
    struct Context
    {
        VideoPlayer *player;
        int generation;
    };
    gst_bus_set_sync_handler(
        bus,
        [](GstBus *, GstMessage *message, gpointer data) {
            const auto *context = static_cast<Context *>(data);
            switch (GST_MESSAGE_TYPE(message)) {
            case GST_MESSAGE_EOS:
            case GST_MESSAGE_ERROR:
            case GST_MESSAGE_ASYNC_DONE:
            case GST_MESSAGE_STATE_CHANGED:
            case GST_MESSAGE_DURATION_CHANGED:
            case GST_MESSAGE_STREAM_START: {
                std::shared_ptr<GstMessage> copy(gst_message_ref(message), gst_message_unref);
                VideoPlayer *player = context->player;
                const int generation = context->generation;
                QMetaObject::invokeMethod(
                    player,
                    [player, generation, copy] {
                        if (generation == player->m_generation)
                            player->handleMessage(copy.get());
                    },
                    Qt::QueuedConnection);
                break;
            }
            default:
                break;
            }
            return GST_BUS_DROP;
        },
        new Context {this, generation}, [](gpointer data) { delete static_cast<Context *>(data); });
    gst_object_unref(bus);

    for (const char *changed : {"audio-changed", "text-changed"}) {
        g_signal_connect(m_pipeline, changed, G_CALLBACK(+[](GstElement *, gpointer self) {
                             auto *player = static_cast<VideoPlayer *>(self);
                             QMetaObject::invokeMethod(player, &VideoPlayer::updateTracks, Qt::QueuedConnection);
                         }),
                         this);
    }

    m_loaded = false;
    m_wantPlaying = true;
    m_framesReceived = 0;
    m_dmabufFrames = 0;
    m_pendingSeek = m_resume ? ResumePositions::position(path) : 0;
    m_position = m_pendingSeek;
    emit positionChanged();
    setStatus(Loading);
    // Paused first: a remembered position is sought before anything plays
    gst_element_set_state(m_pipeline, GST_STATE_PAUSED);
}

void VideoPlayer::close()
{
    m_positionTimer.stop();
    if (m_pipeline) {
        // for the log: did the frames come in time, and from the hardware decoder?
        qCInfo(lcPlayer, "stopped %s at %lld of %lld ms: %d frames reached the player, %d of them DMA-BUFs",
               qPrintable(m_source), m_position, m_duration, int(m_framesReceived), int(m_dmabufFrames));
        ++m_generation;
        gst_element_set_state(m_pipeline, GST_STATE_NULL);
        gst_object_unref(m_pipeline);
        m_pipeline = nullptr;
    }
    {
        std::lock_guard lock(m_frameMutex);
        if (m_pendingFrame)
            gst_sample_unref(m_pendingFrame);
        m_pendingFrame = nullptr;
        m_resetFrames = true;
    }
    m_loaded = false;
    if (m_duration != 0) {
        m_duration = 0;
        emit durationChanged();
    }
    if (!m_audioTracks.isEmpty() || !m_subtitleTracks.isEmpty()) {
        m_audioTracks.clear();
        m_subtitleTracks.clear();
        m_audioTrack = m_subtitleTrack = -1;
        emit tracksChanged();
    }
    setSubtitle({}, 0);
}

void VideoPlayer::handleMessage(GstMessage *message)
{
    switch (GST_MESSAGE_TYPE(message)) {
    case GST_MESSAGE_EOS:
        m_positionTimer.stop();
        m_position = m_duration;
        emit positionChanged();
        ResumePositions::forget(QFileInfo(m_source).absoluteFilePath());
        setStatus(Ended);
        break;
    case GST_MESSAGE_ERROR: {
        GError *error = nullptr;
        gchar *debug = nullptr;
        gst_message_parse_error(message, &error, &debug);
        const QString text = error ? QString::fromUtf8(error->message) : tr("Unknown error");
        qCWarning(lcPlayer, "%s: %s (%s)", qPrintable(m_source), qPrintable(text), debug ? debug : "");
        g_clear_error(&error);
        g_free(debug);
        close();
        setStatus(Failed, text);
        break;
    }
    case GST_MESSAGE_ASYNC_DONE:
        if (!m_loaded) {
            m_loaded = true;
            loaded();
            if (m_pendingSeek > 0) {
                const qint64 to = m_pendingSeek;
                m_pendingSeek = 0;
                seek(to); // its own ASYNC_DONE starts playing
                break;
            }
        }
        updatePosition();
        if (m_wantPlaying)
            gst_element_set_state(m_pipeline, GST_STATE_PLAYING);
        break;
    case GST_MESSAGE_STATE_CHANGED:
        if (GST_MESSAGE_SRC(message) == GST_OBJECT(m_pipeline)) {
            GstState state;
            gst_message_parse_state_changed(message, nullptr, &state, nullptr);
            if (state == GST_STATE_PLAYING) {
                m_positionTimer.start();
                setStatus(Playing);
            } else if (state == GST_STATE_PAUSED && m_loaded && !m_wantPlaying) {
                m_positionTimer.stop();
                updatePosition();
                setStatus(Paused);
            }
        }
        break;
    case GST_MESSAGE_DURATION_CHANGED:
    case GST_MESSAGE_STREAM_START:
        if (m_loaded)
            loaded();
        break;
    default:
        break;
    }
}

void VideoPlayer::loaded()
{
    gint64 duration = 0;
    if (m_pipeline && gst_element_query_duration(m_pipeline, GST_FORMAT_TIME, &duration) && duration > 0
        && duration / GST_MSECOND != m_duration) {
        m_duration = duration / GST_MSECOND;
        emit durationChanged();
    }
    updateTracks();
}

void VideoPlayer::updatePosition()
{
    gint64 position = 0;
    if (m_pipeline && gst_element_query_position(m_pipeline, GST_FORMAT_TIME, &position)
        && position / GST_MSECOND != m_position) {
        m_position = position / GST_MSECOND;
        emit positionChanged();
    }
}

void VideoPlayer::updateTracks()
{
    if (!m_pipeline)
        return;
    gint audioCount = 0, textCount = 0, audio = -1, text = -1;
    g_object_get(m_pipeline, "n-audio", &audioCount, "n-text", &textCount, "current-audio", &audio, "current-text",
                 &text, nullptr);
    QStringList audioTracks, subtitleTracks;
    for (int i = 0; i < audioCount; ++i) {
        GstTagList *tags = nullptr;
        g_signal_emit_by_name(m_pipeline, "get-audio-tags", i, &tags);
        audioTracks << trackName(tags, i);
    }
    for (int i = 0; i < textCount; ++i) {
        GstTagList *tags = nullptr;
        g_signal_emit_by_name(m_pipeline, "get-text-tags", i, &tags);
        subtitleTracks << trackName(tags, i);
    }
    audioTracks = numberTwins(audioTracks);
    subtitleTracks = numberTwins(subtitleTracks);
    // subtitles stay off until chosen; a chosen track stays chosen
    const int subtitle = m_subtitleTrack >= 0 && m_subtitleTrack < textCount ? m_subtitleTrack : -1;
    if (audioTracks != m_audioTracks || subtitleTracks != m_subtitleTracks || audio != m_audioTrack
        || subtitle != m_subtitleTrack) {
        m_audioTracks = audioTracks;
        m_subtitleTracks = subtitleTracks;
        m_audioTrack = audio;
        m_subtitleTrack = subtitle;
        emit tracksChanged();
    }
}

void VideoPlayer::setAudioTrack(int index)
{
    if (!m_pipeline || index < 0 || index >= m_audioTracks.size() || index == m_audioTrack)
        return;
    g_object_set(m_pipeline, "current-audio", index, nullptr);
    m_audioTrack = index;
    emit tracksChanged();
}

void VideoPlayer::setSubtitleTrack(int index)
{
    if (!m_pipeline || index < -1 || index >= m_subtitleTracks.size() || index == m_subtitleTrack)
        return;
    if (index >= 0)
        g_object_set(m_pipeline, "current-text", index, nullptr);
    m_subtitleTrack = index;
    setSubtitle({}, 0);
    emit tracksChanged();
}

void VideoPlayer::setSubtitle(const QString &text, qint64 durationMs)
{
    if (!text.isEmpty() && m_subtitleTrack < 0)
        return;
    if (!text.isEmpty())
        m_subtitleTimer.start(durationMs > 0 ? int(durationMs) : 5000);
    else
        m_subtitleTimer.stop();
    if (text != m_subtitleText) {
        m_subtitleText = text;
        emit subtitleTextChanged();
    }
}

void VideoPlayer::play()
{
    if (!m_pipeline) {
        if (m_status == Ended || m_status == NoMedia)
            open();
        return;
    }
    m_wantPlaying = true;
    if (m_status == Ended)
        seek(0);
    else if (m_loaded)
        gst_element_set_state(m_pipeline, GST_STATE_PLAYING);
}

void VideoPlayer::pause()
{
    if (!m_pipeline)
        return;
    m_wantPlaying = false;
    if (m_loaded)
        gst_element_set_state(m_pipeline, GST_STATE_PAUSED);
}

void VideoPlayer::togglePause()
{
    if (m_status == Playing || (m_status == Loading && m_wantPlaying))
        pause();
    else
        play();
}

void VideoPlayer::stop()
{
    rememberPosition();
    close();
    setStatus(NoMedia);
}

void VideoPlayer::seek(qint64 ms)
{
    if (!m_pipeline)
        return;
    ms = qBound<qint64>(0, ms, m_duration > 0 ? m_duration : ms);
    if (!m_loaded) {
        m_pendingSeek = ms;
        return;
    }
    // to the nearest key frame before: fast, and the decoder needs one anyway
    gst_element_seek_simple(m_pipeline, GST_FORMAT_TIME,
                            GstSeekFlags(GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_KEY_UNIT | GST_SEEK_FLAG_SNAP_BEFORE),
                            ms * GST_MSECOND);
    m_position = ms;
    emit positionChanged();
    setSubtitle({}, 0);
    if (m_status == Ended)
        setStatus(m_wantPlaying ? Loading : Paused);
}

void VideoPlayer::seekBy(qint64 ms)
{
    seek(m_position + ms);
}

void VideoPlayer::rememberPosition()
{
    if (m_resume && m_loaded && !m_source.isEmpty() && m_status != Ended && m_status != Failed)
        ResumePositions::save(QFileInfo(m_source).absoluteFilePath(), m_position, m_duration);
}

void VideoPlayer::setStatus(Status status, const QString &error)
{
    if (status == m_status && error == m_error)
        return;
    m_status = status;
    m_error = error;
    emit statusChanged();
}

void VideoPlayer::newFrame(GstSample *sample)
{
    if (!sample)
        return;
    ++m_framesReceived;
    GstBuffer *buffer = gst_sample_get_buffer(sample);
    if (buffer && gst_buffer_n_memory(buffer) > 0 && gst_is_dmabuf_memory(gst_buffer_peek_memory(buffer, 0)))
        ++m_dmabufFrames;
    {
        std::lock_guard lock(m_frameMutex);
        if (m_pendingFrame)
            gst_sample_unref(m_pendingFrame); // replaced before it was drawn: that frame isn't shown
        m_pendingFrame = sample;
    }
    QMetaObject::invokeMethod(
        this,
        [this] {
            if (window())
                window()->update();
        },
        Qt::QueuedConnection);
}

void VideoPlayer::itemChange(ItemChange change, const ItemChangeData &value)
{
    if (change == ItemSceneChange && value.window) {
        connect(value.window, &QQuickWindow::beforeSynchronizing, this, &VideoPlayer::sync,
                Qt::ConnectionType(Qt::DirectConnection | Qt::UniqueConnection));
        connect(value.window, &QQuickWindow::sceneGraphInvalidated, this, &VideoPlayer::cleanup,
                Qt::ConnectionType(Qt::DirectConnection | Qt::UniqueConnection));
    }
    QQuickItem::itemChange(change, value);
}

void VideoPlayer::sync()
{
    if (!m_renderer) {
        if (window()->rendererInterface()->graphicsApi() != QSGRendererInterface::OpenGL)
            return; // no GL (the tests' software renderer): nothing to draw with
        m_renderer = new VideoRenderer(window());
        connect(window(), &QQuickWindow::beforeRenderPassRecording, m_renderer, &VideoRenderer::render,
                Qt::DirectConnection);
    }
    GstSample *frame = nullptr;
    bool reset = false;
    {
        std::lock_guard lock(m_frameMutex);
        std::swap(frame, m_pendingFrame);
        std::swap(reset, m_resetFrames);
    }
    if (reset)
        m_renderer->reset();
    if (frame)
        m_renderer->setFrame(frame);
    const qreal dpr = window()->effectiveDevicePixelRatio();
    const QRectF rect = mapRectToScene(boundingRect());
    m_renderer->setTarget(QRectF(rect.topLeft() * dpr, rect.size() * dpr).toRect(), qRound(window()->height() * dpr),
                          isVisible() && m_status != NoMedia && m_status != Failed);
}

void VideoPlayer::cleanup()
{
    delete m_renderer;
    m_renderer = nullptr;
}

void VideoPlayer::releaseResources()
{
    if (m_renderer)
        window()->scheduleRenderJob(new CleanupJob(m_renderer), QQuickWindow::BeforeSynchronizingStage);
    m_renderer = nullptr;
}
