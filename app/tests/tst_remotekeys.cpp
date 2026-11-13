#include "remotekeys.h"

#include <QTest>

class TestRemoteKeys : public QObject
{
    Q_OBJECT

private slots:
    void action_data();
    void action();
    void name_data();
    void name();
};

void TestRemoteKeys::action_data()
{
    QTest::addColumn<int>("key");
    QTest::addColumn<RemoteKeys::Action>("expected");

    QTest::newRow("up") << int(Qt::Key_Up) << RemoteKeys::Up;
    QTest::newRow("down") << int(Qt::Key_Down) << RemoteKeys::Down;
    QTest::newRow("left") << int(Qt::Key_Left) << RemoteKeys::Left;
    QTest::newRow("right") << int(Qt::Key_Right) << RemoteKeys::Right;
    QTest::newRow("return is ok") << int(Qt::Key_Return) << RemoteKeys::Ok;
    QTest::newRow("keypad enter is ok") << int(Qt::Key_Enter) << RemoteKeys::Ok;
    QTest::newRow("select is ok") << int(Qt::Key_Select) << RemoteKeys::Ok;
    QTest::newRow("escape is back") << int(Qt::Key_Escape) << RemoteKeys::Back;
    QTest::newRow("back") << int(Qt::Key_Back) << RemoteKeys::Back;
    QTest::newRow("backspace is back") << int(Qt::Key_Backspace) << RemoteKeys::Back;
    QTest::newRow("exit is back") << int(Qt::Key_Exit) << RemoteKeys::Back;
    QTest::newRow("home") << int(Qt::Key_Home) << RemoteKeys::Home;
    QTest::newRow("home page is home") << int(Qt::Key_HomePage) << RemoteKeys::Home;
    QTest::newRow("menu") << int(Qt::Key_Menu) << RemoteKeys::Menu;
    QTest::newRow("space is play/pause") << int(Qt::Key_Space) << RemoteKeys::PlayPause;
    QTest::newRow("media play/pause") << int(Qt::Key_MediaTogglePlayPause) << RemoteKeys::PlayPause;
    QTest::newRow("media play") << int(Qt::Key_MediaPlay) << RemoteKeys::PlayPause;
    QTest::newRow("media pause") << int(Qt::Key_MediaPause) << RemoteKeys::PlayPause;
    QTest::newRow("volume up") << int(Qt::Key_VolumeUp) << RemoteKeys::VolumeUp;
    QTest::newRow("volume down") << int(Qt::Key_VolumeDown) << RemoteKeys::VolumeDown;
    QTest::newRow("a letter is nothing") << int(Qt::Key_A) << RemoteKeys::None;
    QTest::newRow("no key is nothing") << 0 << RemoteKeys::None;
    QTest::newRow("an unknown key is nothing") << int(Qt::Key_unknown) << RemoteKeys::None;
}

void TestRemoteKeys::action()
{
    QFETCH(int, key);
    QFETCH(RemoteKeys::Action, expected);
    QCOMPARE(RemoteKeys().action(key), expected);
}

void TestRemoteKeys::name_data()
{
    QTest::addColumn<RemoteKeys::Action>("action");
    QTest::addColumn<QString>("expected");

    QTest::newRow("none") << RemoteKeys::None << "none";
    QTest::newRow("up") << RemoteKeys::Up << "up";
    QTest::newRow("ok") << RemoteKeys::Ok << "ok";
    QTest::newRow("play/pause") << RemoteKeys::PlayPause << "playpause";
    QTest::newRow("volume down") << RemoteKeys::VolumeDown << "volumedown";
    QTest::newRow("out of range") << static_cast<RemoteKeys::Action>(99) << "none";
}

void TestRemoteKeys::name()
{
    QFETCH(RemoteKeys::Action, action);
    QFETCH(QString, expected);
    QCOMPARE(RemoteKeys().name(action), expected);
}

QTEST_GUILESS_MAIN(TestRemoteKeys)
#include "tst_remotekeys.moc"
