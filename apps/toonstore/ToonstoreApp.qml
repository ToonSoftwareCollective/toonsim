import QtQuick 2.1
import BxtClient 1.0
import FileIO 1.0
import qb.components 1.0
import qb.base 1.0;
import "toonstore.js" as ToonstoreJS

App {
	id: toonstoreApp
	property url fullScreenUrl : "ToonstoreScreen.qml"
	property url fullSettingsUrl : "ToonstoreSettings.qml"
	property url fullChangelogUrl : "ToonstoreDelegateChangelog.qml"
	property url thumbnailIcon: "qrc:/tsc/repo.png"
	property url toonstoreMenuIconUrl: "qrc:/tsc/repo.png"
	property url trayUrl: "ToonstoreTray.qml"
	property url toonstoreDelegateGalleryPopupUrl : "ToonstoreDelegateGalleryPopup.qml"

	property Popup toonstoreDelegateGalleryPopup
	property string configMsgUuid

	property ToonstoreScreen toonstoreScreen
	property ToonstoreDelegateChangelog toonstoreDelegateChangelog
	property ToonstoreSettings toonstoreSettings
	property bool dialogShown : false  //shown when changes have been made in the list of apps. Shown only once.
	property string toonSoftwareVersion  //actual firmware version

	// Toonstore data in XML string format
	property string repoDataAll
	property variant installedApps
	property int updatesCount : 0

	property string repoRefreshDateTime

	// package names ("folder-version") selected for install / removal, and the list the daily
	// auto update would install. Always replace these arrays, never mutate them in place, so bindings update.
	property var updatesToBeApplied : []
	property var autoUpdatesToBeApplied : []
	property var deletesToBeApplied : []
	property string delegateChangelog : "Leeg...."
	property string delegateChangelogTitle : "Nieuwe functies"
	property int delegateChangelogScreenshots 
	property string screenshotURLchunk 

	property bool showStoreIcon : true
	property bool updateViaTSCscripts : false
	property bool autoUpdate : false
	property bool sendNotificationOfNewApps : false
	property bool sendNotificationOfNewAppVersions : false
	property string autoUpdateTime
	property SystrayIcon toonstoreTray
	property variant namesOldRepo : []
	property variant versionsOldRepo : []

	property bool toonstoreDataRead: false
	property string activeRepoBranch : "main"
	property string lanIp: "0.0.0.0"
	property int numberOfAppsSelectedToInstall : updatesToBeApplied.length
	property int numberOfAppsSelectedToDelete : deletesToBeApplied.length

	// set by the auto update timer; the auto update itself runs once the repo refresh has completed
	property bool autoUpdatePending : false
	property var repoRequest

	// Toonstore signals, used to update the listview and filter enabled button
	signal toonstoreUpdated()

	// user settings from config file
	property variant toonstoreSettingsJson

	FileIO {
		id: toonstoreSettingsFile
		source: "file:///mnt/data/tsc/toonstore.userSettings.json"
 	}

	FileIO {
		id: toonstoreOldRepoInfoFile
		source: "file:///mnt/data/tsc/toonstore.oldRepoInfo.json"
		onError: { sendNotificationOfNewApps = false; }
	}

	property var installedAppVersions: ({})

	FileIO {
		id: installedVersionFile
	}

	FileIO {
		id: qmlDir
		source: "file:///qmf/qml/apps"
	}

	FileIO {
		id: toonConfig
		source: "file:///usr/lib/opkg/info/base-qb2-ene.control"
	}

	FileIO {
		id: toonConfigUni
		source: "file:///usr/lib/opkg/info/base-qb2-uni.control"
	}

	FileIO {
		id: toonConfigNxt
		source: "file:///var/lib/opkg/info/base-nxt-uni.control"
	}

	// Init the toonstore app by registering the widgets
	function init() {
		registry.registerWidget("screen", fullScreenUrl, this, "toonstoreScreen");
		registry.registerWidget("screen", fullSettingsUrl, this, "toonstoreSettings");
		registry.registerWidget("screen", fullChangelogUrl, this, "toonstoreDelegateChangelog");
		registry.registerWidget("menuItem", null, this, null, {objectName: "toonstoreMenuItem", label: qsTr("ToonStore"), image: toonstoreMenuIconUrl, screenUrl: fullScreenUrl, weight: 120});
		registry.registerWidget("systrayIcon", trayUrl, toonstoreApp);
		registry.registerWidget("popup", toonstoreDelegateGalleryPopupUrl, this, "toonstoreDelegateGalleryPopup");
		notifications.registerType("toonstore", notifications.prio_HIGHEST, Qt.resolvedUrl("qrc:/tsc/notification-update.svg"), fullScreenUrl , {"categoryUrl": fullScreenUrl }, "ToonStore mededelingen");
		notifications.registerSubtype("toonstore", "mededeling", fullScreenUrl , {"categoryUrl": fullScreenUrl});
	}

	function sendNotification(text) {
		notifications.send("toonstore", "mededeling", false, text, "category=mededeling");
	}


	function saveUpdateTime(text) {

		autoUpdateTime = text;
   		saveSettings();
		if (autoUpdate) {
			activateUpdateTimer();
		}
	}

	function saveShowStoreIcon(text) {

		showStoreIcon = (text == "Yes");
   		saveSettings();
	}

	function saveShowNotifications(text) {

		sendNotificationOfNewApps = (text == "Yes");
   		saveSettings();
	}

	function saveShowNotificationsVersions(text) {

		sendNotificationOfNewAppVersions = (text == "Yes");
   		saveSettings();
	}

	function saveAutoUpdate(text) {

		autoUpdate = (text == "Yes");
   		saveSettings();
		if (autoUpdate) {
			activateUpdateTimer();
		}
	}

	// ---- selection of apps to install / remove (used by the list delegates) ----

	function isSelectedForInstall(packageName) {
		return updatesToBeApplied.indexOf(packageName) >= 0;
	}

	function isSelectedForDelete(packageName) {
		return deletesToBeApplied.indexOf(packageName) >= 0;
	}

	function selectForInstall(packageName) {
		deletesToBeApplied = withoutPackage(deletesToBeApplied, packageName);
		if (!isSelectedForInstall(packageName)) {
			updatesToBeApplied = updatesToBeApplied.concat([packageName]);
		}
		selectionChanged();
	}

	function deselectForInstall(packageName) {
		updatesToBeApplied = withoutPackage(updatesToBeApplied, packageName);
		selectionChanged();
	}

	function selectForDelete(packageName) {
		updatesToBeApplied = withoutPackage(updatesToBeApplied, packageName);
		if (!isSelectedForDelete(packageName)) {
			deletesToBeApplied = deletesToBeApplied.concat([packageName]);
		}
		selectionChanged();
	}

	function deselectForDelete(packageName) {
		deletesToBeApplied = withoutPackage(deletesToBeApplied, packageName);
		selectionChanged();
	}

	function withoutPackage(list, packageName) {
		return list.filter(function(p) { return p !== packageName; });
	}

	function selectionChanged() {
		if (toonstoreScreen) {
			toonstoreScreen.updateInstallButton();
		}
	}

	function activateUpdateTimer() {
			/// calculates miliseconds till next scheduled update time and starts timer
		if (!/^[0-9]{4}$/.test(autoUpdateTime)) {
			console.log("ToonStore: invalid auto update time '" + autoUpdateTime + "', timer not started");
			autoUpdateTimer.running = false;
			return;
		}
		var now = new Date();
		var nowUtc = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours(), now.getMinutes(), now.getSeconds(),now.getMilliseconds());
		var addaday = 0;
		var targetHour = ToonstoreJS.updateHour(autoUpdateTime);
		var targetMinute = ToonstoreJS.updateMinute(autoUpdateTime);

		if (now.getHours() > targetHour) {
			addaday = 1;
		} else {
			if (now.getHours() == targetHour) {
				if (now.getMinutes() >= targetMinute) {
					addaday = 1;
				}
			}
		}
		var targetTimer = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate() + addaday, targetHour, targetMinute, 0, 0);
		targetTimer = targetTimer - nowUtc;
		if (autoUpdate) {
			autoUpdateTimer.interval = targetTimer;
			autoUpdateTimer.running = true;
			console.log("ToonStore auto update timer set for " + targetTimer + " from " + now);
		} else {
			autoUpdateTimer.running = false;	
		}
	}

	// Writes a space separated package list for the TSC scripts. Returns false when there is nothing to write.
	function writePackageList(fileUrl, packages) {
		if (!packages || packages.length == 0) {
			return false;
		}
		var doc = new XMLHttpRequest();
		doc.open("PUT", fileUrl);
		doc.send(packages.join(" "));
		return true;
	}

	function writeTSCscriptCommand() {
 		var doc4 = new XMLHttpRequest();
  		doc4.open("PUT", "file:///tmp/tsc.command");
   		doc4.send("toonstore");
	}

	function applyUpdates() {
		var check1 = writePackageList("file:///tmp/packages_to_install.txt", updatesToBeApplied);
		var check2 = writePackageList("file:///tmp/packages_to_delete.txt", deletesToBeApplied);
		if (check1 || check2) {
			writeTSCscriptCommand();
		}
	}


	function readToonSoftwareVersion() {
		// the control file differs per Toon model; take the first one that contains a version line
		var files = [toonConfig, toonConfigUni, toonConfigNxt];
		var versionRegex = /Version:\s*([0-9]+(?:\.[0-9]+)*)/;
		for (var i = 0; i < files.length; i++) {
			var match = versionRegex.exec(files[i].read());
			if (match) {
				toonSoftwareVersion = match[1];
				return;
			}
		}
		console.log("ToonStore: could not determine firmware version from opkg control files");
		toonSoftwareVersion = "onbekend";
	}

	function updateRepoInfo() {

		readOldRepoInfo();

		if (repoRequest) {
			// a previous request is still in flight; abort it, the failure handler below will ignore it
			var old = repoRequest;
			repoRequest = undefined;
			old.abort();
		}
		repoFetchTimeout.stop();

		var xmlhttp = new XMLHttpRequest();
		repoRequest = xmlhttp;
		xmlhttp.onreadystatechange=function() {
			if (xmlhttp.readyState == 4) {
				if (repoRequest !== xmlhttp) {
					return; // superseded or timed out
				}
				repoRequest = undefined;
				repoFetchTimeout.stop();
				var now = new Date().getTime();
				if (xmlhttp.status == 200) {
					toonstoreDataRead = true;
					repoDataAll = xmlhttp.responseText;
					repoRefreshDateTime = "Bijgewerkt: " + i18n.dateTime(now,i18n.time_yes + i18n.mon_full);
					toonstoreUpdated();
				} else {
					repoFetchFailed(xmlhttp.status, now);
				}
			}
		}
		xmlhttp.open("GET", "https://raw.githubusercontent.com/ToonSoftwareCollective/toonstore_AppRepository/" + activeRepoBranch + "/ToonRepo.xml", true);
		xmlhttp.send();
		repoFetchTimeout.start();
	}

	function repoFetchFailed(status, now) {
		console.log("ToonStore: repository refresh failed, http status " + status);
		repoRefreshDateTime = "Bijwerken mislukt: " + i18n.dateTime(now,i18n.time_yes + i18n.mon_full);
		// never auto install from stale data
		autoUpdatePending = false;
		if (!toonstoreDataRead) {
			// nothing loaded yet, let the screen show the connection error
			toonstoreUpdated();
		}
	}

	// Called by the screen once the auto update list has been rebuilt from fresh repository data
	function runAutoUpdate() {
		if (!autoUpdatePending) {
			return;
		}
		autoUpdatePending = false;
		if (writePackageList("file:///tmp/packages_to_install.txt", autoUpdatesToBeApplied)) {
			console.log("ToonStore auto update: " + autoUpdatesToBeApplied.join(" "));
			writeTSCscriptCommand();
		}
	}

	// settings used to be stored as the strings "true"/"false"; accept both forms
	function toBool(value) {
		return value === true || value === "true";
	}

	Component.onCompleted: {
		initToonstore();
	}

	function initToonstore() {

		readToonSoftwareVersion();

		// read user settings

		try {
			toonstoreSettingsJson = JSON.parse(toonstoreSettingsFile.read());
			showStoreIcon = toBool(toonstoreSettingsJson.showStoreIcon);
			autoUpdate = toBool(toonstoreSettingsJson.autoUpdate);
			if (typeof toonstoreSettingsJson.autoUpdateTime === "string") {
				autoUpdateTime = toonstoreSettingsJson.autoUpdateTime;
			}
			sendNotificationOfNewApps = toBool(toonstoreSettingsJson.sendNotificationOfNewApps);
			sendNotificationOfNewAppVersions = toBool(toonstoreSettingsJson.sendNotificationOfNewAppVersions);
			if (autoUpdate) {
				activateUpdateTimer();
			}
		} catch(e) {
			console.log("ToonStore: no valid settings file, using defaults");
		}

		readOldRepoInfo();

		updatesToBeApplied = [];
		autoUpdatesToBeApplied = [];
		deletesToBeApplied = [];
		refreshInstalledVersions();
		updateRepoInfo();
	}

	function refreshInstalledVersions() {
		var versions = {};
		var apps = qmlDir.dirEntries || [];
		installedApps = apps;
		for (var i = 0; i < apps.length; i++) {
			var appFolder = apps[i];
			try {
				installedVersionFile.source = "file:///qmf/qml/apps/" + appFolder + "/version.txt";
				var v = installedVersionFile.read();
				versions[appFolder] = v ? v.trim() : "";
			} catch(e) {
				versions[appFolder] = "";
			}
		}
		installedAppVersions = versions;
	}

	function getInstalledVersion(folder) {
		return (installedAppVersions && installedAppVersions[folder] !== undefined)
			? installedAppVersions[folder]
			: "";
	}

	function isInstalled(folder) {
		return installedApps && installedApps.indexOf(folder) >= 0;
	}
	
	function readOldRepoInfo() {

		// read old RepoInfo

		try {
			var toonstoreOldRepoInfoJson = JSON.parse(toonstoreOldRepoInfoFile.read());
			namesOldRepo = toonstoreOldRepoInfoJson.names || [];
			versionsOldRepo = toonstoreOldRepoInfoJson.versions || [];
		} catch(e) {
			namesOldRepo = [];
			versionsOldRepo = [];
		}
	}

	function saveSettings() {
		
		// save user settings

 		toonstoreSettingsJson = {
			"showStoreIcon" : showStoreIcon,
			"autoUpdate" : autoUpdate,
			"autoUpdateTime" : autoUpdateTime,
			"sendNotificationOfNewApps" : sendNotificationOfNewApps,
			"sendNotificationOfNewAppVersions" : sendNotificationOfNewAppVersions
		}

  		var doc3 = new XMLHttpRequest();
   		doc3.open("PUT", "file:///mnt/data/tsc/toonstore.userSettings.json");
   		doc3.send(JSON.stringify(toonstoreSettingsJson ));
	}

	Timer {
		id: autoUpdateTimer
		interval: 999999999
		triggeredOnStart: false
		running: false
		// single shot: the interval is "time until the next scheduled moment", so a repeating
		// timer would drift. activateUpdateTimer() re-arms it for the next day.
		repeat: false
		onTriggered: {
			autoUpdatePending = true;
			updateRepoInfo();
			activateUpdateTimer();
		}
	}

	Timer {
		id: repoFetchTimeout
		interval: 30000
		repeat: false
		onTriggered: {
			if (repoRequest) {
				var xhr = repoRequest;
				repoRequest = undefined;
				xhr.abort();
				repoFetchFailed("timeout", new Date().getTime());
			}
		}
	}

	Timer {
		id: updateRepoTimer
		interval: 10800000  //every three hours
		triggeredOnStart: false
		running: true
		repeat: true
		onTriggered: updateRepoInfo()
	}
	
	BxtDiscoveryHandler {
		id : netconDiscoHandler
		deviceType: "hcb_netcon"
		onDiscoReceived: {
			statusNotifyHandler.sourceUuid = deviceUuid;
		}
	}

	BxtNotifyHandler {
		id: statusNotifyHandler
		serviceId: "gwif"
		onNotificationReceived : {
			var address = message.getArgument("ipaddress");
			if (address) {
				lanIp = address;
			}
		}
	}
}
