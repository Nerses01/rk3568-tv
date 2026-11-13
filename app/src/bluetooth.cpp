#include "bluetooth.h"

#include "command.h"

#include <QRegularExpression>
#include <QSet>
#include <QVariantMap>

#include <algorithm>
#include <memory>

namespace {

QString bluetoothctl()
{
    return Command::program("RK3568_TV_BLUETOOTHCTL", QStringLiteral("bluetoothctl"));
}

// "Device AA:BB:CC:DD:EE:FF Name" lines: address -> name
QList<QPair<QString, QString>> deviceLines(const QString &text)
{
    static const QRegularExpression line(QStringLiteral("^Device ([0-9A-F:]{17}) ?(.*)$"),
                                         QRegularExpression::MultilineOption);
    QList<QPair<QString, QString>> result;
    auto it = line.globalMatch(text);
    while (it.hasNext()) {
        const auto match = it.next();
        result.append({match.captured(1), match.captured(2).trimmed()});
    }
    return result;
}

} // namespace

QVariantList Bluetooth::parseDevices(const QString &devices, const QString &paired, const QStringList &connected)
{
    QSet<QString> pairedSet;
    for (const auto &[address, name] : deviceLines(paired))
        pairedSet.insert(address);
    QList<QVariantMap> list;
    for (const auto &[address, name] : deviceLines(devices)) {
        const bool isPaired = pairedSet.contains(address);
        // BlueZ names a device without a name after its address, with dashes
        const bool unnamed = name.isEmpty() || name == QString(address).replace(QLatin1Char(':'), QLatin1Char('-'));
        if (unnamed && !isPaired)
            continue;
        list.append({{"address", address},
                     {"name", unnamed ? address : name},
                     {"paired", isPaired},
                     {"connected", connected.contains(address)}});
    }
    std::stable_sort(list.begin(), list.end(), [](const QVariantMap &a, const QVariantMap &b) {
        return a.value("paired").toBool() && !b.value("paired").toBool();
    });
    QVariantList result;
    for (const QVariantMap &device : list)
        result.append(device);
    return result;
}

void Bluetooth::refresh()
{
    Command::run(this, bluetoothctl(), {"devices"}, [this](Command::Result all) {
        Command::run(this, bluetoothctl(), {"paired-devices"}, [this, all](Command::Result paired) {
            // the connected ones: `info` of each paired device
            const auto pairedDevices = deviceLines(paired.output);
            auto connected = std::make_shared<QStringList>();
            auto remaining = std::make_shared<int>(int(pairedDevices.size()));
            auto finish = [this, all, paired, connected] {
                m_devices = parseDevices(all.output, paired.output, *connected);
                emit devicesChanged();
            };
            if (pairedDevices.isEmpty()) {
                finish();
                return;
            }
            for (const auto &[address, name] : pairedDevices) {
                const QString device = address;
                Command::run(this, bluetoothctl(), {"info", device},
                             [device, connected, remaining, finish](Command::Result info) {
                                 if (info.output.contains(QLatin1String("Connected: yes")))
                                     connected->append(device);
                                 if (--*remaining == 0)
                                     finish();
                             });
            }
        });
    });
}

void Bluetooth::scan(int seconds)
{
    if (m_busy)
        return;
    setBusy(true);
    setMessage(tr("Looking for devices…"));
    Command::run(
        this, bluetoothctl(), {"--timeout", QString::number(seconds), "scan", "on"},
        [this](Command::Result) {
            setBusy(false);
            setMessage({});
            refresh();
        },
        (seconds + 10) * 1000);
}

void Bluetooth::step(const QStringList &arguments, const QString &success, std::function<void(bool)> then,
                     int timeoutMs)
{
    Command::run(
        this, bluetoothctl(), arguments,
        [success, then](Command::Result result) { then(result.output.contains(success)); }, timeoutMs);
}

void Bluetooth::pair(const QString &address)
{
    if (m_busy)
        return;
    setBusy(true);
    const QString name = nameOf(address);
    setMessage(tr("Pairing with %1…").arg(name));
    step(
        {"--agent", "NoInputNoOutput", "--timeout", "30", "pair", address}, QStringLiteral("Pairing successful"),
        [this, address, name](bool paired) {
            if (!paired) {
                setBusy(false);
                setMessage(tr("Couldn't pair with %1. Is it in pairing mode?").arg(name));
                refresh();
                return;
            }
            step(
                {"trust", address}, QStringLiteral("trust succeeded"),
                [this, address, name](bool) {
                    step(
                        {"--timeout", "15", "connect", address}, QStringLiteral("Connection successful"),
                        [this, name](bool connected) {
                            setBusy(false);
                            setMessage(connected ? tr("%1 is paired and connected.").arg(name)
                                                 : tr("%1 is paired, but didn't connect.").arg(name));
                            refresh();
                        },
                        20'000);
                },
                10'000);
        },
        40'000);
}

void Bluetooth::connectDevice(const QString &address)
{
    if (m_busy)
        return;
    setBusy(true);
    const QString name = nameOf(address);
    step(
        {"--timeout", "15", "connect", address}, QStringLiteral("Connection successful"),
        [this, name](bool ok) {
            setBusy(false);
            setMessage(ok ? tr("%1 is connected.").arg(name) : tr("Couldn't connect %1. Is it on?").arg(name));
            refresh();
        },
        20'000);
}

void Bluetooth::disconnectDevice(const QString &address)
{
    if (m_busy)
        return;
    setBusy(true);
    const QString name = nameOf(address);
    step(
        {"disconnect", address}, QStringLiteral("Successful disconnected"),
        [this, name](bool) {
            setBusy(false);
            setMessage(tr("%1 is disconnected.").arg(name));
            refresh();
        },
        10'000);
}

void Bluetooth::forget(const QString &address)
{
    if (m_busy)
        return;
    setBusy(true);
    const QString name = nameOf(address);
    step(
        {"remove", address}, QStringLiteral("Device has been removed"),
        [this, name](bool ok) {
            setBusy(false);
            setMessage(ok ? tr("Forgot %1.").arg(name) : tr("Couldn't forget %1.").arg(name));
            refresh();
        },
        10'000);
}

QString Bluetooth::nameOf(const QString &address) const
{
    for (const QVariant &device : m_devices) {
        const QVariantMap map = device.toMap();
        if (map.value("address").toString() == address)
            return map.value("name").toString();
    }
    return address;
}

void Bluetooth::setBusy(bool busy)
{
    if (busy != m_busy) {
        m_busy = busy;
        emit busyChanged();
    }
}

void Bluetooth::setMessage(const QString &message)
{
    if (message != m_message) {
        m_message = message;
        emit messageChanged();
    }
}
