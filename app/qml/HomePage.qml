import QtQuick
import Rk3568Tv

// Home: one tile per section, left and right to choose, OK to open. More sections join as they arrive: USB drives
// (step 1.5), online sources (Phase 2).
Page {
    id: home

    readonly property var sections: [{
            "symbol": "▶",
            "label": qsTr("Videos"),
            "detail": qsTr("On this box and on USB drives"),
            "page": videosPage
        }, {
            "symbol": "⚙",
            "label": qsTr("Settings"),
            "detail": qsTr("Wi-Fi, Bluetooth, display, about"),
            "page": settingsPage
        }]

    title: Qt.application.name

    ListView {
        id: tiles

        anchors.centerIn: parent
        focus: true
        height: 320
        interactive: false // no flicking: there is no pointer
        keyNavigationEnabled: true // it would follow interactive
        model: home.sections
        objectName: "tiles"
        orientation: ListView.Horizontal
        spacing: 2 * Theme.gap
        width: tiles.contentWidth

        delegate: Tile {
            required property var modelData

            detail: modelData.detail
            highlighted: ListView.isCurrentItem && tiles.activeFocus
            label: modelData.label
            symbol: modelData.symbol
        }

        // OK opens the section; every other key goes on to the list (the arrows) and the window (Back, Home)
        Keys.onPressed: function (event) {
            event.accepted = RemoteKeys.action(event.key) === RemoteKeys.Ok;
            if (!event.accepted)
                return;
            const section = home.sections[tiles.currentIndex];
            home.stack.push(section.page, {
                    "title": section.label
                });
        }
    }
    Component {
        id: videosPage

        VideosPage {
        }
    }
    Component {
        id: settingsPage

        SettingsPage {
        }
    }
}
