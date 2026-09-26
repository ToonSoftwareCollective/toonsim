import QtQuick 2.1

	// monthly usage per type (elec, gas, heat, solar) with the target per month; qt-gui's C++ fills it from
	// happ_pwrusage. Here the simulated happ_pwrusage gives the targets it has (monthData in
	// sim/devices/happ_pwrusage.js: the expected solar yield per month while the panels are on), once at
	// the start: the apps waiting for it (graph's initVar 8, solar's initVar 1) finish loading on that
	// update. An entry is { year (since 1900, as GraphScreen compares it with getYear()), month (from 0),
	// targetUsage, targetLowUsage, targetCost, targetLowCost }; getMonth takes a Date (year, month).
Item {
	id: root
	property var discoHandler
	property var _months: ({})
	signal monthDataUpdated()
	function getMonths(type) { return _months[type] || []; }
	function getMonth(type, date) {
		var m = getMonths(type), d = new Date(date);
		for (var i = 0; i < m.length; i++)
			if (m[i].year === d.getFullYear() - 1900 && m[i].month === d.getMonth()) return m[i];
		return null;
	}
	function setMonths(type, months) { _months[type] = months; monthDataUpdated(); }
	function _load() {
		var pwr = (typeof simDevices !== "undefined") ? simDevices.byType("happ_pwrusage") : null;
		var all = {};
		["elec", "gas", "heat", "solar"].forEach(function (type) {
			all[type] = pwr && pwr.monthData ? pwr.monthData(pwr, type) : [];
		});
		_months = all;
	}
	// on the next event loop turn: the app is complete by then (its initVars set)
	Timer { interval: 1; running: true; onTriggered: { root._load(); root.monthDataUpdated(); } }
}
