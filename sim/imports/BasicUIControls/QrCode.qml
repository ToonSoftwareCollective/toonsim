import QtQuick 2.1

	// qt-gui draws a real QR code here; the simulator shows a placeholder with the content
Rectangle {
	property string content
	color: "white"
	border.color: "#999999"
	Text { anchors.fill: parent; anchors.margins: 4; text: "QR\n" + parent.content; wrapMode: Text.WrapAnywhere; font.pixelSize: 9; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
}
