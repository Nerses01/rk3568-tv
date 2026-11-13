import QtQuick
import Rk3568Tv // the module's own types: in Qt 6.2 a file in qml/ doesn't see them without it

// The app's window: its pages, laid out in 1920x1080 units and scaled to the screen. Back and Home work on every
// page; a key no page takes goes to the log, which helps to find the codes of the TV's remote (step 1.7).
Window {
    id: window

    readonly property alias pages: pages
    readonly property real unitScale: Math.min(window.width / Theme.width, window.height / Theme.height)

    color: Theme.background
    title: Qt.application.name
    visibility: Window.FullScreen
    visible: true

    FocusScope {
        focus: true
        height: Theme.height
        scale: window.unitScale
        transformOrigin: Item.TopLeft
        width: Theme.width
        x: (window.width - Theme.width * window.unitScale) / 2
        y: (window.height - Theme.height * window.unitScale) / 2

        Keys.onPressed: function (event) {
            const action = RemoteKeys.action(event.key);
            if (action === RemoteKeys.Back) {
                event.accepted = pages.pop();
            } else if (action === RemoteKeys.Home) {
                pages.popToFirst();
                event.accepted = true;
            } else if (action === RemoteKeys.None) {
                console.info("a key without an action: 0x" + event.key.toString(16));
            }
        }

        PageStack {
            id: pages

            anchors.fill: parent

            Component.onCompleted: pages.push(homePage)
        }
        Component {
            id: homePage

            HomePage {
            }
        }
    }
}
