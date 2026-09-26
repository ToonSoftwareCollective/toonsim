.pragma library
.import "energy.js" as Energy

// hcb_rrd: the Toon's round-robin databases. Every minute it logs the thermostat's values, and apps read
// them over the local web server:
//   http://localhost/hcb_rrd?action=getRrdData&loggerName=thermstat_boilerTemp&rra=30days
//        &readableTime=1&nullForNaN=1&from=24-09-2026 12:23
// answered as the Toon does: { "24-09-2026 12:24:00": 24.50,"24-09-2026 12:25:00": 24.50, ...} (epoch
// seconds as keys without readableTime, null for "no value" with nullForNaN). rra 30days has a sample
// per minute; for the longer ones (e.g. 5yrhours, 10yrdays) the minutes are averaged per hour / day.
// Before the simulator started there are no samples (null or NaN, as a Toon that just started logging).
// The values follow happ_thermstat, including its simulated boiler (see boiler() there).

var LOGGERS = {
	thermstat_realTemps:        function (t) { return t.currentTemp / 100; },
	thermstat_setpoint:         function (t) { return t.currentSetpoint / 100; },
	thermstat_boilerTemp:       function (t) { return t.boilerTemp; },
	thermstat_boilerRetTemp:    function (t) { return t.boilerRetTemp; },
	thermstat_boilerSetpoint:   function (t) { return t.boilerSetpoint; },
	thermstat_boilerChPressure: function (t) { return t.boilerPressure; },
	thermstat_modulationLevel:  function (t) { return t.modulation; },
	thermstat_burnerInfo:       function (t) { return t.burnerInfo; }
};
var KEEP_MINUTES = 30 * 24 * 60;

// the meters: computed from the household model (energy.js) for any moment, so they have a full
// history - the meter readings in Wh (electricity from the grid, normal and low tariff) and litres
// (gas), and the flows in W and l/h (for an archive of hours or days: the average over the step). The
// Toon the simulator copies has no water meter: water_flow exists but has no values (as on a Toon
// without one). The solar loggers exist while the panels are on (TSC's "Zon Op Toon"), as on a Toon
// with a solar meter; without them they are unknown.
function averaged(utility) {
	return function (t, step) {
		if (step <= 300000) return Energy.flow(utility, new Date(t));
		return Energy.quantity(utility, new Date(t - step), new Date(t)) * 3600000 / step;
	};
}
var MODEL = {
	elec_quantity_nt: function (t) { return Energy.meter("electricity", "nt", t); },
	elec_quantity_lt: function (t) { return Energy.meter("electricity", "lt", t); },
	gas_quantity:     function (t) { return Energy.meter("gas", "all", t); },
	elec_flow:        averaged("import"),                 // from the grid now (all of the house's use without solar)
	gas_flow:         averaged("gas"),
	water_flow:       function (t) { return null; }
};
var SOLAR_MODEL = {
	elec_solar_flow:        averaged("solar"),
	elec_solar_quantity:    function (t) { return Energy.meter("solar", "all", t); },
	elec_produ_flow:        averaged("export"),           // back to the grid now
	elec_quantity_nt_produ: function (t) { return Energy.meter("export", "nt", t); },
	elec_quantity_lt_produ: function (t) { return Energy.meter("export", "lt", t); }
};

function model(name) {
	return MODEL[name] || (Energy.SOLAR.on ? SOLAR_MODEL[name] : null) || null;
}

function device(Bxt) {
	return {
		type: "hcb_rrd",
		state: { samples: {}, started: 0, lastMinute: 0 },
		init: function (dev) {
			dev.state.started = minuteOf(Date.now());
			sample(dev);
		},
		tick: function (dev) { sample(dev); },
		http: {
			"getRrdData": function (q, dev) {
				var name = q.loggerName, fn = model(name);
				if (!LOGGERS[name] && !fn)
					return { status: 200, type: "application/json", body: "{\"result\": \"error\", \"error\": \"unknown logger\"}" };
				var step = rraStep(q.rra);
				var now = Date.now();
				// up to the step in progress, labelled by its end as on the Toon: apps take the last entry
				var last = LOGGERS[name] ? dev.state.lastMinute : Math.ceil(now / step) * step;
				var from = parseFrom(q.from);
				if (from === null) from = last - (step >= 3600000 ? 365 : 30) * 86400000;
				var to = parseFrom(q.to);
				if (to === null || to > last) to = last;
				var readable = q.readableTime === "1", nullNaN = q.nullForNaN === "1";
				var parts = [];
				var list = dev.state.samples[name] || [];
				var t0 = Math.ceil(from / step) * step;
				if (t0 === from) t0 += step;                    // the Toon starts after 'from'
				for (var t = t0; t <= to; t += step) {
					var v = fn ? fn(Math.min(t, now), step) : bucket(list, t, step);
					var key = readable ? fmt(new Date(t)) : String(Math.floor(t / 1000));
					var val = v === null ? (nullNaN ? "null" : "NaN") : v.toFixed(2);
					parts.push("\"" + key + "\": " + val);
				}
				return { status: 200, type: "application/json", body: "{ " + parts.join(",") + "}" };
			}
		}
	};
}

// As on the Toon a minute is labelled by its end, and the minute in progress is already there with the
// latest value: at 13:35:49 the last entry is "13:36:00". Every tick (5 s) updates that entry.
function sample(dev) {
	var th = dev.hub.byType("happ_thermstat");
	if (!th) return;
	var end = minuteOf(Date.now()) + 60000;
	dev.state.lastMinute = end;
	for (var name in LOGGERS) {
		var list = dev.state.samples[name] || (dev.state.samples[name] = []);
		var v = LOGGERS[name](th.state), last = list[list.length - 1];
		if (last && last[0] === end) last[1] = v;
		else list.push([end, v]);
		if (list.length > KEEP_MINUTES) list.shift();
	}
}

// the value for the step ending at t: the minute sample (30days), or the average of the minutes in it
function bucket(list, t, step) {
	var sum = 0, n = 0;
	for (var i = list.length - 1; i >= 0; i--) {
		var m = list[i][0];
		if (m > t) continue;
		if (m <= t - step) break;
		sum += list[i][1]; n++;
	}
	return n ? sum / n : null;
}

function rraStep(rra) {
	rra = String(rra || "30days");
	if (rra === "5min" || rra.indexOf("5min") === 0) return 300000;
	if (rra.indexOf("hours") >= 0) return 3600000;
	if (rra.indexOf("yrdays") >= 0 || rra.indexOf("days") > 0 && rra.indexOf("30days") < 0) return 86400000;
	return 60000;
}

function minuteOf(ms) { return Math.floor(ms / 60000) * 60000; }

function pad(n) { return (n < 10 ? "0" : "") + n; }

function fmt(d) {
	return pad(d.getDate()) + "-" + pad(d.getMonth() + 1) + "-" + d.getFullYear() + " " + pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":00";
}

// "24-09-2026 12:23" or "24-09-2026 12:23:00" (local time), or epoch seconds
function parseFrom(s) {
	if (s === undefined || s === null || s === "") return null;
	s = String(s).trim();
	if (/^\d{9,}$/.test(s)) return minuteOf(parseInt(s) * 1000);
	var m = /^(\d{1,2})-(\d{1,2})-(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?/.exec(s);
	if (!m) return null;
	return minuteOf(new Date(parseInt(m[3]), parseInt(m[2]) - 1, parseInt(m[1]), parseInt(m[4] || 0), parseInt(m[5] || 0)).getTime());
}
