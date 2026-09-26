pragma Singleton
import QtQuick 2.1

	// the weather service (C++ in qt-gui, fed from Eneco's back office): fixed sample weather
QtObject {
	enum DataState { DATA_STATE_INVALID, DATA_STATE_VALID, NoValidDataError }
	property string cityName: "Amsterdam"
	property int cityId: 2759794
	property real latitude: 52.37
	property real longitude: 4.89
	property int dataState: 1
	property real temperature: 14.5
	property real perceivedTemperature: 13.0
	property string icon: "partly_cloudy"
	property var forecast: []
	property string windDirection: "ZW"
	property real windSpeed: 4
	property int humidity: 72
	property real precipitation: 0
	property int uvIndex: 2
	property date sunrise: new Date(new Date().setHours(7, 20, 0, 0))
	property date sunset: new Date(new Date().setHours(19, 25, 0, 0))
	function refresh() {}
	function resolveCityInfo() {}
}
