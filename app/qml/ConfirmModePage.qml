import QtQuick
import Rk3568Tv

// After a new screen mode: OK keeps it; Back, or nothing for 15 s, goes back to the mode before
Page {
    id: page

    property int secondsLeft: 15

    title: qsTr("Keep this screen mode?")

    Keys.onPressed: function (event) {
        const action = RemoteKeys.action(event.key);
        event.accepted = action === RemoteKeys.Ok || action === RemoteKeys.Back || action === RemoteKeys.Home;
        if (action === RemoteKeys.Ok) {
            DisplaySettings.keep();
            page.stack.pop();
        } else if (event.accepted) {
            DisplaySettings.revert();
        }
    }

    Text {
        color: Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.textBody
        text: qsTr("%1\n\nOK keeps it. Back, or no answer within %2 s, goes back to the one before.").arg(DisplaySettings.current).arg(page.secondsLeft)
        width: parent.width
        wrapMode: Text.WordWrap
    }
    Timer {
        interval: 1000
        repeat: true
        running: page.secondsLeft > 0

        onTriggered: {
            page.secondsLeft -= 1;
            if (page.secondsLeft <= 0)
                DisplaySettings.revert();
        }
    }
}
