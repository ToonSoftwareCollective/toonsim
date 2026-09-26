import QtQuick 2.1

	// the callback object of doAsyncBxtRequest(msg, callback, timeout): messageReceived(null) on timeout
Item {
	signal messageReceived(var message)
}
