import QtQuick
import Rk3568Tv

// A big tile on the home screen: a symbol, a name and a line about it. When highlighted it grows and gets a white
// frame, so the focus shows by shape as well as by colour.
Item {
    id: tile

    property string detail
    property bool highlighted
    property string label
    property string symbol

    Accessible.description: tile.detail
    Accessible.name: tile.label
    Accessible.role: Accessible.Button
    height: 320
    width: 480
    z: tile.highlighted ? 1 : 0

    Rectangle {
        anchors.fill: parent
        border.color: Theme.focusRing
        border.width: tile.highlighted ? Theme.focusRingWidth : 0
        color: tile.highlighted ? Theme.surfaceFocused : Theme.surface
        radius: Theme.radius
        scale: tile.highlighted ? Theme.focusScale : 1

        Behavior on scale  {
            ScaleAnimator {
                duration: Theme.focusDuration
                easing.type: Easing.OutCubic
            }
        }

        Text {
            Accessible.ignored: true
            color: Theme.textPrimary
            font.family: Theme.symbolFamily
            font.pixelSize: 96
            text: tile.symbol
            x: 40
            y: 24
        }
        Text {
            anchors.bottom: detailText.top
            anchors.left: detailText.left
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.textHeading
            font.weight: Font.Medium
            text: tile.label
        }
        Text {
            id: detailText

            anchors.bottom: parent.bottom
            anchors.bottomMargin: 32
            anchors.left: parent.left
            anchors.leftMargin: 40
            anchors.right: parent.right
            anchors.rightMargin: 40
            color: Theme.textSecondary
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.textCaption
            text: tile.detail
        }
    }
}
