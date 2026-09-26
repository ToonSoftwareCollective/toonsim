import QtQuick 2.1

	// receives a device's dataset (an XML tree, see bxt.js Node) whenever it changes
Item {
	property string dataset
	property var discoHandler
	signal datasetUpdate(var update)
	Component.onCompleted: BxtClient.registerHandler("dataset", this)
	Component.onDestruction: BxtClient.unregisterHandler("dataset", this)
	onDiscoHandlerChanged: BxtClient.datasetHandlerReady(this)
}
