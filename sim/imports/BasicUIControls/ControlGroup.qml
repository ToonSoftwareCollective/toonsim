import QtQuick 2.1

	// qt-gui's ControlGroup (C++): buttons join with controlGroup: <group> and controlGroupId: <n>
	// (a button without an id gets the next free one); currentControlId is the selected one
	// (exclusive: at most one), -1 for none
Item {
	id: group
	property bool exclusive: true
	property int currentControlId: -1
	property var _controls: ({})
	signal currentControlIdChangedByUser()

	function addControl(c) {
		var id = c.controlGroupId;
		if (id === undefined || id < 0) { id = 0; while (_controls[id]) id++; }
		_controls[id] = c;
		c.selected = (id === currentControlId);
		return id;
	}
	function removeControl(c) {
		for (var k in _controls) if (_controls[k] === c) delete _controls[k];
	}
	function selectControl(id, select) {
		if (select) {
			if (exclusive) for (var k in _controls) if (Number(k) !== id) _controls[k].selected = false;
			if (_controls[id]) _controls[id].selected = true;
			if (currentControlId !== id) { currentControlId = id; currentControlIdChangedByUser(); }
		} else {
			if (_controls[id]) _controls[id].selected = false;
			if (currentControlId === id) { currentControlId = -1; currentControlIdChangedByUser(); }
		}
	}
	// selecting from code (the graph screen restoring its tabs): no currentControlIdChangedByUser
	function setControlSelectState(id, select) {
		if (select) currentControlId = id;
		else if (currentControlId === id) currentControlId = -1;
	}
	function getControl(id) { return _controls[id] || null; }
	function getSelectedControl() { return _controls[currentControlId] || null; }
	onCurrentControlIdChanged: {
		for (var k in _controls) _controls[k].selected = (Number(k) === currentControlId);
	}
}