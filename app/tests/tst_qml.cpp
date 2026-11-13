#include <QObject>
#include <QQmlEngine>
#include <QtQml/QQmlExtensionPlugin>
#include <QtQuickTest/quicktest.h>

// The app's QML module, linked in statically, so that the tests `import Rk3568Tv`
Q_IMPORT_QML_PLUGIN(Rk3568TvPlugin)

class Setup : public QObject
{
    Q_OBJECT

public slots:
    // As in the app (src/main.cpp): Qt 6.2 doesn't look in qrc:/qt/qml for modules by itself
    void qmlEngineAvailable(QQmlEngine *engine) { engine->addImportPath(QStringLiteral("qrc:/qt/qml")); }
};

QUICK_TEST_MAIN_WITH_SETUP(rk3568tv, Setup)

#include "tst_qml.moc"
