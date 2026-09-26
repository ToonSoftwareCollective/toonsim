.pragma library

// hcb_netcon: the network daemon. It reports its connection state machine (status: 1 no medium,
// 2 connected, 3 configured, 4 internet, 5 tunnel to the back office), the active interface (gwif)
// and the wifi state. The defaults are a Toon on wifi with a working internet connection.

function device(Bxt) {
	return {
		type: "hcb_netcon",
		state: {
			statemachine: 5, iface: "wlan0", ipaddress: "192.168.2.99", mac: "00:0f:11:22:33:44",
			wifiStatus: "Connected", essid: "Thuisnetwerk", quality: 78, netmask: "255.255.255.0",
			gateway: "192.168.2.254", dns: "192.168.2.254"
		},
		notifies: {
			"status": function (dev) { return { statemachine: dev.state.statemachine }; },
			"gwif": function (dev) { return { iface: dev.state.iface, ipaddress: dev.state.ipaddress }; },
			"WifiInformation": function (dev) { return { WifiStatus: dev.state.wifiStatus }; }
		},
		requests: {
			"NetworkInformation.GetInterfaceInfo": function (msg, dev) {
				var s = dev.state, r = msg.createResponse();
				r.addArgument("iface", msg.getArgument("iface") || s.iface);
				r.addArgument("ipaddress", s.ipaddress);
				r.addArgument("netmask", s.netmask);
				r.addArgument("gateway", s.gateway);
				r.addArgument("dns", s.dns);
				r.addArgument("mac", s.mac);
				r.addArgument("dhcp", "1");
				return r;
			},
			"NetworkInformation.GetWirelessNetworkInformation": function (msg, dev) {
				var s = dev.state, r = msg.createResponse();
				r.addArgument("Essid", s.essid);
				r.addArgument("Quality", s.quality);
				r.addArgument("Mac", s.mac);
				r.addArgument("Encryption", "WPA2");
				return r;
			},
			"NetworkInformation.GetWirelessNetworks": function (msg, dev) {
				var s = dev.state, r = msg.createResponse();
				r.addArgument("networks", null);
				var n = r.getArgumentXml("networks").addChild("network", null, 0);
				n.addChild("Essid", s.essid, 0); n.addChild("Quality", s.quality, 0);
				n.addChild("Mac", s.mac, 0); n.addChild("Encryption", "WPA2", 0);
				return r;
			},
			"specific1.reSendAllNotifies": function () { return null; }
		}
	};
}

// the back-office tunnel (ConnectedState.IsConnected): 1 = the Toon is online with Eneco / TSC
function upstream(Bxt) {
	return {
		type: "UpstreamConnection",
		state: { isConnected: 1 },
		notifies: {
			"ConnectedState": function (dev) { return { IsConnected: dev.state.isConnected }; }
		}
	};
}
