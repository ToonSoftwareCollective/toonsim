.pragma library

// A small XML reader for SimpleXmlListModel: elements, attributes, text, CDATA, comments, the
// <?xml ?> declaration and the usual entities. Returns the document element as
// { name, attrs: {}, children: [], text } or null when there is none.

var ENTITIES = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'" };

function decode(s) {
	return s.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|\w+);/g, function (m, e) {
		if (e[0] === "#") return String.fromCharCode(e[1] === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10));
		return ENTITIES[e] !== undefined ? ENTITIES[e] : m;
	});
}

function parse(text) {
	var root = { name: "#document", attrs: {}, children: [], text: "" };
	var stack = [root], i = 0, n = text.length;
	while (i < n) {
		var lt = text.indexOf("<", i);
		if (lt < 0) lt = n;
		if (lt > i) stack[stack.length - 1].text += decode(text.slice(i, lt));
		if (lt >= n) break;
		if (text.startsWith("<!--", lt)) { var c = text.indexOf("-->", lt); i = c < 0 ? n : c + 3; continue; }
		if (text.startsWith("<![CDATA[", lt)) {
			var cd = text.indexOf("]]>", lt);
			stack[stack.length - 1].text += text.slice(lt + 9, cd < 0 ? n : cd);
			i = cd < 0 ? n : cd + 3;
			continue;
		}
		if (text[lt + 1] === "?" || text[lt + 1] === "!") { var q = text.indexOf(">", lt); i = q < 0 ? n : q + 1; continue; }
		var gt = text.indexOf(">", lt);
		if (gt < 0) break;
		var tag = text.slice(lt + 1, gt);
		i = gt + 1;
		if (tag[0] === "/") {
			if (stack.length > 1) stack.pop();
			continue;
		}
		var selfClosing = tag[tag.length - 1] === "/";
		if (selfClosing) tag = tag.slice(0, -1);
		var m = /^\s*([^\s\/>]+)/.exec(tag);
		if (!m) continue;
		var el = { name: m[1], attrs: {}, children: [], text: "" };
		var re = /([^\s=]+)\s*=\s*("([^"]*)"|'([^']*)')/g, a;
		while ((a = re.exec(tag.slice(m[0].length))) !== null)
			el.attrs[a[1]] = decode(a[3] !== undefined ? a[3] : a[4]);
		stack[stack.length - 1].children.push(el);
		if (!selfClosing) stack.push(el);
	}
	for (var k = 0; k < root.children.length; k++) return root.children[k];
	return null;
}

// the elements at an absolute path like "/repository/app" (the first step is the document element)
function select(doc, query) {
	var steps = String(query || "").split("/").filter(function (s) { return s !== ""; });
	if (!doc || steps.length === 0) return [];
	if (steps[0] !== doc.name && steps[0] !== "*") return [];
	var nodes = [doc];
	for (var s = 1; s < steps.length; s++) {
		var next = [];
		nodes.forEach(function (nd) {
			nd.children.forEach(function (ch) { if (ch.name === steps[s] || steps[s] === "*") next.push(ch); });
		});
		nodes = next;
	}
	return nodes;
}

// a role's value: the text of the child element of that name, else the attribute
function value(el, role) {
	for (var i = 0; i < el.children.length; i++)
		if (el.children[i].name === role) return el.children[i].text.trim();
	return el.attrs[role] !== undefined ? el.attrs[role] : "";
}
