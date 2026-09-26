import QtQuick 2.1

	// a horizontal (or, taller than wide, vertical) line, optionally dashed
Item {
	id: root
	property color color: "black"
	property real thickness: 1
	property int lineStyle: Qt.SolidLine
	Canvas {
		anchors.fill: parent
		onPaint: {
			var ctx = getContext("2d"); ctx.reset();
			ctx.strokeStyle = root.color; ctx.lineWidth = root.thickness;
			if (root.lineStyle !== Qt.SolidLine && ctx.setLineDash) ctx.setLineDash([root.thickness * 3, root.thickness * 2]);
			ctx.beginPath();
			if (width >= height) { ctx.moveTo(0, height / 2); ctx.lineTo(width, height / 2); }
			else { ctx.moveTo(width / 2, 0); ctx.lineTo(width / 2, height); }
			ctx.stroke();
		}
	}
}
