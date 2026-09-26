import QtQuick 2.1

	// only for the enum: BxtMessage.ACTION_INVOKE etc. The messages themselves are bxt.js objects.
QtObject {
	enum MessageType { ACTION_INVOKE, ACTION_RESPONSE, NOTIFICATION, DATASET }
}
