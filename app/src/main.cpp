#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QUrl>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("rk3568-tv"));
    QGuiApplication::setApplicationVersion(QStringLiteral(RK3568_TV_VERSION));

    QQmlApplicationEngine engine;
    // Qt 6.2 has no loadFromModule(); its QML modules live under qrc:/<URI>/ (the default resource prefix "/").
    const QUrl url(QStringLiteral("qrc:/Rk3568Tv/qml/Main.qml"));
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
