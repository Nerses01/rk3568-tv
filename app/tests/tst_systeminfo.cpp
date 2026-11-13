#include "systeminfo.h"

#include <QHostAddress>
#include <QSysInfo>
#include <QTest>

class TestSystemInfo : public QObject
{
    Q_OBJECT

private slots:
    void facts();
    void addressesAreIpv4WithoutLoopback();
};

void TestSystemInfo::facts()
{
    const SystemInfo info;
    QCOMPARE(info.qtVersion(), QString::fromLatin1(qVersion()));
    QCOMPARE(info.hostName(), QSysInfo::machineHostName());
    QVERIFY(!info.kernel().isEmpty());
}

void TestSystemInfo::addressesAreIpv4WithoutLoopback()
{
    const QStringList addresses = SystemInfo().addresses();
    for (const QString &address : addresses) {
        const QHostAddress parsed(address);
        QCOMPARE(parsed.protocol(), QAbstractSocket::IPv4Protocol);
        QVERIFY2(!parsed.isLoopback(), qPrintable(address));
    }
}

QTEST_GUILESS_MAIN(TestSystemInfo)
#include "tst_systeminfo.moc"
