#include "displaysettings.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QVariantMap>

// The KMS configuration lives in a temporary folder (QT_QPA_EGLFS_KMS_CONFIG), as /var/lib/rk3568-tv/kms.json does on
// the board
class TestDisplaySettings : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void cleanup();
    void modeOf();
    void withModeKeepsTheRest();
    void withModeOfNothing();
    void modeList();
    void chooseKeepsTheOldModeAndRestarts();
    void keep();
    void revert();
    void aSecondChoiceStillRevertsToTheFirstMode();
    void threeFailedStartsGoBack();
    void withoutAConfigurationNothingChanges();

private:
    QString path(const QString &suffix = {}) const { return m_dir.filePath("kms.json" + suffix); }
    QString modeIn(const QString &file) const;

    QTemporaryDir m_dir;
    const QByteArray m_config
        = R"({ "device": "/dev/dri/card0", "hwcursor": false, "outputs": [ { "name": "HDMI1", "mode": "1920x1080@60" } ] })";
};

void TestDisplaySettings::init()
{
    QVERIFY(m_dir.isValid());
    for (const QString &suffix : {QString(), QStringLiteral(".previous"), QStringLiteral(".attempts")})
        QFile::remove(path(suffix));
    QFile file(path());
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(m_config);
    qputenv("QT_QPA_EGLFS_KMS_CONFIG", path().toUtf8());
}

void TestDisplaySettings::cleanup()
{
    qunsetenv("QT_QPA_EGLFS_KMS_CONFIG");
}

QString TestDisplaySettings::modeIn(const QString &file) const
{
    QFile f(file);
    return f.open(QIODevice::ReadOnly) ? DisplaySettings::modeOf(f.readAll()) : QString();
}

void TestDisplaySettings::modeOf()
{
    QCOMPARE(DisplaySettings::modeOf(m_config), QStringLiteral("1920x1080@60"));
    QCOMPARE(DisplaySettings::modeOf("{}"), QString());
    QCOMPARE(DisplaySettings::modeOf("not JSON"), QString());
}

void TestDisplaySettings::withModeKeepsTheRest()
{
    const QJsonObject config = QJsonDocument::fromJson(DisplaySettings::withMode(m_config, "1280x720@50")).object();
    QCOMPARE(config.value("device").toString(), QStringLiteral("/dev/dri/card0"));
    QCOMPARE(config.value("hwcursor").toBool(true), false);
    const QJsonObject output = config.value("outputs").toArray().first().toObject();
    QCOMPARE(output.value("name").toString(), QStringLiteral("HDMI1"));
    QCOMPARE(output.value("mode").toString(), QStringLiteral("1280x720@50"));
}

void TestDisplaySettings::withModeOfNothing()
{
    const QByteArray config = DisplaySettings::withMode({}, "3840x2160@30");
    QCOMPARE(DisplaySettings::modeOf(config), QStringLiteral("3840x2160@30"));
    const QJsonObject root = QJsonDocument::fromJson(config).object();
    QCOMPARE(root.value("device").toString(), QStringLiteral("/dev/dri/card0"));
    QCOMPARE(root.value("outputs").toArray().first().toObject().value("name").toString(), QStringLiteral("HDMI1"));
}

void TestDisplaySettings::modeList()
{
    using Mode = DisplaySettings::Mode;
    const QList<Mode> screen = {
        {1280, 720, 60, false, false},  {1920, 1080, 60, false, false}, {1920, 1080, 60, true, false},
        {1920, 1080, 50, false, false}, {1920, 1080, 60, false, true},  {3840, 2160, 30, false, false},
    };
    const QVariantList modes = DisplaySettings::modeList(screen, "1920x1080@50");
    QStringList names;
    for (const QVariant &mode : modes)
        names << mode.toMap().value("mode").toString();
    // largest first, then fastest; no interlaced modes, no repeats
    QCOMPARE(names, (QStringList {"3840x2160@30", "1920x1080@60", "1920x1080@50", "1280x720@60"}));
    QCOMPARE(modes.at(1).toMap().value("label").toString(), QStringLiteral("1920 × 1080, 60 Hz (the screen's own)"));
    QCOMPARE(modes.at(2).toMap().value("label").toString(), QStringLiteral("1920 × 1080, 50 Hz"));
    QCOMPARE(modes.at(2).toMap().value("current").toBool(), true);
    QCOMPARE(modes.at(1).toMap().value("current").toBool(), false);
}

void TestDisplaySettings::chooseKeepsTheOldModeAndRestarts()
{
    DisplaySettings settings;
    QCOMPARE(settings.current(), QStringLiteral("1920x1080@60"));
    QCOMPARE(settings.awaitingConfirmation(), false);
    QSignalSpy restart(&settings, &DisplaySettings::restartRequested);
    QVERIFY(!settings.choose("1920x1080@60")); // the mode it has
    QCOMPARE(restart.count(), 0);
    QVERIFY(settings.choose("1280x720@50"));
    QCOMPARE(restart.count(), 1);
    QCOMPARE(modeIn(path()), QStringLiteral("1280x720@50"));
    QCOMPARE(modeIn(path(".previous")), QStringLiteral("1920x1080@60"));

    const DisplaySettings restarted;
    QCOMPARE(restarted.current(), QStringLiteral("1280x720@50"));
    QCOMPARE(restarted.awaitingConfirmation(), true);
}

void TestDisplaySettings::keep()
{
    QVERIFY(DisplaySettings().choose("1280x720@50"));
    DisplaySettings restarted;
    QSignalSpy awaiting(&restarted, &DisplaySettings::awaitingConfirmationChanged);
    QSignalSpy restart(&restarted, &DisplaySettings::restartRequested);
    restarted.keep();
    QCOMPARE(restarted.awaitingConfirmation(), false);
    QCOMPARE(awaiting.count(), 1);
    QCOMPARE(restart.count(), 0);
    QVERIFY(!QFile::exists(path(".previous")));
    QCOMPARE(modeIn(path()), QStringLiteral("1280x720@50"));
    QCOMPARE(DisplaySettings().awaitingConfirmation(), false);
}

void TestDisplaySettings::revert()
{
    QVERIFY(DisplaySettings().choose("1280x720@50"));
    DisplaySettings restarted;
    QSignalSpy restart(&restarted, &DisplaySettings::restartRequested);
    restarted.revert();
    QCOMPARE(restart.count(), 1);
    QCOMPARE(modeIn(path()), QStringLiteral("1920x1080@60"));
    QVERIFY(!QFile::exists(path(".previous")));
    QCOMPARE(DisplaySettings().awaitingConfirmation(), false);
}

void TestDisplaySettings::aSecondChoiceStillRevertsToTheFirstMode()
{
    QVERIFY(DisplaySettings().choose("1280x720@50"));
    QVERIFY(DisplaySettings().choose("3840x2160@30")); // from the confirmation, before keeping the first
    QCOMPARE(modeIn(path()), QStringLiteral("3840x2160@30"));
    DisplaySettings().revert();
    QCOMPARE(modeIn(path()), QStringLiteral("1920x1080@60"));
}

void TestDisplaySettings::threeFailedStartsGoBack()
{
    DisplaySettings::recoverBeforeStart(); // nothing new: nothing to do
    QVERIFY(!QFile::exists(path(".attempts")));
    QVERIFY(DisplaySettings().choose("1280x720@50"));
    for (int start = 1; start <= 3; ++start) {
        DisplaySettings::recoverBeforeStart();
        QCOMPARE(modeIn(path()), QStringLiteral("1280x720@50"));
    }
    DisplaySettings::recoverBeforeStart(); // the fourth: the new mode never came up
    QCOMPARE(modeIn(path()), QStringLiteral("1920x1080@60"));
    QVERIFY(!QFile::exists(path(".previous")));
    QVERIFY(!QFile::exists(path(".attempts")));
}

void TestDisplaySettings::withoutAConfigurationNothingChanges()
{
    qunsetenv("QT_QPA_EGLFS_KMS_CONFIG");
    DisplaySettings settings;
    QSignalSpy restart(&settings, &DisplaySettings::restartRequested);
    QVERIFY(!settings.choose("1280x720@50"));
    QCOMPARE(restart.count(), 0);
    QCOMPARE(modeIn(path()), QStringLiteral("1920x1080@60"));
}

QTEST_GUILESS_MAIN(TestDisplaySettings)
#include "tst_displaysettings.moc"
