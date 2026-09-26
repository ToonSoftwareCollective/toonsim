import QtQuick 2.1

	// a square check box with a text; 'selected' is checked, a click flips it
StyledButton {
	id: root
	property real squareOffset: 0
	property real squareRadius: 3
	property real smallSquareRadius: 2
	property color backgroundColor: "white"
	property color checkMarkColor: "#2b8ad8"
	property string fontFamilyUnselected
	property string fontFamilySelected
	property color fontColorSelected: fontColor
	property color squareSelectedColor: "#2b8ad8"
	property color squareUnselectedColor: "#999999"
	property color squareDisabledColor: "#cccccc"
	property color squareBackgroundColor: backgroundColor
	property color squareColor: selected ? squareSelectedColor : squareUnselectedColor
	property real checkMarkStartYOffset: 0
	property real checkMarkStartXOffset: 0
	color: "transparent"
	leftMargin: 30 + squareOffset
	onClicked: if (!controlGroup) { selected = !selected; selectedChangedByUser(); }
	Rectangle {
		x: root.squareOffset; anchors.verticalCenter: parent.verticalCenter
		width: 22; height: 22; radius: root.squareRadius
		color: root.backgroundColor
		border.color: root.enabled ? root.squareColor : root.squareDisabledColor
		border.width: 2
		Text { anchors.centerIn: parent; text: "\u2713"; visible: root.selected; color: root.checkMarkColor; font.pixelSize: 16; font.bold: true }
	}
}
