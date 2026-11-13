import QtQuick
import Rk3568Tv

// A keyboard for the remote: arrows choose a key, OK types it. ⇧ switches capitals, #+= the symbols, ⌫ deletes, Done
// accepts. A real keyboard types straight into it.
FocusScope {
    id: keyboard

    property bool capitals: false
    readonly property var letterRows: ["1234567890", "qwertyuiop", "asdfghjkl-", "zxcvbnm_.@"]
    readonly property var specials: ["⇧", "#+=", "␣", "⌫", qsTr("Done")]
    property bool symbols: false
    readonly property var symbolRows: ["!\"#$%&'()*", "+,-./:;<=>", "?@[\\]^_`{|", "}~€£¥§°·¿¡"]
    property string text

    signal accepted

    function press(key) {
        if (key === "⇧")
            keyboard.capitals = !keyboard.capitals;
        else if (key === "#+=")
            keyboard.symbols = !keyboard.symbols;
        else if (key === "␣")
            keyboard.text += " ";
        else if (key === "⌫")
            keyboard.text = keyboard.text.slice(0, -1);
        else if (key === qsTr("Done"))
            keyboard.accepted();
        else
            keyboard.text += key;
    }

    height: grid.height
    width: grid.width

    GridView {
        id: grid

        readonly property var keys: {
            const rows = keyboard.symbols ? keyboard.symbolRows : keyboard.letterRows;
            const keys = [];
            for (const row of rows)
                for (const c of row)
                    keys.push(keyboard.capitals && !keyboard.symbols ? c.toUpperCase() : c);
            return keys.concat(keyboard.specials);
        }

        cellHeight: 88
        cellWidth: 110
        focus: true
        height: 5 * grid.cellHeight
        interactive: false // no flicking: there is no pointer
        keyNavigationEnabled: true // it would follow interactive
        model: grid.keys
        objectName: "keys"
        width: 10 * grid.cellWidth

        delegate: Rectangle {
            required property string modelData
            readonly property bool highlighted: GridView.isCurrentItem && grid.activeFocus

            border.color: Theme.focusRing
            border.width: highlighted ? Theme.focusRingWidth : 0
            color: highlighted ? Theme.surfaceFocused : Theme.surface
            height: grid.cellHeight - 8
            radius: Theme.radius / 2
            width: grid.cellWidth - 8

            Text {
                anchors.centerIn: parent
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.textBody
                text: modelData
            }
        }

        // OK types the key; a real keyboard types its characters, Backspace deletes; arrows and the rest go on
        Keys.onPressed: function (event) {
            if (RemoteKeys.action(event.key) === RemoteKeys.Ok) {
                keyboard.press(grid.keys[grid.currentIndex]);
                event.accepted = true;
            } else if (event.key === Qt.Key_Backspace) {
                keyboard.press("⌫");
                event.accepted = true;
            } else if (event.text.length === 1 && event.text >= " " && event.key !== Qt.Key_Space) {
                keyboard.text += event.text;
                event.accepted = true;
            } else {
                event.accepted = false;
            }
        }
    }
}
