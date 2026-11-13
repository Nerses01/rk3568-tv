#include "systeminfo.h"

#include <QNetworkInterface>
#include <QSysInfo>

QString SystemInfo::hostName() const
{
    return QSysInfo::machineHostName();
}

QString SystemInfo::kernel() const
{
    return QSysInfo::kernelVersion();
}

QString SystemInfo::qtVersion() const
{
    return QString::fromLatin1(qVersion());
}

QStringList SystemInfo::addresses() const
{
    QStringList result;
    const auto interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &interface : interfaces) {
        const auto flags = interface.flags();
        if (!flags.testFlag(QNetworkInterface::IsUp) || !flags.testFlag(QNetworkInterface::IsRunning)
            || flags.testFlag(QNetworkInterface::IsLoopBack))
            continue;
        const auto entries = interface.addressEntries();
        for (const QNetworkAddressEntry &entry : entries) {
            if (entry.ip().protocol() == QAbstractSocket::IPv4Protocol)
                result.append(entry.ip().toString());
        }
    }
    return result;
}
