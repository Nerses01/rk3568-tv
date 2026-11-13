#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqml.h> // in Qt 6.2, qqmlregistration.h alone lacks what QML_SINGLETON needs

// The one remote-control model that every input maps to (docs/01-plan.md, §4.4). Keyboards, the TV's remote over
// HDMI-CEC and an IR remote all reach the app as Qt key events; RemoteKeys says which action a key stands for.
// QML uses it as the singleton RemoteKeys: RemoteKeys.action(event.key) === RemoteKeys.Ok.
class RemoteKeys : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    enum Action { None, Up, Down, Left, Right, Ok, Back, Home, Menu, PlayPause, VolumeUp, VolumeDown };
    Q_ENUM(Action)

    using QObject::QObject;

    // The action a Qt key (Qt::Key) stands for, or None.
    Q_INVOKABLE Action action(int key) const;

    // The action's name in lower case, such as "up" or "playpause"; "none" for anything else.
    Q_INVOKABLE QString name(Action action) const;
};
