.pragma library

// happ_usermsg: the notifications in the bar at the top of the screen. Apps create them with
// Notification.CreateNotification (type, subType, text, unique, args) and remove them with
// DeleteNotification (by uuid, by type or by type + subType); the GUI shows the "notifications"
// dataset. On the Toon scripts also send them (/HCBv2/bin/bxt -d :happ_usermsg ...): the simulator's
// tsc does that with simDevices.createNotification(type, subType, text) over the control port.

var counter = 0;

function device(Bxt) {
	return {
		type: "happ_usermsg",
		state: { notifications: [] },
		datasets: {
			"notifications": function (dev) {
				var n = new Bxt.Node("notifications");
				dev.state.notifications.forEach(function (m) {
					var c = n.addChild("notification", null, 0);
					["uuid", "type", "subType", "text", "args", "creationTime"].forEach(function (k) {
						if (m[k] !== undefined && m[k] !== "") c.addChild(k, m[k], 0);
					});
				});
				return n;
			}
		},
		requests: {
			"Notification.CreateNotification": function (msg, dev) {
				create(dev, msg.getArgument("type"), msg.getArgument("subType"), msg.getArgument("text"),
				       msg.getArgument("args"), msg.getArgument("unique") === "true");
				return null;
			},
			"Notification.DeleteNotification": function (msg, dev) {
				var uuid = msg.getArgument("uuid"), type = msg.getArgument("type"), sub = msg.getArgument("subType");
				var args = msg.getArgument("args");
				var before = dev.state.notifications.length;
				dev.state.notifications = dev.state.notifications.filter(function (m) {
					if (uuid) return m.uuid !== uuid;
					if (type && m.type !== type) return true;
					if (sub && m.subType !== sub) return true;
					if (args && m.args !== args) return true;
					return false;
				});
				// only when something went: the notification bar asks to delete "error/network" every time
				// it shows, and an update for nothing would show it again (a loop)
				if (dev.state.notifications.length !== before) dev.hub.publish(dev);
				return null;
			}
		}
	};
}

function create(dev, type, subType, text, args, unique) {
	if (!type || !subType || !text) return;
	if (unique)
		dev.state.notifications = dev.state.notifications.filter(function (m) { return m.type !== type || m.subType !== subType; });
	dev.state.notifications.push({ uuid: "sim-notification-" + (++counter), type: type, subType: subType, text: text,
	                               args: args || "", creationTime: Math.floor(Date.now() / 1000) });
	console.log("toonsim happ_usermsg: notification", type + "/" + subType + ":", text);
	dev.hub.publish(dev);
}
