pragma Singleton
import QtQuick 2.1

	// Eneco's in-app feedback campaigns: none in the simulator
QtObject {
	property var campaigns: []
	signal campaignAvailable(var campaign)
	function startFetchCampaigns() {}
	function actionTriggered(name) {}
	function submitFeedback(id, rating, comment) { console.log("toonsim feedback:", id, rating, comment); }
	function setCampaignAnswered(id, answered) {}
}
