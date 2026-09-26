pragma Singleton
import QtQuick 2.1

	// the current date for tiles that change with it (the logo at Easter, ...); updated every minute
QtObject {
	property date now: new Date()
	property int day: now.getDate()
	property int month: now.getMonth() + 1
	property double timestamp: now.getTime()
	property bool isEaster: false
	property Timer _t: Timer { interval: 60000; running: true; repeat: true; onTriggered: now = new Date() }
}
