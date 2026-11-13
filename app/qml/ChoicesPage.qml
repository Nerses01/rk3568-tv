import QtQuick
import Rk3568Tv

// A short list of actions, such as "Connect" and "Forget" for one device: OK runs the chosen one and goes back
Page {
    id: page

    // each: label, and run, a function
    property var choices: []
    property string text

    Column {
        spacing: Theme.gap
        width: parent.width

        Text {
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Theme.textBody
            text: page.text
            visible: page.text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
        }
        ListView {
            id: list

            focus: true
            height: list.contentHeight
            interactive: false // no flicking: there is no pointer
            keyNavigationEnabled: true // it would follow interactive
            model: page.choices
            objectName: "choices"
            spacing: Theme.gap / 2
            width: 1100

            delegate: MenuRow {
                required property var modelData

                highlighted: ListView.isCurrentItem && list.activeFocus
                label: modelData.label
                opens: false
                width: list.width
            }

            Keys.onPressed: function (event) {
                event.accepted = RemoteKeys.action(event.key) === RemoteKeys.Ok && list.count > 0;
                if (!event.accepted)
                    return;
                const choice = page.choices[list.currentIndex];
                page.stack.pop();
                choice.run();
            }
        }
    }
}
