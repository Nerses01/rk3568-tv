#include "wifi.h"

#include "command.h"

#include <QSet>
#include <QVariantMap>

#include <algorithm>

namespace {

QString nmcli()
{
    return Command::program("RK3568_TV_NMCLI", QStringLiteral("nmcli"));
}

// nmcli's "Error: ..." line, without the prefix
QString errorOf(const Command::Result &result)
{
    QString text = (result.error.isEmpty() ? result.output : result.error).trimmed();
    if (text.startsWith(QLatin1String("Error: ")))
        text = text.mid(7);
    return text.isEmpty() ? Wifi::tr("nmcli failed (%1)").arg(result.exitCode) : text;
}

} // namespace

QStringList Wifi::splitTerse(const QString &line)
{
    QStringList fields;
    QString field;
    for (int i = 0; i < line.size(); ++i) {
        const QChar c = line.at(i);
        if (c == QLatin1Char('\\') && i + 1 < line.size()) {
            field += line.at(++i);
        } else if (c == QLatin1Char(':')) {
            fields << field;
            field.clear();
        } else {
            field += c;
        }
    }
    fields << field;
    return fields;
}

QVariantList Wifi::parseNetworks(const QString &list, const QString &connections)
{
    QSet<QString> saved;
    for (const QString &line : connections.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QStringList fields = splitTerse(line);
        if (fields.size() >= 2 && fields.at(1) == QLatin1String("802-11-wireless"))
            saved.insert(fields.at(0));
    }
    QList<QVariantMap> networks;
    for (const QString &line : list.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QStringList fields = splitTerse(line);
        if (fields.size() < 4 || fields.at(1).isEmpty()) // a hidden network has no name to show
            continue;
        const QString ssid = fields.at(1);
        const bool active = fields.at(0) == QLatin1String("*");
        const int signal = fields.at(2).toInt();
        const bool secured = !fields.at(3).isEmpty() && fields.at(3) != QLatin1String("--");
        auto it = std::find_if(networks.begin(), networks.end(),
                               [&ssid](const QVariantMap &n) { return n.value("ssid").toString() == ssid; });
        if (it == networks.end()) {
            networks.append({{"ssid", ssid},
                             {"signal", signal},
                             {"secured", secured},
                             {"active", active},
                             {"saved", saved.contains(ssid)}});
        } else { // the same network on another access point or band
            (*it)["signal"] = qMax(it->value("signal").toInt(), signal);
            (*it)["active"] = it->value("active").toBool() || active;
        }
    }
    std::stable_sort(networks.begin(), networks.end(), [](const QVariantMap &a, const QVariantMap &b) {
        if (a.value("active").toBool() != b.value("active").toBool())
            return a.value("active").toBool();
        return a.value("signal").toInt() > b.value("signal").toInt();
    });
    QVariantList result;
    for (const QVariantMap &network : networks)
        result.append(network);
    return result;
}

void Wifi::scan()
{
    refresh(true);
}

void Wifi::refresh(bool rescan)
{
    if (m_busy)
        return;
    setBusy(true);
    Command::run(this, nmcli(), {"-t", "-f", "NAME,TYPE", "connection", "show"}, [this, rescan](Command::Result known) {
        Command::run(
            this, nmcli(),
            {"-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", rescan ? "yes" : "no"},
            [this, known](Command::Result list) {
                setBusy(false);
                if (!list.ok()) {
                    setMessage(errorOf(list));
                    return;
                }
                m_networks = parseNetworks(list.output, known.output);
                emit networksChanged();
            });
    });
}

void Wifi::join(const QString &ssid, const QString &password)
{
    if (m_busy || ssid.isEmpty())
        return;
    setBusy(true);
    setMessage(tr("Joining %1…").arg(ssid));
    const bool wasSaved = isSaved(ssid);
    QStringList arguments = {"--wait", "45", "device", "wifi", "connect", ssid};
    if (!password.isEmpty())
        arguments << "password" << password;
    Command::run(
        this, nmcli(), arguments,
        [this, ssid, wasSaved](Command::Result result) {
            setBusy(false);
            if (result.ok()) {
                setMessage(tr("Joined %1.").arg(ssid));
                emit joined(ssid);
                refresh(false);
                return;
            }
            setMessage(tr("Couldn't join %1: %2").arg(ssid, errorOf(result)));
            emit failed(ssid);
            // a failed first try leaves a profile with the wrong password behind: it goes
            if (!wasSaved)
                Command::run(this, nmcli(), {"connection", "delete", "id", ssid},
                             [this](Command::Result) { refresh(false); });
            else
                refresh(false);
        },
        60'000);
}

void Wifi::forget(const QString &ssid)
{
    if (m_busy || ssid.isEmpty())
        return;
    setBusy(true);
    Command::run(this, nmcli(), {"connection", "delete", "id", ssid}, [this, ssid](Command::Result result) {
        setBusy(false);
        setMessage(result.ok() ? tr("Forgot %1.").arg(ssid) : tr("Couldn't forget %1: %2").arg(ssid, errorOf(result)));
        refresh(false);
    });
}

bool Wifi::isSaved(const QString &ssid) const
{
    return std::any_of(m_networks.begin(), m_networks.end(), [&ssid](const QVariant &network) {
        const QVariantMap map = network.toMap();
        return map.value("ssid").toString() == ssid && map.value("saved").toBool();
    });
}

void Wifi::setBusy(bool busy)
{
    if (busy != m_busy) {
        m_busy = busy;
        emit busyChanged();
    }
}

void Wifi::setMessage(const QString &message)
{
    if (message != m_message) {
        m_message = message;
        emit messageChanged();
    }
}
