import QtQuick 2.1

	// a text field look-alike with a blinking cursor at the end (the on-screen keyboards type into it)
StyledRectangle {
	id: root
	property string text
	property string fontFamily
	property real fontPixelSize: 16
	property color fontColor: "black"
	property real leftMargin: 8
	property real rightMargin: 8
	// qt-gui's names ("AlignmentLeft", "AlignmentCenter", "AlignmentRight") or Qt's Text.Align* numbers
	property var alignment: "AlignmentLeft"
	readonly property int _hAlign: (typeof alignment === "number") ? alignment : (String(alignment).indexOf("Right") >= 0 ? Text.AlignRight : String(alignment).indexOf("Center") >= 0 ? Text.AlignHCenter : Text.AlignLeft)
	property real cursorHeight: fontPixelSize
	property bool cursorActivated: true
	property real maxTextWidth: 0
	property int maxTextLength: 0
	Text {
		id: t
		anchors.fill: parent; anchors.leftMargin: root.leftMargin; anchors.rightMargin: root.rightMargin
		text: root.text; color: root.fontColor; font.family: root.fontFamily; font.pixelSize: root.fontPixelSize
		horizontalAlignment: root._hAlign; verticalAlignment: Text.AlignVCenter; elide: Text.ElideLeft
	}
	Rectangle {
		width: 2; height: root.cursorHeight; color: root.fontColor
		anchors.verticalCenter: parent.verticalCenter
		x: Math.min(root.width - root.rightMargin, root.leftMargin + t.contentWidth + 1)
		visible: root.cursorActivated && blink.on
		Timer { id: blink; property bool on: true; interval: 500; repeat: true; running: root.cursorActivated; onTriggered: on = !on }
	}
}
