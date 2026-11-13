import QtQuick
import Rk3568Tv

// Bluetooth: the paired devices first, then the ones found. The first row searches; OK on a new device pairs it (it
// must be in pairing mode), on a paired one offers to connect, disconnect or forget it.
Page {
    id: page

    readonly property var rows: [{
            "label": Bluetooth.busy ? qsTr("Busy…") : qsTr("Search for devices"),
            "value": "",
            "device": null
        }].concat(Bluetooth.devices.map(function (device) {
                return {
                    "label": device.name,
                    "value": device.connected ? qsTr("connected") : device.paired ? qsTr("paired") : "",
                    "device": device
                };
            }))

    Component.onCompleted: Bluetooth.refresh()

    Text {
        id: status

        color: Theme.textSecondary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.textBody
        text: Bluetooth.message
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
        objectName: "devices"
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
            const device = page.rows[list.currentIndex].device;
            if (!device) {
                Bluetooth.scan();
            } else if (!device.paired) {
                Bluetooth.pair(device.address);
            } else {
                page.stack.push(choicesPage, {
                        "title": device.name,
                        "choices": [device.connected ? {
                                "label": qsTr("Disconnect"),
                                "run": function () {
                                    Bluetooth.disconnectDevice(device.address);
                                }
                            } : {
                                "label": qsTr("Connect"),
                                "run": function () {
                                    Bluetooth.connectDevice(device.address);
                                }
                            }, {
                                "label": qsTr("Forget"),
                                "run": function () {
                                    Bluetooth.forget(device.address);
                                }
                            }]
                    });
            }
        }
    }
    Component {
        id: choicesPage

        ChoicesPage {
        }
    }
}
