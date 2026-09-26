.pragma library

// hcb_config: the Toon's configuration store. Apps save objects in it (SetObjectConfig) and read them
// back (GetObjectConfig, GetPackageConfig): the thermostat's week program and temperature presets,
// the home screen's tile layout, screen and keyboard settings. The store is kept in
// data/mnt/data/qmf/config/toonsim_hcb_config.xml, so a restart keeps it, as on the device.
// Delete that file to start from the defaults below (the program and presets of a real Toon).

var STORE = "file:///mnt/data/qmf/config/toonsim_hcb_config.xml";

// [day (0 = Sunday), hour, minute, state (0 comfort, 1 home, 2 sleep, 3 away)] - taken from a real Toon
var DEFAULT_PROGRAM = [[0,10,0,1],[0,18,0,0],[0,23,0,2],[1,7,0,1],[1,8,0,3],[1,18,0,0],[1,23,0,2],[2,7,0,1],[2,8,0,3],
	[2,18,0,0],[2,23,0,2],[3,7,0,1],[3,8,0,3],[3,18,0,0],[3,23,0,2],[4,7,0,1],[4,8,0,3],[4,18,0,0],[4,23,0,2],[5,7,0,1],
	[5,8,0,3],[5,18,0,0],[5,23,0,2],[6,10,0,1],[6,18,0,0],[6,23,0,2]];
// [state id, temperature in 1/100 degree, dhw]: comfort 20, home 18, sleep 15, away 12, holiday 6
var DEFAULT_STATES = [[0,2000,1],[1,1800,1],[2,1500,1],[3,1200,1],[4,600,1]];

function defaultObjects(Bxt) {
	var objects = {};
	var prog = new Bxt.Node("device");
	prog.addChild("package", "happ_thermstat", 0);
	prog.addChild("internalAddress", "thermostatProgram", 0);
	var sched = prog.addChild("schedule", null, 0);
	for (var i = 0; i < DEFAULT_PROGRAM.length; i++) {
		var b = DEFAULT_PROGRAM[i], n = DEFAULT_PROGRAM[(i + 1) % DEFAULT_PROGRAM.length];
		var e = sched.addChild("entry", null, 0);
		e.setAttribute("type", "weekly_recurring");
		e.addChild("type", "weekly_recurring", 0);
		e.addChild("startMin", b[2], 0); e.addChild("startHour", b[1], 0); e.addChild("startDayOfWeek", b[0], 0);
		e.addChild("targetState", b[3], 0);
		e.addChild("endMin", n[2], 0); e.addChild("endHour", n[1], 0); e.addChild("endDayOfWeek", n[0], 0);
	}
	objects["thermostatProgram"] = prog;
	var st = new Bxt.Node("device");
	st.addChild("package", "happ_thermstat", 0);
	st.addChild("type", "states", 0);
	st.addChild("name", "thermostatStates", 0);
	st.addChild("internalAddress", "thermostatStates", 0);
	var states = st.addChild("states", null, 0);
	DEFAULT_STATES.forEach(function (s) {
		var n = states.addChild("state", null, 0);
		n.addChild("id", s[0], 0); n.addChild("tempValue", s[1], 0); n.addChild("dhw", s[2], 0);
	});
	objects["thermostatStates"] = st;
	// happ_scsync's agreement as stored on a real Toon (TSC settings reads it)
	var ag = new Bxt.Node("device");
	ag.addChild("package", "happ_scsync", 0);
	ag.addChild("type", "agreementDetail", 0);
	ag.addChild("internalAddress", "agreementDetail", 0);
	ag.addChild("visibility", "0", 0);
	[["StartDate", "1525737600"], ["EndDate", "-1"], ["Status", "IN_SUPPLY"], ["ProductVariant", "Toon"], ["activated", "1"],
	 ["wizardDone", "1"], ["ElectricityDisplay", "1"], ["GasDisplay", "1"], ["HeatDisplay", "0"], ["SolarDisplay", "0"],
	 ["SolarActivated", "0"], ["OtherProviderElec", "0"], ["OtherProviderGas", "0"], ["SME", "0"], ["HeatWinner", "0"],
	 ["mobileAccess", "0"], ["supportEnabled", "0"], ["researchEnabled", "0"], ["statusUsageFirstUse", "0"],
	 ["scStatusFlags", "0"], ["commissionState", "0"]].forEach(function (kv) { ag.addChild(kv[0], kv[1], 0); });
	ag.addChild("features", null, 0);
	ag.addChild("featureInputs", null, 0);
	objects["agreementDetail"] = ag;
	return objects;
}

// an object as the web API's getObjectConfigTree writes it: every child a list, a text child a list of
// strings: {"states":[{"state":[{"id":["0"],"tempValue":["2000"]}, ...]}],"internalAddress":[...]}
function toTree(node) {
	var o = {};
	for (var c = node.child; c; c = c.sibling) {
		var v = c.child ? toTree(c) : c.text;
		(o[c.name] || (o[c.name] = [])).push(v);
	}
	return o;
}

// the key an object is stored under: its internalAddress, or tile:<uuid> for home screen tiles
function keyOf(node) {
	if (node.name === "tile") return "tile:" + node.getChildText("uuid");
	return node.getChildText("internalAddress") || node.name;
}

// a store saved by an older toonsim gets the default objects it does not have yet
function withDefaults(stored, defaults) {
	if (!stored) return defaults;
	for (var k in defaults) if (!stored[k]) stored[k] = defaults[k];
	return stored;
}

function load(Bxt) {
	try {
		var xhr = new XMLHttpRequest();
		xhr.open("GET", STORE, false);
		xhr.send();
		if (xhr.responseText) {
			var objects = {};
			var root = Bxt.parseXml(xhr.responseText).getChild("store");
			for (var c = root ? root.child : null; c; c = c.sibling) objects[keyOf(c)] = c;
			return objects;
		}
	} catch (e) {}
	return null;
}

function save(dev) {
	var xml = "<store>";
	for (var k in dev.state.objects) xml += dev.state.objects[k].toXml();
	xml += "</store>";
	try {
		var xhr = new XMLHttpRequest();
		xhr.open("PUT", STORE, false);
		xhr.send(xml);
	} catch (e) { console.log("toonsim hcb_config: cannot save", e); }
}

function device(Bxt) {
	var stored = load(Bxt);
	var dev = {
		type: "hcb_config",
		state: {
			locale: "nl_NL", currency: "EUR", timezone: "Europe/Amsterdam",
			brightness: 80, dimBrightness: 20, autoBrightness: 0,
			timeBeforeDimmingInSec: 60, timeBeforeScreenOffInMin: 0, screenOffIsProgramBased: 0,
			prominentWidgetLeft: 0, keyboardLocale: "nl_NL",
			objects: withDefaults(stored, defaultObjects(Bxt))
		},
		// the local web server: http://localhost/hcb_config?action=...
		http: {
			"getLocale": function (q, dev) {
				return { result: "ok", locale: dev.state.locale, timezone: dev.state.timezone };
			},
			// &package=happ_thermstat&internalAddress=thermostatStates
			"getObjectConfigTree": function (q, dev) {
				var o = dev.state.objects[q.internalAddress];
				if (!o) return { result: "error", reason: "object not found" };
				var tree = toTree(o);
				if (!tree.uuid) tree.uuid = ["sim-" + q.internalAddress];
				if (q.internalAddress === "thermostatStates" && !tree.statesSaved) tree.statesSaved = ["1"];
				return tree;
			}
		},
		requests: {
			"ConfigProvider.GetPackageConfig": function (msg, dev) {
				var s = dev.state, pkg = msg.getArgument("PackageName") || "qt-gui";
				var r = msg.createResponse();
				r.addArgument("Config", null);
				var cfg = r.getArgumentXml("Config");
				if (pkg === "qt-gui") {
					var sys = cfg.addChild("sysConfig", null, 0);
					sys.addChild("locale", s.locale, 0);
					sys.addChild("currency", s.currency, 0);
					sys.addChild("timezone", s.timezone, 0);
					var sc = cfg.addChild("screenConfig", null, 0);
					["brightness", "dimBrightness", "autoBrightness", "timeBeforeDimmingInSec", "timeBeforeScreenOffInMin",
					 "screenOffIsProgramBased", "prominentWidgetLeft"].forEach(function (k) { sc.addChild(k, s[k], 0); });
				}
				for (var k in s.objects) {
					var o = s.objects[k];
					if ((o.getChildText("package") || "qt-gui") === pkg) cfg.appendNode(o.clone());
				}
				return r;
			},
			// TSC settings asks for a reboot after writing its startup file (and after subscription changes)
			"specific1.RequestReboot": function (msg, dev) {
				dev.hub.reboot();
				return null;
			},
			"ConfigProvider.GetObjectConfig": function (msg, dev) {
				var key = msg.getArgument("internalAddress");
				var r = msg.createResponse();
				r.addArgument("Config", null);
				var o = dev.state.objects[key];
				if (o) r.getArgumentXml("Config").appendNode(o.clone());
				return r;
			},
			"ConfigProvider.SetObjectConfig": function (msg, dev) {
				var cfg = msg.getArgumentXml("Config");
				var changed = [];
				for (var c = cfg ? cfg.child : null; c; c = c.sibling) {
					if (c.name === "package") continue;          // the tile messages carry a stray <package> first
					var key = keyOf(c);
					if (c.name === "tile" && c.getChild("isZombie")) { delete dev.state.objects[key]; changed.push(key); continue; }
					var prev = dev.state.objects[key];
					var node = c.clone();
					// a partial update (e.g. qtConfig.baseSetTilesLoaded) keeps the other stored fields
					if (prev && node.name !== "device")
						for (var f = prev.child; f; f = f.sibling) if (!node.getChild(f.name)) node.appendNode(f.clone());
					dev.state.objects[key] = node;
					changed.push(key);
				}
				save(dev);
				changed.forEach(function (k) { if (dev.hub) dev.hub.configStored(k, dev.state.objects[k] || null); });
				return msg.createResponse();
			}
		}
	};
	return dev;
}
