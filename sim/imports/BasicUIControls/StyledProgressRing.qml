import QtQuick 2.1

	// a ring filled clockwise to 'value' (0..1)
Item {
	id: root
	property color backgroundColor: "#dddddd"
	property color fillColor: "#2b8ad8"
	property real radius: 20
	property real thickness: 4
	property real gap: 0
	property real value: 0
	property bool mouseEnabled: false
	width: radius * 2; height: radius * 2
	onValueChanged: ring.requestPaint()
	Canvas {
		id: ring
		anchors.fill: parent
		onPaint: {
			var ctx = getContext("2d"); ctx.reset();
			var r = root.radius - root.thickness / 2;
			ctx.lineWidth = root.thickness;
			ctx.strokeStyle = root.backgroundColor;
			ctx.beginPath(); ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI); ctx.stroke();
			ctx.strokeStyle = root.fillColor;
			ctx.beginPath(); ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * root.value); ctx.stroke();
		}
	}
}
