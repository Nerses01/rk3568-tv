import QtQuick
import Rk3568Tv // the module's own C++ types: in Qt 6.2 a file in qml/ doesn't see them without it

// A placeholder until step 1.3 builds the home screen. It shows the version, when the app started and the last
// key pressed, so that a deploy and the keys can be checked on the screen, or without sitting at the TV with
// `scripts/board.sh keys` and `scripts/board.sh shot`. A key that is no remote-control action shows as its Qt
// key code, which helps to find the codes of the TV's remote (step 1.7).
Window {
    id: root

    readonly property real unit: height / 1080   // layout units: designed for 1920x1080
    readonly property string startedAt: Qt.formatTime(new Date(), "hh:mm:ss")
    property string lastKey: "none yet"

    color: "#0b0e12"
    title: Qt.application.name
    visibility: Window.FullScreen
    visible: true

    Column {
        anchors.centerIn: parent
        focus: true
        spacing: 24 * root.unit

        // a function, not an arrow function: qmlformat 6.2 breaks arrow functions (scripts/format.sh)
        Keys.onPressed: function (event) {
            const action = RemoteKeys.action(event.key);
            const name = action === RemoteKeys.None ? "0x" + event.key.toString(16) : RemoteKeys.name(action);
            root.lastKey = name + (event.isAutoRepeat ? " (repeat)" : "");
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "white"
            font.pixelSize: 96 * root.unit
            font.bold: true
            text: Qt.application.name
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#a0a8b0"
            font.pixelSize: 36 * root.unit
            text: "version " + Qt.application.version + "  ·  started " + root.startedAt
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: "#a0a8b0"
            font.pixelSize: 36 * root.unit
            text: "last key: " + root.lastKey
        }
    }
}
