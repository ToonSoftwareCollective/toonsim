import QtQuick 2.1

	// qt-gui's StyledToggle (C++): an on/off slider with one state under three names:
	// isSwitchedOn, selected (the same) and positionIsLeft (where the knob is; on is on the right
	// unless leftIsSwitchedOn). A click flips it and reports selectedChangedByUser().
	// Texts: useOnOffTexts -> leftTextOn/Off and rightTextOn/Off follow the state (OnOffToggle);
	// otherwise leftText/rightText stay, the active side in bold (OptionToggle).
StyledRectangle {
	id: root
	property bool isSwitchedOn: false
	property bool positionIsLeft: !(isSwitchedOn !== leftIsSwitchedOn)
	property bool leftIsSwitchedOn: false
	property bool useOnOffTexts: false
	property bool incorporateTextsInSize: false
	property bool useBoldChangeForLeftRight: false
	property string leftText
	property string rightText
	property string leftTextOn: leftText
	property string leftTextOff: leftText
	property string rightTextOn: rightText
	property string rightTextOff: rightText
	property real shadowPixelSize: 0
	property real sliderWidth: 46
	property real sliderHeight: 24
	property real knobWidth: 20
	property color backgroundColorKnob: "white"
	property color shadowColorKnob: "#80000000"
	property color backgroundColorLeft: "#cccccc"
	property color shadowColorLeft: "#999999"
	property color backgroundColorRight: "#5ca33f"
	property color shadowColorRight: "#3f7a2a"
	property string fontFamily
	property real fontPixelSize: 16
	property color fontColor: "black"
	property real leftSpacing: 8
	property real rightSpacing: 8
	property real topSpacing: 0
	property real bottomSpacing: 0
	readonly property bool _knobRight: isSwitchedOn !== leftIsSwitchedOn
	signal isSwitchedOnChangedByUser()

		// keep the three names of the one state in step
	onSelectedChanged: if (selected !== isSwitchedOn) isSwitchedOn = selected
	onIsSwitchedOnChanged: {
		if (selected !== isSwitchedOn) selected = isSwitchedOn;
		if (positionIsLeft !== !_knobRight) positionIsLeft = !_knobRight;
	}
	onPositionIsLeftChanged: { var on = (positionIsLeft === leftIsSwitchedOn); if (on !== isSwitchedOn) isSwitchedOn = on; }

	mouseEnabled: true
	color: "transparent"
	implicitWidth: ((leftLabel.text || rightLabel.text) ? leftLabel.width + leftSpacing + rightLabel.width + rightSpacing : 0) + sliderWidth
	implicitHeight: sliderHeight
	width: implicitWidth
	height: implicitHeight
	onClicked: { isSwitchedOn = !isSwitchedOn; selectedChangedByUser(); isSwitchedOnChangedByUser(); }

	Text {
		id: leftLabel
		anchors.verticalCenter: parent.verticalCenter
		text: root.useOnOffTexts ? (root.isSwitchedOn ? root.leftTextOn : root.leftTextOff) : root.leftText
		font.family: root.fontFamily; font.pixelSize: root.fontPixelSize; color: root.fontColor
		font.bold: root.useBoldChangeForLeftRight && !root._knobRight
	}
	Rectangle {
		id: track
		x: leftLabel.text ? leftLabel.width + root.leftSpacing : 0
		anchors.verticalCenter: parent.verticalCenter
		width: root.sliderWidth; height: root.sliderHeight; radius: height / 2
		color: root._knobRight ? root.backgroundColorRight : root.backgroundColorLeft
		Rectangle {
			width: root.knobWidth; height: root.sliderHeight - 4; radius: height / 2
			y: 2
			x: root._knobRight ? track.width - width - 2 : 2
			color: root.backgroundColorKnob
			Behavior on x { NumberAnimation { duration: 120 } }
		}
	}
	Text {
		id: rightLabel
		anchors.verticalCenter: parent.verticalCenter
		x: track.x + track.width + root.rightSpacing
		text: root.useOnOffTexts ? (root.isSwitchedOn ? root.rightTextOn : root.rightTextOff) : root.rightText
		font.family: root.fontFamily; font.pixelSize: root.fontPixelSize; color: root.fontColor
		font.bold: root.useBoldChangeForLeftRight && root._knobRight
	}
}