import QtQuick 2.1

	// qt-gui's DateSelectorComponent (C++): the period of a graph (a day, week, month or year), stepped
	// with previousPeriod()/nextPeriod() between periodMinimum and periodMaximum. periodStart is the first
	// and periodEnd the last day of the period (both at 00:00); 'period' is the text the firmware's
	// DateSelector.qml shows (its periodChanged is the signal the graphs react to), built from the month
	// names the QML hands over.
Item {
	id: root

	enum Mode { MODE_DAY, MODE_WEEK, MODE_MONTH, MODE_YEAR }

	property int implicitWidthWeekMode: implicitWidth
	property int mode: DateSelectorComponent.MODE_DAY
	property var periodStart: new Date()
	property var periodEnd: new Date()
	property var periodMinimum: new Date(new Date().getFullYear() - 5, 0, 1)
	property var periodMaximum: new Date()
	property string period
	property var currentDate: periodStart
	property var _short: ["jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
	property var _long: ["januari", "februari", "maart", "april", "mei", "juni", "juli", "augustus", "september", "oktober", "november", "december"]
	property bool _updating: false

	signal periodMinimumReached(bool reached)
	signal periodMaximumReached(bool reached)

	function setShortMonthNames(names) { if (names && names.length === 12) _short = names; _update(); }
	function setLongMonthNames(names) { if (names && names.length === 12) _long = names; _update(); }

	function _startOf(d) {
		var s = new Date(d);
		s.setHours(0, 0, 0, 0);
		if (mode === DateSelectorComponent.MODE_WEEK) s.setDate(s.getDate() - (s.getDay() + 6) % 7);
		else if (mode === DateSelectorComponent.MODE_MONTH) s.setDate(1);
		else if (mode === DateSelectorComponent.MODE_YEAR) s.setMonth(0, 1);
		return s;
	}
	function _endOf(s) {
		var e = new Date(s);
		if (mode === DateSelectorComponent.MODE_DAY) e.setDate(e.getDate() + 1);
		else if (mode === DateSelectorComponent.MODE_WEEK) e.setDate(e.getDate() + 7);
		else if (mode === DateSelectorComponent.MODE_MONTH) e.setMonth(e.getMonth() + 1);
		else e.setFullYear(e.getFullYear() + 1);
		return e;
	}
	function _week(d) {
		var t = new Date(d); t.setHours(0, 0, 0, 0);
		t.setDate(t.getDate() + 3 - (t.getDay() + 6) % 7);
		var w1 = new Date(t.getFullYear(), 0, 4);
		return 1 + Math.round(((t - w1) / 86400000 - 3 + (w1.getDay() + 6) % 7) / 7);
	}
	function _text(s) {
		if (mode === DateSelectorComponent.MODE_DAY) return s.getDate() + " " + _long[s.getMonth()] + " " + s.getFullYear();
		if (mode === DateSelectorComponent.MODE_WEEK) {
			var e = new Date(s); e.setDate(e.getDate() + 6);
			return s.getDate() + " " + _short[s.getMonth()] + " - " + e.getDate() + " " + _short[e.getMonth()] + " (wk " + _week(s) + ")";
		}
		if (mode === DateSelectorComponent.MODE_MONTH) return _long[s.getMonth()] + " " + s.getFullYear();
		return "" + s.getFullYear();
	}

	// normalises periodStart to the start of its period and derives the rest
	function _update() {
		if (_updating) return;
		_updating = true;
		var s = _startOf(periodStart);
		if (s.getTime() !== new Date(periodStart).getTime()) periodStart = s;
		// the last day of the period at 00:00 (a day: the same day), as the graphs expect
		var last = _endOf(s); last.setDate(last.getDate() - 1);
		periodEnd = last;
		period = _text(s);
		_updating = false;
		periodMinimumReached(_startOf(periodMinimum).getTime() >= s.getTime());
		periodMaximumReached(_startOf(periodMaximum).getTime() <= s.getTime());
	}

	function _step(n) {
		var s = new Date(periodStart);
		if (mode === DateSelectorComponent.MODE_DAY) s.setDate(s.getDate() + n);
		else if (mode === DateSelectorComponent.MODE_WEEK) s.setDate(s.getDate() + 7 * n);
		else if (mode === DateSelectorComponent.MODE_MONTH) s.setMonth(s.getMonth() + n);
		else s.setFullYear(s.getFullYear() + n);
		if (s.getTime() < _startOf(periodMinimum).getTime() || s.getTime() > _startOf(periodMaximum).getTime()) return;
		periodStart = s;
	}
	function previousPeriod() { _step(-1); }
	function nextPeriod() { _step(1); }

	onPeriodStartChanged: _update()
	onModeChanged: _update()
	onPeriodMinimumChanged: _update()
	onPeriodMaximumChanged: _update()
	Component.onCompleted: _update()
}
