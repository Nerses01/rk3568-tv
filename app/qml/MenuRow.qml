import QtQuick
import Rk3568Tv

// A row in a list such as Settings: a name, maybe a value, and › when OK opens a page. When highlighted it gets a
// white frame, so the focus shows by shape as well as by colour.
Rectangle {
    id: row

    property bool highlighted
    property string label
    property bool opens: true
    property string value

    Accessible.description: row.value
    Accessible.name: row.label
    Accessible.role: row.opens ? Accessible.Button : Accessible.StaticText
    border.color: Theme.focusRing
    border.width: row.highlighted ? Theme.focusRingWidth : 0
    color: row.highlighted ? Theme.surfaceFocused : Theme.surface
    height: 96
    radius: Theme.radius

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 40
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.textBody
        text: row.label
    }
    Text {
        anchors.right: chevron.visible ? chevron.left : parent.right
        anchors.rightMargin: chevron.visible ? Theme.gap : 40
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.textBody
        text: row.value
    }
    Text {
        id: chevron

        Accessible.ignored: true
        anchors.right: parent.right
        anchors.rightMargin: 40
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.textHeading
        text: "›"
        visible: row.opens
    }
}
