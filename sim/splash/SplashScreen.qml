import QtQuick 2.1

Item {
	id: splash
	anchors.fill: parent
	width: parent ? parent.width : (isNxt ? 1024 : 800)
	height: parent ? parent.height : (isNxt ? 600 : 480)
	z: 999999

	property int progress: qtUtils ? qtUtils.splashProgress : 0
	property bool isDismissed: false

	// Background color matches the modern Quby bootsplash
	Rectangle {
		anchors.fill: parent
		color: "#000000"
	}

	Image {
		id: splashImage
		anchors.fill: parent
		fillMode: Image.PreserveAspectFit
		source: isNxt ? "psplash-quby-nxt.png" : "psplash-quby.png"
		smooth: true
	}

	// Progress bar container
	Item {
		id: progressContainer
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.bottom: parent.bottom
		anchors.bottomMargin: isNxt ? 50 : 40
		width: isNxt ? 420 : 320
		height: isNxt ? 24 : 20

		// Background track
		Rectangle {
			anchors.fill: parent
			radius: 6
			color: "#1e1e1e"
			border.color: "#444444"
			border.width: 2

			// Filled bar
			Rectangle {
				id: fillBar
				anchors.left: parent.left
				anchors.top: parent.top
				anchors.bottom: parent.bottom
				anchors.margins: 2
				radius: 4
				color: "#ffffff"
				width: Math.max(0, Math.min(parent.width - 4, (parent.width - 4) * (splash.progress / 100.0)))

				Behavior on width {
					NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
				}
			}
		}
	}

	function dismiss() {
		if (isDismissed) return;
		isDismissed = true;
		fadeAnim.start();
	}

	NumberAnimation {
		id: fadeAnim
		target: splash
		property: "opacity"
		to: 0.0
		duration: 350
		easing.type: Easing.InOutQuad
		onStopped: {
			splash.visible = false;
			splash.enabled = false;
		}
	}

	Connections {
		target: qtUtils
		ignoreUnknownSignals: true
		onPsplashProgressChanged: {
			// Boot progress must strictly move forward, never backward
			if (progress > splash.progress) {
				splash.progress = progress;
			}
		}
		onPsplashQuitRequested: {
			splash.progress = 100;
			splash.dismiss();
		}
	}

	// Safety fallback: dismiss after 15 seconds if psplashQuit is never received
	Timer {
		interval: 15000
		running: true
		repeat: false
		onTriggered: splash.dismiss()
	}

	// Click to dismiss for development / testing
	MouseArea {
		anchors.fill: parent
		onClicked: splash.dismiss()
	}
}
