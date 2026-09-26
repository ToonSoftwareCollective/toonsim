pragma Singleton
import QtQuick 2.1
import "bxt.js" as Bxt

	// The bxt bus as the Toon's QML sees it (qt-gui's BxtClient singleton), connected to the simulated
	// devices of sim/devices (context property simDevices) instead of the real hcb_* / happ_* daemons.
	//
	// GUI -> device: sendMsg / doAsyncBxtRequest route a message to the device with that uuid; its
	//   answer goes to the request's callback, or to the BxtResponseHandlers for that response.
	// device -> GUI: discovery (BxtDiscoveryHandler), datasets (BxtDatasetHandler), notifications
	//   (BxtNotifyHandler) and actions (BxtActionHandler).
	// A request no device answers is logged as "toonsim bxt: unhandled ...": the to-do list.
QtObject {
	id: bus

	property bool started: false
	property var _handlers: ({ disco: [], dataset: [], response: [], notify: [], action: [] })
	property int unhandledCount: 0

	function registerHandler(kind, h) {
		_handlers[kind].push(h);
		if (!started) return;
			// a handler created after start-up (an app loaded later) still hears about devices and data
		if (kind === "disco") simDevices.list().forEach(function (d) { if (_matches(h, d)) _disco(h, d); });
		else if (kind === "dataset" && h.discoHandler && h.discoHandler.deviceUuid) _pushDatasets(h, h.discoHandler.deviceUuid);
		else if (kind === "notify") notifyHandlerReady(h);
	}

	// a dataset handler whose discoHandler was set (or changed) after start-up: send it the current data
	function datasetHandlerReady(h) {
		if (started && h.discoHandler && h.discoHandler.deviceUuid) _pushDatasets(h, h.discoHandler.deviceUuid);
	}

	function unregisterHandler(kind, h) {
		var list = _handlers[kind];
		var i = list.indexOf(h);
		if (i >= 0) list.splice(i, 1);
	}

	// ---- qt-gui's API ----

	function start() {
		started = true;
		sendDiscoMsg();
		_handlers.notify.slice().forEach(notifyHandlerReady);
	}

	function sendDiscoMsg() {
		simDevices.list().forEach(function (d) {
			_handlers.disco.slice().forEach(function (h) { if (_matches(h, d)) _disco(h, d); });
		});
	}

	function sendMsg(msg) {
		Qt.callLater(function () { _route(msg, null); });
	}

	function doAsyncBxtRequest(msg, callback, timeoutSec) {
		Qt.callLater(function () { _route(msg, callback || function () {}); });
	}

	function getCommonname(uuid) {
		var d = simDevices.byUuid(uuid);
		return d ? d.commonName : "";
	}

	property int _uuidSeq: 0
	function getNewUuid() { return "sim-" + Date.now().toString(16) + "-" + (++_uuidSeq); }
	function setLocale(locale) {}
	function setTimezone(tz) {}

	// ---- used by the simulated devices ----

	function publishDataset(uuid, name, node) {
		_handlers.dataset.slice().forEach(function (h) {
			if (h.dataset === name && h.discoHandler && h.discoHandler.deviceUuid === uuid) h.datasetUpdate(node);
		});
	}

	function notify(uuid, serviceId, msg) {
		_handlers.notify.slice().forEach(function (h) {
			if (h.serviceId === serviceId && (!h.sourceUuid || h.sourceUuid === uuid)) h.notificationReceived(msg);
		});
	}

	// a device (or the remote control) invokes an action on the GUI, e.g. setScreenState
	function invokeAction(msg) {
		var n = 0;
		_handlers.action.slice().forEach(function (h) { if (h.action === msg.name) { h.actionReceived(msg); n++; } });
		return n;
	}

	function newMessage(type, source, destination, serviceId, action) {
		return new Bxt.Message(type, source, destination, serviceId, action);
	}

	// ---- routing ----

	function _matches(h, d) {
		if (h.deviceType === d.type) return true;
		var eq = h.equivalentDeviceTypes;
		return !!eq && eq.length !== undefined && Array.prototype.indexOf.call(eq, d.type) >= 0;
	}

	function _disco(h, d) {
		h.deviceUuid = d.uuid;
		h.discoReceived(d.uuid, d.type, d.commonName);
		_handlers.dataset.slice().forEach(function (dh) { if (dh.discoHandler === h) _pushDatasets(dh, d.uuid); });
	}

	// a notify handler that is ready (created, or its sourceUuid set after discovery) hears the
	// current state of every device that reports its serviceId, like hcb_netcon's initial poll
	function notifyHandlerReady(h) {
		if (!started) return;
		simDevices.list().forEach(function (d) {
			if (h.sourceUuid && h.sourceUuid !== d.uuid) return;
			var msg = simDevices.notification(d.uuid, h.serviceId);
			if (msg) h.notificationReceived(msg);
		});
	}

	function _pushDatasets(dh, uuid) {
		var node = simDevices.dataset(uuid, dh.dataset);
		if (node) dh.datasetUpdate(node);
	}

	function _route(msg, callback) {
		var reply = simDevices.handle(msg);
		if (reply === undefined) {
			unhandledCount++;
			console.log("toonsim bxt: unhandled", msg.serviceId + "." + msg.name, "to", msg.destination || "(no destination)");
		}
		if (callback) {
			if (typeof callback === "function") callback(reply || null);
			else if (callback.messageReceived) callback.messageReceived(reply || null);
			return;
		}
		if (!reply) return;
		_handlers.response.slice().forEach(function (h) {
			if (h.response === reply.name && (!h.serviceId || h.serviceId === reply.serviceId)) h.responseReceived(reply);
		});
	}
}
