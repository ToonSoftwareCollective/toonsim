import QtQuick 2.1

	// a StyledRectangle with one line of text: centred, or with its baseline at textBaseline from the top
	// (the thermostat panel's setpoint sits low, next to its icon)
StyledRectangle {
	id: root

	// qt-gui's enum; the values are Qt's Text.Align* so both can be passed
	enum Alignment { AlignmentLeft = 1, AlignmentRight = 2, AlignmentCenter = 4 }

	property string text
	property string fontFamily
	property real fontPixelSize: 16
	property color fontColor: "black"
	// StyledValueLabel.Alignment*, qt-gui's names as strings, or Qt's Text.Align* numbers
	property var alignment: StyledValueLabel.AlignmentCenter
	readonly property int _hAlign: (typeof alignment === "number") ? alignment : (String(alignment).indexOf("Right") >= 0 ? Text.AlignRight : String(alignment).indexOf("Center") >= 0 ? Text.AlignHCenter : Text.AlignLeft)
	property real leftMargin: 0
	property real rightMargin: 0
	property real textBaseline: -1          // distance of the text baseline from the top, -1 = centred
	Text {
		id: label
		x: root.leftMargin
		width: root.width - root.leftMargin - root.rightMargin
		y: root.textBaseline >= 0 ? root.textBaseline - baselineOffset : (root.height - height) / 2
		text: root.text
		color: root.fontColor
		font.family: root.fontFamily
		font.pixelSize: root.fontPixelSize
		horizontalAlignment: root._hAlign
		elide: Text.ElideRight
	}
}
