#include "wifi.h"

#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QVariantMap>

// A stub nmcli (RK3568_TV_NMCLI) stands in for NetworkManager: it records its arguments and answers like nmcli does.
// "Home" is saved and joined; "Office" is new and takes the password "right"; "Cafe" is open.
class TestWifi : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void cleanup();
    void splitTerse_data();
    void splitTerse();
    void parseNetworks();
    void scanListsTheNetworks();
    void joinsWithAPassword();
    void aFailedFirstJoinForgetsTheNewProfile();
    void aFailedJoinKeepsASavedNetwork();
    void forgets();
    void withoutNmcliSaysSo();

private:
    QStringList calls() const;
    void scanned(Wifi &wifi);

    QTemporaryDir m_dir;
};

void TestWifi::init()
{
    QVERIFY(m_dir.isValid());
    const QString stub = m_dir.filePath("nmcli");
    QFile file(stub);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(QStringLiteral(R"(#!/bin/sh
printf '%s\n' "$*" >> '%1/calls'
case "$*" in
"-t -f NAME,TYPE connection show")
    printf 'Home:802-11-wireless\nWired connection 1:802-3-ethernet\n' ;;
"-t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list"*)
    printf '*:Home:70:WPA2\n :Office:55:WPA2 WPA3\n :Home:80:WPA2\n :Cafe:40:\n :::WPA2\n' ;;
"--wait 45 device wifi connect Office password right")
    echo "Device 'wlan0' successfully activated." ;;
"--wait 45 device wifi connect "*)
    echo "Error: Connection activation failed: Secrets were required, but not provided." >&2
    exit 4 ;;
"connection delete id "*)
    echo "Connection successfully deleted." ;;
esac
)")
                   .arg(m_dir.path())
                   .toUtf8());
    file.close();
    QVERIFY(file.setPermissions(file.permissions() | QFile::ExeOwner));
    qputenv("RK3568_TV_NMCLI", stub.toUtf8());
    QFile::remove(m_dir.filePath("calls"));
}

void TestWifi::cleanup()
{
    qunsetenv("RK3568_TV_NMCLI");
}

QStringList TestWifi::calls() const
{
    QFile file(m_dir.filePath("calls"));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
}

void TestWifi::scanned(Wifi &wifi)
{
    QSignalSpy networks(&wifi, &Wifi::networksChanged);
    wifi.scan();
    QVERIFY(networks.wait(5000));
}

void TestWifi::splitTerse_data()
{
    QTest::addColumn<QString>("line");
    QTest::addColumn<QStringList>("fields");
    QTest::newRow("plain") << "*:Home:70" << QStringList {"*", "Home", "70"};
    QTest::newRow("escaped colon") << R"(:a\:b:WPA2)" << QStringList {"", "a:b", "WPA2"};
    QTest::newRow("escaped backslash") << R"(a\\:b)" << QStringList {R"(a\)", "b"};
    QTest::newRow("empty last") << "Cafe:" << QStringList {"Cafe", ""};
}

void TestWifi::splitTerse()
{
    QFETCH(QString, line);
    QFETCH(QStringList, fields);
    QCOMPARE(Wifi::splitTerse(line), fields);
}

void TestWifi::parseNetworks()
{
    const QVariantList networks = Wifi::parseNetworks(" :Office:55:WPA2\n*:Home:70:WPA2\n :Home:80:WPA2\n :Cafe:90:\n"
                                                      " :::WPA2\n :Free:20:--\n",
                                                      "Home:802-11-wireless\nOffice:802-3-ethernet\n");
    QCOMPARE(networks.size(), 4); // the hidden one has no name
    const QVariantMap home = networks.at(0).toMap();
    QCOMPARE(home.value("ssid").toString(), QStringLiteral("Home")); // joined: first
    QCOMPARE(home.value("signal").toInt(), 80); // its strongest access point
    QCOMPARE(home.value("active").toBool(), true);
    QCOMPARE(home.value("saved").toBool(), true);
    QCOMPARE(home.value("secured").toBool(), true);
    const QVariantMap cafe = networks.at(1).toMap();
    QCOMPARE(cafe.value("ssid").toString(), QStringLiteral("Cafe")); // then by signal
    QCOMPARE(cafe.value("secured").toBool(), false);
    QCOMPARE(cafe.value("active").toBool(), false);
    const QVariantMap office = networks.at(2).toMap();
    QCOMPARE(office.value("ssid").toString(), QStringLiteral("Office"));
    QCOMPARE(office.value("saved").toBool(), false); // a wired profile of that name isn't this network
    QCOMPARE(networks.at(3).toMap().value("secured").toBool(), false); // "--": open
}

void TestWifi::scanListsTheNetworks()
{
    Wifi wifi;
    QSignalSpy busy(&wifi, &Wifi::busyChanged);
    scanned(wifi);
    QCOMPARE(wifi.busy(), false);
    QCOMPARE(busy.count(), 2);
    QVERIFY(calls().last().endsWith(QLatin1String("--rescan yes")));
    QCOMPARE(wifi.networks().size(), 3);
    QCOMPARE(wifi.networks().first().toMap().value("ssid").toString(), QStringLiteral("Home"));
}

void TestWifi::joinsWithAPassword()
{
    Wifi wifi;
    scanned(wifi);
    QSignalSpy joined(&wifi, &Wifi::joined);
    QSignalSpy networks(&wifi, &Wifi::networksChanged);
    wifi.join("Office", "right");
    QVERIFY(wifi.busy());
    QVERIFY(networks.wait(5000)); // joined, then the list again
    QCOMPARE(joined.count(), 1);
    QCOMPARE(joined.first().first().toString(), QStringLiteral("Office"));
    QVERIFY(calls().contains("--wait 45 device wifi connect Office password right"));
    QVERIFY(!calls().contains("connection delete id Office"));
    QCOMPARE(wifi.message(), QStringLiteral("Joined Office."));
}

void TestWifi::aFailedFirstJoinForgetsTheNewProfile()
{
    Wifi wifi;
    scanned(wifi);
    QSignalSpy failed(&wifi, &Wifi::failed);
    QSignalSpy networks(&wifi, &Wifi::networksChanged);
    wifi.join("Office", "wrong");
    QVERIFY(networks.wait(5000));
    QCOMPARE(failed.count(), 1);
    QVERIFY(calls().contains("connection delete id Office")); // no profile with the wrong password left behind
    QCOMPARE(wifi.message(),
             QStringLiteral("Couldn't join Office: Connection activation failed: Secrets were required, but not "
                            "provided."));
}

void TestWifi::aFailedJoinKeepsASavedNetwork()
{
    Wifi wifi;
    scanned(wifi);
    QSignalSpy failed(&wifi, &Wifi::failed);
    QSignalSpy networks(&wifi, &Wifi::networksChanged);
    wifi.join("Home", "");
    QVERIFY(networks.wait(5000));
    QCOMPARE(failed.count(), 1);
    QVERIFY(calls().contains("--wait 45 device wifi connect Home")); // no password: NetworkManager has it
    QVERIFY(!calls().contains("connection delete id Home"));
}

void TestWifi::forgets()
{
    Wifi wifi;
    QSignalSpy networks(&wifi, &Wifi::networksChanged);
    wifi.forget("Home");
    QVERIFY(networks.wait(5000));
    QCOMPARE(calls().first(), QStringLiteral("connection delete id Home"));
    QCOMPARE(wifi.message(), QStringLiteral("Forgot Home."));
}

void TestWifi::withoutNmcliSaysSo()
{
    qputenv("RK3568_TV_NMCLI", m_dir.filePath("none").toUtf8());
    Wifi wifi;
    QSignalSpy message(&wifi, &Wifi::messageChanged);
    wifi.scan();
    QTRY_COMPARE_WITH_TIMEOUT(message.count(), 1, 5000); // perhaps already in scan(): the program can't start
    QCOMPARE(wifi.busy(), false);
    QVERIFY(!wifi.message().isEmpty());
    QVERIFY(wifi.networks().isEmpty());
}

QTEST_GUILESS_MAIN(TestWifi)
#include "tst_wifi.moc"
