import QtQuick 2.1

	// the graphs' date helpers (C++ in qt-gui); the instance is the context property graphUtils
QtObject {
	enum Period { PERIOD_HOURS, PERIOD_DAYS, PERIOD_WEEKS, PERIOD_MONTHS, PERIOD_YEARS }

	function _pad(n) { return (n < 10 ? "0" : "") + n; }
	// local time with its offset, as the insights requests take it: 2026-09-23T00:00:00+02:00
	function dateToISOString(d) {
		d = new Date(d);
		var off = -d.getTimezoneOffset(), a = Math.abs(off);
		return d.getFullYear() + "-" + _pad(d.getMonth() + 1) + "-" + _pad(d.getDate()) + "T"
			+ _pad(d.getHours()) + ":" + _pad(d.getMinutes()) + ":" + _pad(d.getSeconds())
			+ (off < 0 ? "-" : "+") + _pad(Math.floor(a / 60)) + ":" + _pad(a % 60);
	}
	function dayStart(d) { d = new Date(d); d.setHours(0, 0, 0, 0); return d; }
	function weekNumber(d) {
		d = new Date(d); d.setHours(0, 0, 0, 0);
		d.setDate(d.getDate() + 3 - (d.getDay() + 6) % 7);
		var w1 = new Date(d.getFullYear(), 0, 4);
		return 1 + Math.round(((d - w1) / 86400000 - 3 + (w1.getDay() + 6) % 7) / 7);
	}
	function _monday(d) { d = dayStart(d); d.setDate(d.getDate() - (d.getDay() + 6) % 7); return d; }
	// { startDate, endDate } (end exclusive) of what the graph screen shows at interval 'period' for the
	// date selector's period starting at 'date': hours -> that day, days -> its week (Monday first),
	// weeks -> the 6 weeks up to the end of its month, months -> its year, years -> the last 6 years
	function getFromToISODate(period, date) {
		var s = dayStart(date), e;
		switch (period) {
		case 0: e = new Date(s); e.setDate(e.getDate() + 1); break;
		case 1: s = _monday(s); e = new Date(s); e.setDate(e.getDate() + 7); break;
		case 2:
			var monthEnd = new Date(s.getFullYear(), s.getMonth() + 1, 0);
			e = _monday(monthEnd); e.setDate(e.getDate() + 7);
			s = new Date(e); s.setDate(s.getDate() - 42);
			break;
		case 3: s = new Date(s.getFullYear(), 0, 1); e = new Date(s.getFullYear() + 1, 0, 1); break;
		default: e = new Date(s.getFullYear() + 1, 0, 1); s = new Date(s.getFullYear() - 5, 0, 1); break;
		}
		return { startDate: dateToISOString(s), endDate: dateToISOString(e) };
	}
}
