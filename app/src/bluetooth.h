#pragma once

#include <QObject>
#include <QVariantList>
#include <QtQml/qqml.h> // in Qt 6.2, qqmlregistration.h alone lacks what QML_SINGLETON needs

#include <functional>

// Bluetooth devices through BlueZ's bluetoothctl (step 1.6): finding devices, pairing, connecting, forgetting.
// Pairing uses the agent "NoInputNoOutput": devices that need no PIN (headphones, speakers, game pads, most
// keyboards in their pairing mode). It never switches Bluetooth off: the chip would lose its firmware
// (docs/02-board.md). QML uses it as the singleton Bluetooth.
class Bluetooth : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // each: address, name, paired, connected; paired ones first
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)

public:
    using QObject::QObject;

    QVariantList devices() const { return m_devices; }
    bool busy() const { return m_busy; }
    QString message() const { return m_message; }

    // The known devices, and whether they are connected
    Q_INVOKABLE void refresh();
    // Looks for devices for seconds, then refreshes
    Q_INVOKABLE void scan(int seconds = 10);
    // Pairs, trusts (so that it reconnects by itself) and connects
    Q_INVOKABLE void pair(const QString &address);
    Q_INVOKABLE void connectDevice(const QString &address);
    Q_INVOKABLE void disconnectDevice(const QString &address);
    // Unpairs and forgets
    Q_INVOKABLE void forget(const QString &address);

    // `bluetoothctl devices` and `bluetoothctl paired-devices`, with the addresses of the connected ones: devices
    // without a name (only their address) are left out unless paired
    static QVariantList parseDevices(const QString &devices, const QString &paired, const QStringList &connected);

signals:
    void devicesChanged();
    void busyChanged();
    void messageChanged();

private:
    void step(const QStringList &arguments, const QString &success, std::function<void(bool)> then, int timeoutMs);
    void setBusy(bool busy);
    void setMessage(const QString &message);
    QString nameOf(const QString &address) const;

    QVariantList m_devices;
    bool m_busy = false;
    QString m_message;
};
