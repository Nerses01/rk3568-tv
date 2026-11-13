#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QtQml/qqml.h> // in Qt 6.2, qqmlregistration.h alone lacks what QML_SINGLETON needs

// Facts about the box for the About page; QML uses it as the singleton SystemInfo
class SystemInfo : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString hostName READ hostName CONSTANT)
    Q_PROPERTY(QString kernel READ kernel CONSTANT)
    Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT)

public:
    using QObject::QObject;

    QString hostName() const;
    QString kernel() const;
    QString qtVersion() const;

    // The box's IPv4 addresses on its networks (up, running, not loopback): where to reach it over SSH
    Q_INVOKABLE QStringList addresses() const;
};
