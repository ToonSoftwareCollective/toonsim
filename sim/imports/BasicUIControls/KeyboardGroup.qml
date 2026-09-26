import QtQuick 2.1

	// the key buttons of an on-screen keyboard join it as controlGroup; keyPressed(key) per press
ControlGroup {
	property bool enableLongPress: false
	signal keyPressed(var key)
	exclusive: false
}
