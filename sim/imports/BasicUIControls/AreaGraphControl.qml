import QtQuick 2.1

	// qt-gui's AreaGraphControl (C++): a filled area graph of 'values' (NaN = no data), scaled by yScale.
	// colorChangeIndexes switch to color2 from those indexes on (the second tariff), NaN stretches are
	// drawn in colorNaN.
Item {
	id: root
	property var values: []
	property real yScale: 1
	property color color: "#2b8ad8"
	property color color2: color
	property var colorChangeIndexes: []
	property bool showNaN: false
	property color colorNaN: "#cccccc"
	property real opacityNaN: 0.5
	onValuesChanged: c.requestPaint()
	onYScaleChanged: c.requestPaint()
	onColorChanged: c.requestPaint()
	onColor2Changed: c.requestPaint()
	onColorChangeIndexesChanged: c.requestPaint()
	onWidthChanged: c.requestPaint()
	onHeightChanged: c.requestPaint()
	Canvas {
		id: c
		anchors.fill: parent
		onPaint: {
			var ctx = getContext("2d"); ctx.reset();
			var v = root.values || [], n = v.length;
			if (!n) return;
			var step = width / Math.max(1, n - 1);
			var changes = root.colorChangeIndexes || [];
			function colourAt(i) {
				var second = false;
				for (var k = 0; k < changes.length; k++) if (i >= changes[k]) second = !second;
				return second ? root.color2 : root.color;
			}
			for (var i = 0; i < n - 1; i++) {
				var a = v[i], b = v[i + 1];
				var nan = isNaN(a) || isNaN(b);
				if (nan && !root.showNaN) continue;
				ctx.globalAlpha = nan ? root.opacityNaN : 1;
				ctx.fillStyle = nan ? root.colorNaN : colourAt(i);
				var ya = nan ? height : height - a * root.yScale, yb = nan ? height : height - b * root.yScale;
				if (nan) { ya = 0; yb = 0; }
				ctx.beginPath();
				ctx.moveTo(i * step, height); ctx.lineTo(i * step, ya); ctx.lineTo((i + 1) * step, yb); ctx.lineTo((i + 1) * step, height);
				ctx.closePath(); ctx.fill();
			}
		}
	}
}