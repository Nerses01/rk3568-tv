import QtQuick
import Rk3568Tv

// Videos: every video file in the media folder, up and down to choose, OK to play. Step 1.5 adds USB drives and
// folders.
Page {
    id: videos

    readonly property var files: VideoLibrary.videos()

    Text {
        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.textBody
        text: qsTr("No videos in %1").arg(VideoLibrary.folder)
        visible: videos.files.length === 0
        width: parent.width
        wrapMode: Text.WordWrap
    }
    ListView {
        id: list

        anchors.fill: parent
        clip: true // a long list scrolls inside the safe area
        focus: true
        highlightRangeMode: ListView.ApplyRange
        interactive: false // no flicking: there is no pointer
        keyNavigationEnabled: true // it would follow interactive
        model: videos.files
        objectName: "videos"
        preferredHighlightBegin: 0
        preferredHighlightEnd: list.height
        spacing: Theme.gap / 2

        delegate: MenuRow {
            required property var modelData

            highlighted: ListView.isCurrentItem && list.activeFocus
            label: modelData.name
            value: modelData.place
            width: list.width
        }

        // OK plays the video; every other key goes on to the list (the arrows) and the window (Back, Home)
        Keys.onPressed: function (event) {
            event.accepted = RemoteKeys.action(event.key) === RemoteKeys.Ok && list.count > 0;
            if (!event.accepted)
                return;
            const file = videos.files[list.currentIndex];
            videos.stack.push(playerPage, {
                    "title": file.name,
                    "source": file.path
                });
        }
    }
    Component {
        id: playerPage

        PlayerPage {
        }
    }
}
