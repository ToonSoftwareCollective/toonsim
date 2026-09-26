import QtQuick 2.1

	// an action a device invokes on the GUI (e.g. setScreenState)
Item {
	property string action
	property string dialogContentSource
	signal actionReceived(var message)
	Component.onCompleted: BxtClient.registerHandler("action", this)
	Component.onDestruction: BxtClient.unregisterHandler("action", this)
}
