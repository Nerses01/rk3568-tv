import QtQuick
import Rk3568Tv

// Wi-Fi: the networks in range, the joined one first. OK on a new network asks for its password; on a known one it
// offers to join or forget it. The first row searches again.
Page {
    id: page

    readonly property var rows: [{
            "label": Wifi.busy ? qsTr("Searching…") : qsTr("Search again"),
            "value": "",
            "network": null
        }].concat(Wifi.networks.map(function (network) {
                return {
                    "label": network.ssid,
                    "value": network.active ? qsTr("connected") : network.saved ? qsTr("known") : network.signal + " %" + (network.secured ? "" : qsTr(", open")),
                    "network": network
                };
            }))

    Component.onCompleted: Wifi.scan()

    Text {
        id: status

        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.textBody
        text: Wifi.message
        width: parent.width
        wrapMode: Text.WordWrap
    }
    ListView {
        id: list

        anchors.bottom: parent.bottom
        anchors.top: status.bottom
        anchors.topMargin: Theme.gap
        clip: true // a long list scrolls inside the safe area
        focus: true
        highlightRangeMode: ListView.ApplyRange
        interactive: false // no flicking: there is no pointer
        keyNavigationEnabled: true // it would follow interactive
        model: page.rows
        objectName: "networks"
        preferredHighlightBegin: 0
        preferredHighlightEnd: list.height
        spacing: Theme.gap / 2
        width: 1100

        delegate: MenuRow {
            required property var modelData

            highlighted: ListView.isCurrentItem && list.activeFocus
            label: modelData.label
            value: modelData.value
            width: list.width
        }

        Keys.onPressed: function (event) {
            event.accepted = RemoteKeys.action(event.key) === RemoteKeys.Ok;
            if (!event.accepted)
                return;
            const network = page.rows[list.currentIndex].network;
            if (!network)
                Wifi.scan();
            else if (network.saved || network.active)
                page.stack.push(choicesPage, {
                        "title": network.ssid,
                        "choices": [{
                                "label": qsTr("Join"),
                                "run": function () {
                                    Wifi.join(network.ssid, "");
                                }
                            }, {
                                "label": qsTr("Forget"),
                                "run": function () {
                                    Wifi.forget(network.ssid);
                                }
                            }],
                        "text": network.active ? qsTr("The box is on this network. Forgetting it leaves it.") : ""
                    });
            else if (network.secured)
                page.stack.push(passwordPage, {
                        "title": network.ssid
                    });
            else
                Wifi.join(network.ssid, "");
        }
    }
    Component {
        id: choicesPage

        ChoicesPage {
        }
    }
    Component {
        id: passwordPage

        PasswordPage {
        }
    }
}
