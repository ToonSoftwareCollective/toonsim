import QtQuick 2.1

	// a pass-through stand-in for the C++ sort/filter proxy: exposes sourceModel unchanged
ListModel {
	property var sourceModel
	property string sortRoleName
	property string filterRoleName
	property var filterPattern
	property int sortOrder: Qt.AscendingOrder
}
