import QtQuick
import Rk3568Tv

// Settings: a list, up and down to choose, OK to open. Wi-Fi, Bluetooth and display arrive in step 1.6.
Page {
    id: settings

    readonly property var entries: [{
            "label": qsTr("Wi-Fi"),
            "page": notYetPage
        }, {
            "label": qsTr("Bluetooth"),
            "page": notYetPage
        }, {
            "label": qsTr("Display"),
            "value": qsTr("%1 × %2").arg(Screen.width).arg(Screen.height),
            "page": notYetPage
        }, {
            "label": qsTr("About"),
            "page": aboutPage
        }]

    ListView {
        id: rows

        focus: true
        height: rows.contentHeight
        interactive: false // no flicking: there is no pointer
        keyNavigationEnabled: true // it would follow interactive
        model: settings.entries
        objectName: "rows"
        spacing: Theme.gap / 2
        width: 1100

        delegate: MenuRow {
            required property var modelData

            highlighted: ListView.isCurrentItem && rows.activeFocus
            label: modelData.label
            value: modelData.value || ""
            width: rows.width
        }

        // OK opens the entry; every other key goes on to the list (the arrows) and the window (Back, Home)
        Keys.onPressed: function (event) {
            event.accepted = RemoteKeys.action(event.key) === RemoteKeys.Ok;
            if (!event.accepted)
                return;
            const entry = settings.entries[rows.currentIndex];
            settings.stack.push(entry.page, {
                    "title": entry.label
                });
        }
    }
    Component {
        id: notYetPage

        NotYetPage {
        }
    }
    Component {
        id: aboutPage

        AboutPage {
        }
    }
}
