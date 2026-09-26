import QtQuick 2.1

	// re-emits target.queuedSignal() one event-loop turn later as signalEmitted()
Item {
	id: qc
	property var target
	signal signalEmitted()
	Connections {
		target: qc.target
		ignoreUnknownSignals: true
		function onQueuedSignal() { Qt.callLater(qc.signalEmitted); }
	}
}
