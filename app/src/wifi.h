#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QtQml/qqml.h> // in Qt 6.2, qqmlregistration.h alone lacks what QML_SINGLETON needs

// Wi-Fi through NetworkManager's nmcli (step 1.6): the networks in range, joining one, forgetting one. The user tv
// may do this through a polkit grant (system/rk3568-tv.pkla). QML uses it as the singleton Wifi.
class Wifi : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // each: ssid, signal (0-100), secured, active (joined now), saved (NetworkManager knows it)
    Q_PROPERTY(QVariantList networks READ networks NOTIFY networksChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    // what happened last, for the viewer: empty, or a sentence
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)

public:
    using QObject::QObject;

    QVariantList networks() const { return m_networks; }
    bool busy() const { return m_busy; }
    QString message() const { return m_message; }

    // Looks for networks again (a few seconds)
    Q_INVOKABLE void scan();
    // Joins ssid; password may be empty for an open network or one NetworkManager knows
    Q_INVOKABLE void join(const QString &ssid, const QString &password);
    // Forgets a known network; the box leaves it if it is on it
    Q_INVOKABLE void forget(const QString &ssid);

    // nmcli's terse output (-t) split into fields: ':' separates, '\' escapes
    static QStringList splitTerse(const QString &line);
    // The networks from `nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list` and the known names from
    // `nmcli -t -f NAME,TYPE connection show`: one entry per network name, the strongest, joined ones first
    static QVariantList parseNetworks(const QString &list, const QString &connections);

signals:
    void networksChanged();
    void busyChanged();
    void messageChanged();
    void joined(const QString &ssid);
    void failed(const QString &ssid);

private:
    void refresh(bool rescan);
    void setBusy(bool busy);
    void setMessage(const QString &message);
    bool isSaved(const QString &ssid) const;

    QVariantList m_networks;
    bool m_busy = false;
    QString m_message;
};
