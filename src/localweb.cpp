#include "localweb.h"
#include "pathmap.h"

#include <QTcpServer>
#include <QTcpSocket>
#include <QFile>
#include <QFileInfo>
#include <QUrl>
#include <QVariant>
#include <QMimeDatabase>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QThread>
#include <QTimer>
#include <QDebug>

LocalWeb *LocalWeb::s_instance = nullptr;

static QByteArray reasonOf(int status)
{
	switch (status) {
	case 200: return "OK";
	case 301: return "Moved Permanently";
	case 400: return "Bad Request";
	case 404: return "Not Found";
	default: return "Error";
	}
}

LocalWeb::LocalWeb(QObject *devices, QObject *parent) : QObject(parent), m_devices(devices)
{
	s_instance = this;
}

int LocalWeb::listen(int port)
{
	m_server = new QTcpServer(this);
	if (!m_server->listen(QHostAddress::LocalHost, port)) {
		if (port) qWarning("toonsim: web port %d is taken, using another one", port);
		if (!port || !m_server->listen(QHostAddress::LocalHost, 0)) return 0;
	}
	connect(m_server, &QTcpServer::newConnection, this, [this]() {
		while (QTcpSocket *s = m_server->nextPendingConnection()) {
			auto buf = QSharedPointer<QByteArray>::create();
			connect(s, &QTcpSocket::readyRead, s, [this, s, buf]() {
				buf->append(s->readAll());
				if (buf->contains("\r\n\r\n")) {           // the request line and headers are in (bodies are not used)
					const QByteArray req = *buf;
					buf->clear();
					serve(s, req);
				}
			});
			connect(s, &QTcpSocket::disconnected, s, &QObject::deleteLater);
		}
	});
	qInfo("toonsim: local web server (the Toon's http://localhost) on http://127.0.0.1:%d/ - Toon mobile: http://127.0.0.1:%d/mobile/",
	      m_server->serverPort(), m_server->serverPort());
	return m_server->serverPort();
}

LocalWeb::Answer LocalWeb::answer(const QByteArray &targetBytes, bool followRedirects)
{
	Answer a;
	// /hcb_rrd?action=getRrdData&...
	const QString target = QString::fromUtf8(targetBytes);
	const int q = target.indexOf('?');
	const QString path = QUrl::fromPercentEncoding((q < 0 ? target : target.left(q)).toUtf8());
	const QString query = q < 0 ? QString() : target.mid(q + 1);

	// files: the web root /HCBv2/www (a folder: its index.html), and TSC's link for boilerstatus
	QString device = "/HCBv2/www" + path;
	if (device.endsWith('/')) device += "index.html";
	else if (QFileInfo(PathMap::instance().localPath(device)).isDir()) {     // /mobile -> /mobile/
		if (!followRedirects) {
			a.status = 301;
			a.location = path.toUtf8() + "/";
			return a;
		}
		device += "/index.html";
	}
	if (path == "/boilerstatus/boilervalues.txt") device = "/var/volatile/tmp/boilervalues.txt";
	const QString local = PathMap::instance().localPath(device);
	if (!local.isEmpty() && QFileInfo(local).isFile()) {
		QFile f(local);
		if (f.open(QIODevice::ReadOnly)) {
			a.type = QMimeDatabase().mimeTypeForFile(local).name().toUtf8();
			a.body = f.readAll();
			return a;
		}
	}

	// the daemons
	QVariant ret;
	QMetaObject::invokeMethod(m_devices, "httpRequest", Q_RETURN_ARG(QVariant, ret), Q_ARG(QVariant, path), Q_ARG(QVariant, query));
	const QVariantMap r = ret.toMap();
	if (r.isEmpty()) { a.status = 500; a.type = "text/plain"; a.body = "no answer"; return a; }
	a.status = r.value("status", 200).toInt();
	a.type = r.value("type", "application/json").toString().toUtf8();
	a.body = r.value("body").toString().toUtf8();
	return a;
}

void LocalWeb::send(QTcpSocket *s, const Answer &a)
{
	QByteArray head = "HTTP/1.1 " + QByteArray::number(a.status) + " " + reasonOf(a.status) + "\r\n";
	if (!a.location.isEmpty()) head += "Location: " + a.location + "\r\n";
	if (!a.type.isEmpty()) head += "Content-Type: " + a.type + "\r\n";
	head += "Content-Length: " + QByteArray::number(a.body.size()) + "\r\n"
		"Server: lighttpd/1.4.35 (toonsim)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n";
	s->write(head + a.body);
	s->disconnectFromHost();
}

void LocalWeb::serve(QTcpSocket *s, const QByteArray &request)
{
	// GET /hcb_rrd?action=getRrdData&... HTTP/1.1
	const QList<QByteArray> first = request.left(request.indexOf("\r\n")).split(' ');
	if (first.size() < 2) {
		Answer bad;
		bad.status = 400; bad.type = "text/plain"; bad.body = "bad request";
		send(s, bad);
		return;
	}
	send(s, answer(first[1]));
}

namespace {
// a reply that is complete when it is made: what QNetworkAccessManager would have after reading the
// answer from the socket (status, headers, body). Synchronous XMLHttpRequests read it right away; for
// the others the signals follow on the next event loop turn, as for a real reply.
class LocalReply : public QNetworkReply
{
public:
	LocalReply(QNetworkAccessManager::Operation op, const QNetworkRequest &req, const LocalWeb::Answer &a, QObject *parent)
		: QNetworkReply(parent), m_data(op == QNetworkAccessManager::HeadOperation ? QByteArray() : a.body)
	{
		setRequest(req);
		setUrl(req.url());
		setOperation(op);
		setAttribute(QNetworkRequest::HttpStatusCodeAttribute, a.status);
		setAttribute(QNetworkRequest::HttpReasonPhraseAttribute, reasonOf(a.status));
		if (!a.type.isEmpty()) setHeader(QNetworkRequest::ContentTypeHeader, a.type);
		setHeader(QNetworkRequest::ContentLengthHeader, m_data.size());
		setRawHeader("Server", "lighttpd/1.4.35 (toonsim)");
		setRawHeader("Access-Control-Allow-Origin", "*");
		if (!a.location.isEmpty()) setHeader(QNetworkRequest::LocationHeader, QUrl(req.url()).resolved(QUrl(QString::fromUtf8(a.location))));
		// the errors QNetworkAccessManager gives for these HTTP statuses (XMLHttpRequest then reports the status)
		if (a.status >= 400) {
			const NetworkError e = a.status == 404 ? ContentNotFoundError : a.status == 400 ? ProtocolInvalidOperationError
				: a.status == 403 ? ContentAccessDenied : a.status == 405 ? ContentOperationNotPermittedError : InternalServerError;
			setError(e, QString::fromUtf8(reasonOf(a.status)));
		}
		open(QIODevice::ReadOnly | QIODevice::Unbuffered);
		setFinished(true);
		QTimer::singleShot(0, this, [this]() {
			emit metaDataChanged();
			if (m_data.size()) emit readyRead();
			if (error() != NoError) {
				emit errorOccurred(error());
QT_WARNING_PUSH
QT_WARNING_DISABLE_DEPRECATED
				emit QNetworkReply::error(error());
QT_WARNING_POP
			}
			emit finished();
		});
	}
	void abort() override {}
	bool isSequential() const override { return true; }
	qint64 bytesAvailable() const override { return m_data.size() - m_pos + QNetworkReply::bytesAvailable(); }
protected:
	qint64 readData(char *out, qint64 max) override
	{
		const qint64 n = qMin<qint64>(max, m_data.size() - m_pos);
		if (n <= 0) return -1;
		memcpy(out, m_data.constData() + m_pos, size_t(n));
		m_pos += n;
		return n;
	}
private:
	QByteArray m_data;
	qint64 m_pos = 0;
};
}

QNetworkReply *LocalWeb::reply(QNetworkAccessManager::Operation op, const QNetworkRequest &req, QObject *parent)
{
	if (QThread::currentThread() != m_devices->thread()) return nullptr;      // e.g. a WorkerScript's request
	if (op != QNetworkAccessManager::GetOperation && op != QNetworkAccessManager::HeadOperation
			&& op != QNetworkAccessManager::PostOperation)
		return nullptr;
	const QUrl url = req.url();
	QByteArray target = url.path(QUrl::FullyEncoded).toUtf8();
	if (target.isEmpty()) target = "/";
	if (url.hasQuery()) target += "?" + url.query(QUrl::FullyEncoded).toUtf8();
	// a folder without its / gives its index.html at once (where the 301 would lead)
	return new LocalReply(op, req, answer(target, true), parent);
}
