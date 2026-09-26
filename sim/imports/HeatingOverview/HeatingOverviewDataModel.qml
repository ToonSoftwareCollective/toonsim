import QtQuick 2.1

ListModel {
	enum State { STATE_NO_DATA, STATE_FETCHING_DATA, STATE_DATA, STATE_ERROR }
	property int state: 0
}
