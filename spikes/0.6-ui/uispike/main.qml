import QtQuick

// Step 0.6 UI spike: a TV home screen. Throwaway measurement code (see main.cpp).
// Laid out in 1920x1080 units and scaled to the screen, so 1080p and 4K show the same picture at their own
// resolution. Eight rows of 100 poster tiles; the arrow keys move the focus. When the focus rests, the focused
// poster's still fills the background with a cross-fade. The focused tile's frame pulses all the time, so Qt Quick
// draws a new frame on every refresh: the worst case for a TV UI, and what makes frame times measurable.
Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: "#0b0e12"

    readonly property real k: width / 1920   // screen pixels per layout unit
    readonly property int columns: 100
    readonly property var rowNames: ["Continue watching", "Recently added", "Movies", "Series", "Documentaries",
        "Music", "Kids", "Live TV"]
    readonly property var adjectives: ["Midnight", "Silver", "Lost", "Northern", "Hidden", "Electric", "Quiet",
        "Golden", "Wild", "Distant"]
    readonly property var nouns: ["Harbor", "Signal", "Garden", "Frontier", "Echo", "River", "Machine", "Summer",
        "Archive", "Voyage", "Kingdom", "Orbit"]
    readonly property int focusId: rows.currentIndex * columns + (rows.currentItem ? rows.currentItem.column : 0)

    function pad(n, width) { return ("000" + n).slice(-width) }
    function poster(id) { return id * 37 % 120 }
    function thumbUrl(id) { return "file://" + posterDir + "/thumb-" + pad(poster(id) + 1, 3) + ".jpg" }
    function heroUrl(id) { return "file://" + posterDir + "/hero-" + pad(poster(id) % 20 + 1, 2) + ".jpg" }
    function title(id) { return adjectives[id % 10] + " " + nouns[id * 7 % 12] }

    onFocusIdChanged: heroTimer.restart()

    Timer {
        id: heroTimer
        interval: 400
        onTriggered: ui.showHero(win.heroUrl(win.focusId))
    }

    FocusScope {
        id: ui
        width: 1920
        height: 1080
        scale: win.k
        transformOrigin: Item.TopLeft
        focus: true

        // two background layers: the back one loads the next still, then the two cross-fade and swap roles
        property Image front: heroA
        property Image back: heroB

        function showHero(url) {
            if (noStills || noPosters || front.source.toString() === url)
                return
            if (back.source.toString() === url && back.status === Image.Ready)
                swapHero()
            else
                back.source = url
        }
        function swapHero() {
            back.opacity = 1
            front.opacity = 0
            const t = front
            front = back
            back = t
        }

        Component.onCompleted: showHero(win.heroUrl(0))

        Image {
            id: heroA
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(1920 * win.k, 1080 * win.k)
            opacity: 0
            Behavior on opacity { NumberAnimation { duration: 500 } }
            onStatusChanged: if (status === Image.Ready && ui.back === heroA) ui.swapHero()
        }
        Image {
            id: heroB
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(1920 * win.k, 1080 * win.k)
            opacity: 0
            Behavior on opacity { NumberAnimation { duration: 500 } }
            onStatusChanged: if (status === Image.Ready && ui.back === heroB) ui.swapHero()
        }

        Rectangle {   // darken the still towards the rows
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#200b0e12" }
                GradientStop { position: 0.45; color: "#a00b0e12" }
                GradientStop { position: 0.6; color: "#f00b0e12" }
            }
        }
        Rectangle {   // and towards the text on the left
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#e00b0e12" }
                GradientStop { position: 0.6; color: "#000b0e12" }
            }
        }

        Column {
            x: 96
            y: 96
            width: 1000
            spacing: 16
            Text {
                text: win.title(win.focusId)
                color: "white"
                font.pixelSize: 72
                font.bold: true
            }
            Text {
                text: win.rowNames[rows.currentIndex] + "  ·  " + (2000 + win.focusId % 25) + "  ·  "
                      + (1 + win.focusId % 2) + " h " + (10 + win.focusId % 50) + " min"
                color: "#c0c8d0"
                font.pixelSize: 30
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                color: "#a0a8b0"
                font.pixelSize: 28
                text: "A placeholder synopsis, long enough to wrap over two or three lines the way a real one does on "
                      + "a TV home screen, so that the text layout changes with every move of the focus."
            }
        }

        Text {
            id: clock
            anchors.right: parent.right
            anchors.rightMargin: 96
            y: 96
            color: "white"
            font.pixelSize: 40
            text: Qt.formatTime(new Date(), "hh:mm")
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: clock.text = Qt.formatTime(new Date(), "hh:mm")
            }
        }

        ListView {
            id: rows
            y: 500
            width: 1920
            height: 580
            clip: true
            focus: true
            model: win.rowNames.length
            spacing: 10
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: 0
            preferredHighlightEnd: 290
            highlightMoveDuration: 250
            cacheBuffer: 300

            delegate: FocusScope {
                id: row
                required property int index
                readonly property int column: tiles.currentIndex
                width: 1920
                height: 290

                Text {
                    x: 96
                    text: win.rowNames[row.index]
                    color: row.ListView.isCurrentItem ? "white" : "#808890"
                    font.pixelSize: 32
                    font.bold: true
                }

                ListView {
                    id: tiles
                    y: 56
                    width: 1920
                    height: 234
                    orientation: ListView.Horizontal
                    focus: true
                    model: win.columns
                    spacing: 32
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: 96
                    preferredHighlightEnd: 96 + 320
                    highlightMoveDuration: 220
                    cacheBuffer: 704

                    delegate: Item {
                        id: tile
                        required property int index
                        readonly property int itemId: row.index * win.columns + index
                        readonly property bool focused: ListView.isCurrentItem && ListView.view.activeFocus
                        width: 320
                        height: 234
                        z: focused ? 1 : 0

                        Item {
                            width: 320
                            height: 180
                            scale: tile.focused ? 1.12 : 1
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Rectangle {   // shows while the poster loads
                                anchors.fill: parent
                                color: "#1c232b"
                            }
                            Image {
                                anchors.fill: parent
                                source: noPosters ? "" : win.thumbUrl(tile.itemId)
                                asynchronous: true
                                sourceSize: Qt.size(360 * win.k, 203 * win.k)   // the focused size, in screen pixels
                                fillMode: Image.PreserveAspectCrop
                            }
                            Rectangle {   // the focus frame, pulsing
                                anchors.fill: parent
                                anchors.margins: -6
                                visible: tile.focused
                                color: "transparent"
                                border.color: "white"
                                border.width: 5
                                radius: 10
                                SequentialAnimation on opacity {
                                    running: tile.focused
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.5; duration: 700; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                                }
                            }
                        }

                        Text {
                            y: 198
                            width: 320
                            elide: Text.ElideRight
                            text: win.title(tile.itemId)
                            color: tile.focused ? "white" : "#8a949e"
                            font.pixelSize: 24
                        }
                    }
                }
            }
        }
    }
}
