.pragma library

// hdrv_zwave: the Z-Wave driver (smart plugs, smoke detectors). The simulated Toon has no Z-Wave
// devices: the device list is empty ({} as on a Toon without any), commands are acknowledged.

function device(Bxt) {
	return {
		type: "hdrv_zwave",
		http: {
			"getDevices.json": function () { return {}; },
			"getDevices": function () { return {}; },
			"basicCommand": function () { return { result: "ok" }; },
			"GetBasic": function () { return { result: "ok" }; }
		}
	};
}
