.pragma library
.import "energy.js" as Energy

// happ_pwrusage: the live usage on the tiles (powerUsage, gasUsage: this moment, today, the meter
// readings), the tariffs and yearly estimates (billingInfo), and the month status of the "status usage"
// app (GetStatusUsage). Values come from the household model in energy.js and move on every tick.
// Tariffs: electricity single rate (rate 0; 1 = day/night), prices in EUR incl. VAT; changed tariffs
// and the expected solar yield are kept in data/mnt/data/qmf/config/toonsim_pwrusage.json, so they
// survive a restart.
// Solar panels: on when the agreement (hcb_config's agreementDetail) has SolarActivated - TSC's
// "Zon Op Toon", which reboots. solarWattPeak sets their size (simDevices.set("happ_pwrusage",
// { solarWattPeak: 6000 })), solarYearTarget is the expected yield the user enters under Instellingen >
// Meters (SetStandardYearTargets), spread over the months by the hours of sunshine.

var STORE = "file:///mnt/data/qmf/config/toonsim_pwrusage.json";
var TARIFFS = ["elecRate", "elecPrice", "elecLowPrice", "gasPrice", "solarYearTarget"];
// the share of a year's solar yield per month in the Netherlands (January .. December)
var SOLAR_MONTHS = [0.03, 0.05, 0.08, 0.11, 0.13, 0.13, 0.13, 0.11, 0.09, 0.07, 0.04, 0.03];

function saveState(dev) {
	var saved = {};
	TARIFFS.forEach(function (k) { saved[k] = dev.state[k]; });
	try {
		var xhr = new XMLHttpRequest();
		xhr.open("PUT", STORE, false);
		xhr.send(JSON.stringify(saved));
	} catch (e) { console.log("toonsim happ_pwrusage: cannot save", e); }
}

// solar on or off, as the stored agreement says
function syncSolar(dev) {
	var cfg = dev.hub.byType("hcb_config");
	var ag = cfg && cfg.state.objects["agreementDetail"];
	var on = !!ag && ag.getChildText("SolarActivated") === "1";
	if (on !== Energy.SOLAR.on) console.log("toonsim happ_pwrusage: solar panels", on ? "on (" + dev.state.solarWattPeak + " Wp)" : "off");
	Energy.setSolar(on, dev.state.solarWattPeak);
}

function device(Bxt) {
	return {
		type: "happ_pwrusage",
		state: {
			elecRate: 0, elecPrice: 0.30, elecLowPrice: 0.28, gasPrice: 1.40, vat: 21,
			elecYearUsage: 3000000, gasYearUsage: 1200000,        // the yearly estimate (Wh, litres)
			solarWattPeak: 4000, solarYearTarget: 3600000          // the panels (Wp), their expected yield a year (Wh)
		},
		init: function (dev) {
			try {
				var xhr = new XMLHttpRequest();
				xhr.open("GET", STORE, false);
				xhr.send();
				if (xhr.responseText) {
					var saved = JSON.parse(xhr.responseText);
					TARIFFS.forEach(function (k) { if (saved[k] !== undefined) dev.state[k] = saved[k]; });
				}
			} catch (e) {}
			Energy.PRICE.electricity = Energy.PRICE.solar = dev.state.elecPrice;
			Energy.PRICE.gas = dev.state.gasPrice;
			syncSolar(dev);
		},
		tick: function (dev) { dev.hub.publish(dev); },
		configStored: function (dev, key) { if (key === "agreementDetail") syncSolar(dev); },
		// the months' targets for MonthDataDataset (sim/imports/GraphUtils): solar only, from when the
		// panels came (year as years since 1900, month from 0, as qt-gui has them)
		monthData: function (dev, type) {
			if (type !== "solar" || !Energy.SOLAR.on) return [];
			var list = [], first = new Date(Energy.METER_BASE_TIME).getFullYear(), last = new Date().getFullYear() + 1;
			for (var y = first; y <= last; y++)
				for (var m = 0; m < 12; m++) {
					var wh = Math.round(dev.state.solarYearTarget * SOLAR_MONTHS[m]);
					list.push({ year: y - 1900, month: m, targetUsage: wh, targetLowUsage: 0,
					            targetCost: Energy.cost("solar", wh), targetLowCost: 0 });
				}
			return list;
		},
		// the local web server: http://localhost/happ_pwrusage?action=GetCurrentUsage (the mobile site)
		http: {
			"GetCurrentUsage": function (q, dev) {
				var now = new Date(), weekAgo = new Date(now - 7 * 86400000);
				var avgPower = Energy.quantity("electricity", weekAgo, now) / (7 * 24);        // W
				var avgGas = Energy.quantity("gas", weekAgo, now) / (7 * 24);                  // l/h
				var avgSolar = Energy.quantity("solar", weekAgo, now) / (7 * 24);              // W
				var body = "{\"result\":\"ok\",\n"
					+ "\"powerUsage\": {\"value\":" + Energy.power(now) + ", \"avgValue\":" + avgPower.toFixed(2) + "},\n"
					+ "\"powerProduction\": {\"value\":" + Energy.solarPower(now) + ", \"avgValue\":" + avgSolar.toFixed(2) + "},\n"
					+ "\"gasUsage\": {\"value\":" + Energy.gasFlow(now) + ", \"avgValue\":" + avgGas.toFixed(2) + "}\n}\n";
				return { status: 200, type: "application/json", body: body };
			}
		},
		datasets: {
			"powerUsage": function (dev) {
				var now = new Date(), today = dayStart(now), s = dev.state, t = now.getTime();
				if (Energy.SOLAR.on) Energy.setSolar(true, s.solarWattPeak);     // simDevices.set may have changed it
				var n = new Bxt.Node("powerUsage");
				// value: what the house uses now; valueSolar: what the panels give (take or return is the difference)
				n.addChild("value", Energy.power(now), 0);
				n.addChild("avgValue", Math.round(Energy.quantity("electricity", new Date(now - 7 * 86400000), now) / (7 * 24)), 0);
				n.addChild("dayUsage", Energy.quantity("electricity", today, now), 0);
				n.addChild("dayCost", Energy.cost("electricity", Energy.quantity("electricity", today, now)), 0);
				n.addChild("dayLowUsage", 0, 0);                  // single tariff: all of it counts as normal
				n.addChild("dayLowCost", 0, 0);
				// the "Stroom vandaag" tile compares today with the daily average of the last week
				var week = Energy.quantity("electricity", new Date(today - 7 * 86400000), today);
				n.addChild("avgDayValue", Math.round(week / 7), 0);
				n.addChild("avgDayValueCost", Energy.cost("electricity", week / 7), 0);
				// the lowest use of the last 24 hours (W), for the "laagste verbruik" tile
				var lowest = Infinity;
				for (var t = now - 86400000; t < now.getTime(); t += 300000) lowest = Math.min(lowest, Energy.power(new Date(t)));
				n.addChild("lowestDayValue", lowest, 0);
				// the smart meter: from the grid and back to it, normal and low tariff (as hcb_rrd's elec_quantity_*)
				n.addChild("meterReading", Math.round(Energy.meter("electricity", "nt", t)), 0);
				n.addChild("meterReadingLow", Math.round(Energy.meter("electricity", "lt", t)), 0);
				n.addChild("meterReadingProdu", Math.round(Energy.meter("export", "nt", t)), 0);
				n.addChild("meterReadingLowProdu", Math.round(Energy.meter("export", "lt", t)), 0);
				var solarToday = Energy.quantity("solar", today, now);
				n.addChild("valueSolar", Energy.solarPower(now), 0);
				n.addChild("solarProducedToday", solarToday, 0);
				n.addChild("solarProducedTodaySavings", Energy.cost("solar", solarToday), 0);
				n.addChild("avgDayProduValue", Math.round(Energy.quantity("solar", new Date(today - 7 * 86400000), today) / 7), 0);
				n.addChild("isSmart", 1, 0);
				return n;
			},
			"gasUsage": function (dev) {
				var now = new Date(), today = dayStart(now), s = dev.state;
				var n = new Bxt.Node("gasUsage");
				n.addChild("value", Energy.gasFlow(now), 0);
				var gasWeek = Energy.quantity("gas", new Date(today - 7 * 86400000), today);
				n.addChild("avgValue", Math.round(gasWeek / 7), 0);
				n.addChild("avgDayValue", Math.round(gasWeek / 7), 0);
				n.addChild("dayUsage", Energy.quantity("gas", today, now), 0);
				n.addChild("dayCost", Energy.cost("gas", Energy.quantity("gas", today, now)), 0);
				n.addChild("meterReading", Math.round(Energy.meter("gas", "all", now.getTime())), 0);
				n.addChild("isSmart", 1, 0);
				return n;
			},
			"billingInfo": function (dev) {
				var s = dev.state, n = new Bxt.Node("billingInfo");
				var next = new Date(); next.setMonth(next.getMonth() + 3, 1); next.setHours(0, 0, 0, 0);
				var add = function (type, fields) {
					var info = n.addChild("info", null, 0);
					info.addChild("type", type, 0);
					for (var k in fields) info.addChild(k, fields[k], 0);
				};
				add("elec", { price: s.elecPrice, lowPrice: s.elecLowPrice, rate: s.elecRate, vat: s.vat, usage: s.elecYearUsage,
					lowUsage: 0, nextBillingDate: Math.floor(next / 1000), installedDate: 1525737600 });
				add("gas", { price: s.gasPrice, rate: 0, vat: s.vat, usage: s.gasYearUsage,
					nextBillingDate: Math.floor(next / 1000), installedDate: 1525737600 });
				if (Energy.SOLAR.on)          // usage: the expected yield a year; the panels came with METER_BASE_TIME
					add("elec_produ", { price: s.elecPrice, lowPrice: s.elecRate ? s.elecLowPrice : s.elecPrice, rate: s.elecRate,
						vat: s.vat, usage: s.solarYearTarget, lowUsage: 0, installedDate: Math.floor(Energy.METER_BASE_TIME / 1000) });
				else
					add("elec_produ", { error: "notSet", price: 0, usage: 0, vat: s.vat, installedDate: 0 });
				return n;
			}
		},
		requests: {
			// new tariffs (TSC settings > Change tariff): <BaseField><Type>POWER|PRODU|GAS</Type>
			// <SeparateBilling>true|false</SeparateBilling><TariffPeak>..</TariffPeak><TariffOffPeak>..</TariffOffPeak>
			"specific1.BaseData": function (msg, dev) {
				var s = dev.state;
				msg._args.forEach(function (a) {
					if (a.name !== "BaseField" || !a.xml) return;
					var f = a.xml, type = f.getChildText("Type");
					var peak = parseFloat(f.getChildText("TariffPeak")), offPeak = parseFloat(f.getChildText("TariffOffPeak"));
					if (type === "POWER") {
						if (!isNaN(peak)) s.elecPrice = peak;
						s.elecRate = f.getChildText("SeparateBilling") === "true" ? 1 : 0;
						s.elecLowPrice = isNaN(offPeak) ? s.elecPrice : offPeak;
					} else if (type === "GAS" && !isNaN(peak)) {
						s.gasPrice = peak;
					}
				});
				Energy.PRICE.electricity = Energy.PRICE.solar = s.elecPrice;
				Energy.PRICE.gas = s.gasPrice;
				saveState(dev);
				console.log("toonsim happ_pwrusage: tariffs elec", s.elecPrice, s.elecRate ? "/ " + s.elecLowPrice : "", "gas", s.gasPrice);
				dev.hub.publish(dev);
				return null;
			},
			// the expected solar yield a year (Instellingen > Meters > Estimated generation), in Wh
			"SetStandardYearTargets": function (msg, dev) {
				var target = parseInt(msg.getArgument("elecProduTarget"));
				if (!isNaN(target) && target >= 0) {
					dev.state.solarYearTarget = target;
					saveState(dev);
					console.log("toonsim happ_pwrusage: expected solar yield", target / 1000, "kWh a year");
					dev.hub.publish(dev);
				}
				return null;
			},
			"specific1.GetStatusUsageAvailable": function (msg, dev) {
				var r = msg.createResponse(), now = new Date();
				r.addArgument("statusUsageAvailable", JSON.stringify({
					isAvailable: true, firstAvailableMonth: new Date(now.getFullYear() - 1, now.getMonth(), 1).getTime()
				}));
				return r;
			},
			"specific1.GetStatusUsage": function (msg, dev) {
				var month = parseInt(msg.getArgument("month")), year = parseInt(msg.getArgument("year"));
				var r = msg.createResponse();
				r.addArgument("statusUsage", JSON.stringify({
					electricity: Energy.monthStatus("electricity", year, month),
					gas: Energy.monthStatus("gas", year, month)
				}));
				return r;
			}
		}
	};
}

function dayStart(d) { var s = new Date(d); s.setHours(0, 0, 0, 0); return s; }
