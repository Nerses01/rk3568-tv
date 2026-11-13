import QtQuick
import Rk3568Tv

// The password for the Wi-Fi network in the title, typed on the on-screen keyboard (or a real one). Done joins; the
// page stays until the network is joined, and shows why not if it isn't.
Page {
    id: page

    Column {
        spacing: Theme.gap
        width: parent.width

        Text {
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.textBody
            text: Wifi.busy || Wifi.message !== "" ? Wifi.message : qsTr("Password")
            width: parent.width
            wrapMode: Text.WordWrap
        }
        Rectangle {
            color: Theme.surface
            height: 96
            radius: Theme.radius
            width: 1100

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 40
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Theme.textBody
                objectName: "password"
                text: keyboard.text + "_"
            }
        }
        OnScreenKeyboard {
            id: keyboard

            focus: true

            onAccepted: {
                if (keyboard.text.length > 0)
                    Wifi.join(page.title, keyboard.text);
            }
        }
    }
    Connections {
        function onJoined(ssid) {
            if (ssid === page.title)
                page.stack.pop();
        }

        target: Wifi
    }
}
