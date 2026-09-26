.pragma library

// The bxt message model of qt-gui's C++ BxtClient plugin, in plain JS: messages with named
// arguments, where an argument is either text or an XML tree. The Toon's QML walks those trees with
// node.child / node.sibling / getChild(name) / getChildText(name), exactly as below.

var ACTION_INVOKE = 0;
var ACTION_RESPONSE = 1;
var NOTIFICATION = 2;
var DATASET = 3;

// ---- XML nodes ----

function Node(name, text) {
	this.name = name || "";
	this.text = (text === undefined || text === null) ? "" : String(text);
	this.child = null;          // first child
	this.sibling = null;        // next sibling
	this.parent = null;
	this._attrs = [];           // [[name, value], ...], order kept
}

// the next sibling with the same name (sibling is the next of any name): the firmware walks lists with
// for (n = x.getChild("state"); n; n = n.next), and a <statesSaved> after the states must not come up
Object.defineProperty(Node.prototype, "next", {
	get: function () {
		for (var s = this.sibling; s; s = s.sibling) if (s.name === this.name) return s;
		return null;
	}
});

Node.prototype.addChild = function (name, text, flags) {
	var n = new Node(name, text);
	n.parent = this;
	if (!this.child) this.child = n;
	else {
		var last = this.child;
		while (last.sibling) last = last.sibling;
		last.sibling = n;
	}
	return n;
};
Node.prototype.getChild = function (name) {
	for (var c = this.child; c; c = c.sibling) if (c.name === name) return c;
	return null;
};
Node.prototype.getChildren = function (name) {
	var out = [];
	for (var c = this.child; c; c = c.sibling) if (!name || c.name === name) out.push(c);
	return out;
};
Node.prototype.getChildText = function (name) {
	var c = this.getChild(name);
	return c ? c.text : "";
};
Node.prototype.setChildText = function (name, text) {
	var c = this.getChild(name);
	if (c) c.text = String(text); else this.addChild(name, text, 0);
};
Node.prototype.setText = function (t) { this.text = String(t); };
Node.prototype.setAttribute = function (name, value) {
	for (var i = 0; i < this._attrs.length; i++)
		if (this._attrs[i][0] === name) { this._attrs[i][1] = String(value); return; }
	this._attrs.push([name, String(value)]);
};
Node.prototype.getAttribute = function (name) {
	for (var i = 0; i < this._attrs.length; i++) if (this._attrs[i][0] === name) return this._attrs[i][1];
	return "";
};
Node.prototype.getAttributeCount = function () { return this._attrs.length; };
Node.prototype.getAttributeName = function (i) { return this._attrs[i] ? this._attrs[i][0] : ""; };
Node.prototype.getAttributeValue = function (i) { return this._attrs[i] ? this._attrs[i][1] : ""; };
Node.prototype.clone = function () {
	var n = new Node(this.name, this.text);
	for (var i = 0; i < this._attrs.length; i++) n._attrs.push([this._attrs[i][0], this._attrs[i][1]]);
	for (var c = this.child; c; c = c.sibling) {
		var cc = c.clone();
		cc.parent = n;
		if (!n.child) n.child = cc;
		else { var last = n.child; while (last.sibling) last = last.sibling; last.sibling = cc; }
	}
	return n;
};
// appends an existing node (e.g. a clone) as the last child
Node.prototype.appendNode = function (node) {
	node.parent = this; node.sibling = null;
	if (!this.child) this.child = node;
	else { var last = this.child; while (last.sibling) last = last.sibling; last.sibling = node; }
	return node;
};
Node.prototype.toXml = function () {
	var a = "";
	for (var i = 0; i < this._attrs.length; i++) a += " " + this._attrs[i][0] + "=\"" + escape(this._attrs[i][1]) + "\"";
	var inner = escape(this.text);
	for (var c = this.child; c; c = c.sibling) inner += c.toXml();
	return "<" + this.name + a + ">" + inner + "</" + this.name + ">";
};

function escape(s) {
	return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
function unescape(s) {
	return s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&amp;/g, "&");
}

// a small XML reader, enough for bxt payloads: elements, attributes, text, no DTDs/CDATA
function parseXml(text) {
	var root = new Node("#root");
	var stack = [root];
	var re = /<(\/?)([A-Za-z_][\w.:-]*)([^>]*?)(\/?)>|([^<]+)/g;
	var m;
	while ((m = re.exec(text)) !== null) {
		var top = stack[stack.length - 1];
		if (m[5] !== undefined) {
			var t = m[5];
			if (t.trim().length) top.text += unescape(t.trim());
		} else if (m[1] === "/") {
			if (stack.length > 1) stack.pop();
		} else {
			var n = top.addChild(m[2], "", 0);
			var ar = /([\w.:-]+)\s*=\s*"([^"]*)"/g, am;
			while ((am = ar.exec(m[3])) !== null) n.setAttribute(am[1], unescape(am[2]));
			if (m[4] !== "/") stack.push(n);
		}
	}
	return root;
}

// builds an XML tree from a JS object: { a: "1", b: { c: "2" } } -> <name><a>1</a><b><c>2</c></b></name>
function fromObject(name, obj) {
	var n = new Node(name);
	fill(n, obj);
	return n;
}
function fill(node, obj) {
	if (obj === null || obj === undefined) return;
	if (typeof obj !== "object") { node.text = String(obj); return; }
	for (var k in obj) {
		var v = obj[k];
		if (Array.isArray(v)) {
			for (var i = 0; i < v.length; i++) fill(node.addChild(k, "", 0), v[i]);
		} else if (k.charAt(0) === "@") {
			node.setAttribute(k.substring(1), v);
		} else if (k === "#text") {
			node.text = String(v);
		} else {
			fill(node.addChild(k, "", 0), v);
		}
	}
}

// ---- messages ----

var uuidCounter = 0;

function Message(type, source, destination, serviceId, action) {
	this.type = type;
	this.source = source || "";
	this.destination = destination || "";
	this.serviceId = serviceId || "";
	this.name = action || "";          // the action name ("GetFeatures", "GetFeaturesResponse", ...)
	this.action = this.name;
	this.uuid = "msg-" + (++uuidCounter);
	this.receivedLong = Date.now();
	this._args = [];                   // [{ name, text, xml }]
}

Message.prototype._find = function (name) {
	for (var i = 0; i < this._args.length; i++) if (this._args[i].name === name) return this._args[i];
	return null;
};
Message.prototype.addArgument = function (name, value) {
	var a = { name: name, text: (value === null || value === undefined) ? "" : String(value), xml: null };
	this._args.push(a);
	return this;
};
Message.prototype.getArgument = function (name) {
	var a = this._find(name);
	if (!a) return "";
	if (a.xml && !a.text) return a.xml.text;
	return a.text;
};
// the XML tree of an argument; created on first use, so addArgument(name, null) + getArgumentXml(name)
// builds a tree in place, as the Toon's QML does
Message.prototype.getArgumentXml = function (name) {
	var a = this._find(name);
	if (!a && this.lenient) { a = { name: name, text: "", xml: new Node(name) }; this._args.push(a); }
	if (!a) return null;
	if (!a.xml) { a.xml = new Node(name, a.text); }
	return a.xml;
};
Message.prototype.addArgumentXmlText = function (name, xmlText) {
	if (xmlText === undefined) { xmlText = name; name = null; }
	var parsed = parseXml(String(xmlText));
	for (var c = parsed.child; c; c = c.sibling) {
		var a = { name: name || c.name, text: "", xml: c };
		c.parent = null;
		this._args.push(a);
	}
	return this;
};
Message.prototype.setArgumentXml = function (name, node) {
	var a = this._find(name);
	if (!a) { a = { name: name, text: "", xml: null }; this._args.push(a); }
	a.xml = node;
	return this;
};
Message.prototype.argumentNames = function () {
	return this._args.map(function (a) { return a.name; });
};
Message.prototype.createResponse = function () {
	var r = new Message(ACTION_RESPONSE, this.destination, this.source, this.serviceId, this.name + "Response");
	r.requestUuid = this.uuid;
	return r;
};
Message.prototype.getChild = function (name) {       // some QML treats the message as a tree
	var a = this._find(name);
	return a ? this.getArgumentXml(name) : null;
};
Object.defineProperty(Message.prototype, "stringContent", {
	get: function () {
		var s = "<" + (this.type === ACTION_RESPONSE ? "response" : "action") + " class=\"" + this.serviceId
			+ "\" name=\"" + this.name + "\" destination=\"" + this.destination + "\" source=\"" + this.source + "\">";
		for (var i = 0; i < this._args.length; i++) {
			var a = this._args[i];
			s += a.xml ? a.xml.toXml() : "<" + a.name + ">" + escape(a.text) + "</" + a.name + ">";
		}
		return s + "</" + (this.type === ACTION_RESPONSE ? "response" : "action") + ">";
	}
});

function newMessage(type, destination, serviceId, action) {
	return new Message(type, "qt-gui", destination, serviceId, action);
}
