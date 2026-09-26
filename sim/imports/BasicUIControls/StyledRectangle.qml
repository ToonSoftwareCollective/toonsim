import QtQuick 2.1

	// qt-gui's StyledRectangle (C++): a rectangle whose corners can each be rounded differently
	// (radius x ...RadiusRatio), with an optional (dashed) border, gradient or hatching, and its own
	// touch area that reaches beyond its edges by the ...ClickMargin values. Plain cases are drawn
	// with a Rectangle, the rest with a Canvas.
Item {
	id: root

	enum GradientStyle { NoGradient, TopToBottom, LeftToRight, TopLeftToBottomRight }

	property color color: "transparent"
	property real radius: 0
	property real topLeftRadiusRatio: 1
	property real topRightRadiusRatio: 1
	property real bottomLeftRadiusRatio: 1
	property real bottomRightRadiusRatio: 1
	property color borderColor: "transparent"
	property real borderWidth: 0
	// Qt.SolidLine/DashLine/DotLine or qt-gui's names "SolidLine", "DashLine", "DotLine"
	property var borderStyle: Qt.SolidLine
	readonly property int _borderStyle: (typeof borderStyle === "number") ? borderStyle
		: (String(borderStyle).indexOf("Dash") >= 0 ? Qt.DashLine : String(borderStyle).indexOf("Dot") >= 0 ? Qt.DotLine : Qt.SolidLine)
	property int gradientStyle: 0                 // StyledRectangle.NoGradient / TopToBottom / LeftToRight / TopLeftToBottomRight
	property var gradientColors: []
	property color hatchColor: "transparent"
	property real hatchLineWidth: 0
	property bool bottomLeftArrowVisible: false
	property bool bottomRightArrowVisible: false
	property real horArrowSize: 0
	property real verArrowSize: 0

	property bool mouseEnabled: true          // as qt-gui: the firmware turns it off where it must not click
	property bool mouseIsActiveInDimState: false
	property real leftClickMargin: 0
	property real rightClickMargin: 0
	property real topClickMargin: 0
	property real bottomClickMargin: 0
	property string kpiId
	property bool selected: false

		// membership of a ControlGroup (controlGroup + controlGroupId): a click selects this one
	property var controlGroup: null
	property int controlGroupId: -1
	property string selectionTrigger: "OnClick"
	property string unselectionTrigger: "OnClick"
	property bool manualStateChange: false
	signal selectedChangedByUser()
	property var _joinedGroup: null
	function _join() {
		if (_joinedGroup && _joinedGroup.removeControl) _joinedGroup.removeControl(root);
		_joinedGroup = controlGroup;
		if (controlGroup && controlGroup.addControl) controlGroupId = controlGroup.addControl(root);
	}
	Component.onCompleted: _join()
	onControlGroupChanged: if (_joinedGroup !== null || controlGroup) Qt.callLater(_join)
	Component.onDestruction: if (_joinedGroup && _joinedGroup.removeControl) _joinedGroup.removeControl(root)
	function _groupClick() {
		if (!controlGroup || manualStateChange) return;
		var was = selected;
		if (!selected && selectionTrigger !== "None") controlGroup.selectControl(controlGroupId, true);
		else if (selected && unselectionTrigger === "OnClick" && !controlGroup.exclusive) controlGroup.selectControl(controlGroupId, false);
		if (selected !== was) selectedChangedByUser();
	}
	readonly property bool _mousePressed: mouse.pressed
	readonly property bool containsMouse: mouse.containsMouse

	signal clicked()
	signal pressed()
	signal released()
	signal entered()
	signal exited()
	signal pressAndHold()

	readonly property bool _simple: topLeftRadiusRatio === topRightRadiusRatio && topLeftRadiusRatio === bottomLeftRadiusRatio
		&& topLeftRadiusRatio === bottomRightRadiusRatio && _borderStyle === Qt.SolidLine && gradientStyle === 0
		&& hatchLineWidth <= 0 && !bottomLeftArrowVisible && !bottomRightArrowVisible

	Rectangle {
		anchors.fill: parent
		visible: root._simple
		color: root.color
		radius: Math.min(root.radius * root.topLeftRadiusRatio, Math.min(width, height) / 2)
		border.color: root.borderColor
		border.width: root.borderWidth
	}

	Canvas {
		id: canvas
		anchors.fill: parent
		visible: !root._simple
		onPaint: {
			var ctx = getContext("2d");
			ctx.reset();
			var w = width, h = height, lim = Math.min(w, h) / 2;
			var tl = Math.min(root.radius * root.topLeftRadiusRatio, lim), tr = Math.min(root.radius * root.topRightRadiusRatio, lim);
			var bl = Math.min(root.radius * root.bottomLeftRadiusRatio, lim), br = Math.min(root.radius * root.bottomRightRadiusRatio, lim);
			var bw = root.borderWidth, o = bw / 2;
			ctx.beginPath();
			ctx.moveTo(o + tl, o);
			ctx.lineTo(w - o - tr, o);   ctx.arcTo(w - o, o, w - o, o + tr, tr);
			ctx.lineTo(w - o, h - o - br); ctx.arcTo(w - o, h - o, w - o - br, h - o, br);
			ctx.lineTo(o + bl, h - o);   ctx.arcTo(o, h - o, o, h - o - bl, bl);
			ctx.lineTo(o, o + tl);       ctx.arcTo(o, o, o + tl, o, tl);
			ctx.closePath();
			if (root.gradientStyle && root.gradientColors.length > 1) {
				var g = root.gradientStyle === 2 ? ctx.createLinearGradient(0, 0, w, 0)
					: root.gradientStyle === 3 ? ctx.createLinearGradient(0, 0, w, h) : ctx.createLinearGradient(0, 0, 0, h);
				for (var i = 0; i < root.gradientColors.length; i++) g.addColorStop(i / (root.gradientColors.length - 1), root.gradientColors[i]);
				ctx.fillStyle = g;
			} else {
				ctx.fillStyle = root.color;
			}
			ctx.fill();
			if (root.hatchLineWidth > 0) {
				ctx.save(); ctx.clip();
				ctx.strokeStyle = root.hatchColor; ctx.lineWidth = root.hatchLineWidth;
				for (var x = -h; x < w; x += root.hatchLineWidth * 4) { ctx.beginPath(); ctx.moveTo(x, h); ctx.lineTo(x + h, 0); ctx.stroke(); }
				ctx.restore();
			}
			if (bw > 0) {
				ctx.lineWidth = bw;
				ctx.strokeStyle = root.borderColor;
				if (root._borderStyle === Qt.DashLine) ctx.setLineDash ? ctx.setLineDash([bw * 3, bw * 2]) : null;
				else if (root._borderStyle === Qt.DotLine) ctx.setLineDash ? ctx.setLineDash([bw, bw * 2]) : null;
				ctx.stroke();
			}
		}
	}

	function _repaint() { if (!_simple) canvas.requestPaint(); }
	onColorChanged: _repaint()
	onRadiusChanged: _repaint()
	onBorderColorChanged: _repaint()
	onBorderWidthChanged: _repaint()
	onWidthChanged: _repaint()
	onHeightChanged: _repaint()
	onGradientColorsChanged: _repaint()
	onGradientStyleChanged: _repaint()
	on_SimpleChanged: _repaint()

	MouseArea {
		id: mouse
		enabled: root.mouseEnabled && root.enabled
		x: -root.leftClickMargin
		y: -root.topClickMargin
		width: root.width + root.leftClickMargin + root.rightClickMargin
		height: root.height + root.topClickMargin + root.bottomClickMargin
		hoverEnabled: false
		z: -1
		onClicked: { root._groupClick(); root.clicked(); }
		onPressed: root.pressed()
		onReleased: root.released()
		// entered/exited only while pressed (a finger sliding off and back on), as qt-gui's C++ does.
		// MouseArea also reports "exited" at the end of every touch, after clicked(): passed on, that
		// undoes what a click handler just set (IconButton goes back to "up" on exited)
		onEntered: if (pressed) root.entered()
		onExited: if (pressed) root.exited()
		onPressAndHold: root.pressAndHold()
		onCanceled: root.exited()
	}
}
