import QtQuick
import QtTest
import Rk3568Tv

// The app's window, Main.qml: it runs, takes keys, and names the last one
TestCase {
    name: "Main"
    when: windowShown

    Component {
        id: mainComponent

        Main {
        }
    }

    function createMain() {
        const main = createTemporaryObject(mainComponent, null);
        verify(main, "Main.qml loads");
        main.requestActivate(); // the test's keys go to the active window
        tryVerify(function () {
                return main.active;
            }, 1000, "Main's window becomes active");
        return main;
    }

    function test_remote_keys() {
        const main = createMain();
        compare(main.lastKey, "none yet");
        keyClick(Qt.Key_Right);
        compare(main.lastKey, "right");
        keyClick(Qt.Key_Return);
        compare(main.lastKey, "ok");
        keyClick(Qt.Key_Escape);
        compare(main.lastKey, "back");
    }

    function test_other_keys_show_their_code() {
        const main = createMain();
        keyClick(Qt.Key_A);
        compare(main.lastKey, "0x41");
    }
}
