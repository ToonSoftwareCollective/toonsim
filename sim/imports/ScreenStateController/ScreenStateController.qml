import QtQuick 2.1

	// qt-gui's screen state machine: active -> (after timeBeforeDimmingInSec without a touch) dimmed
	// colours, when screenColorDimmedIsReachable. The instance is the context property
	// screenStateController (sim/SimContext.qml); main.cpp calls wakeup() on every touch. The enum
	// values match Canvas.qml's setScreenState action handler.
Item {
	id: ctl

	enum State { ScreenOff = 4, ScreenActive = 1, ScreenDimmed = 2, ScreenColorDimmed = 3 }

	property int screenState: ScreenStateController.ScreenActive
	property int previousScreenState: ScreenStateController.ScreenActive
	property bool screenColorDimmedIsReachable: true
	property bool dimmedColors: screenState === ScreenStateController.ScreenColorDimmed
	property bool manualDim: false
	property bool screenOffBlackMode: false
	property bool prominentWidgetLeft: false
	property bool screenOffIsProgramBased: false
	property bool canAutoBrightness: false
	property int autoBrightnessControl: 0
	property int backLightValueScreenActive: 80
	property int backLightValueScreenDimmed: 20
	property int timeBeforeDimmingInSec: 60
	property int timeBeforeScreenOffInMin: 0
	property bool running: false

	signal settingsChanged()
	signal screenTouched()

	function init() {}
	function start() { running = true; dimTimer.restart(); }
	// the dim button on the home screen (DimIcon) sets manualDim: dim now; the next touch wakes it up
	onManualDimChanged: {
		if (!manualDim) return;
		dimTimer.stop();
		setState(screenColorDimmedIsReachable ? ScreenStateController.ScreenColorDimmed : ScreenStateController.ScreenDimmed);
	}
	function wakeup() {
		manualDim = false;
		screenTouched();
		if (screenState !== ScreenStateController.ScreenActive) setState(ScreenStateController.ScreenActive);
		if (running) dimTimer.restart();
	}
	function setState(s) {
		if (s === screenState) return;
		previousScreenState = screenState;
		screenState = s;
	}
	function forceTestScreenState(s) { setState(s); }
	function getMaxBackLightValueScreenDimmed() { return 50; }
	function notifyChangeOfSettings() { settingsChanged(); }
	function setProgramBasedScreenOffParameters() {}

	Timer {
		id: dimTimer
		interval: Math.max(5, ctl.timeBeforeDimmingInSec) * 1000
		onTriggered: if (ctl.screenColorDimmedIsReachable) ctl.setState(ScreenStateController.ScreenColorDimmed)
	}
	onScreenColorDimmedIsReachableChanged: if (running) dimTimer.restart()
}
