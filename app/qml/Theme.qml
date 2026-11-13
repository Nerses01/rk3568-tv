pragma Singleton
import QtQuick

// The TV look (step 1.3), for a viewer about 3 m away. Sizes are 1920x1080 layout units, which Main scales to the
// screen. Colours are named by their role. Type sizes follow a modular scale (base 36, ratio 1.333), with nothing
// below 28.
QtObject {
    readonly property int width: 1920
    readonly property int height: 1080

    // Title-safe area: content keeps 5 % of the width and height clear, for TVs that overscan
    readonly property int safeX: 96
    readonly property int safeY: 54
    readonly property int gap: 24

    readonly property color background: "#0b0e12"
    readonly property color surface: "#1a2129"
    readonly property color surfaceFocused: "#2c3846"
    readonly property color textPrimary: "#f2f4f7"
    readonly property color textSecondary: "#a8b2bd"
    readonly property color focusRing: "#ffffff"

    readonly property string fontFamily: "Ubuntu"
    readonly property string symbolFamily: "DejaVu Sans"
    readonly property int textCaption: 28
    readonly property int textBody: 36
    readonly property int textHeading: 48
    readonly property int textTitle: 64

    readonly property int radius: 16
    readonly property int focusRingWidth: 6
    readonly property real focusScale: 1.06

    // false: changes happen at once, without animation
    property bool motion: true
    readonly property int focusDuration: motion ? 150 : 0
    readonly property int pageDuration: motion ? 250 : 0
}
