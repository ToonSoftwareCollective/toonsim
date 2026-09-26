import QtQuick 2.1
import ScreenStateController 1.0
import GraphUtils 1.0
import "devices"

	// qt-gui's context properties. Every property declared here becomes a context property with the
	// same name (main.cpp), so the Toon's QML sees them exactly as on the device. isNxt is set by
	// main.cpp from --size. The remote control reaches this object as "toonsim".
QtObject {
	id: sim

	property bool isDemoBuild: false
	property bool isHello: false             // the "Toon Hello" variant; this simulates a regular Toon

	property QtObject displaySettings: QtObject {
		property bool rotateTiles: false
	}

	// Eneco's usage analytics
	property QtObject countly: QtObject {
		function startSession() {}
		function stopSession() {}
		function sendEvent() {}
		function sendPageViewEvent() {}
	}

	property ScreenStateController screenStateController: ScreenStateController {}

	// the graphs' date helpers (GraphUtils.PERIOD_* comes from the type, the functions from this instance)
	property GraphUtils graphUtils: GraphUtils {}

	// the simulated daemons behind the bxt bus (sim/devices)
	property Devices simDevices: Devices {}

	// qt-gui's QtUtils: helpers the QML calls into C++ for
	property QtObject qtUtils: QtObject {
		function escapeHtml(s) {
			return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
		}
		function mightBeRichText(s) { return /<[a-zA-Z\/][^>]*>/.test(String(s)); }
		// the path of a URL, for "image://scaled/" + urlPath(url): qrc:/a/b.svg -> /a/b.svg
		function urlPath(u) {
			var s = String(u);
			var m = s.match(/^[a-zA-Z][\w+.-]*:(\/\/[^\/]*)?(\/.*)$/);
			return m ? m[2] : s;
		}
		function clearFocus() {}
		function psplashProgress(p) {}
		function psplashQuit() { console.log("toonsim: splash screen removed, GUI is up"); }
		function reboot() { console.log("toonsim: the GUI asked for a reboot (ignored)"); }
		function getTenant() { return "eneco"; }
		function screenDpiY() { return isNxt ? 158 : 125; }
		function isRootItem(item) { return item && !item.parent; }
		function getChildByName(parent, name) {
			if (!parent) return null;
			var kids = parent.children || [];
			for (var i = 0; i < kids.length; i++) {
				if (kids[i].objectName === name) return kids[i];
				var deep = getChildByName(kids[i], name);
				if (deep) return deep;
			}
			return null;
		}
		function queuedConnect(sender, signalSig, receiver, slotSig) {
			var sig = signalSig.split("(")[0], slot = slotSig.split("(")[0];
			sender[sig].connect(function () {
				var args = arguments;
				Qt.callLater(function () { receiver[slot].apply(receiver, args); });
			});
		}
		function colorToArgbString(c) {
			var q = Qt.lighter(c, 1.0);
			function h(v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s; }
			return "#" + h(q.a) + h(q.r) + h(q.g) + h(q.b);
		}
		function addColorAlpha(c, alpha) { var q = Qt.lighter(c, 1.0); return Qt.rgba(q.r, q.g, q.b, alpha); }
		function toISOString(d) { return d ? d.toISOString() : ""; }
		function fromISOString(s) { return new Date(s); }
		function stringToDate(s, format) { return new Date(s); }
		function dateToString(d, format) { return Qt.formatDateTime(d, format); }
		function isDateValid(d) { return d instanceof Date && !isNaN(d.getTime()); }
		function daysInMonth(year, month) { return new Date(year, month, 0).getDate(); }
		function getWeatherDefaultCityName() { return "Amsterdam"; }
		function getWeatherDefaultCityId() { return 2759794; }
	}

	// the feature switches: as qt-gui, from the tenant settings /qmf/qml/config/TenantSettings.json (TSC's
	// "Toon subscription features" screen writes them, then reboots); the defaults below for the ones it
	// does not have. Read at the start, as the Toon does.
	property QtObject feature: QtObject {
		property var on: ({ appStatusUsageEnabled: true, appInboxEnabled: true, appHeatingOverviewEnabled: false,
		                    appCustomerServiceEnabled: false, appSmokeDetectorEnabled: false })
		property var tenant: {
			try {
				var xhr = new XMLHttpRequest();
				xhr.open("GET", "file:///qmf/qml/config/TenantSettings.json", false);
				xhr.send();
				if (xhr.responseText) return JSON.parse(xhr.responseText);
			} catch (e) { console.log("toonsim: TenantSettings.json not readable:", e); }
			return {};
		}
		function _v(name, def) { return tenant.hasOwnProperty(name) ? tenant[name] : def; }
		function _f(name) { return !!_v(name, on[name]); }
		function i18nLocales() { return _v("i18nLocales", ["nl_NL", "en_GB"]); }
		function appUpsellUrl() { return _v("appUpsellUrl", ""); }
		function onlineErrorHelpUrl() { return ""; }
		function featPinProtectNumber() { return ""; }
		function featBenchmarkFriendsEnabled() { return _f("featBenchmarkFriendsEnabled"); }
		function appSolarEnabled() { return _f("appSolarEnabled"); }
		function appUpsellFeatures() { return _v("appUpsellFeatures", []); }
		function featElecFixedDayCostEnabled() { return _f("featElecFixedDayCostEnabled"); }
		function appSmokeDetectorEnabled() { return _f("appSmokeDetectorEnabled"); }
		function featSMEEnabled() { return _f("featSMEEnabled"); }
		function appHeatRecoveryEnabled() { return _f("appHeatRecoveryEnabled"); }
		function featWaterInsightsEnabled() { return _f("featWaterInsightsEnabled"); }
		function appInternetSettingsPinProtectWifiNetworkChange() { return !!_v("appInternetSettingsPinProtectWifiNetworkChange", false); }
		function appStrvFeatureEnabled() { return _f("appStrvFeatureEnabled"); }
		function featShowEnergyMeterImages() { return _f("featShowEnergyMeterImages"); }
		function featHolidayOffPeakEnabled() { return !!_v("featHolidayOffPeakEnabled", false); }
		function appEMetersSettingsAdvancedDisabled() { return !!_v("appEMetersSettingsAdvancedDisabled", false); }
		function featFlexibleTariffsEnabled() { return !!_v("featFlexibleTariffsEnabled", false); }
		function enabledHeatingModeNoHeating() { return !!_v("enabledHeatingModeNoHeating", false); }
		function featHumidityEnabled() { return _f("featHumidityEnabled"); }
		function appControlPanelPinProtectRemoveBridge() { return !!_v("appControlPanelPinProtectRemoveBridge", false); }
		function appControlPanelLampRenameDisabled() { return !!_v("appControlPanelLampRenameDisabled", false); }
		function appControlPanelSmartplugHardRemoveDisabled() { return !!_v("appControlPanelSmartplugHardRemoveDisabled", false); }
		function appControlPanelPlugRenameDisabled() { return !!_v("appControlPanelPlugRenameDisabled", false); }
		function appControlPanelHueSceneSaveDisabled() { return !!_v("appControlPanelHueSceneSaveDisabled", false); }
		function appCustomerServiceQrScreenEnabled() { return !!_v("appCustomerServiceQrScreenEnabled", false); }
		function appImprintEnabled() { return !!_v("appImprintEnabled", false); }
		function enabledGasMeterConfiguration() { return !!_v("enabledGasMeterConfiguration", true); }
		function appGraphTileLowestUsage() { return !!_v("appGraphTileLowestUsage", false); }
		function demoDisplayEnabled() { return !!_v("demoDisplayEnabled", false); }
		function featSmokeDetectorSensitivityEnabled() { return !!_v("featSmokeDetectorSensitivityEnabled", false); }
		function appSystemSettingsFactoryResetDisabled() { return !!_v("appSystemSettingsFactoryResetDisabled", true); }
		function featContactSettingsTabEnabled() { return !!_v("featContactSettingsTabEnabled", false); }
		function enabledHeatingSourceConfiguration() { return !!_v("enabledHeatingSourceConfiguration", true); }
		function appInboxEnabled() { return _f("appInboxEnabled"); }
		function appCustomerServiceEnabled() { return _f("appCustomerServiceEnabled"); }
		function appImageViewerEnabled() { return !!_v("appImageViewerEnabled", false); }
		function appUpsellEnabled() { return !!_v("appUpsellEnabled", false); }
		function appHeatingOverviewEnabled() { return _f("appHeatingOverviewEnabled"); }
		function appStatusUsageEnabled() { return _f("appStatusUsageEnabled"); }
		function appFionaEnabled() { return !!_v("appFionaEnabled", false); }
	}

	// (qlanguage, the translations, is src/language.h)

	// qt-gui's dialog manager (dialogpopup.c): one DialogPopup (qrc:/qb/components) in the container
	// Home.qml hands over; showDialog(size, title, content, button1, callback1, button2, callback2).
	// content is text, or a .qml URL that is loaded into the dialog. A button (or the close cross)
	// runs its callback and closes the dialog, unless the callback returns true.
	// (the context property 'qdialog' is src/dialogfacade.h, which adds SizeSmall/Medium/Large and calls these)
	property QtObject qdialogImpl: QtObject {
		property QtObject context: null
		property var _closeCallback: null
		property var _cb1: null
		property var _cb2: null

		// dialogfacade.h creates the DialogPopup in the GUI's context and hands it over here
		function attach(popup) {
			context = popup;
			context.button1.clicked.connect(function () { _press(_cb1); });
			context.button2.clicked.connect(function () { _press(_cb2); });
		}
		function _press(cb) {
			var keep = (typeof cb === "function") ? cb() : false;
			if (keep !== true) _close(false);
		}
		function _close(runCloseCallback) {
			if (!context) return;
			if (runCloseCallback && typeof _closeCallback === "function") _closeCallback();
			context.hide();
			_closeCallback = null;
		}
		function reset() {
			if (!context) return;
			context.size = 0; context.title = ""; context.content = ""; context.contentSource = "";
			context.iconSource = ""; context.rightIconSource = ""; context.closeBtnForceShow = false;
			context.closeBtnForceHide = false; context.highlightPrimaryBtn = false; context.bodyTextAlignLeft = false;
			context.bodyHorizontalMargins = -1; context.blockDimState = true;
			context.button1.text = ""; context.button2.text = "";
			_cb1 = null; _cb2 = null; _closeCallback = null;
		}
		function showDialog(size, title, content, btn1Text, btn1Callback, btn2Text, btn2Callback) {
			if (!context) return;
			reset();
			context.size = size;
			context.title = title || "";
			var c = content === undefined || content === null ? "" : String(content);
			if (/\.qml$/i.test(c)) context.contentSource = c; else context.content = c;
			context.button1.text = btn1Text || "";
			context.button2.text = btn2Text || "";
			_cb1 = btn1Callback || null;
			_cb2 = btn2Callback || null;
			context.show();
			console.log("toonsim qdialog: shown '" + context.title + "'");
		}
		function setClosePopupCallback(cb) { _closeCallback = cb; }
		function buttonHeaderRightClicked() { _close(true); }
	}

	property QtObject hcblog: QtObject {
		property string kpiUuid
		function logKpi() {}
		function logMsg(m) { console.log("hcblog:", m); }
	}

	// the install wizard is done: every stage completed, none pending
	property QtObject wizardstate: QtObject {
		property bool completed: true
		function hasStage(name) { return false; }
		function stageCompleted(name) { return true; }
		function setStageCompleted(name, done) {}
		function stageMandatory(name) { return false; }
		function stages() { return []; }
		function deleteFile() {}
	}

	property QtObject parentalControl: QtObject {
		property bool enabled: false
		property bool hasPin: false
		function isValidPin(pin) { return true; }
		function setPin(pin) {}
		function reset() {}
		function getResetPrefix() { return ""; }
	}
}
