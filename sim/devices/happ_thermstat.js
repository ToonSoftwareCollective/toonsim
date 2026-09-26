.pragma library

// happ_thermstat: the thermostat. It follows the week program stored in hcb_config, takes setpoint and
// preset changes from the GUI (ChangeSchemeState), and simulates the house: while the room is below
// the setpoint the burner heats it, otherwise it cools slowly towards the outside temperature.
// Temperatures are in 1/100 degree, as on the wire. Drive it from outside with
//   simDevices.set("happ_thermstat", { currentTemp: 1650, outsideTemp: 500, heatRate: 20 })
//
// programState: 0 manual, 1 program, 2 temporary override (until the next program block), 4 holiday.

var STATE_TEMPS_KEY = "thermostatStates";

function device(Bxt) {
	return {
		type: "happ_thermstat",
		state: {
			currentTemp: 1950,          // measured room temperature
			outsideTemp: 800,
			programState: 1,
			activeState: 1,             // 0 comfort, 1 home, 2 sleep, 3 away, 4 holiday, -1 none (manual setpoint)
			currentSetpoint: 1800,
			overrideUntil: 0,           // epoch ms: end of a temporary override
			nextTime: 0, nextState: -1, nextSetpoint: 0,
			burnerInfo: 0, modulation: 0,
			heatRate: 8,                // 1/100 degree per tick (5 s) while heating; high so a change is visible
			coolRate: 1,
			stateTemps: { 0: 2000, 1: 1800, 2: 1500, 3: 1200, 4: 600 },
			// the heating installation (a real Toon's values): type 3, max 90 C, 3 C/h, gas; hot water 60 C
			heatingType: 3, maxHeaterTemp: 90, maxHeatingRate: 3, heaterFuelType: "gasFuel",
			dhwEnabled: 1, dhwSetpoint: 60, dhwMinSetpoint: 40, dhwMaxSetpoint: 65, tempOffset: 0,
			// the boiler behind the OpenTherm link, in degrees / bar as hcb_rrd logs them: the flow
			// temperature follows the boiler setpoint while the burner is on, both cool down towards
			// the room when it is off (then the setpoint is 6, as a real Toon reports)
			boilerSetpoint: 6, boilerTemp: 24.5, boilerRetTemp: 25.0, boilerPressure: 1.19
		},

		// hcb_config stored something: pick up new presets or a new program right away
		configStored: function (dev, key, node) {
			if (key === STATE_TEMPS_KEY && node) { readStates(dev, node); publish(dev); }
			if (key === "thermostatProgram") { followProgram(dev, true); publish(dev); }
		},

		init: function (dev) {
			var cfg = dev.hub.byType("hcb_config");
			var st = cfg && cfg.state.objects[STATE_TEMPS_KEY];
			if (st) readStates(dev, st);
			followProgram(dev, true);
		},

		tick: function (dev) {
			var s = dev.state, before = JSON.stringify(s);
			followProgram(dev, false);
			// the house: heat while below the setpoint (with a little hysteresis), cool otherwise
			if (s.currentTemp < s.currentSetpoint - 10) {
				s.burnerInfo = 1;
				s.modulation = Math.min(100, Math.round((s.currentSetpoint - s.currentTemp) / 2));
				s.currentTemp = Math.min(s.currentSetpoint + 20, s.currentTemp + s.heatRate);
			} else {
				s.burnerInfo = 0;
				s.modulation = 0;
				if (s.currentTemp > s.outsideTemp) s.currentTemp -= s.coolRate;
			}
			boiler(s);
			if (JSON.stringify(s) !== before) publish(dev);
		},

		// the local web server (http://localhost/happ_thermstat?action=...), which TSC apps use
		http: {
			"getThermostatInfo": function (q, dev) {
				var s = dev.state, r = { result: "ok" };
				var v = {
					currentTemp: Math.round(s.currentTemp), currentSetpoint: s.currentSetpoint,
					currentInternalBoilerSetpoint: Math.round(s.boilerSetpoint), programState: s.programState,
					activeState: s.activeState, nextProgram: s.programState === 1 ? 1 : -1, nextState: s.nextState,
					nextTime: Math.floor(s.nextTime / 1000), nextSetpoint: s.nextSetpoint, randomConfigId: 1804289383,
					errorFound: 255, connection: 0, burnerInfo: s.burnerInfo, otCommError: 0, currentModulationLevel: s.modulation
				};
				for (var k in v) r[k] = String(v[k]);            // the Toon sends every value as a string
				return r;
			},
			"getThermostatStates": function (q, dev) {
				var states = [];
				for (var id = 0; id < 5; id++) states.push({ id: String(id), tempValue: String(dev.state.stateTemps[id]), dhw: "1" });
				return { result: "ok", states: [{ state: states }] };
			},
			// ?action=setSetpoint&Setpoint=1950 (1/100 degree): a temporary setpoint
			"setSetpoint": function (q, dev) {
				var sp = parseInt(q.Setpoint || q.setpoint);
				if (isNaN(sp)) return { result: "error" };
				var s = dev.state;
				s.activeState = -1; s.currentSetpoint = sp; s.programState = s.programState === 1 ? 2 : s.programState;
				publish(dev);
				return { result: "ok" };
			},
			// the mobile site's name for it: ?action=roomSetpoint&Setpoint=1950
			"roomSetpoint": function (q, dev) { return dev.http.setSetpoint(q, dev); },
			// ?action=changeSchemeState&state=2&temperatureState=0
			"changeSchemeState": function (q, dev) {
				var s = dev.state, st = parseInt(q.state), ts = parseInt(q.temperatureState);
				if (!isNaN(st)) s.programState = st;
				if (!isNaN(ts) && s.stateTemps[ts] !== undefined) { s.activeState = ts; s.currentSetpoint = s.stateTemps[ts]; }
				if (s.programState === 1) followProgram(dev, true);
				publish(dev);
				return { result: "ok" };
			}
		},

		datasets: {
			"thermostatInfo": function (dev) {
				var s = dev.state;
				var n = new Bxt.Node("thermostatInfo");
				n.addChild("currentTemp", Math.round(s.currentTemp), 0);
				n.addChild("currentDisplayTemp", Math.round(s.currentTemp / 10) * 10, 0);
				n.addChild("currentSetpoint", s.currentSetpoint, 0);
				n.addChild("realSetpoint", s.currentSetpoint, 0);
				n.addChild("programState", s.programState, 0);
				n.addChild("activeState", s.activeState, 0);
				n.addChild("nextProgram", s.programState === 1 ? 1 : 0, 0);
				n.addChild("nextState", s.nextState, 0);
				n.addChild("nextTime", Math.floor(s.nextTime / 1000), 0);
				n.addChild("nextSetpoint", s.nextSetpoint, 0);
				n.addChild("errorFound", 255, 0);
				n.addChild("boilerModuleConnected", 1, 0);
				n.addChild("haveOTBoiler", 1, 0);
				n.addChild("hasBoilerFault", 0, 0);
				n.addChild("otCommError", 0, 0);
				n.addChild("burnerInfo", s.burnerInfo, 0);
				n.addChild("currentModulationLevel", s.modulation, 0);
				n.addChild("preheating", 0, 0);
				n.addChild("setByLoadShifting", 0, 0);
				n.addChild("randomConfigId", 0, 0);
				return n;
			},
			"thermostatStates": function (dev) {
				var n = new Bxt.Node("thermostatStates");
				for (var id = 0; id < 5; id++) {
					var st = n.addChild("state", null, 0);
					st.addChild("id", id, 0);
					st.addChild("tempValue", dev.state.stateTemps[id], 0);
					st.addChild("dhw", 1, 0);
				}
				n.addChild("statesSaved", "true", 0);
				return n;
			},
			"features": function (dev) {
				var n = new Bxt.Node("features");
				n.addChild("FF_BoilerControl_reveal", 1, 0);
				n.addChild("FF_HeatingBeat_UiElements", 0, 0);
				n.addChild("FF_Dhw_PreHeat_Settings", 1, 0);
				n.addChild("FF_Dhw_UiElements_Settings", 0, 0);   // no separate hot-water tank (a combi boiler)
				return n;
			},
			// the hot-water week schedule's runtime, JSON as the text of the dataset: none programmed
			"scheduleRuntime": function (dev) {
				return new Bxt.Node("scheduleRuntime", JSON.stringify({
					dhw: { active: false, scheduleHash: "toonsim", stateTransitions: [] }
				}));
			}
		},

		requests: {
			// state: 0 manual / 1 program / 2 temporary; with temperature (1/100 degree) or temperatureState
			"ChangeSchemeState": function (msg, dev) {
				var s = dev.state;
				var state = parseInt(msg.getArgument("state"));
				var temp = msg.getArgument("temperature"), tstate = msg.getArgument("temperatureState");
				if (!isNaN(state)) s.programState = state;
				if (tstate !== "") { s.activeState = parseInt(tstate); s.currentSetpoint = s.stateTemps[s.activeState]; }
				else if (temp !== "") { s.activeState = -1; s.currentSetpoint = Math.round(parseFloat(temp)); }
				if (s.programState === 2) {
					var cur = dev.hub.thermostatUtils.currentBlock(program(dev));
					s.overrideUntil = cur ? cur.nextStart.getTime() : 0;
				}
				if (s.programState === 1) followProgram(dev, true);
				console.log("toonsim happ_thermstat: programState", s.programState, "setpoint", s.currentSetpoint / 100);
				publish(dev);
				return null;
			},
			"Thermostat.GetHolidays": function (msg, dev) {
				var r = msg.createResponse();
				r.addArgument("holidays", null);
				return r;
			},
			"Thermostat.SetHoliday": function (msg, dev) { dev.state.programState = 4; dev.state.activeState = 4; dev.state.currentSetpoint = dev.state.stateTemps[4]; publish(dev); return null; },
			"Thermostat.AbortHoliday": function (msg, dev) { dev.state.programState = 1; followProgram(dev, true); publish(dev); return null; },
			"Thermostat.SetPreheating": function () { return null; },
			"Thermostat.GetChSettings": function (msg, dev) {
				var s = dev.state, r = msg.createResponse();
				r.addArgument("heatingType", s.heatingType);
				r.addArgument("maxHeaterTemp", s.maxHeaterTemp);
				r.addArgument("maxHeatingRate", s.maxHeatingRate);
				r.addArgument("heaterFuelType", s.heaterFuelType);
				return r;
			},
			"Thermostat.SetChSettings": function (msg, dev) {
				["heatingType", "maxHeaterTemp", "maxHeatingRate", "heaterFuelType"].forEach(function (k) {
					var v = msg.getArgument(k); if (v !== "") dev.state[k] = v;
				});
				return msg.createResponse();
			},
			"Thermostat.GetDhwSettings": function (msg, dev) {
				var s = dev.state, r = msg.createResponse();
				r.addArgument("dhwEnabled", s.dhwEnabled);
				r.addArgument("dhwSetpoint", s.dhwSetpoint);
				r.addArgument("dhwMinSetpoint", s.dhwMinSetpoint);
				r.addArgument("dhwMaxSetpoint", s.dhwMaxSetpoint);
				return r;
			},
			"Thermostat.SetDhwSettings": function (msg, dev) {
				["dhwEnabled", "dhwSetpoint"].forEach(function (k) { var v = msg.getArgument(k); if (v !== "") dev.state[k] = parseInt(v); });
				return msg.createResponse();
			},
			"Thermostat.GetTempOffset": function (msg, dev) {
				var r = msg.createResponse();
				r.addArgument("offset", dev.state.tempOffset);
				r.addArgument("measuredTemp", Math.round(dev.state.currentTemp) / 100);
				return r;
			},
			"Thermostat.SetTempOffset": function (msg, dev) { var v = msg.getArgument("offset"); if (v !== "") dev.state.tempOffset = parseFloat(v); return msg.createResponse(); },
			"Thermostat.TestBoilerType": function (msg, dev) {
				var r = msg.createResponse();
				r.addArgument("result", "ok");
				r.addArgument("ot", "0");
				return r;
			}		}
	};
}

function readStates(dev, node) {
	var states = node.getChild("states") || node;
	for (var st = states.getChild("state"); st; st = st.next)
		dev.state.stateTemps[parseInt(st.getChildText("id"))] = parseInt(st.getChildText("tempValue"));
}

function program(dev) {
	var cfg = dev.hub.byType("hcb_config");
	var node = cfg && cfg.state.objects["thermostatProgram"];
	return node ? dev.hub.thermostatUtils.parseSchedule(node.getChild("schedule")) : [];
}

// in program mode: the active block decides state and setpoint; a temporary override ends at the next block
function followProgram(dev, force) {
	var s = dev.state;
	var cur = dev.hub.thermostatUtils.currentBlock(program(dev));
	if (!cur) return;
	s.nextTime = cur.nextStart.getTime();
	s.nextState = cur.next.targetState;
	s.nextSetpoint = s.stateTemps[cur.next.targetState];
	if (s.programState === 2 && Date.now() >= s.overrideUntil) s.programState = 1;
	if (s.programState === 1 && (force || s.activeState !== cur.block.targetState)) {
		s.activeState = cur.block.targetState;
		s.currentSetpoint = s.stateTemps[s.activeState];
	}
}

function publish(dev) {
	dev.hub.publish(dev);
}

// one 5 s step of the boiler: burning, the setpoint rises with the modulation (to maxHeaterTemp) and
// the flow follows it, the return 5-10 degrees below; idle, both drift to a little above the room
function boiler(s) {
	var room = s.currentTemp / 100;
	if (s.burnerInfo) {
		s.boilerSetpoint = Math.min(s.maxHeaterTemp, 35 + s.modulation * 0.4);
		s.boilerTemp += (s.boilerSetpoint - s.boilerTemp) * 0.15;
		s.boilerRetTemp += (s.boilerTemp - (5 + s.modulation * 0.05) - s.boilerRetTemp) * 0.15;
	} else {
		s.boilerSetpoint = 6;
		s.boilerTemp += (room + 3.5 - s.boilerTemp) * 0.02;
		s.boilerRetTemp += (room + 4 - s.boilerRetTemp) * 0.02;
	}
	s.boilerTemp = Math.round(s.boilerTemp * 100) / 100;
	s.boilerRetTemp = Math.round(s.boilerRetTemp * 100) / 100;
}
