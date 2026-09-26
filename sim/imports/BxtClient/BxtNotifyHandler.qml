import QtQuick 2.1

	// receives notifications of serviceId (from sourceUuid, when set)
Item {
	property string serviceId
	property string sourceUuid
	property var variables: []
	property bool initialPoll: false
	signal notificationReceived(var message)
	Component.onCompleted: BxtClient.registerHandler("notify", this)
	Component.onDestruction: BxtClient.unregisterHandler("notify", this)
	onSourceUuidChanged: BxtClient.notifyHandlerReady(this)
}
