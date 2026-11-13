#include "bluetooth.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QVariantMap>

// A stub bluetoothctl (RK3568_TV_BLUETOOTHCTL) stands in for BlueZ: it records its arguments and answers like
// bluetoothctl does. The speaker is paired and connected; the game pad pairs; the keyboard doesn't.
namespace {
const QString speaker = QStringLiteral("00:00:5E:00:53:01");
const QString unnamed = QStringLiteral("00:00:5E:00:53:02");
const QString pad = QStringLiteral("00:00:5E:00:53:03");
const QString keyboard = QStringLiteral("00:00:5E:00:53:04");
} // namespace

class TestBluetooth : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void cleanup();
    void parseDevices();
    void refreshFindsTheConnectedOnes();
    void pairsTrustsAndConnects();
    void aFailedPairingSaysSo();
    void forgets();

private:
    QStringList calls() const;
    void refreshed(Bluetooth &bluetooth);

    QTemporaryDir m_dir;
};

void TestBluetooth::init()
{
    QVERIFY(m_dir.isValid());
    const QString stub = m_dir.filePath("bluetoothctl");
    QFile file(stub);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(QStringLiteral(R"(#!/bin/sh
dir='%1'
printf '%s\n' "$*" >> "$dir/calls"
case "$*" in
devices)
    printf 'Device %2 Speaker\nDevice %3 %4\nDevice %5 Pad\nDevice %6 Keyboard\n' ;;
paired-devices)
    cat "$dir/paired" ;;
"info %2")
    printf 'Device %2 (public)\n\tName: Speaker\n\tPaired: yes\n\tConnected: yes\n' ;;
"info "*)
    printf '\tConnected: no\n' ;;
"--agent NoInputNoOutput --timeout 30 pair %5")
    echo "Attempting to pair with %5"
    echo "Pairing successful"
    echo "Device %5 Pad" >> "$dir/paired" ;;
"--agent NoInputNoOutput --timeout 30 pair "*)
    echo "Failed to pair: org.bluez.Error.AuthenticationFailed" ;;
"trust "*)
    echo "Changing $2 trust succeeded" ;;
"--timeout 15 connect "*)
    echo "Attempting to connect"
    echo "Connection successful" ;;
"remove "*)
    echo "Device has been removed" ;;
esac
)")
                   .arg(m_dir.path(), speaker, unnamed, QString(unnamed).replace(':', '-'), pad, keyboard)
                   .toUtf8());
    file.close();
    QVERIFY(file.setPermissions(file.permissions() | QFile::ExeOwner));
    QFile paired(m_dir.filePath("paired"));
    QVERIFY(paired.open(QIODevice::WriteOnly | QIODevice::Truncate));
    paired.write(QStringLiteral("Device %1 Speaker\n").arg(speaker).toUtf8());
    qputenv("RK3568_TV_BLUETOOTHCTL", stub.toUtf8());
    QFile::remove(m_dir.filePath("calls"));
}

void TestBluetooth::cleanup()
{
    qunsetenv("RK3568_TV_BLUETOOTHCTL");
}

QStringList TestBluetooth::calls() const
{
    QFile file(m_dir.filePath("calls"));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
}

void TestBluetooth::refreshed(Bluetooth &bluetooth)
{
    QSignalSpy devices(&bluetooth, &Bluetooth::devicesChanged);
    bluetooth.refresh();
    QVERIFY(devices.wait(5000));
}

void TestBluetooth::parseDevices()
{
    const QString all = QStringLiteral("Device %1 Pad\nDevice %2 %3\nDevice %4 Speaker\nDevice %5\n")
                            .arg(pad, unnamed, QString(unnamed).replace(':', '-'), speaker, keyboard);
    const QVariantList devices
        = Bluetooth::parseDevices(all, QStringLiteral("Device %1 Speaker\n").arg(speaker), {speaker});
    QCOMPARE(devices.size(), 2); // the ones without a name aren't shown
    const QVariantMap first = devices.at(0).toMap();
    QCOMPARE(first.value("address").toString(), speaker); // paired: first
    QCOMPARE(first.value("name").toString(), QStringLiteral("Speaker"));
    QCOMPARE(first.value("paired").toBool(), true);
    QCOMPARE(first.value("connected").toBool(), true);
    const QVariantMap second = devices.at(1).toMap();
    QCOMPARE(second.value("name").toString(), QStringLiteral("Pad"));
    QCOMPARE(second.value("paired").toBool(), false);
    QCOMPARE(second.value("connected").toBool(), false);

    // a paired device without a name is shown, by its address
    const QVariantList withUnnamed = Bluetooth::parseDevices(QStringLiteral("Device %1\n").arg(unnamed),
                                                             QStringLiteral("Device %1\n").arg(unnamed), {});
    QCOMPARE(withUnnamed.size(), 1);
    QCOMPARE(withUnnamed.first().toMap().value("name").toString(), unnamed);
}

void TestBluetooth::refreshFindsTheConnectedOnes()
{
    Bluetooth bluetooth;
    refreshed(bluetooth);
    QCOMPARE(bluetooth.devices().size(), 3);
    const QVariantMap first = bluetooth.devices().first().toMap();
    QCOMPARE(first.value("name").toString(), QStringLiteral("Speaker"));
    QCOMPARE(first.value("connected").toBool(), true);
    QVERIFY(calls().contains("info " + speaker));
}

void TestBluetooth::pairsTrustsAndConnects()
{
    Bluetooth bluetooth;
    refreshed(bluetooth);
    QSignalSpy devices(&bluetooth, &Bluetooth::devicesChanged);
    bluetooth.pair(pad);
    QVERIFY(bluetooth.busy());
    QCOMPARE(bluetooth.message(), QStringLiteral("Pairing with Pad…"));
    QVERIFY(devices.wait(5000));
    QCOMPARE(bluetooth.busy(), false);
    const QStringList all = calls();
    const qsizetype paired = all.indexOf("--agent NoInputNoOutput --timeout 30 pair " + pad);
    const qsizetype trusted = all.indexOf("trust " + pad);
    const qsizetype connected = all.indexOf("--timeout 15 connect " + pad);
    QVERIFY(paired >= 0);
    QVERIFY(trusted > paired);
    QVERIFY(connected > trusted);
    QCOMPARE(bluetooth.message(), QStringLiteral("Pad is paired and connected."));
    QCOMPARE(bluetooth.devices().at(1).toMap().value("paired").toBool(), true);
}

void TestBluetooth::aFailedPairingSaysSo()
{
    Bluetooth bluetooth;
    refreshed(bluetooth);
    QSignalSpy devices(&bluetooth, &Bluetooth::devicesChanged);
    bluetooth.pair(keyboard);
    QVERIFY(devices.wait(5000));
    QCOMPARE(bluetooth.message(), QStringLiteral("Couldn't pair with Keyboard. Is it in pairing mode?"));
    QVERIFY(!calls().contains("trust " + keyboard));
}

void TestBluetooth::forgets()
{
    Bluetooth bluetooth;
    refreshed(bluetooth);
    QSignalSpy devices(&bluetooth, &Bluetooth::devicesChanged);
    bluetooth.forget(speaker);
    QVERIFY(devices.wait(5000));
    QVERIFY(calls().contains("remove " + speaker));
    QCOMPARE(bluetooth.message(), QStringLiteral("Forgot Speaker."));
}

QTEST_GUILESS_MAIN(TestBluetooth)
#include "tst_bluetooth.moc"
