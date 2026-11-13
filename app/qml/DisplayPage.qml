import QtQuick
import Rk3568Tv

// Display: the screen's modes, the current one marked. OK on another restarts the app in it; the app then asks to keep
// it, and goes back by itself if nobody answers (the screen may show nothing).
Page {
    id: page

    Text {
        id: status

        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.textBody
        text: DisplaySettings.modes.length === 0 ? qsTr("No screen modes found.") : ""
        visible: text !== ""
        width: parent.width
        wrapMode: Text.WordWrap
    }
    ListView {
        id: list

        anchors.bottom: parent.bottom
        anchors.top: status.visible ? status.bottom : parent.top
        anchors.topMargin: status.visible ? Theme.gap : 0
        clip: true // a long list scrolls inside the safe area
        focus: true
        highlightRangeMode: ListView.ApplyRange
        interactive: false // no flicking: there is no pointer
        keyNavigationEnabled: true // it would follow interactive
        model: DisplaySettings.modes
        objectName: "modes"
        preferredHighlightBegin: 0
        preferredHighlightEnd: list.height
        spacing: Theme.gap / 2
        width: 1100

        delegate: MenuRow {
            required property var modelData

            highlighted: ListView.isCurrentItem && list.activeFocus
            label: modelData.label
            opens: false
            value: modelData.current ? qsTr("now") : ""
            width: list.width
        }

        Keys.onPressed: function (event) {
            event.accepted = RemoteKeys.action(event.key) === RemoteKeys.Ok && list.count > 0;
            if (event.accepted)
                DisplaySettings.choose(DisplaySettings.modes[list.currentIndex].mode);
        }
    }
}
