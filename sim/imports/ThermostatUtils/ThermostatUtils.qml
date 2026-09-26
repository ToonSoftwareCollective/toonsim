pragma Singleton
import QtQuick 2.1
import "../BxtClient/bxt.js" as Bxt

	// qt-gui's ThermostatUtils (C++): the thermostat's week program.
	//
	// On the wire (hcb_config, package happ_thermstat, internalAddress thermostatProgram) the program is
	// a list of <entry type="weekly_recurring"> with start/end day (0 = Sunday), hour and minute and a
	// targetState (0 comfort, 1 home, 2 sleep, 3 away). In the QML it is an array of 8: index 0..6 the
	// days (Sunday first), each a list of blocks where block 0 is the one still running at 00:00 (it
	// started on an earlier day) and the rest start on that day; index 7 the holiday periods.
	//
	// Here every program is derived from one canonical list: the weekly blocks sorted by start, each
	// ending where the next one starts. Edits change that list and rebuild the days, so the days can
	// never contradict each other.
QtObject {
	id: tu

	// ---- conversions between the canonical week and the day view ----

	function _weekMin(day, hour, min) { return ((day % 7) * 24 + hour) * 60 + min; }

	function _sorted(blocks) {
		var list = blocks.slice().sort(function (a, b) {
			return _weekMin(a.startDayOfWeek, a.startHour, a.startMin) - _weekMin(b.startDayOfWeek, b.startHour, b.startMin);
		});
		// one block per start time (the last one given wins)
		var out = [];
		for (var i = 0; i < list.length; i++) {
			var b = list[i];
			if (out.length && _weekMin(b.startDayOfWeek, b.startHour, b.startMin)
					=== _weekMin(out[out.length - 1].startDayOfWeek, out[out.length - 1].startHour, out[out.length - 1].startMin))
				out[out.length - 1] = b;
			else out.push(b);
		}
		return out;
	}

	function _block(day, hour, min, state) {
		return { type: "weekly_recurring", startDayOfWeek: day, startHour: hour, startMin: min, targetState: state,
		         endDayOfWeek: day, endHour: hour, endMin: min };
	}

	function _copyBlock(b) {
		var c = {};
		for (var k in b) c[k] = b[k];
		return c;
	}

	// the program array (8 entries) from canonical weekly blocks and holiday periods
	function _toProgram(canon, holidays) {
		canon = _sorted(canon);
		var n = canon.length;
		for (var i = 0; i < n; i++) {
			var next = canon[(i + 1) % n];
			canon[i].endDayOfWeek = next.startDayOfWeek;
			canon[i].endHour = next.startHour;
			canon[i].endMin = next.startMin;
		}
		var program = [];
		for (var d = 0; d < 7; d++) {
			var day = [];
			if (n) {
				// the block running at 00:00 of day d: the last one starting at or before it (wrapping round the week)
				var at0 = canon[n - 1];
				for (var j = 0; j < n; j++) if (_weekMin(canon[j].startDayOfWeek, canon[j].startHour, canon[j].startMin) <= _weekMin(d, 0, 0)) at0 = canon[j];
				day.push(_copyBlock(at0));
				for (var k = 0; k < n; k++) {
					var b = canon[k];
					if (b.startDayOfWeek === d && (b.startHour || b.startMin)) day.push(_copyBlock(b));
				}
			}
			program.push(day);
		}
		program.push((holidays || []).map(function (h) { return { startTime: new Date(h.startTime), endTime: new Date(h.endTime), targetState: h.targetState }; }));
		return program;
	}

	// canonical weekly blocks from a program array: every block counted once, on the day it starts
	function _fromProgram(program) {
		var canon = [];
		if (!program) return canon;
		for (var d = 0; d < 7 && d < program.length; d++) {
			var day = program[d] || [];
			for (var i = 0; i < day.length; i++) {
				var b = day[i];
				if (!b) continue;
				if (i === 0 && !(b.startDayOfWeek === d && !b.startHour && !b.startMin)) continue;    // started earlier
				canon.push(_block(b.startDayOfWeek, b.startHour, b.startMin, b.targetState));
			}
		}
		if (!canon.length) for (var e = 0; e < 7 && e < program.length; e++) {
			var f = (program[e] || [])[0];
			if (f) canon.push(_block(f.startDayOfWeek, f.startHour, f.startMin, f.targetState));
		}
		return _sorted(canon);
	}

	function _holidays(program) { return (program && program[7]) ? program[7] : []; }

	// ---- the API the QML uses ----

	// the <schedule> node from hcb_config -> program
	function parseSchedule(schedule) {
		var canon = [], holidays = [];
		for (var e = schedule ? schedule.getChild("entry") : null; e; e = e.next) {
			var type = e.getChildText("type") || e.getAttribute("type");
			if (type === "weekly_recurring") {
				canon.push(_block(parseInt(e.getChildText("startDayOfWeek")), parseInt(e.getChildText("startHour")),
				                  parseInt(e.getChildText("startMin")), parseInt(e.getChildText("targetState"))));
			} else if (type === "holiday" || e.getChild("startTime")) {
				holidays.push({ startTime: parseInt(e.getChildText("startTime")) * 1000, endTime: parseInt(e.getChildText("endTime")) * 1000,
				                targetState: parseInt(e.getChildText("targetState")) || 4 });
			}
		}
		return canon.length ? _toProgram(canon, holidays) : [];
	}

	// program -> SetObjectConfig message for hcb_config
	function addScheduleToBxtMsg(program, msg) {
		msg.addArgument("Config", null);
		var dev = msg.getArgumentXml("Config").addChild("device", null, 0);
		dev.addChild("package", "happ_thermstat", 0);
		dev.addChild("internalAddress", "thermostatProgram", 0);
		var sched = dev.addChild("schedule", null, 0);
		var canon = _sorted(_fromProgram(program));
		for (var i = 0; i < canon.length; i++) {
			var b = canon[i], next = canon[(i + 1) % canon.length];
			var e = sched.addChild("entry", null, 0);
			e.setAttribute("type", "weekly_recurring");
			e.addChild("type", "weekly_recurring", 0);
			e.addChild("startMin", b.startMin, 0); e.addChild("startHour", b.startHour, 0);
			e.addChild("startDayOfWeek", b.startDayOfWeek, 0); e.addChild("targetState", b.targetState, 0);
			e.addChild("endMin", next.startMin, 0); e.addChild("endHour", next.startHour, 0);
			e.addChild("endDayOfWeek", next.startDayOfWeek, 0);
		}
		_holidays(program).forEach(function (h) {
			var e = sched.addChild("entry", null, 0);
			e.setAttribute("type", "holiday");
			e.addChild("type", "holiday", 0);
			e.addChild("startTime", Math.floor(new Date(h.startTime).getTime() / 1000), 0);
			e.addChild("endTime", Math.floor(new Date(h.endTime).getTime() / 1000), 0);
			e.addChild("targetState", h.targetState === undefined ? 4 : h.targetState, 0);
		});
	}

	// the program in force at 'when' (default now): { block, next, nextStart (Date) } - used by the
	// simulated happ_thermstat to follow the program
	function currentBlock(program, when) {
		var canon = _sorted(_fromProgram(program));
		if (!canon.length) return null;
		when = when || new Date();
		var now = _weekMin(when.getDay(), when.getHours(), when.getMinutes());
		var idx = canon.length - 1;
		for (var i = 0; i < canon.length; i++)
			if (_weekMin(canon[i].startDayOfWeek, canon[i].startHour, canon[i].startMin) <= now) idx = i;
		var next = canon[(idx + 1) % canon.length];
		var delta = _weekMin(next.startDayOfWeek, next.startHour, next.startMin) - now;
		if (delta <= 0) delta += 7 * 24 * 60;
		var start = new Date(when.getTime() + delta * 60000);
		start.setSeconds(0, 0);
		return { block: canon[idx], next: next, nextStart: start };
	}

	// Toon's default: weekdays up at 7:00, away 8:00-18:00; weekend up at 10:00; comfort from 18:00, sleep from 23:00
	function getDefaultSchedule() {
		var canon = [];
		for (var d = 0; d < 7; d++) {
			var weekend = (d === 0 || d === 6);
			canon.push(_block(d, weekend ? 10 : 7, 0, 1));
			if (!weekend) canon.push(_block(d, 8, 0, 3));
			canon.push(_block(d, 18, 0, 0));
			canon.push(_block(d, 23, 0, 2));
		}
		return _toProgram(canon, []);
	}

	function getDefaultBusinessSchedule() {
		var canon = [];
		for (var d = 1; d < 6; d++) {
			canon.push(_block(d, 7, 30, 0));
			canon.push(_block(d, 18, 0, 3));
		}
		return _toProgram(canon, []);
	}

	function createProgramCopy(program) {
		return program ? _toProgram(_fromProgram(program), _holidays(program)) : [];
	}

	function comparePrograms(a, b) {
		return JSON.stringify(_fromProgram(a)) === JSON.stringify(_fromProgram(b))
			&& JSON.stringify(_holidays(a)) === JSON.stringify(_holidays(b));
	}

	function programLength(program) { return _fromProgram(program).length; }

	// neighbouring blocks with the same state become one
	function simplifyProgram(program) {
		var canon = _sorted(_fromProgram(program)), out = [];
		for (var i = 0; i < canon.length; i++)
			if (!out.length || out[out.length - 1].targetState !== canon[i].targetState) out.push(canon[i]);
		if (out.length > 1 && out[0].targetState === out[out.length - 1].targetState) out.shift();
		return _toProgram(out, _holidays(program));
	}

	// program[day][index] gets a new start and state; its end follows from the next block
	function editBlockInSchedule(program, day, index, startMin, startHour, startDay, endMin, endHour, endDay, targetState) {
		var target = (program[day] || [])[index];
		var canon = _fromProgram(program);
		if (target) {
			var key = _weekMin(target.startDayOfWeek, target.startHour, target.startMin);
			canon = canon.filter(function (b) { return _weekMin(b.startDayOfWeek, b.startHour, b.startMin) !== key; });
		}
		canon.push(_block(startDay === undefined ? day : startDay, startHour, startMin, targetState));
		return _toProgram(canon, _holidays(program));
	}

	// a new block after program[day][index - 1], 30 minutes later with the same state (the QML edits it next)
	function addBlockToSchedule(program, day, index) {
		var prev = (program[day] || [])[Math.max(0, index - 1)];
		var d = day, h = 12, m = 0, state = 1;
		if (prev) {
			state = prev.targetState;
			if (prev.startDayOfWeek === day) { h = prev.startHour; m = prev.startMin + 30; } else { h = 0; m = 30; }
		}
		if (m >= 60) { h += 1; m -= 60; }
		var canon = _fromProgram(program);
		canon.push(_block(d, h, m, state));
		return _toProgram(canon, _holidays(program));
	}

	function deleteBlockFromSchedule(program, day, index) {
		var target = (program[day] || [])[index];
		if (!target) return program;
		var key = _weekMin(target.startDayOfWeek, target.startHour, target.startMin);
		var canon = _fromProgram(program).filter(function (b) { return _weekMin(b.startDayOfWeek, b.startHour, b.startMin) !== key; });
		return _toProgram(canon, _holidays(program));
	}

	// the blocks that start on day 'from' replace those of each day in 'toDays' (Sunday-based)
	function copyDayProgram(program, from, toDays) {
		var canon = _fromProgram(program);
		var src = canon.filter(function (b) { return b.startDayOfWeek === from; });
		var targets = [].concat(toDays);
		canon = canon.filter(function (b) { return targets.indexOf(b.startDayOfWeek) < 0; });
		targets.forEach(function (d) { src.forEach(function (b) { canon.push(_block(d, b.startHour, b.startMin, b.targetState)); }); });
		return _toProgram(canon, _holidays(program));
	}

	// a new (default) program keeps the holidays of the old one
	function swapHoliday(oldProgram, newProgram) {
		return _toProgram(_fromProgram(newProgram), _holidays(oldProgram));
	}

	function weekdayTodayMB() { return (new Date().getDay() + 6) % 7; }          // Monday = 0
	function mondayBaseToSundayBase(d) { return (d + 1) % 7; }
	function sundayBaseToMondayBase(d) { return (d + 6) % 7; }

	// the smart radiator valves' (STRV) schedules: not simulated
	function parseHvacSchedule(x) { return []; }
	function generateHvacSchedule(p) { return ""; }
}
