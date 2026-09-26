import QtQuick 2.1
import BxtClient 1.0
import "../imports/BxtClient/bxt.js" as Bxt
import "hcb_config.js" as HcbConfig
import "happ_scsync.js" as HappScsync
import "hcb_netcon.js" as HcbNetcon
import "happ_thermstat.js" as HappThermstat
import "hdrv_p1.js" as HdrvP1
import "happ_pwrusage.js" as HappPwrusage
import "happ_usermsg.js" as HappUsermsg
import "hcb_rrd.js" as HcbRrd
import "hdrv_zwave.js" as HdrvZwave
import ThermostatUtils 1.0

	// The simulated Toon daemons behind the bxt bus. Each device is a JS file in this folder that
	// defines { type, commonName, state, requests: { "Service.Action": fn(msg, dev) }, datasets:
	// { name: fn(dev) }, notifies: { serviceId: fn(dev) -> { argument: value } } }; see hcb_config.js for the pattern. A request returns a response message
	// (msg.createResponse() + arguments), null for "handled, no answer", or nothing at all, which
	// the bus logs as unhandled.
	//
	// Changing device state from outside (remote control, tests): simDevices.set("happ_thermstat",
	// { currentTemp: 2150 }) updates the state and republishes that device's datasets.
QtObject {
	id: devices

	property var _devices: []

	function _add(module) {
		var d = module.device(Bxt);
		d.uuid = d.uuid || ("sim-" + d.type + "-0001");
		d.commonName = d.commonName || d.type;
		d.state = d.state || {};
		d.requests = d.requests || {};
		d.datasets = d.datasets || {};
		d.notifies = d.notifies || {};
		d.hub = hub;
		_devices.push(d);
	}

	// every daemon type the GUI looks for exists; the ones without their own file answer with empty
	// datasets and empty responses (logged), so no app waits for them forever
	readonly property var _genericTypes: ["happ_thermstat", "happ_pwrusage", "hdrv_p1", "happ_eventmgr",
		"hcb_netcon", "happ_kpi", "hdrv_sensory", "happ_smartplug", "hcb_bxtproxy", "hdrv_hue", "happ_hvac"]

	Component.onCompleted: {
		_add(HcbConfig);
		_add(HappScsync);
		_add(HcbNetcon);
		_add(HappThermstat);
		_add(HdrvP1);
		_add(HappPwrusage);
		_add(HappUsermsg);
		_add(HcbRrd);
		_add(HdrvZwave);
		_add({ device: HcbNetcon.upstream });
		_genericTypes.forEach(function (t) {
			if (!byType(t)) _add({ device: function () { return { type: t }; } });
		});
		_devices.forEach(function (d) { if (d.init) d.init(d); });
	}

		// what a device can reach of the others (d.hub): other devices, publishing its own data, the
		// thermostat program helpers, and a hook when hcb_config stores something
	property var hub: ({
		byType: function (t) { return devices.byType(t); },
		thermostatUtils: ThermostatUtils,
		// a dataset goes out only when it changed, as the Toon's daemons do: apps react to every update
		// (TSC's summer mode takes an update of thermostatStates as "changed by hand")
		publish: function (d) {
			d._published = d._published || {};
			for (var name in d.datasets) {
				var node = d.datasets[name](d);
				var xml = node.toXml ? node.toXml() : String(node);
				if (d._published[name] === xml) continue;
				d._published[name] = xml;
				BxtClient.publishDataset(d.uuid, name, node);
			}
			for (var svc in d.notifies) BxtClient.notify(d.uuid, svc, devices.notification(d.uuid, svc));
		},
		configStored: function (key, node) {
			devices._devices.forEach(function (d) { if (d.configStored) d.configStored(d, key, node); });
		},
		// a reboot of the Toon (hcb_config's RequestReboot): here the GUI restarts
		reboot: function () {
			console.log("toonsim: reboot requested, restarting the GUI");
			if (typeof toonsimControl !== "undefined") toonsimControl.restart();
		}
	})

	// the local web server (src/localweb.cpp): http://localhost/<daemon>?action=<name>&... goes to the
	// daemon's http.<name>(query, dev), which returns an object (sent as JSON), a string, or
	// { status, type, body }
	function httpRequest(path, query) {
		var q = {};
		String(query || "").split("&").forEach(function (kv) {
			if (!kv) return;
			var i = kv.indexOf("=");
			var k = decodeURIComponent((i < 0 ? kv : kv.slice(0, i)).replace(/\+/g, " "));
			q[k] = i < 0 ? "" : decodeURIComponent(kv.slice(i + 1).replace(/\+/g, " "));
		});
		// the Toon 2's sensors, which tsc writes to /qmf/www/tsc/sensors every round
		if (path === "/tsc/sensors") {
			var th = byType("happ_thermstat");
			return { status: 200, type: "application/json", body: JSON.stringify({
				temperature: Math.round(th.state.currentTemp / 10) / 10, humidity: 55.0, tvoc: 11, eco2: 473, intensity: 56 }) };
		}
		var name = String(path).replace(/^\/+/, "").split("/")[0];
		var d = byType(name);
		var fn = d && d.http ? d.http[q.action] : null;
		if (!fn) {
			console.log("toonsim web: no handler for", path + (query ? "?" + query : ""));
			return { status: 404, type: "text/plain", body: "not simulated: " + path };
		}
		var r = fn(q, d);
		if (r && r.body !== undefined && r.status !== undefined) return r;
		if (typeof r === "string") return { status: 200, type: "text/plain", body: r };
		return { status: 200, type: "application/json", body: JSON.stringify(r) };
	}

	// a notification from outside the GUI, as scripts on the Toon send them with /HCBv2/bin/bxt
	function createNotification(type, subType, text, args) {
		var d = byType("happ_usermsg");
		HappUsermsg.create(d, type, subType, text, args, false);
		return "ok";
	}

		// the simulation clock: every device with a tick() moves on (the thermostat heats or cools)
	property Timer _clock: Timer {
		interval: 5000
		running: true
		repeat: true
		onTriggered: devices._devices.forEach(function (d) { if (d.tick) d.tick(d); })
	}

	function list() { return _devices; }

	function byUuid(uuid) {
		for (var i = 0; i < _devices.length; i++) if (_devices[i].uuid === uuid) return _devices[i];
		return null;
	}

	function byType(type) {
		for (var i = 0; i < _devices.length; i++) if (_devices[i].type === type) return _devices[i];
		return null;
	}

	// a request from the GUI: the answer, null (handled, nothing to say) or undefined (nobody knows it)
	function handle(msg) {
		var d = byUuid(msg.destination);
			// sent before discovery (no destination yet): the device that answers this service takes it
		if (!d && !msg.destination) {
			var key = msg.serviceId + "." + msg.name;
			for (var i = 0; i < _devices.length && !d; i++) if (_devices[i].requests[key]) d = _devices[i];
		}
		if (!d) return undefined;		var fn = d.requests[msg.serviceId + "." + msg.name] || d.requests[msg.name];
		if (!fn) {
			console.log("toonsim bxt: default answer for", msg.serviceId + "." + msg.name, "to", d.type);
			var empty = msg.createResponse();
			empty.lenient = true;          // every XML argument the GUI asks for exists, and is empty
			return empty;
		}
		var reply = fn(msg, d);
		return reply === undefined ? null : reply;
	}

	// a dataset the device does not define arrives empty, so the handler runs and the app goes on
	function dataset(uuid, name) {
		var d = byUuid(uuid);
		if (!d) return null;
		var fn = d.datasets[name];
		return fn ? fn(d) : new Bxt.Node(name);
	}

	// the current notification of a device for serviceId, as a message ({ arg: value } from its
	// 'notifies' table), or null when the device does not report that service
	function notification(uuid, serviceId) {
		var d = byUuid(uuid);
		var fn = d ? d.notifies[serviceId] : null;
		if (!fn) return null;
		var args = fn(d);
		var msg = new Bxt.Message(Bxt.NOTIFICATION, d.uuid, "qt-gui", serviceId, serviceId);
		for (var k in args) msg.addArgument(k, args[k]);
		return msg;
	}

	// ---- driving the simulation ----

	function set(type, changes) {
		var d = byType(type);
		if (!d) return "no device " + type;
		for (var k in changes) d.state[k] = changes[k];
		hub.publish(d);
		return "ok";
	}

	function get(type) {
		var d = byType(type);
		return d ? JSON.stringify(d.state) : "no device " + type;
	}
}
