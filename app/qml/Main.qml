import QtQuick

// A placeholder until step 1.3 builds the home screen. It shows the version, when the app started and the last
// key pressed, so that a deploy and the keys can be checked on the screen, or without sitting at the TV with
// `scripts/board.sh keys` and `scripts/board.sh shot`.
Window {
    id: root

    readonly property real unit: height / 1080   // layout units: designed for 1920x1080
    readonly property string startedAt: Qt.formatTime(new Date(), "hh:mm:ss")
    property string lastKey: "none yet"

    function keyName(key) {
        const names = {
            [Qt.Key_Up]: "up", [Qt.Key_Down]: "down", [Qt.Key_Left]: "left", [Qt.Key_Right]: "right",
            [Qt.Key_Return]: "enter", [Qt.Key_Enter]: "enter", [Qt.Key_Back]: "back", [Qt.Key_Escape]: "esc",
            [Qt.Key_HomePage]: "home", [Qt.Key_Menu]: "menu", [Qt.Key_Space]: "space"
        }
        return names[key] || "0x" + key.toString(16)
    }

    color: "#0b0e12"
    title: Qt.application.name
    visibility: Window.FullScreen
    visible: true

    Column {
        anchors.centerIn: parent
        focus: true
        spacing: 24 * root.unit

        Keys.onPressed: event => {
            root.lastKey = root.keyName(event.key) + (event.isAutoRepeat ? " (repeat)" : "")
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
