// Step 0.6 UI spike: a TV home screen in Qt Quick on EGLFS. Throwaway measurement code.
//
// usage: uispike NAME MODE
// Shows the home screen in main.qml until Esc. From the first key press to Esc it records when every frame was
// presented, then prints one tab-separated line (MODE is only copied into it):
//   test framebuffer mode hz seconds frames fps p50_ms p99_ms max_ms janks keys repeats first_frame_ms
//   proc_cpu% sys_cpu% gpu% gpu_MHz soc_C rss_MB
// A jank is a frame interval longer than 1.5 refresh periods: the screen showed the previous frame again at
// least once. keys counts key presses, repeats the presses Qt repeated while a key was held. proc_cpu% is this
// process as a percentage of one core, sys_cpu% the whole system as a percentage of all four.
//
// Environment: UISPIKE_POSTERS the pictures' folder (default /userdata/media/posters); UISPIKE_NO_STILLS no
// background stills; UISPIKE_NO_POSTERS no pictures at all; UISPIKE_QML another scene from a file.

#include <QElapsedTimer>
#include <QFile>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMutex>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QScreen>
#include <QTimer>
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <thread>
#include <unistd.h>
#include <vector>

namespace {

struct CpuTimes {
    qint64 total = 0;
    qint64 idle = 0;
};

CpuTimes systemCpu()
{
    CpuTimes t;
    QFile f("/proc/stat");
    if (!f.open(QIODevice::ReadOnly))
        return t;
    const QList<QByteArray> v = f.readLine().simplified().split(' ');   // cpu user nice system idle iowait irq softirq steal
    for (int i = 1; i <= 8 && i < v.size(); ++i)
        t.total += v[i].toLongLong();
    if (v.size() > 5)
        t.idle = v[4].toLongLong() + v[5].toLongLong();
    return t;
}

qint64 processTicks()   // utime + stime of this process
{
    QFile f("/proc/self/stat");
    if (!f.open(QIODevice::ReadOnly))
        return 0;
    const QByteArray s = f.readAll();
    const QList<QByteArray> v = s.mid(s.lastIndexOf(')') + 2).split(' ');   // v[0] is field 3, so utime (14) is v[11]
    return v.size() > 12 ? v[11].toLongLong() + v[12].toLongLong() : 0;
}

long readNumber(const char *path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll().trimmed().toLong() : -1;
}

long rssKb()
{
    QFile f("/proc/self/status");
    if (!f.open(QIODevice::ReadOnly))
        return -1;
    for (QByteArray line = f.readLine(); !line.isEmpty(); line = f.readLine())
        if (line.startsWith("VmRSS:"))
            return line.mid(6).simplified().split(' ').value(0).toLong();
    return -1;
}

class Stats : public QObject
{
public:
    Stats(QQuickWindow *window, QString name, QString mode, QElapsedTimer sinceStart)
        : m_window(window), m_name(std::move(name)), m_mode(std::move(mode)), m_sinceStart(sinceStart)
    {
        m_frames.reserve(1 << 16);
        window->installEventFilter(this);
        // frameSwapped comes from the render thread, right after the swap (on eglfs_kms: after the page flip)
        connect(window, &QQuickWindow::frameSwapped, this, [this] { onFrame(); }, Qt::DirectConnection);
    }

    ~Stats() override { stopSampler(); }

protected:
    bool eventFilter(QObject *obj, QEvent *e) override
    {
        if (e->type() != QEvent::KeyPress)
            return QObject::eventFilter(obj, e);
        const auto *k = static_cast<QKeyEvent *>(e);
        if (k->key() == Qt::Key_Escape) {
            finish();
            return true;
        }
        ++(k->isAutoRepeat() ? m_repeats : m_keys);
        if (!m_started)
            start();
        return false;   // the key goes on to the QML scene
    }

private:
    void onFrame()   // render thread
    {
        const qint64 now = m_sinceStart.nsecsElapsed();
        QMutexLocker lock(&m_mutex);
        if (m_firstFrameNs < 0)
            m_firstFrameNs = now;
        if (m_recording)
            m_frames.push_back(now);
    }

    void start()
    {
        m_started = true;
        m_cpu0 = systemCpu();
        m_ticks0 = processTicks();
        m_run.start();
        // Mali's utilisation file answers only after measuring for its period (100 ms), so it is read on a thread
        // of its own, back to back; read on the GUI thread, it held every frame up by 100 ms.
        m_sampling = true;
        m_sampler = std::thread([this] {
            while (m_sampling) {
                m_gpuLoad += readNumber("/sys/devices/platform/fde60000.gpu/utilisation");   // percent
                m_gpuMHz += readNumber("/sys/class/devfreq/fde60000.gpu/cur_freq") / 1000000;
                ++m_samples;
            }
        });
        QMutexLocker lock(&m_mutex);
        m_recording = true;
    }

    void stopSampler()
    {
        m_sampling = false;
        if (m_sampler.joinable())
            m_sampler.join();
    }

    void finish()
    {
        if (m_finished)
            return;
        m_finished = true;
        stopSampler();
        const double wall = m_run.isValid() ? m_run.nsecsElapsed() / 1e9 : 0;
        const CpuTimes cpu1 = systemCpu();
        const qint64 ticks1 = processTicks();
        std::vector<qint64> f;
        qint64 firstFrameNs;
        {
            QMutexLocker lock(&m_mutex);
            m_recording = false;
            f = m_frames;
            firstFrameNs = m_firstFrameNs;
        }
        QTimer::singleShot(0, qApp, &QCoreApplication::quit);

        if (f.size() < 2) {
            std::printf("%s\t-\t%s\tNO FRAMES (keys %d)\n", qPrintable(m_name), qPrintable(m_mode), m_keys);
            return;
        }
        const double hz = m_window->screen()->refreshRate();
        std::vector<double> iv;   // frame intervals in ms
        for (size_t i = 1; i < f.size(); ++i)
            iv.push_back((f[i] - f[i - 1]) / 1e6);
        const auto janks = std::count_if(iv.begin(), iv.end(), [hz](double ms) { return ms > 1.5 * 1000 / hz; });
        std::sort(iv.begin(), iv.end());
        const double seconds = (f.back() - f.front()) / 1e9;
        const QSize fb = m_window->size() * m_window->devicePixelRatio();
        const double busy = (cpu1.total - m_cpu0.total) - (cpu1.idle - m_cpu0.idle);
        std::printf("%s\t%dx%d\t%s\t%.0f\t%.1f\t%zu\t%.1f\t%.1f\t%.1f\t%.1f\t%ld\t%d\t%d\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\t%ld\t%ld\n",
                    qPrintable(m_name), fb.width(), fb.height(), qPrintable(m_mode), hz, seconds, f.size(),
                    (f.size() - 1) / seconds, iv[iv.size() / 2], iv[iv.size() * 99 / 100], iv.back(), long(janks),
                    m_keys, m_repeats, firstFrameNs / 1e6, 100.0 * (ticks1 - m_ticks0) / sysconf(_SC_CLK_TCK) / wall,
                    100.0 * busy / (cpu1.total - m_cpu0.total), m_samples ? double(m_gpuLoad) / m_samples : -1.0,
                    m_samples ? double(m_gpuMHz) / m_samples : -1.0,
                    readNumber("/sys/class/thermal/thermal_zone0/temp") / 1000, rssKb() / 1024);
        std::fflush(stdout);
    }

    QQuickWindow *m_window;
    QString m_name;
    QString m_mode;
    QElapsedTimer m_sinceStart;
    QElapsedTimer m_run;
    std::thread m_sampler;
    std::atomic<bool> m_sampling = false;
    std::atomic<long> m_gpuLoad = 0;
    std::atomic<long> m_gpuMHz = 0;
    std::atomic<int> m_samples = 0;
    QMutex m_mutex;
    std::vector<qint64> m_frames;   // guarded by m_mutex
    qint64 m_firstFrameNs = -1;     // guarded by m_mutex
    bool m_recording = false;       // guarded by m_mutex
    bool m_started = false;
    bool m_finished = false;
    int m_keys = 0;
    int m_repeats = 0;
    CpuTimes m_cpu0;
    qint64 m_ticks0 = 0;
};

} // namespace

int main(int argc, char *argv[])
{
    QElapsedTimer sinceStart;
    sinceStart.start();
    if (argc < 3) {
        std::fprintf(stderr, "usage: uispike NAME MODE\n");
        return 1;
    }
    QGuiApplication app(argc, argv);
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("posterDir",
                                             qEnvironmentVariable("UISPIKE_POSTERS", "/userdata/media/posters"));
    // to find what costs frames: no background stills, or no pictures at all
    engine.rootContext()->setContextProperty("noStills", qEnvironmentVariableIsSet("UISPIKE_NO_STILLS"));
    engine.rootContext()->setContextProperty("noPosters", qEnvironmentVariableIsSet("UISPIKE_NO_POSTERS"));
    const QString qml = qEnvironmentVariable("UISPIKE_QML");   // another scene from a file, to compare
    engine.load(qml.isEmpty() ? QUrl("qrc:/main.qml") : QUrl::fromLocalFile(qml));
    auto *window = engine.rootObjects().isEmpty() ? nullptr : qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    if (!window)
        return 1;
    window->requestActivate();   // key events go to the active window
    Stats stats(window, argv[1], argv[2], sinceStart);
    return app.exec();
}
