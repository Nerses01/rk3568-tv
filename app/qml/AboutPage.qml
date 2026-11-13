import QtQuick
import Rk3568Tv

// About: the app's version and the box's facts, including its network address, where to reach it over SSH
Page {
    id: about

    readonly property var addresses: SystemInfo.addresses()
    readonly property var facts: [[qsTr("Version"), Qt.application.version], [qsTr("Address"), about.addresses.length > 0 ? about.addresses.join(", ") : qsTr("Not connected")], [qsTr("Name"), SystemInfo.hostName], [qsTr("Kernel"), SystemInfo.kernel], [qsTr("Qt"), SystemInfo.qtVersion]]

    Column {
        spacing: Theme.gap

        Repeater {
            model: about.facts

            delegate: Row {
                required property var modelData

                objectName: modelData[0]
                spacing: 2 * Theme.gap

                Text {
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.textBody
                    text: modelData[0]
                    width: 280
                }
                Text {
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.textBody
                    text: modelData[1]
                }
            }
        }
    }
}
