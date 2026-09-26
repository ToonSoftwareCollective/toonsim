#include "pathmap.h"
#include "localweb.h"

#include <QQmlEngine>
#include <QNetworkRequest>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QLibraryInfo>

PathMap &PathMap::instance()
{
	static PathMap map;
	return map;
}

void PathMap::configure(const QString &home, const QString &appsDir, const QString &dataDir)
{
	m_home = QDir::cleanPath(home);
	m_apps = appsDir.isEmpty() ? m_home + "/apps" : QDir::cleanPath(QDir(appsDir).absolutePath());
	m_data = dataDir.isEmpty() ? m_home + "/data" : QDir::cleanPath(QDir(dataDir).absolutePath());
	// On Windows a device path (/usr/..., /tmp/...) can never be a real one. On Linux it can: the
	// simulator's own folders and Qt's (its QML modules under /usr/lib/...) are what they are.
	m_realPrefixes = QStringList{ m_home, m_apps, m_data };
	for (QLibraryInfo::LibraryLocation l : { QLibraryInfo::Qml2ImportsPath, QLibraryInfo::PluginsPath, QLibraryInfo::LibrariesPath,
	                                         QLibraryInfo::DataPath, QLibraryInfo::ArchDataPath, QLibraryInfo::TranslationsPath })
		m_realPrefixes << QDir::cleanPath(QLibraryInfo::location(l));
	m_realPrefixes.removeAll(QString());
	m_realPrefixes.removeAll("/");
	QDir().mkpath(m_data + "/mnt/data/tsc");
	QDir().mkpath(m_data + "/mnt/data/qmf/config");
	QDir().mkpath(m_data + "/tmp");
	QDir().mkpath(m_apps);
	// /qmf/qml/config starts as the firmware's (pulled from the device); files there are then this data
	// folder's own
	QDir().mkpath(m_data + "/qmf/qml/config");
	for (const QFileInfo &fi : QDir(m_home + "/firmware/config").entryInfoList(QDir::Files)) {
		const QString to = m_data + "/qmf/qml/config/" + fi.fileName();
		if (!QFileInfo::exists(to)) QFile::copy(fi.absoluteFilePath(), to);
	}
	// the firewall rules of a Toon with TSC (apps that open a port add their line, e.g. thermostatPlus's
	// web page; nothing enforces them here)
	const QString iptables = m_data + "/etc/default/iptables.conf";
	if (!QFileInfo::exists(iptables)) {
		QDir().mkpath(QFileInfo(iptables).absolutePath());
		QFile f(iptables);
		if (f.open(QIODevice::WriteOnly))
			f.write("##############################################################################\n"
			        "*nat\n:PREROUTING ACCEPT [0:0]\n:POSTROUTING ACCEPT [0:0]\n:OUTPUT ACCEPT [0:0]\nCOMMIT\n"
			        "##############################################################################\n"
			        "*filter\n:INPUT ACCEPT [0:0]\n:FORWARD ACCEPT [0:0]\n:OUTPUT ACCEPT [0:0]\n:HCB-INPUT - [0:0]\n"
			        "-A INPUT -j HCB-INPUT\n-A FORWARD -j HCB-INPUT\n"
			        "-A HCB-INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT\n"
			        "# These are all closed for Quby/Toon:\n"
			        "-A HCB-INPUT -p tcp -m tcp --dport 22 --tcp-flags SYN,RST,ACK SYN -j ACCEPT\n"
			        "-A HCB-INPUT -p tcp -m tcp --dport 80 --tcp-flags SYN,RST,ACK SYN -j ACCEPT\n"
			        "-A HCB-INPUT -p tcp -m tcp --dport 5900 --tcp-flags SYN,RST,ACK SYN -j ACCEPT\n"
			        "-A HCB-INPUT -p tcp -m tcp --dport 10081 --tcp-flags SYN,RST,ACK SYN -j ACCEPT\n"
			        "-A HCB-INPUT -p udp -m udp --sport 67:68 --dport 67:68 -j ACCEPT\n"
			        "-A HCB-INPUT -p udp -m udp --dport 137:138 -j ACCEPT\n"
			        "-A HCB-INPUT -i lo -j ACCEPT\n-A HCB-INPUT -i tap+ -j ACCEPT\n-A HCB-INPUT -i tun+ -j ACCEPT\n"
			        "-A HCB-INPUT -p tcp -m tcp --tcp-flags SYN,RST,ACK SYN -j DROP\n"
			        "-A HCB-INPUT -p udp -m udp -j DROP\nCOMMIT\n"
			        "##############################################################################\n");
	}
	// a Toon with TSC has its boot script; without it the TSC settings app writes it and reboots the Toon
	const QString boot = m_data + "/etc/rc5.d/S99tsc.sh";
	if (!QFileInfo::exists(boot)) {
		QDir().mkpath(QFileInfo(boot).absolutePath());
		QFile f(boot);
		if (f.open(QIODevice::WriteOnly))
			f.write("if [ ! -s /usr/bin/tsc ] || grep -q no-check-certificate /usr/bin/tsc ; then /usr/bin/curl -Nks --retry 5 "
			        "--connect-timeout 2 https://raw.githubusercontent.com/ToonSoftwareCollective/tscSettings/main/tsc -o /usr/bin/tsc ; "
			        "chmod +x /usr/bin/tsc ; fi ; if ! grep -q tscs /etc/inittab ; then sed -i '/qtqt/a\\tscs:245:respawn:/usr/bin/tsc "
			        ">/var/log/tsc 2>&1' /etc/inittab ; if grep -q tscs /etc/inittab ; then init q ; fi ; fi");
	}
}

void PathMap::install(QQmlEngine *engine)
{
	engine->setUrlInterceptor(this);
	engine->setNetworkAccessManagerFactory(this);
}

QString PathMap::localPath(const QString &in) const
{
	QString p = in;
	if (p.startsWith("file:")) {
		p = p.mid(5);
		while (p.startsWith("//")) p = p.mid(1);      // file:////qmf/... and file:///qmf/... alike
	}
	if (p.length() > 2 && p[1] == ':') return QString();  // already a Windows path
	p = QDir::cleanPath(p);
	for (const QString &real : m_realPrefixes)
		if (p == real || p.startsWith(real + "/")) return QString();
	if (p.startsWith("/qmf/qml/apps")) return m_apps + p.mid(13);
	// the tenant settings (TenantSettings.json: the feature switches TSC's subscription screen writes)
	// belong to a data folder, not to the shared firmware copy they start from
	if (p.startsWith("/qmf/qml/config/") || p == "/qmf/qml/config") return m_data + p;
	if (p.startsWith("/qmf/qml/")) return m_home + "/firmware/" + p.mid(9);  // /qmf/qml/qb -> firmware/qb
	// on the Toon /qmf/config is a link to /mnt/data/qmf/config (the daemons' config_*.xml)
	if (p.startsWith("/qmf/config/") || p == "/qmf/config") return m_data + "/mnt/data" + p;
	// /qmf/www and /qmf/etc are the same as /HCBv2/www and /HCBv2/etc there: the web root (apps publish
	// pages in it, e.g. thermostatPlus's Thermostat+.html) and lighttpd's settings (lighttpd.user, the
	// mobile login TSC writes as /HCBv2/etc/lighttpd/lighttpd.user)
	if (p.startsWith("/qmf/www/") || p == "/qmf/www" || p.startsWith("/qmf/etc/") || p == "/qmf/etc")
		return m_data + "/HCBv2" + p.mid(4);
	if (p.startsWith("/qmf/")) return m_home + "/firmware/qmf/" + p.mid(5);
	// tools/tsc.py maps the same paths (keep the two lists alike)
	if (p.startsWith("/mnt/data") || p.startsWith("/tmp") || p.startsWith("/var/") || p.startsWith("/HCBv2")
			|| p.startsWith("/proc") || p.startsWith("/etc") || p.startsWith("/root") || p.startsWith("/usr/"))
		return m_data + p;
	return QString();
}

QUrl PathMap::mapUrl(const QUrl &url) const
{
	if (url.scheme() == "file") {
		const QString local = localPath(url.toString());
		if (!local.isEmpty()) return QUrl::fromLocalFile(local);
	}
	// https without OpenSSL in this Qt: through tools/netbridge.py, as http://127.0.0.1:<port>/<host>/<path>
	if (url.scheme() == "https" && m_httpsBridgePort > 0) {
		QUrl u;
		u.setScheme("http");
		u.setHost("127.0.0.1");
		u.setPort(m_httpsBridgePort);
		const QString host = url.host() + (url.port() > 0 ? ":" + QString::number(url.port()) : QString());
		u.setPath("/" + host + (url.path().isEmpty() ? "/" : url.path()));
		u.setQuery(url.query(QUrl::FullyEncoded));
		return u;
	}
	// the Toon's own web server: http://localhost/... or http://127.0.0.1/... on port 80 only - an
	// explicit other port is something else (the https bridge above, a URL already mapped)
	if (url.scheme() == "http" && m_httpPort > 0 && url.port(80) == 80) {
		const QString host = url.host();
		if (host == "localhost" || host == "127.0.0.1") {
			QUrl u(url);
			u.setPort(m_httpPort);
			u.setHost("127.0.0.1");
			return u;
		}
	}
	return url;
}

QUrl PathMap::intercept(const QUrl &url, DataType)
{
	return mapUrl(url);
}

namespace {
// XMLHttpRequest goes through this: the same mapping as for QML files
class MappingNam : public QNetworkAccessManager
{
public:
	explicit MappingNam(QObject *parent) : QNetworkAccessManager(parent) {}
protected:
	QNetworkReply *createRequest(Operation op, const QNetworkRequest &req, QIODevice *data) override
	{
		QNetworkRequest r(req);
		const QUrl mapped = PathMap::instance().mapUrl(req.url());
		if (mapped != req.url()) r.setUrl(mapped);
		// the simulator's own web server (the Toon's http://localhost): answered here, not over the
		// socket - a synchronous request would otherwise block the thread that has to answer it
		const int web = PathMap::instance().httpPort();
		if (web > 0 && mapped.scheme() == "http" && mapped.host() == "127.0.0.1" && mapped.port() == web && LocalWeb::instance())
			if (QNetworkReply *local = LocalWeb::instance()->reply(op, r, this)) return local;
		// PUT to a file: URL creates it on the device; make sure the folder exists here too
		if (op == PutOperation && mapped.isLocalFile())
			QDir().mkpath(QFileInfo(mapped.toLocalFile()).absolutePath());
		return QNetworkAccessManager::createRequest(op, r, data);
	}
};
}

QNetworkAccessManager *PathMap::create(QObject *parent)
{
	return new MappingNam(parent);
}
