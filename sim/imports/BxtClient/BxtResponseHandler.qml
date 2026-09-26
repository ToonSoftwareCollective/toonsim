import QtQuick 2.1

	// receives responses named 'response' (from serviceId, when set) to messages sent with sendMsg
Item {
	property string serviceId
	property string response
	signal responseReceived(var message)
	Component.onCompleted: BxtClient.registerHandler("response", this)
	Component.onDestruction: BxtClient.unregisterHandler("response", this)
}
