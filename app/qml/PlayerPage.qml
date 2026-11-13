import QtQuick
import Rk3568Tv

// Plays one video on the whole screen. OK or Play/Pause pauses; left and right go back 10 s and on 30 s; up changes
// the sound track, down the subtitles; Back stops and goes back, and the video goes on from there next time. The
// information shows for a few seconds after a key, and while paused.
Page {
    id: page

    property alias source: player.source

    // 75000 -> "1:15", 3675000 -> "1:01:15"
    function clock(ms) {
        const seconds = Math.floor(Math.max(0, ms) / 1000);
        const h = Math.floor(seconds / 3600);
        const m = Math.floor(seconds / 60) % 60;
        const s = seconds % 60;
        const two = function (n) {
            return n < 10 ? "0" + n : "" + n;
        };
        return (h > 0 ? h + ":" + two(m) : "" + m) + ":" + two(s);
    }

    function showInfo() {
        hideInfo.restart();
        info.visible = true;
    }

    chrome: false

    Keys.onPressed: function (event) {
        const action = RemoteKeys.action(event.key);
        event.accepted = true;
        if (action === RemoteKeys.Ok || action === RemoteKeys.PlayPause)
            player.togglePause();
        else if (action === RemoteKeys.Left)
            player.seekBy(-10000);
        else if (action === RemoteKeys.Right)
            player.seekBy(30000);
        else if (action === RemoteKeys.Up && player.audioTracks.length > 1)
            player.audioTrack = (player.audioTrack + 1) % player.audioTracks.length;
        else if (action === RemoteKeys.Down && player.subtitleTracks.length > 0)
            player.subtitleTrack = player.subtitleTrack + 1 < player.subtitleTracks.length ? player.subtitleTrack + 1 : -1;
        else
            event.accepted = false; // Back and Home go to the window
        page.showInfo();
    }

    VideoPlayer {
        id: player

        anchors.fill: parent
        objectName: "player"

        onStatusChanged: {
            if (player.status === VideoPlayer.Ended)
                page.stack.pop();
            else
                page.showInfo();
        }
    }
    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.safeY + 2 * Theme.gap
        anchors.horizontalCenter: parent.horizontalCenter
        color: Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.textHeading
        horizontalAlignment: Text.AlignHCenter
        style: Text.Outline
        styleColor: Theme.background
        text: player.subtitleText
        textFormat: Text.StyledText
        width: Theme.width - 2 * Theme.safeX
        wrapMode: Text.WordWrap
    }
    Timer {
        id: hideInfo

        interval: 4000
        onTriggered: info.visible = player.status !== VideoPlayer.Playing
    }
    Column {
        id: info

        spacing: Theme.gap
        width: Theme.width - 2 * Theme.safeX
        x: Theme.safeX
        y: Theme.safeY

        Text {
            color: Theme.textPrimary
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.textHeading
            style: Text.Outline
            styleColor: Theme.background
            text: page.title
            width: parent.width
        }
        Text {
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.textBody
            objectName: "state"
            style: Text.Outline
            styleColor: Theme.background
            text: {
                switch (player.status) {
                case VideoPlayer.Loading:
                    return qsTr("Loading…");
                case VideoPlayer.Paused:
                    return qsTr("Paused  %1 / %2").arg(page.clock(player.position)).arg(page.clock(player.duration));
                case VideoPlayer.Failed:
                    return qsTr("Can't play this video: %1").arg(player.errorString);
                default:
                    return qsTr("%1 / %2").arg(page.clock(player.position)).arg(page.clock(player.duration));
                }
            }
            width: parent.width
            wrapMode: Text.WordWrap
        }
        Text {
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.textCaption
            style: Text.Outline
            styleColor: Theme.background
            text: qsTr("Sound: %1 · Subtitles: %2").arg(player.audioTrack >= 0 ? player.audioTracks[player.audioTrack] : qsTr("none")).arg(player.subtitleTrack >= 0 ? player.subtitleTracks[player.subtitleTrack] : qsTr("off"))
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }
}
