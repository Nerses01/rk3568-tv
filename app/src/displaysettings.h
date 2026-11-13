#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QtQml/qqml.h> // in Qt 6.2, qqmlregistration.h alone lacks what QML_SINGLETON needs

// The screen mode (step 1.6). Qt takes it from its KMS configuration at start (QT_QPA_EGLFS_KMS_CONFIG, the unit's
// /var/lib/rk3568-tv/kms.json), so a new mode means a restart. A mode the screen can't show must not strand the
// viewer: the old configuration is kept next to the new one, the app asks to keep the new mode and goes back by
// itself after a while, and a new mode the app can't even start in goes back after three tries. QML uses it as the
// singleton DisplaySettings.
class DisplaySettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    // each: mode ("1920x1080@60"), label, current; the screen's modes, largest and fastest first
    Q_PROPERTY(QVariantList modes READ modes CONSTANT)
    Q_PROPERTY(QString current READ current CONSTANT)
    // a new mode waits for the viewer to keep it
    Q_PROPERTY(bool awaitingConfirmation READ awaitingConfirmation NOTIFY awaitingConfirmationChanged)

public:
    struct Mode
    {
        int width = 0;
        int height = 0;
        int refresh = 0;
        bool interlaced = false;
        bool preferred = false;
    };

    explicit DisplaySettings(QObject *parent = nullptr);

    QVariantList modes() const { return m_modes; }
    QString current() const { return m_current; }
    bool awaitingConfirmation() const { return m_awaiting; }

    // Saves mode, keeping the configuration before it, and asks for a restart
    Q_INVOKABLE bool choose(const QString &mode);
    // The new mode stays
    Q_INVOKABLE void keep();
    // Back to the mode before, with a restart
    Q_INVOKABLE void revert();

    // Before Qt starts: a new mode tried three times without being kept goes back to the old one
    static void recoverBeforeStart();

    static QString configPath();
    // "1920x1080@60" from a KMS configuration, or empty
    static QString modeOf(const QByteArray &config);
    // config with its first output's mode set to mode (a fresh one if config is empty)
    static QByteArray withMode(const QByteArray &config, const QString &mode);
    static QVariantList modeList(const QList<Mode> &modes, const QString &current);
    // The connected HDMI screen's modes, from DRM
    static QList<Mode> screenModes();

signals:
    void awaitingConfirmationChanged();
    // the configuration changed: the app quits, and systemd starts it again
    void restartRequested();

private:
    QVariantList m_modes;
    QString m_current;
    bool m_awaiting = false;
};
