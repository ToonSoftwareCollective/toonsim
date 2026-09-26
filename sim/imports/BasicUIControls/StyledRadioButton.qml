import QtQuick 2.1

	// a round radio button with a text; joins a ControlGroup like StyledButton
StyledButton {
	id: root
	property string caption
	property string description
	property real dotOffset: 0
	property real dotRadius: 12
	property real smallDotRadius: 6
	property color smallDotColor: "transparent"
	property color smallDotShadowColor: "transparent"
	property color smallDotColorSelected: "#2b8ad8"
	property color smallDotShadowColorSelected: "transparent"
	property color backgroundColor: "white"
	property real shadowPixelSizeSmallDot: 0
	text: caption || text
	color: "transparent"
	leftMargin: dotRadius * 2 + spacing + dotOffset
	Rectangle {
		x: root.dotOffset; anchors.verticalCenter: parent.verticalCenter
		width: root.dotRadius * 2; height: width; radius: root.dotRadius
		color: root.backgroundColor; border.color: "#999999"; border.width: 1
		Rectangle {
			anchors.centerIn: parent
			width: root.smallDotRadius * 2; height: width; radius: root.smallDotRadius
			color: root.selected ? root.smallDotColorSelected : root.smallDotColor
		}
	}
}
