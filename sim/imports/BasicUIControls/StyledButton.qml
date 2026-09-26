import QtQuick 2.1
import QtGraphicalEffects 1.0

	// qt-gui's StyledButton (C++): a StyledRectangle with a label and/or icon that sizes itself to its
	// content, press/release/click signals, membership of a ControlGroup (selected), and long-press
	// repeat (timerEnabled: clicked() repeats while held, speeding up with 'acceleration').
	// The colours per state are set by the QML that extends it (StandardButton, IconButton, ...).
StyledRectangle {
	id: root

	property string text
	property url iconSource
	property string fontFamily
	property real fontPixelSize: 16
	property color fontColor: "black"
	property color overlayColor: fontColor
	property bool useOverlayColor: false
	property real leftMargin: 10
	property real rightMargin: 10
	property real spacing: 10
	property real defaultHeight: 36
	property real minWidth: 0
	property bool timerEnabled: false
	property int longPressStartTime: 500
	property int longPressIntervalTime: 100
	property int pressingEndTime: 0
	property real acceleration: 1.0
	property bool useExtension: false
	property real extensionHeight: 0
	property bool bottomTab: false
	property alias iconItem: icon
	property alias textItem: label

	mouseEnabled: true
	implicitHeight: defaultHeight
	implicitWidth: Math.max(minWidth, leftMargin + (icon.visible ? icon.width : 0)
		+ (icon.visible && label.text ? spacing : 0) + (label.text ? label.implicitWidth : 0) + rightMargin)
	width: implicitWidth
	height: implicitHeight

	signal longPressed()
	signal longPressInterval()
	signal pressingEnded()

	// pressingEnded comes pressingEndTime ms after the last release (so taps add up, as on the setpoint
	// spinner), or at the release itself when pressingEndTime is 0; discardPressingEndTime() drops a
	// pending one (the spinner's other button was pressed)
	function discardPressingEndTime() { endTimer.stop(); }

	property bool _pressing: false
	onPressed: {
		_pressing = true;
		endTimer.stop();
		if (timerEnabled) { repeat.interval = longPressStartTime; repeat.count = 0; repeat.start(); }
	}
	onReleased: _endPressing()
	onExited: _endPressing()
	function _endPressing() {
		if (!_pressing) return;
		_pressing = false;
		repeat.stop();
		if (pressingEndTime > 0) endTimer.restart();
		else pressingEnded();
	}

	Timer {
		id: endTimer
		interval: Math.max(1, root.pressingEndTime)
		onTriggered: root.pressingEnded()
	}

	Timer {
		id: repeat
		property int count: 0
		repeat: true
		onTriggered: {
			count++;
			interval = Math.max(20, root.longPressIntervalTime / Math.pow(root.acceleration, count / 10));
			root.longPressInterval();
			root.longPressed();
		}
	}

	Row {
		anchors.centerIn: parent
		spacing: (icon.visible && label.text) ? root.spacing : 0

		Item {
			width: icon.visible ? icon.width : 0
			height: icon.height
			anchors.verticalCenter: parent.verticalCenter
			Image {
				id: icon
				source: root.iconSource
				visible: root.iconSource != ""
				opacity: root.useOverlayColor ? 0 : 1
			}
			ColorOverlay {
				anchors.fill: icon
				source: icon
				color: root.overlayColor
				visible: icon.visible && root.useOverlayColor
			}
		}

		Text {
			id: label
			text: root.text
			visible: text !== ""
			color: root.fontColor
			font.family: root.fontFamily
			font.pixelSize: root.fontPixelSize
			anchors.verticalCenter: parent.verticalCenter
		}
	}
}
