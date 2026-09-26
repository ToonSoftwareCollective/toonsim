import QtQuick 2.1
import "xml.js" as Xml

	// qt-gui's SimpleXmlListModel (C++, registered by qt-gui itself; ToonStore uses it): a list model
	// filled from XML, one row per element at 'query' (an absolute path, "/repository/app"), with
	// one role per entry in 'roles' ({ name: "string" | "number" }) taken from the child element of
	// that name (or the attribute). The XML comes from 'xml' or is loaded from 'source'; 'sortBy'
	// sorts the rows on a role. count and get(i) are ListModel's.
ListModel {
	id: model

	property string xml
	property url source
	property string query
	property var roles: ({})
	property string sortBy
	property bool _complete: false

	// empties the model and forgets the XML, so the next "model.xml = ..." fills it again even when it
	// is the same text as before: apps refresh with clear() + xml = <data> (Domoticz every 15 s), and a
	// property set to its current value does not change, which left the list empty
	function clear() {
		if (count > 0) remove(0, count);
		xml = "";
	}

	function _reload() {
		if (!_complete) return;
		if (count > 0) remove(0, count);
		if (!xml || !query) return;
		var doc;
		try { doc = Xml.parse(xml); } catch (e) { console.log("SimpleXmlListModel:", e); return; }
		var rows = Xml.select(doc, query).map(function (el) {
			var row = {};
			for (var r in roles) {
				var v = Xml.value(el, r);
				row[r] = (roles[r] === "number") ? (v === "" ? 0 : Number(v)) : v;
			}
			return row;
		});
		if (sortBy) rows.sort(function (a, b) { return a[sortBy] < b[sortBy] ? -1 : a[sortBy] > b[sortBy] ? 1 : 0; });
		rows.forEach(function (row) { append(row); });
	}

	function _load() {
		if (!source.toString()) return;
		var xhr = new XMLHttpRequest();
		xhr.onreadystatechange = function () {
			if (xhr.readyState !== XMLHttpRequest.DONE) return;
			if (xhr.status === 200 || (xhr.status === 0 && xhr.responseText)) model.xml = xhr.responseText;
			else console.log("SimpleXmlListModel: cannot load", source, xhr.status);
		};
		xhr.open("GET", source);
		xhr.send();
	}

	onXmlChanged: _reload()
	onQueryChanged: _reload()
	onRolesChanged: _reload()
	onSortByChanged: _reload()
	onSourceChanged: _load()
	Component.onCompleted: { _complete = true; if (xml) _reload(); else _load(); }
}
