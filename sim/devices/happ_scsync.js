.pragma library

// happ_scsync: the link with Eneco's back office. The GUI asks it which product options the
// customer has (which decides the apps it loads), whether the install wizard is done, and the
// feature flags. The defaults are a gas + electricity customer with a finished wizard.

// its config file, as on the Toon: /mnt/data/qmf/config/config_happ_scsync.xml (also /qmf/config/...).
// The <feature> entries in it are the features GetFeatures reports, read at every start - e.g.
// <feature>noHeating</feature>: a Toon without heating, whose home screen has 6 tiles instead of the
// large thermostat (thermostatPlus's "6 Tiles <=> 4 Tiles" edits the file and reboots). Written from
// the stored agreement when it is not there yet.
var CONFIG = "file:///mnt/data/qmf/config/config_happ_scsync.xml";

function readFeatures(dev) {
	var text = "";
	try {
		var xhr = new XMLHttpRequest();
		xhr.open("GET", CONFIG, false);
		xhr.send();
		text = xhr.responseText || "";
	} catch (e) {}
	if (!text) {
		var cfg = dev.hub.byType("hcb_config");
		var ag = cfg && cfg.state.objects["agreementDetail"];
		if (ag) {
			text = "<Config><package>happ_scsync</package>" + ag.toXml() + "</Config>\n";
			try {
				var put = new XMLHttpRequest();
				put.open("PUT", CONFIG, false);
				put.send(text);
			} catch (e) { console.log("toonsim happ_scsync: cannot write", CONFIG, e); }
		}
	}
	var found = [], re = /<feature>\s*([^<\s]+)\s*<\/feature>/g, m;
	while ((m = re.exec(text)) !== null) if (found.indexOf(m[1]) < 0) found.push(m[1]);
	if (found.length) console.log("toonsim happ_scsync: features from config_happ_scsync.xml:", found.join(", "));
	return found;
}

// the firmware version the Software tab shows: from the opkg control file main.cpp writes (the version
// of the Toon the firmware was pulled from); null when there is none
function readFirmwareVersion() {
	var files = ["file:///var/lib/opkg/info/base-nxt-uni.control", "file:///usr/lib/opkg/info/base-qb2-ene.control"];
	for (var i = 0; i < files.length; i++) {
		try {
			var xhr = new XMLHttpRequest();
			xhr.open("GET", files[i], false);
			xhr.send();
			var m = /Version:\s*([0-9]+(?:\.[0-9]+)*)/.exec(xhr.responseText || "");
			if (m) return m[1];
		} catch (e) {}
	}
	return null;
}

function device(Bxt) {
	return {
		type: "happ_scsync",
		init: function (dev) {
			dev.state.features = readFeatures(dev);
			var version = readFirmwareVersion();
			if (version) {
				var display = dev.state.deviceInfo[0];
				display.SoftwareVersion = display.SoftwareVersion.replace(/[^\/]*$/, version);
				display.AvailableVersion = display.AvailableVersion.replace(/[^\/]*$/, version);
			}
			// the meter settings ask without a service (".GetDeviceInfo"): the same answer
			dev.requests["GetDeviceInfo"] = dev.requests["specific1.GetDeviceInfo"];
		},
		state: {
			standalone: 0, activated: 1, wizardDone: 1, statusUsageFirstUse: 0,
			productOptions: {
				// every option the firmware reads must be present: a missing one counts as "on" in
				// places (parseInt(undefined) !== 0), e.g. district heating in statusUsage
				district_heating: 0, smart_district_heating_basic: 0, smart_district_heating_full: 0, solar: 0, electricity: 1, gas: 1, sw_updates: 1, content_apps: 1,
				telmi_enabeld: 0, boiler_management: 1, other_provider_elec: 0, other_provider_gas: 0,
				heatwinner: 0, SME: 0
			},
			features: [],            // names from GetFeatures, e.g. "displayAutoBrightness"
			deviceInfo: [
				{ DeviceType: "Display", SoftwareVersion: "qb2/ene/6.0.0", AvailableVersion: "qb2/ene/6.0.0", SerialNumber: "SIM-00000001",
				  DeviceModel: "6599-1500-0100", deviceUuid: "sim-hcb_config-0001" },
				{ DeviceType: "BoilerAdapter", SoftwareVersion: "1.3.13", AvailableVersion: "1.3.13", SerialNumber: "SIM-OT-0001",
				  DeviceModel: "OpenTherm boiler module", deviceUuid: "sim-happ_thermstat-0001" },
				{ DeviceType: "MeterAdapter", SoftwareVersion: "2.9.0", AvailableVersion: "2.9.0", SerialNumber: "SIM-MA-0001",
				  DeviceModel: "Meter adapter (P1)", deviceUuid: "sim-hdrv_p1-0001" }
			]		},
		requests: {
			"specific1.GetAgreementDetails": function (msg, dev) {
				var s = dev.state;
				// the stored agreement (TSC's "Zon Op Toon" toggle changes it) decides solar, as on the Toon
				var cfg = dev.hub.byType("hcb_config");
				var ag = cfg && cfg.state.objects["agreementDetail"];
				if (ag && ag.getChildText("SolarActivated") !== "") s.productOptions.solar = parseInt(ag.getChildText("SolarActivated")) || 0;
				var r = msg.createResponse();
				r.addArgument("standalone", s.standalone);
				r.addArgument("activated", s.activated);
				r.addArgument("productOption", null);
				var node = r.getArgumentXml("productOption");
				for (var k in s.productOptions) {
					var c = node.addChild(k, s.productOptions[k], 0);
					if (k === "boiler_management") c.setAttribute("activated", s.productOptions[k]);
				}
				return r;
			},
			"specific1.GetRegistrationInfo": function (msg, dev) {
				var r = msg.createResponse();
				r.addArgument("wizardDone", dev.state.wizardDone);
				return r;
			},
			// the devices shown in Instellingen > Systeem: the display, the boiler module, the meter adapter
			"specific1.GetDeviceInfo": function (msg, dev) {
				var r = msg.createResponse();
				r.addArgument("devices", null);
				var list = r.getArgumentXml("devices");
				dev.state.deviceInfo.forEach(function (i) {
					var n = list.addChild("device", null, 0);
					for (var k in i) n.addChild(k, i[k], 0);
				});
				return r;
			},
			// "status usage" shows its introduction while firstUse is 1
			"specific1.GetStatusUsageFirstUse": function (msg, dev) {
				var r = msg.createResponse();
				r.addArgument("firstUse", dev.state.statusUsageFirstUse);
				return r;
			},
			"specific1.SetStatusUsageFirstUse": function (msg, dev) {
				dev.state.statusUsageFirstUse = parseInt(msg.getArgument("firstUse")) || 0;
				return null;
			},
			"features.GetFeatures": function (msg, dev) {
				var r = msg.createResponse();
				r.addArgument("json", JSON.stringify({ features: dev.state.features }));
				return r;
			}
		}
	};
}
