#include "displaysettings.h"
#include "unixsignals.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QUrl>
#include <QtQml/QQmlExtensionPlugin>

#include <csignal>

// The app's QML module is a static library; this links its plugin in.
Q_IMPORT_QML_PLUGIN(Rk3568TvPlugin)

int main(int argc, char *argv[])
{
    // a new screen mode the app can't start in goes back to the old one after three tries
    DisplaySettings::recoverBeforeStart();
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("rk3568-tv"));
    QGuiApplication::setApplicationVersion(QStringLiteral(RK3568_TV_VERSION));

    // systemd stops the app with SIGTERM: quit through the event loop, exit 0 (after QGuiApplication, so that these
    // handlers replace Qt's)
    UnixSignals unixSignals({SIGTERM, SIGINT});
    QObject::connect(&unixSignals, &UnixSignals::received, &app, &QCoreApplication::quit);

    QQmlApplicationEngine engine;
    // Qt 6.2 neither looks in qrc:/qt/qml for modules nor has loadFromModule(); Qt 6.5 does both by itself.
    engine.addImportPath(QStringLiteral("qrc:/qt/qml"));
    const QUrl url(QStringLiteral("qrc:/qt/qml/Rk3568Tv/qml/Main.qml"));
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated, &app,
        [url](QObject *object, const QUrl &objectUrl) {
            if (!object && objectUrl == url)
                QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
    engine.load(url);
    return app.exec();
}
