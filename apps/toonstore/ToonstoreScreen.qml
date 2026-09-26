import QtQuick 2.1
import SimpleXmlListModel 1.0
import qb.components 1.0
import BasicUIControls 1.0
import FileIO 1.0
import "toonstore.js" as ToonstoreJS

Screen {
	// toonstore loading indicator
	property bool toonstoreLoaded: false
	property string activeFilter : "all"  // "all" | "updates" | "new" | "installed"
	property string searchFilter : ""

	property int countUpdates : 0
	property int countNew : 0
	property int countInstalled : 0

	ListModel {
		id: filteredModel
	}

	function rebuildFilteredModel() {
		filteredModel.clear();

		var items = [];
		var cUpdates = 0;
		var cNew = 0;
		var cInstalled = 0;

		for (var i = 0; i < toonstoreModel.count; i++) {
			var e = toonstoreModel.get(i);
			var installed = isInstalled(e.folder);
			var installedVer = installed ? getInstalledVersion(e.folder) : "";
			var isUpd = installed && installedVer.length > 0 && ToonstoreJS.compareVersions(e.version, installedVer) > 0;
			var isNew = (app.namesOldRepo && app.namesOldRepo.length > 0 && app.namesOldRepo.indexOf(e.folder) < 0);

			if (installed) cInstalled++;
			if (isUpd) cUpdates++;
			if (isNew) cNew++;

			items.push({
				name: e.name,
				version: e.version,
				folder: e.folder,
				description: e.description,
				author: e.author,
				skipautoupdate: e.skipautoupdate,
				firmwareminimum: e.firmwareminimum,
				firmwaremaximum: e.firmwaremaximum,
				screenshots: e.screenshots,
				toon2only: e.toon2only,
				allowdeletion: e.allowdeletion,
				isInstalled: installed,
				isUpdate: isUpd,
				isNew: isNew
			});
		}

		countUpdates = cUpdates;
		countNew = cNew;
		countInstalled = cInstalled;

		items.sort(function(a, b) {
			var na = (a.name || "").toLowerCase();
			var nb = (b.name || "").toLowerCase();
			return na < nb ? -1 : (na > nb ? 1 : 0);
		});

		var search = searchFilter.trim().toLowerCase();

		for (var j = 0; j < items.length; j++) {
			var item = items[j];

			if (search !== "" && item.name.toLowerCase().indexOf(search) < 0 && (item.description || "").toLowerCase().indexOf(search) < 0) {
				continue;
			}

			if (activeFilter === "updates" && !item.isUpdate) continue;
			if (activeFilter === "new" && !item.isNew) continue;
			if (activeFilter === "installed" && !item.isInstalled) continue;

			filteredModel.append(item);
		}
	}

	onActiveFilterChanged: {
		rebuildFilteredModel();
		toonstoreSimpleList.initialView();
		headerText.text = getHeaderText();
	}

	onSearchFilterChanged: {
		rebuildFilteredModel();
		toonstoreSimpleList.initialView();
		headerText.text = getHeaderText();
	}

	// Function (triggerd by a signal) updates the toonstore list model and the header text
	function updateToonstoreList() {
		if (!app.toonstoreDataRead) {
			noJamsText.visible = true;
			noJamsText.text = "Verbinding met de ToonStore mislukt. Controleer de internetverbinding.";
		}
		else if (app.repoDataAll.length > 0) {
			// Update the toonstore list model
			noJamsText.visible = false;
			toonstoreModel.xml = app.repoDataAll;
			rebuildFilteredModel();
			toonstoreSimpleList.initialView();

			if (app.activeRepoBranch == "main" ) {
				checkNewApps();
				saveCurrentRepoInfo();
			}

			// the auto update list must cover every app in the repository, not only the rows
			// currently on screen, so it is built here instead of in the list delegate
			buildAutoUpdateList();
			app.runAutoUpdate();

		} else {
			noJamsText.visible = true;
			noJamsText.text = "Geen apps in ToonStore";
		}
		toonstoreLoaded = true;

		// Update the header text
		headerText.text = getHeaderText();
	}

	function getEmptyMessage() {
		if (!app.toonstoreDataRead) {
			return "Verbinding met de ToonStore mislukt. Controleer de internetverbinding.";
		}
		if (searchFilter.trim() !== "") {
			return "Geen apps gevonden voor '" + searchFilter + "'.";
		}
		if (activeFilter === "updates") {
			return "Alle geïnstalleerde apps zijn up-to-date.";
		}
		if (activeFilter === "new") {
			return "Geen nieuwe apps beschikbaar in de ToonStore.";
		}
		if (activeFilter === "installed") {
			return "Er zijn nog geen apps geïnstalleerd vanuit de ToonStore.";
		}
		return "Geen apps in ToonStore.";
	}

	// Function creates the header text using the correct XML nodes
	function getHeaderText() {
		var total = filteredModel.count;
		var str = total + " App" + (total === 1 ? "" : "s") + " in de ToonStore";
		if (activeFilter === "updates") str += " (Updates)";
		else if (activeFilter === "new") str += " (Nieuw)";
		else if (activeFilter === "installed") str += " (Geïnstalleerd)";
		return str + ". ";
	}

	anchors.fill: parent
	screenTitleIconUrl: "qrc:/tsc/repo.png"
	screenTitle: "ToonStore"

	Component.onCompleted: {
		app.toonstoreUpdated.connect(updateToonstoreList)
	}

	onShown: {
		updateInstallButton();
		hasBackButton = false;
	}
	
	function isInstalled(folder) {
		return app.isInstalled(folder);
	}

	function getInstalledVersion(folder) {
		return app.getInstalledVersion(folder);
	}

	function isCompatible(item) {
		return ToonstoreJS.firmwareCompatible(item, app.toonSoftwareVersion, isNxt);
	}

	// Rebuilds app.autoUpdatesToBeApplied: every installed app that has a newer, compatible version
	// in the repository and is not excluded from auto updating by the repository (skipautoupdate).
	function buildAutoUpdateList() {
		var packages = [];
		for (var i = 0; i < toonstoreModel.count; i++) {
			var item = toonstoreModel.get(i);
			if (item.skipautoupdate !== "no") continue;
			if (!isInstalled(item.folder)) continue;
			if (!isCompatible(item)) continue;
			var installedVersion = getInstalledVersion(item.folder);
			if (installedVersion.length == 0) continue;
			if (ToonstoreJS.compareVersions(item.version, installedVersion) > 0) {
				packages.push(item.folder + "-" + item.version);
			}
		}
		app.autoUpdatesToBeApplied = packages;
	}

	// Notifies about apps and app versions that appeared since the previous refresh.
	// Only apps that can actually be installed on this Toon are reported.
	function checkNewApps() {

		if (app.namesOldRepo.length == 0) {
			// first run (or unreadable history): everything would look new, so stay quiet
			return;
		}

		for (var i = 0; i < toonstoreModel.count; i++) {
			var item = toonstoreModel.get(i);
			if (!isCompatible(item)) continue;
			var j = app.namesOldRepo.indexOf(item.folder);
			if (j < 0) {
				if (app.sendNotificationOfNewApps) app.sendNotification("Er is een nieuwe app beschikbaar in de ToonStore: " + item.name);
			} else if (app.versionsOldRepo[j] !== item.version && isInstalled(item.folder) && !app.autoUpdate) {
				if (app.sendNotificationOfNewAppVersions) app.sendNotification("Er is een update van de app " + item.name + " beschikbaar in de ToonStore.");
			}
		}
	}

	function saveCurrentRepoInfo() {

		var names = [];
		var versions = [];
		for (var i = 0; i < toonstoreModel.count; i++) {
			names.push(toonstoreModel.get(i).folder);
			versions.push(toonstoreModel.get(i).version);
		}
  		var doc3 = new XMLHttpRequest();
   		doc3.open("PUT", "file:///mnt/data/tsc/toonstore.oldRepoInfo.json");
		doc3.onreadystatechange=function() {
			if (doc3.readyState == 4) {
				app.readOldRepoInfo();
			}
		}
   		doc3.send(JSON.stringify({"names": names, "versions": versions}));
	}

	function footerText() {
		if (app.activeRepoBranch == "main" ) {
			return "Bron: github.com/ToonSoftwareCollective";
		}
		if (app.activeRepoBranch == "test" ) {
			return "Bron: test repository !!";
		}
		if (app.activeRepoBranch == "dev" ) {
			return "Bron: dev repository !!";
		}
	}

	function updateInstallButton() {
		if (anythingToUpdate()) {
			var selected = app.numberOfAppsSelectedToInstall + app.numberOfAppsSelectedToDelete;
			addCustomTopRightButton("Toon Bijwerken (" + selected + ")");
		} else {
			addCustomTopRightButton("Terug");
		}
	}

	onCustomButtonClicked: {
		if (app.numberOfAppsSelectedToInstall > 3) {
			qdialog.showDialog(qdialog.SizeLarge, "ToonStore mededeling", "U kunt niet meer dan drie apps tegelijkertijd installeren", "Sluiten");
		} else {
			if (anythingToUpdate()) {
				qdialog.showDialog(qdialog.SizeLarge, "ToonStore mededeling", "De geselecteerde apps zullen in de achtergrond worden opgehaald en geïnstalleerd dan wel verwijderd.\nAls alle wijzigingen zijn doorgevoerd zal de Toon automatisch herstarten.", "Sluiten");
				app.applyUpdates();
			}
			hide();	
		}
	}

	function anythingToUpdate() {
		return app.updatesToBeApplied.length > 0 || app.deletesToBeApplied.length > 0;
	}

	function toggleBranch() {
		if (app.activeRepoBranch == "main") {
			app.activeRepoBranch = "test" 
		} else {
			if (app.activeRepoBranch == "test") {
				app.activeRepoBranch = "dev"
			} else {
				app.activeRepoBranch = "main"
			}
		}
		app.updateRepoInfo();
	}

	Item {
		id: header
		height: isNxt ? 55 : 45
		anchors.horizontalCenter: parent.horizontalCenter
		width: isNxt ? parent.width - 95 : parent.width - 76

		Text {
			id: headerText
			text: getHeaderText()
			font.family: qfont.semiBold.name
			font.pixelSize: isNxt ? 25 : 20
			anchors {
				left: header.left
				bottom: parent.bottom
			}
		}

		StandardButton {
			id: btnConfigScreen
			width: isNxt ? 190 : 150
			text: "Instellingen"
			anchors.right: refreshButton.left
			anchors.bottom: parent.bottom
			anchors.rightMargin: 10
			leftClickMargin: 3
			bottomClickMargin: 5
			onClicked: {
				if (app.toonstoreSettings) {
					app.toonstoreSettings.show();
				}
			}
		}

		IconButton {
			id: refreshButton
			anchors.right: parent.right
			anchors.bottom: parent.bottom
			leftClickMargin: 3
			bottomClickMargin: 5
			iconSource: "qrc:/tsc/refresh.svg"
			onClicked: app.updateRepoInfo()
		}
	}

	Item {
		id: filterRow
		anchors.horizontalCenter: parent.horizontalCenter
		width: isNxt ? parent.width - 95 : parent.width - 76
		height: isNxt ? 36 : 28
		y: isNxt ? 64 : 50

		// Search box with virtual keyboard integration
		Rectangle {
			id: searchBox
			height: parent.height
			width: isNxt ? 220 : 160
			border.color: "#999999"
			border.width: 1
			radius: 3
			color: "white"
			anchors {
				left: parent.left
				verticalCenter: parent.verticalCenter
			}

			Text {
				id: searchPlaceholder
				visible: searchFilter === ""
				text: "Zoek..."
				color: "#9ca3af"
				anchors {
					left: parent.left
					leftMargin: isNxt ? 8 : 6
					verticalCenter: parent.verticalCenter
				}
				font {
					family: qfont.italic.name
					pixelSize: isNxt ? 16 : 13
				}
			}

			Text {
				id: searchText
				visible: searchFilter !== ""
				text: searchFilter
				color: "#1f2937"
				elide: Text.ElideRight
				anchors {
					left: parent.left
					leftMargin: isNxt ? 8 : 6
					right: parent.right
					rightMargin: isNxt ? 8 : 6
					verticalCenter: parent.verticalCenter
				}
				font {
					family: qfont.regular.name
					pixelSize: isNxt ? 16 : 13
				}
			}

			MouseArea {
				anchors.fill: parent
				onClicked: {
					qkeyboard.open("Zoek app in ToonStore", searchFilter, function(text) {
						searchFilter = text;
					});
				}
			}
		}

		// Bin icon button to the right of the searchbox to clear search
		IconButton {
			id: btnClearSearch
			visible: searchFilter !== ""
			width: isNxt ? 36 : 28
			height: parent.height
			iconSource: "qrc:/tsc/icon_delete.png"
			anchors {
				left: searchBox.right
				leftMargin: isNxt ? 6 : 4
				verticalCenter: parent.verticalCenter
			}
			leftClickMargin: 3
			rightClickMargin: 3
			topClickMargin: 3
			bottomClickMargin: 3
			onClicked: {
				searchFilter = "";
			}
		}

		// Filter Tabs Row: "Alle", "Updates", "Nieuw", "Geïnstalleerd"
		Row {
			anchors {
				right: parent.right
				verticalCenter: parent.verticalCenter
			}
			spacing: isNxt ? 8 : 6

			// Tab: Alle
			Rectangle {
				id: tabAll
				width: isNxt ? 100 : 80
				height: filterRow.height
				radius: 3
				color: activeFilter === "all" ? "#689F38" : (mouseAll.pressed ? "#d1d5db" : "#e5e7eb")
				border.color: activeFilter === "all" ? "#558B2F" : "#d1d5db"
				border.width: 1

				Text {
					anchors.centerIn: parent
					text: "Alle"
					color: activeFilter === "all" ? "white" : "#374151"
					font {
						family: qfont.semiBold.name
						pixelSize: isNxt ? 16 : 13
					}
				}

				MouseArea {
					id: mouseAll
					anchors.fill: parent
					onClicked: activeFilter = "all"
				}
			}

			// Tab: Updates
			Rectangle {
				id: tabUpdates
				width: isNxt ? 150 : 120
				height: filterRow.height
				radius: 3
				color: activeFilter === "updates" ? "#689F38" : (mouseUpdates.pressed ? "#d1d5db" : "#e5e7eb")
				border.color: activeFilter === "updates" ? "#558B2F" : "#d1d5db"
				border.width: 1

				Text {
					anchors.centerIn: parent
					text: countUpdates > 0 ? ("Updates (" + countUpdates + ")") : "Updates"
					color: activeFilter === "updates" ? "white" : (countUpdates > 0 ? "#b91c1c" : "#374151")
					font {
						family: qfont.semiBold.name
						pixelSize: isNxt ? 16 : 13
					}
				}

				MouseArea {
					id: mouseUpdates
					anchors.fill: parent
					onClicked: activeFilter = "updates"
				}
			}

			// Tab: Nieuw
			Rectangle {
				id: tabNew
				width: isNxt ? 130 : 105
				height: filterRow.height
				radius: 3
				color: activeFilter === "new" ? "#689F38" : (mouseNew.pressed ? "#d1d5db" : "#e5e7eb")
				border.color: activeFilter === "new" ? "#558B2F" : "#d1d5db"
				border.width: 1

				Text {
					anchors.centerIn: parent
					text: countNew > 0 ? ("Nieuw (" + countNew + ")") : "Nieuw"
					color: activeFilter === "new" ? "white" : (countNew > 0 ? "#1d4ed8" : "#374151")
					font {
						family: qfont.semiBold.name
						pixelSize: isNxt ? 16 : 13
					}
				}

				MouseArea {
					id: mouseNew
					anchors.fill: parent
					onClicked: activeFilter = "new"
				}
			}

			// Tab: Geïnstalleerd
			Rectangle {
				id: tabInstalled
				width: isNxt ? 170 : 135
				height: filterRow.height
				radius: 3
				color: activeFilter === "installed" ? "#689F38" : (mouseInstalled.pressed ? "#d1d5db" : "#e5e7eb")
				border.color: activeFilter === "installed" ? "#558B2F" : "#d1d5db"
				border.width: 1

				Text {
					anchors.centerIn: parent
					text: countInstalled > 0 ? ("Geïnstalleerd (" + countInstalled + ")") : "Geïnstalleerd"
					color: activeFilter === "installed" ? "white" : "#374151"
					font {
						family: qfont.semiBold.name
						pixelSize: isNxt ? 16 : 13
					}
				}

				MouseArea {
					id: mouseInstalled
					anchors.fill: parent
					onClicked: activeFilter = "installed"
				}
			}
		}
	}

	SimpleXmlListModel {
		id: toonstoreModel
		query: "/repository/app"
		roles: ({
			name: "string",
			version: "string",
			folder: "string",
			description: "string",
			author: "string",
			skipautoupdate : "string",
			firmwareminimum : "string",
			firmwaremaximum : "string",
			screenshots: "string",
			toon2only: "string",
			allowdeletion: "string"
		})
	}

	Rectangle {
		id: content
		anchors.horizontalCenter: parent.horizontalCenter
		width: isNxt ? parent.width - 95 : parent.width - 76
		height: isNxt ? parent.height - 153 : parent.height - 122
		y: isNxt ? 108 : 84
		radius: 3

		ToonstoreSimpleList {
			id: toonstoreSimpleList
			delegate: ToonstoreDelegate{}
			dataModel: filteredModel
			itemHeight: isNxt ? 80 : 62
			itemsPerPage: 4
			anchors.top: parent.top
			downIcon: "qrc:/tsc/arrowScrolldown.png"
			buttonsHeight: isNxt ? 180 : 144
			buttonsVisible: true
			scrollbarVisible: true
		}

		Text {
			id: noJamsText
			visible: filteredModel.count === 0
			anchors.centerIn: parent
			font.family: qfont.italic.name
			font.pixelSize: isNxt ? 18 : 15
			text: getEmptyMessage()
		}
	}

	Text {
		id: footerleft
		text: app.repoRefreshDateTime
		anchors {
			baseline: parent.bottom
			baselineOffset: -5
			left: parent.left
			leftMargin: 5
		}
		font {
			pixelSize: isNxt ? 18 : 15
			family: qfont.italic.name
		}
	}

	Text {
		id: firmwareText
		text: "Firmware: " + app.toonSoftwareVersion + " / IP:" + app.lanIp
		anchors {
			baseline: parent.bottom
			baselineOffset: -5
			horizontalCenter: parent.horizontalCenter
		}
		font {
			pixelSize: isNxt ? 18 : 15
			family: qfont.italic.name
		}
	}

	Text {
		id: footerRight
		text: footerText()
		anchors {
			baseline: parent.bottom
			baselineOffset: -5
			right: parent.right
			rightMargin: 5
		}
		font {
			pixelSize: isNxt ? 18 : 15
			family: qfont.italic.name
		}
	}

	IconButton {
		id: btnToggleBranch;
		width: isNxt ? 48 : 38
		height: isNxt ? 63 : 50
		iconSource: ""
		anchors {
			left: parent.left
			top: parent.top
			topMargin: 150
		}
		colorUp : "transparent"
		colorDown : "transparent"
		onClicked: toggleBranch();
	}
}
