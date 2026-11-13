#include "remotekeys.h"

#include <QMetaEnum>

RemoteKeys::Action RemoteKeys::action(int key) const
{
    switch (key) {
    case Qt::Key_Up:
        return Up;
    case Qt::Key_Down:
        return Down;
    case Qt::Key_Left:
        return Left;
    case Qt::Key_Right:
        return Right;
    case Qt::Key_Return:
    case Qt::Key_Enter:
    case Qt::Key_Select:
        return Ok;
    case Qt::Key_Escape:
    case Qt::Key_Back:
    case Qt::Key_Backspace:
    case Qt::Key_Exit:
        return Back;
    case Qt::Key_Home:
    case Qt::Key_HomePage:
        return Home;
    case Qt::Key_Menu:
        return Menu;
    case Qt::Key_Space:
    case Qt::Key_MediaTogglePlayPause:
    case Qt::Key_MediaPlay:
    case Qt::Key_MediaPause:
        return PlayPause;
    case Qt::Key_VolumeUp:
        return VolumeUp;
    case Qt::Key_VolumeDown:
        return VolumeDown;
    default:
        return None;
    }
}

QString RemoteKeys::name(Action action) const
{
    const char *key = QMetaEnum::fromType<Action>().valueToKey(action);
    return key ? QString::fromLatin1(key).toLower() : QStringLiteral("none");
}
