.pragma library

// The simulated household's energy use, shared by hdrv_p1 (the insights the graphs ask for) and
// happ_pwrusage (the live values on the tiles). Deterministic: the same moment always gives the same
// value, so a graph looks the same every time it is opened and tests can rely on it.
//   electricity: W at a moment (base load, a morning and an evening peak, a bit of noise)
//   gas: litres per hour at a moment (heating in the morning and evening, far more in winter)
// About 3000 kWh and 1200 m3 a year, a typical Dutch home.
//   solar (when TSC's "Zon Op Toon" is on, see SOLAR below): W from the panels at a moment
// With solar, "electricity" in the meter readings is what comes from the grid ("import"), and what the
// panels give beyond the house's use goes back to it ("export"); consumption stays the house's use.

var PRICE = { electricity: 0.30, gas: 1.40, "district-heat": 0.05, water: 0.0045, solar: 0.30 };  // EUR per kWh / m3 / MJ / l
var FIXED_COST_PER_DAY = 0.85;

// 0..1 pseudo random, stable per (seed, t)
function noise(seed, t) {
	var x = Math.sin(seed * 12.9898 + t * 0.0000781) * 43758.5453;
	return x - Math.floor(x);
}

function hourOf(d) { return d.getHours() + d.getMinutes() / 60; }

function bump(h, centre, width) { var x = (h - centre) / width; return Math.exp(-x * x); }

// winter 1, summer 0.1
function season(d) { return 0.55 + 0.45 * Math.cos((d.getMonth() + d.getDate() / 31) / 12 * 2 * Math.PI); }

function power(d) {
	var h = hourOf(d);
	var w = 180 + 450 * bump(h, 7.5, 1.0) + 900 * bump(h, 19, 2.0) + 250 * bump(h, 12.5, 1.5);
	return Math.round(w * (0.8 + 0.4 * noise(1, d.getTime())));
}

function gasFlow(d) {
	var h = hourOf(d);
	var heat = 380 * season(d) * (0.35 + bump(h, 7, 1.2) + 0.8 * bump(h, 19, 2.5));
	var shower = 120 * bump(h, 7.8, 0.3);
	return Math.round((heat + shower) * (0.85 + 0.3 * noise(2, d.getTime())));
}

// ---- solar panels: off unless the agreement has SolarActivated (happ_pwrusage calls setSolar) ----
// A south-facing roof at 52 N, 5 E: the sun's height through the day and the year, times the day's
// weather (clear to overcast, sunnier in summer) and passing clouds on the half-sunny days. About 0.9
// kWh per Wp a year, the Dutch average: 4000 Wp (ten to twelve panels) gives some 3600 kWh.

var SOLAR = { on: false, wattPeak: 4000 };

function setSolar(on, wattPeak) {
	on = !!on;
	wattPeak = wattPeak || SOLAR.wattPeak;
	if (on !== SOLAR.on || wattPeak !== SOLAR.wattPeak) _dayCum = {};    // the meters' history changes
	SOLAR.on = on;
	SOLAR.wattPeak = wattPeak;
}

// sin of the sun's elevation (negative at night)
function sunHeight(d) {
	var n = (d.getTime() - Date.UTC(d.getUTCFullYear(), 0, 1)) / 86400000;
	var decl = 23.44 * Math.PI / 180 * Math.sin(2 * Math.PI * (284 + n) / 365);
	var lat = 52.1 * Math.PI / 180;
	var utc = d.getUTCHours() + d.getUTCMinutes() / 60 + d.getUTCSeconds() / 3600;
	var omega = (utc - 11.65) * 15 * Math.PI / 180;       // the sun is south at about 11:40 UTC here
	return Math.sin(lat) * Math.sin(decl) + Math.cos(lat) * Math.cos(decl) * Math.cos(omega);
}

// 0.15 (overcast) .. 1 (clear) for the whole day, the same all day long
function sunnyDay(d) {
	var local = new Date(d); local.setHours(12, 0, 0, 0);
	var r = noise(7, Math.floor(local.getTime() / 86400000) * 1000);
	return 0.15 + 0.85 * Math.pow(r, 0.2 + 0.9 * season(d));
}

function solarPower(d) {
	if (!SOLAR.on) return 0;
	var s = sunHeight(d);
	if (s <= 0) return 0;
	var day = sunnyDay(d);
	// passing clouds, per 10 minutes: none on a clear or an overcast day, most on the ones in between
	var clouds = 1 - 4 * day * (1 - day) * 0.4 * noise(8, Math.floor(d.getTime() / 600000) * 600000);
	// peak about 80% of Wp on a clear June noon (heat, angle, inverter)
	return Math.round(SOLAR.wattPeak * 0.95 * Math.pow(s, 1.25) * day * clouds);
}

function flow(utility, d) {
	if (utility === "solar") return solarPower(d);
	if (utility === "import") return Math.max(0, power(d) - solarPower(d));
	if (utility === "export") return Math.max(0, solarPower(d) - power(d));
	if (utility === "gas") return gasFlow(d);
	if (utility === "water") return Math.round(20 * bump(hourOf(d), 7.8, 0.4) + 5 * noise(3, d.getTime()));
	if (utility === "district-heat") return Math.round(gasFlow(d) * 30);
	return power(d);
}

// Wh (electricity), litres (gas, water) or kJ-ish (heat) between two moments: hourly samples
function quantity(utility, from, to) {
	var sum = 0, step = 3600000;
	for (var t = from.getTime(); t < to.getTime(); t += step) {
		var part = Math.min(step, to.getTime() - t) / step;
		sum += flow(utility, new Date(t + step / 2)) * part;
	}
	return Math.round(sum);
}

// the burner's on-time in seconds between two moments (gas flow above a small threshold)
function onTime(from, to) {
	var sum = 0, step = 3600000;
	for (var t = from.getTime(); t < to.getTime(); t += step)
		sum += Math.min(3600, gasFlow(new Date(t + step / 2)) / 400 * 3600);
	return Math.round(sum);
}

function cost(utility, qty) {
	var perUnit = PRICE[utility] || 0;
	if (utility === "electricity" || utility === "gas" || utility === "solar") qty /= 1000;       // kWh, m3
	return Math.round(qty * perUnit * 100) / 100;
}

function nextStep(d, interval) {
	var n = new Date(d);
	switch (interval) {
	case "hours": n.setHours(n.getHours() + 1); break;
	case "days": n.setDate(n.getDate() + 1); break;
	case "weeks": n.setDate(n.getDate() + 7); break;
	case "months": n.setMonth(n.getMonth() + 1); break;
	case "years": n.setFullYear(n.getFullYear() + 1); break;
	default: n.setTime(n.getTime() + 300000);              // flow: 5 minute samples
	}
	return n;
}

// the body of an /insights/home/... answer: { data: [{ timestamp, value }], currency? }
// uri: /insights/home/<utility>[/<origin>][/<type>][/unit|price][/<interval>][/<tariff>]?from=..&to=..
function insights(uri) {
	var q = uri.split("?"), parts = q[0].split("/").filter(function (p) { return p; });
	var params = {};
	(q[1] || "").split("&").forEach(function (kv) { var i = kv.indexOf("="); if (i > 0) params[kv.slice(0, i)] = decodeURIComponent(kv.slice(i + 1)); });
	var utility = parts[2], rest = parts.slice(3);
	var has = function (w) { return rest.indexOf(w) >= 0; };
	var interval = ["hours", "days", "weeks", "months", "years"].filter(has)[0];
	var isCost = has("price"), isFlow = has("flow"), fixed = has("fixed-costs"), production = has("production");
	var tariffShare = has("low-tariff") ? 0.4 : has("normal-tariff") ? 0.6 : 1;
	var now = new Date();
	var from = params.from ? new Date(params.from) : new Date(now.getTime() - 86400000);
	var to = params.to ? new Date(params.to) : now;
	if (isNaN(from.getTime())) from = new Date(now.getTime() - 86400000);
	if (isNaN(to.getTime()) || to > now) to = now;

	var body = { data: [] };
	if (isCost || fixed) body.currency = "EUR";
	// a quantity without an interval is one total over the period (the solar app: produced since installed)
	var whole = !interval && !isFlow;
	var guard = 0;
	for (var d = new Date(from); d < to && guard < 5000; d = whole ? new Date(to) : nextStep(d, interval), guard++) {
		var end = whole ? new Date(to) : nextStep(d, interval);
		if (end > to) end = to;
		var v;
		if (production) {
			if (isFlow) v = flow("solar", d);
			else {
				var made = quantity("solar", d, end) * tariffShare;
				v = isCost ? cost("solar", made) : Math.round(made);
			}
		}
		else if (fixed) v = Math.round(FIXED_COST_PER_DAY * (end - d) / 86400000 * 100) / 100;
		else if (utility === "heating") v = onTime(d, end);
		else if (isFlow) v = flow(utility, d);
		else {
			var qty = quantity(utility, d, end) * tariffShare;
			v = isCost ? cost(utility, qty) : Math.round(qty);
		}
		body.data.push({ timestamp: Math.floor(d.getTime() / 1000), value: v });
	}
	return body;
}

// ---- meter readings (hcb_rrd's elec_quantity_nt / _lt, gas_quantity): cumulative, from METER_BASE ----
// Low tariff: 23:00-07:00 and weekends, the Dutch day/night split.

var METER_BASE_TIME = new Date(2024, 0, 1).getTime();
// electricity: from the grid; export: back to the grid; solar: the panels' own kWh meter (all from
// METER_BASE_TIME, when the simulated panels were installed)
var METER_BASE = { electricity: { nt: 9000000, lt: 6000000 }, gas: { all: 3500000 },
                   export: { nt: 0, lt: 0 }, solar: { all: 0 } };   // Wh, litres
var _dayCum = {};                    // "utility/part" -> [cumulative at the start of day i since METER_BASE_TIME]

function isLowTariff(d) {
	var h = d.getHours(), wd = d.getDay();
	return h < 7 || h >= 23 || wd === 0 || wd === 6;
}

// the quantity in one part ("nt", "lt" or "all") between two moments, hourly samples as quantity()
function quantityPart(utility, part, from, to) {
	var sum = 0, step = 3600000;
	if (utility === "electricity" && SOLAR.on) utility = "import";
	for (var t = from; t < to; t += step) {
		var mid = new Date(t + Math.min(step, to - t) / 2);
		if (part === "nt" && isLowTariff(mid)) continue;
		if (part === "lt" && !isLowTariff(mid)) continue;
		sum += flow(utility, mid) * Math.min(step, to - t) / step;
	}
	return sum;
}

// the meter reading at a moment (Wh for electricity, litres for gas)
function meter(utility, part, t) {
	if (t < METER_BASE_TIME) return null;
	var key = utility + "/" + part, days = _dayCum[key] || (_dayCum[key] = [METER_BASE[utility][part]]);
	var day = Math.floor((t - METER_BASE_TIME) / 86400000);
	while (days.length <= day) {
		var i = days.length - 1, start = METER_BASE_TIME + i * 86400000;
		days.push(days[i] + quantityPart(utility, part, start, start + 86400000));
	}
	var dayStart = METER_BASE_TIME + day * 86400000;
	return days[day] + quantityPart(utility, part, dayStart, t);
}

// this month so far and the estimate for the whole month, as happ_pwrusage's GetStatusUsage reports it
function monthStatus(utility, year, month) {
	var start = new Date(year, month - 1, 1), end = new Date(year, month, 1), now = new Date();
	var until = end < now ? end : now;
	var actual = until > start ? quantity(utility, start, until) : 0;
	var complete = quantity(utility, start, end);
	var estimateSoFar = Math.round(complete * (until - start) / (end - start) * 1.05);   // the estimate is 5% higher
	return {
		type: utility, validUsageData: true,
		actualUsage: actual, actualCost: cost(utility, actual),
		estimatedUsage: estimateSoFar, estimatedCost: cost(utility, estimateSoFar),
		completeEstimatedUsage: Math.round(complete * 1.05), completeEstimatedCost: cost(utility, complete * 1.05)
	};
}
