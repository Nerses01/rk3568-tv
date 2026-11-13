import QtQuick
import QtMultimedia

// Step 0.5 video spike. The same live UI is drawn over the video in every candidate: a caption and a
// rotating, half-transparent square, so the scene graph redraws every frame (the worst case for a TV UI).
Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: candidate === "a" ? "black" : "transparent"

    Loader {
        anchors.fill: parent
        active: candidate === "a"
        sourceComponent: Item {
            MediaPlayer {
                id: player
                source: clipUrl
                videoOutput: vo
                onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) stats.finish()
                onErrorOccurred: (error, errorString) => { console.log("player error:", errorString); stats.finish() }
            }
            VideoOutput {
                id: vo
                anchors.fill: parent
            }
            Component.onCompleted: {
                stats.watchSink(vo.videoSink)
                player.play()
                stats.start()
            }
        }
    }

    Rectangle {
        width: 240
        height: 240
        radius: 24
        color: "#80ffffff"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 80
        RotationAnimation on rotation {
            from: 0
            to: 360
            duration: 4000
            loops: Animation.Infinite
        }
    }

    Text {
        x: 60
        y: 60
        color: "white"
        style: Text.Outline
        font.pixelSize: 36
        text: "candidate " + candidate.toUpperCase() + "   " + clipName
    }
}
