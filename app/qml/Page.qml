import QtQuick
import Rk3568Tv

// One screen of the app: its title top left and the time top right, inside the safe area, and its content below.
// PageStack shows one page at a time and sets `stack`.
FocusScope {
    id: page

    property string title
    property PageStack stack
    default property alias content: body.data

    height: Theme.height
    width: Theme.width

    Text {
        id: heading

        color: Theme.textPrimary
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.textTitle
        font.weight: Font.Medium
        text: page.title
        width: Theme.width - 2 * Theme.safeX - clock.width - Theme.gap
        x: Theme.safeX
        y: Theme.safeY
    }
    Clock {
        id: clock

        anchors.baseline: heading.baseline
        anchors.right: page.right
        anchors.rightMargin: Theme.safeX
    }
    Item {
        id: body

        height: Theme.height - Theme.safeY - y
        width: Theme.width - 2 * Theme.safeX
        x: Theme.safeX
        y: heading.y + heading.height + 2 * Theme.gap
    }
}
