import QtQuick
import Rk3568Tv

// One screen of the app: its title top left and the time top right, inside the safe area, and its content below.
// Without chrome (the player), the content has the whole screen. PageStack shows one page at a time and sets `stack`.
FocusScope {
    id: page

    property bool chrome: true
    default property alias content: body.data
    property PageStack stack
    property string title

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
        visible: page.chrome
        width: Theme.width - 2 * Theme.safeX - clock.width - Theme.gap
        x: Theme.safeX
        y: Theme.safeY
    }
    Clock {
        id: clock

        anchors.baseline: heading.baseline
        anchors.right: page.right
        anchors.rightMargin: Theme.safeX
        visible: page.chrome
    }
    Item {
        id: body

        height: page.chrome ? Theme.height - Theme.safeY - y : Theme.height
        width: page.chrome ? Theme.width - 2 * Theme.safeX : Theme.width
        x: page.chrome ? Theme.safeX : 0
        y: page.chrome ? heading.y + heading.height + 2 * Theme.gap : 0
    }
}
