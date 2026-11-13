import QtQuick
import Rk3568Tv

// The time, in the locale's short format
Text {
    id: clock

    property date now: new Date()

    Accessible.name: clock.text
    Accessible.role: Accessible.StaticText
    color: Theme.textSecondary
    font.family: Theme.fontFamily
    font.pixelSize: Theme.textHeading
    text: Qt.formatTime(clock.now, Qt.locale().timeFormat(Locale.ShortFormat))

    Timer {
        interval: 1000
        repeat: true
        running: clock.visible
        onTriggered: clock.now = new Date()
    }
}
