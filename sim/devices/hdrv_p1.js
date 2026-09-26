.pragma library
.import "energy.js" as Energy

// hdrv_p1: the meter adapter on the smart meter's P1 port. The graphs and usage tiles get their history
// from it with rest.RestCall ("/insights/home/electricity/consumption/quantity/unit/days?from=..&to=..",
// see qb/energyinsights), answered here from the household model in energy.js.

function device(Bxt) {
	return {
		type: "hdrv_p1",
		state: {
			gas_smartMeter: 1, elec_smartMeter: 1,
			lowRateStartHour: 23, lowRateStartMinute: 0, highRateStartHour: 7, highRateStartMinute: 0
		},
		datasets: {
			"connectedInfo": function (dev) {
				var n = new Bxt.Node("connectedInfo");
				for (var k in dev.state) n.addChild(k, dev.state[k], 0);
				return n;
			}
		},
		requests: {
			"rest.RestCall": function (msg, dev) {
				var r = msg.createResponse(), uri = "";
				try { uri = JSON.parse(msg.getArgument("json")).requestHeader.uri; } catch (e) {}
				var answer;
				if (uri.indexOf("/insights/home/") === 0)
					answer = { responseHeader: { statusCode: 200 }, body: Energy.insights(uri) };
				else
					answer = { responseHeader: { statusCode: 404 }, body: {} };
				r.addArgument("json", JSON.stringify(answer));
				return r;
			},
			// weekends count as low tariff
			"specific1.IsHolidayOrWeekend": function (msg, dev) {
				var d = new Date(parseInt(msg.getArgument("time")) * 1000);
				var r = msg.createResponse();
				r.addArgument("isLow", (d.getDay() === 0 || d.getDay() === 6) ? 1 : 0);
				return r;
			}
		}
	};
}
