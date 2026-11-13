import QtQuick
import Rk3568Tv

// A section that a later version brings; the caller sets the title
Page {
    id: notYet

    Column {
        spacing: Theme.gap
        width: parent.width

        Text {
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.textBody
            text: qsTr("Not available yet: a later version brings it.")
            width: parent.width
            wrapMode: Text.WordWrap
        }
        Text {
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.textCaption
            text: qsTr("Back returns to the previous screen.")
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }
}
