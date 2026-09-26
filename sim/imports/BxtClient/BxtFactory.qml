pragma Singleton
import QtQuick 2.1
import "bxt.js" as Bxt

	// qt-gui's BxtFactory: newBxtMessage(BxtMessage.ACTION_INVOKE, destinationUuid, serviceId, action)
QtObject {
	function newBxtMessage(type, destination, serviceId, action) {
		return Bxt.newMessage(type, destination, serviceId, action);
	}
}
