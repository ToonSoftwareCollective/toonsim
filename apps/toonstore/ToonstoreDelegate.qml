import QtQuick 2.1
import qb.components 1.0
import FileIO 1.0
import "toonstore.js" as ToonstoreJS

// One row in the ToonStore list. The model roles (name, version, folder, ...) are the XML nodes
// declared in ToonstoreScreen.qml.
Rectangle {
	id: appRow

	/// package name as used in the install / delete lists handed to the TSC scripts
	property string packageName: folder + "-" + version
	property bool installed: app.installedApps.indexOf(folder) >= 0
	property string installedVersion: installed ? app.getInstalledVersion(folder) : ""
	property bool updateAvailable: installed && installedVersion.length > 0 && ToonstoreJS.compareVersions(version, installedVersion) > 0
	property bool compatible: ToonstoreJS.firmwareCompatible({firmwareminimum: firmwareminimum, firmwaremaximum: firmwaremaximum, toon2only: toon2only}, app.toonSoftwareVersion, isNxt)
	/// ToonStore itself can not be removed via ToonStore, nor can apps the repository marks as not deletable
	property bool deletable: installed && allowdeletion != "no" && folder.substring(0, 9) != "toonstore"
	property bool selectedForInstall: app.isSelectedForInstall(packageName)
	property bool selectedForDelete: app.isSelectedForDelete(packageName)

	function getDescription() {
		var str = "App: " + name;
		if (installed) {
			str = str + ". Geïnstalleerde versie: " + installedVersion;
		}
		return str + ". " + description + ", door " + author + ".";
	}

	function getStatusLabel() {
		if (!installed) return "Beschikbaar:";
		return updateAvailable ? "Nieuwe versie:" : "Geïnstalleerd:";
	}

	function showDialogToonstore() {
		if (!app.dialogShown) {
			qdialog.showDialog(qdialog.SizeLarge, "ToonStore mededeling", "Alle wijzigingen in applicaties (toevoegen en/of verwijderen) worden pas geactiveerd als U op de knop 'Toon Bijwerken' heeft gedrukt, rechtsboven op het scherm.\nHierna zullen de gevraagde applicaties worden gedownload waarna de Toon zal herstarten om de wijzigingen te activeren. Hiervoor hoeft U zelf niets meer te doen.", "Sluiten");
			app.dialogShown = true;
		}
	}

	function showDialogToonstore2(text) {
			qdialog.showDialog(qdialog.SizeLarge, "ToonStore mededeling", text , "Sluiten");
	}

	function showChangelog() {

		app.delegateChangelog = "\n\n\n\n\n\n\n          Ophalen changelog ......";
		app.delegateChangelogTitle = "Nieuwe functies " + name;
		app.delegateChangelogScreenshots = parseInt(screenshots);
		app.screenshotURLchunk = folder + "_screenshot_";
		stage.navigateHome();
		app.toonstoreDelegateChangelog.show();

		var xmlhttp = new XMLHttpRequest();
		xmlhttp.onreadystatechange=function() {
			if (xmlhttp.readyState == 4) {
				if (xmlhttp.status == 200) {
					var tmpTxt = xmlhttp.responseText;
					app.delegateChangelog = tmpTxt.replace(/\r\n/g, "\n");
				} else {
					app.delegateChangelog = "\n\n\n\n\n\n\n          De changelog van " + name + " kon niet worden opgehaald (status " + xmlhttp.status + ").";
				}
			}
		}
		xmlhttp.open("GET", "https://raw.githubusercontent.com/ToonSoftwareCollective/" + folder + "/main/Changelog.txt", true);
		xmlhttp.send();
	}

	width: isNxt ? 850 : 646
	height: isNxt ? 80 : 62
	color: compatible ? "white" : "transparent"

	Text {
		id: statusLabel
		x: isNxt ? 13 : 10
		anchors.baseline: parent.top
		anchors.baselineOffset: isNxt ? 24 : 19
		text: getStatusLabel()
		color: (installed && !updateAvailable) ? "#689F38" : "#CC3300"
		font.family: qfont.semiBold.name
		font.pixelSize: isNxt ? 20 : 16
	}

	Text {
		anchors.left: statusLabel.right
		anchors.leftMargin: isNxt ? 6 : 5
		anchors.bottom: statusLabel.bottom
		text: name
		font.family: qfont.semiBold.name
		font.pixelSize: isNxt ? 20 : 16
	}

	Text {
		anchors.baseline: parent.top
		anchors.baselineOffset: isNxt ? 24 : 19
		anchors.right: btnChangelog.left
		anchors.rightMargin: 10
		text: version
		font.family: qfont.semiBold.name
		font.pixelSize: isNxt ? 20 : 16
	}

	Text {
		id: descriptionLabel
		x: isNxt ? 13 : 10
		anchors.baseline: parent.top
		anchors.baselineOffset: isNxt ? 44 : 35
		width: isNxt ? parent.width - 130 : parent.width - 105
		text: getDescription()
		wrapMode: Text.WordWrap
		maximumLineCount: 2
		elide: Text.ElideRight
		lineHeight: 0.85
		font.family: qfont.italic.name
		font.pixelSize: isNxt ? 15 : 12
	}

	StandardButton {
		id: btnChangelog
		width: isNxt ? 38 : 30
		height: isNxt ? 28 : 22
		text: "?"
		anchors.right: parent.right
		anchors.bottom: deleteButton.top
		anchors.bottomMargin : 2
		anchors.rightMargin: 10
		leftClickMargin: 3
		bottomClickMargin: 5
		onClicked: {
			showChangelog();
		}
	}

	IconButton {
		id: deleteButton
		anchors.baseline: parent.top
		anchors.baselineOffset: isNxt ? 36 : 28
		anchors.right: parent.right
		anchors.rightMargin: 10
		leftClickMargin: 3
		bottomClickMargin: 5
		iconSource: "qrc:/tsc/minus.png"
		visible: deletable
		state: selectedForDelete ? "up" : "down"
		onClicked: {
			if (selectedForDelete) {
				deleteButton.state = "down";
				app.deselectForDelete(packageName);
			} else {
				showDialogToonstore();
				deleteButton.state = "up";
				downloadButton.state = "down";
				app.selectForDelete(packageName);
			}
		}
	}

	IconButton {
		id: downloadButton
		anchors.baseline: parent.top
		anchors.baselineOffset: isNxt ? 36 : 28
		anchors.right: parent.right
		anchors.rightMargin: isNxt ? 54 : 44
		leftClickMargin: 3
		bottomClickMargin: 5
		iconSource: compatible ? "qrc:/tsc/plus.png" : "qrc:/tsc/bad_small.png"
		visible: !installed || updateAvailable
		state: selectedForInstall ? "up" : "down"
		onClicked: {
			if (!compatible) {
				downloadButton.state = "down";
				if (!isNxt && toon2only == "yes") {
					showDialogToonstore2("Deze applicatie " + name + " is niet geschikt voor het oude model Toon.");
				} else {
					showDialogToonstore2("Deze applicatie " + name + " is niet geschikt voor de software versie " + app.toonSoftwareVersion + " van uw Toon.");
				}
				return;
			}
			if (selectedForInstall) {
				downloadButton.state = "down";
				app.deselectForInstall(packageName);
			} else {
				showDialogToonstore();
				downloadButton.state = "up";
				deleteButton.state = "down";
				app.selectForInstall(packageName);
			}
		}
	}
}
