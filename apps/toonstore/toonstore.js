function updateHour(strHHMM) {
	return parseInt(strHHMM.substring(0,2));
}

function updateMinute(strHHMM) {
	return parseInt(strHHMM.substring(2,4));
}

function isVersionString(s) {
	return /^[0-9]+(\.[0-9]+)*$/.test(String(s).trim());
}

// Whether a repository entry (with firmwareminimum, firmwaremaximum and toon2only)
// can be installed on this Toon. The firmware range is inclusive on both ends.
// An unknown or malformed firmware version never blocks installation.
function firmwareCompatible(item, firmware, isNxt) {
	if (!isNxt && item.toon2only == "yes") return false;
	if (!isVersionString(firmware)) return true;
	if (isVersionString(item.firmwareminimum) && compareVersions(firmware, item.firmwareminimum) < 0) return false;
	if (isVersionString(item.firmwaremaximum) && compareVersions(firmware, item.firmwaremaximum) > 0) return false;
	return true;
}

// Compares two dotted version strings numerically ("5.1.4" vs "5.1.10").
// Returns -1 when a < b, 0 when equal, 1 when a > b. Missing parts count as 0.
function compareVersions(a, b) {
	var pa = String(a).trim().split(".");
	var pb = String(b).trim().split(".");
	var len = Math.max(pa.length, pb.length);
	for (var i = 0; i < len; i++) {
		var na = i < pa.length ? parseInt(pa[i]) : 0;
		var nb = i < pb.length ? parseInt(pb[i]) : 0;
		if (isNaN(na)) na = 0;
		if (isNaN(nb)) nb = 0;
		if (na < nb) return -1;
		if (na > nb) return 1;
	}
	return 0;
}
