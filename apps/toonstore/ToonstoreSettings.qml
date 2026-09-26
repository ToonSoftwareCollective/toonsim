import QtQuick 2.1
import qb.components 1.0
import BxtClient 1.0

Screen {
	id: toonstoreSettingsScreen


	screenTitle: "ToonStore configuratie"

	onShown: {
		addCustomTopRightButton("Toepassen");
		autoUpdateTimeLabel.inputText = app.autoUpdateTime;
		autoUpdateToggle.isSwitchedOn = app.autoUpdate;
		showNotificationsToggle.isSwitchedOn = app.sendNotificationOfNewApps;
		showNotificationsVersionsToggle.isSwitchedOn = app.sendNotificationOfNewAppVersions;
		showStoreIconToggle.isSwitchedOn = app.showStoreIcon;
	}

	onCustomButtonClicked: {
		// every setting is saved the moment it is changed, so closing is all that is left to do.
		// (re-initialising the app here would also throw away any apps selected for install/removal)
		hide();
	}

	function padTime(text) {
		var timeStr = "0000" + text;
		return timeStr.substr(timeStr.length - 4, timeStr.length);
	}

	function saveUpdateTime(text) {

		var timeStr4POS = padTime(text);
		autoUpdateTimeLabel.inputText = timeStr4POS;
		app.autoUpdateTime = timeStr4POS;
   		app.saveUpdateTime(timeStr4POS);
	}

	function validateTime(text, isFinalString) {
		if (!isFinalString) {
			return null;
		}
		var timeStr = padTime(text);
		var hour = parseInt(timeStr.substring(0, 2));
		var minute = parseInt(timeStr.substring(2, 4));
		var digitsOnly = /^[0-9]{1,4}$/.test(text);
		if (!digitsOnly || isNaN(hour) || isNaN(minute) || hour > 23 || minute > 59) {
			return {title: "Ongeldige tijd", content: "Voer een tijd in als HHMM, bijvoorbeeld 0330 voor half vier 's nachts."};
		}
		return null;
	}

	Text {
		id: autoUpdateText
		x: isNxt ? 36 : 30
		y: isNxt ? 60 : 50
		width: showNotificationsVersions.width
		font.pixelSize: isNxt ? 20 : 16
		font.family: qfont.semiBold.name
		text: qsTr("Apps automatisch bijwerken")
	}

	OnOffToggle {
		id: autoUpdateToggle
		height: isNxt ? 45 : 36
		anchors.left: autoUpdateText.right
		anchors.leftMargin: isNxt ? 25 : 20
		anchors.top: autoUpdateText.top
		leftIsSwitchedOn: false
		onSelectedChangedByUser: {
			if (isSwitchedOn) {
				app.saveAutoUpdate("Yes")
			} else {
				app.saveAutoUpdate("No")
			}
		}
	}

	Text {
		id: autoUpdateTimeText
		anchors {
			top: autoUpdateToggle.top
			left: autoUpdateToggle.right
			leftMargin: isNxt ? 25 : 20
		}
		text: "dagelijks om "
		font.pixelSize: isNxt ? 20 : 16
		font.family: qfont.semiBold.name
		color: colors.rbTitle
	}

	EditTextLabel {
		id: autoUpdateTimeLabel
		width: isNxt ? 250 : 200
		height: isNxt ? 45 : 36
		leftText: "Tijd (hhmm):"

		anchors {
			left: autoUpdateTimeText.right
			leftMargin: isNxt ? 13 : 10
			bottom: autoUpdateTimeText.bottom
			bottomMargin: isNxt ? -8 : -6
		}

		onClicked: {
			qnumKeyboard.open("Voer tijd in (HHMM)", autoUpdateTimeLabel.inputText, app.autoUpdateTime, 1 , saveUpdateTime, validateTime);
		}
	}

	IconButton {
		id: autoUpdateTimeLabelButton;
		width: isNxt ? 50 : 40
		iconSource: "qrc:/tsc/edit.png"

		anchors {
			left: autoUpdateTimeLabel.right
			leftMargin: isNxt ? 8 : 6
			top: autoUpdateTimeLabel.top
		}

		bottomClickMargin: 3
		onClicked: {
			qnumKeyboard.open("Voer tijd in (HHMM)", autoUpdateTimeLabel.inputText, app.autoUpdateTime, 1 , saveUpdateTime, validateTime);
		}
	}
	Text {
		id: showIconText
		anchors {
			top: autoUpdateText.bottom
			topMargin: isNxt ? 25 : 20
			left: autoUpdateText.left
		}
		font.pixelSize: isNxt ? 20 : 16
		font.family: qfont.semiBold.name
		text: qsTr("Icoon in tray")
	}

	OnOffToggle {
		id: showStoreIconToggle
		height: isNxt ? 45 : 36
		anchors.left: autoUpdateToggle.left
		anchors.top: showIconText.top
		leftIsSwitchedOn: false
		onSelectedChangedByUser: {
			if (isSwitchedOn) {
				app.saveShowStoreIcon("Yes")
			} else {
				app.saveShowStoreIcon("No")
			}
		}
	}

	Text {
		id: showNotifications
		anchors {
			top: showIconText.bottom
			topMargin: isNxt ? 25 : 20
			left: autoUpdateText.left
		}
		font.pixelSize: isNxt ? 20 : 16
		font.family: qfont.semiBold.name
		text: qsTr("Show notification of a new app")
	}

	OnOffToggle {
		id: showNotificationsToggle
		height: isNxt ? 45 : 36
		anchors.left: autoUpdateToggle.left
		anchors.top: showNotifications.top
		leftIsSwitchedOn: false
		onSelectedChangedByUser: {
			if (isSwitchedOn) {
				app.saveShowNotifications("Yes")
			} else {
				app.saveShowNotifications("No")
			}
		}
	}

	Text {
		id: showNotificationsVersions
		anchors {
			top: showNotifications.bottom
			topMargin: isNxt ? 25 : 20
			left: autoUpdateText.left
		}
		font.pixelSize: isNxt ? 20 : 16
		font.family: qfont.semiBold.name
		text: qsTr("Show notification of a new app version")
	}

	OnOffToggle {
		id: showNotificationsVersionsToggle
		height: isNxt ? 45 : 36
		anchors.left: autoUpdateToggle.left
		anchors.top: showNotificationsVersions.top
		leftIsSwitchedOn: false
		onSelectedChangedByUser: {
			if (isSwitchedOn) {
				app.saveShowNotificationsVersions("Yes")
			} else {
				app.saveShowNotificationsVersions("No")
			}
		}
	}
}
