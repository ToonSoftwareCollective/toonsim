#pragma once
// The Toon's local web server (lighttpd on the device), which apps and their scripts use as
// http://localhost/... or http://127.0.0.1/...: PathMap sends those URLs here.
//   /<daemon>?action=...      -> the simulated daemon (Devices.qml httpRequest: happ_thermstat, hcb_rrd, ...)
//   other paths               -> files under /HCBv2/www (the device's web root), plus TSC's link
//                                /boilerstatus/boilervalues.txt -> /var/volatile/tmp/boilervalues.txt
// Two ways in: a real socket on 127.0.0.1:<port> (browsers, Toon mobile, the apps' scripts' curl), and,
// for the GUI's own XMLHttpRequests, replies made on the spot (reply()) - on the device lighttpd is
// another process, here the daemons answer on the GUI thread, so a synchronous XMLHttpRequest over the
// socket would wait for itself forever (thermostatPlus's setSetpoint hung the simulator).

#include <QObject>
#include <QNetworkAccessManager>

class QTcpServer;
class QTcpSocket;
class QNetworkReply;
class QNetworkRequest;

class LocalWeb : public QObject
{
public:
	struct Answer {
		int status = 200;
		QByteArray type;
		QByteArray body;
		QByteArray location;        // a redirect (301): a folder without its trailing /
	};

	LocalWeb(QObject *devices, QObject *parent);
	int listen(int port);           // on 127.0.0.1:port (another free one when taken); 0 when that fails
	static LocalWeb *instance() { return s_instance; }

	// the answer to "GET <target>" (target: /path?query); a folder gives its index.html when
	// followRedirects, else a 301 to the folder with a /
	Answer answer(const QByteArray &target, bool followRedirects = false);
	// an XMLHttpRequest to this server, answered at once - complete when it is returned. On the GUI thread
	// only (the daemons live there); nullptr elsewhere, and then the request goes over the socket.
	QNetworkReply *reply(QNetworkAccessManager::Operation op, const QNetworkRequest &req, QObject *parent);

private:
	void serve(QTcpSocket *s, const QByteArray &request);
	void send(QTcpSocket *s, const Answer &a);

	QObject *m_devices;
	QTcpServer *m_server = nullptr;
	static LocalWeb *s_instance;
};
