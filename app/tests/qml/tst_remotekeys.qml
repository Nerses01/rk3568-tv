import QtQuick
import QtTest
import Rk3568Tv

// RemoteKeys as QML sees it: the singleton, its enum and its functions
TestCase {
    name: "RemoteKeysInQml"

    function test_action() {
        compare(RemoteKeys.action(Qt.Key_Up), RemoteKeys.Up);
        compare(RemoteKeys.action(Qt.Key_Return), RemoteKeys.Ok);
        compare(RemoteKeys.action(Qt.Key_Escape), RemoteKeys.Back);
        compare(RemoteKeys.action(Qt.Key_A), RemoteKeys.None);
    }

    function test_name() {
        compare(RemoteKeys.name(RemoteKeys.Ok), "ok");
        compare(RemoteKeys.name(RemoteKeys.action(Qt.Key_Space)), "playpause");
    }
}
