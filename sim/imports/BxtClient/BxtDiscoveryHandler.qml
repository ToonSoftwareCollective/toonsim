import QtQuick 2.1

	// announces a device of deviceType (or one of equivalentDeviceTypes) with discoReceived(deviceUuid, ...)
Item {
	property string deviceType
	property var equivalentDeviceTypes: []
	property string deviceUuid
	signal discoReceived(string deviceUuid, string deviceType, string commonName)
	Component.onCompleted: BxtClient.registerHandler("disco", this)
	Component.onDestruction: BxtClient.unregisterHandler("disco", this)
}
