pragma Singleton
import QtQuick 2.1

	// heating zones (Fiona / smart radiator valves): none in the default simulated home
QtObject {
	property var all: []
	property var _listeners: []
	function byId(id) { for (var i = 0; i < all.length; i++) if (all[i].id === id) return all[i]; return null; }
	function addListener(fn) { _listeners.push(fn); }
	function removeListener(fn) { var i = _listeners.indexOf(fn); if (i >= 0) _listeners.splice(i, 1); }
	function add(z) { all.push(z); }
	function remove(id) { all = all.filter(function (z) { return z.id !== id; }); }
	function updateName(id, name) { var z = byId(id); if (z) z.name = name; }
	function updateSetpoint(id, sp) { var z = byId(id); if (z) z.setpoint = sp; }
}
