#pragma once
// Maps the Toon's device paths to the PC, for QML/JS loading (URL interceptor) and for
// XMLHttpRequest (network access manager):
//   file:///qmf/qml/apps/<app>/...   -> the custom apps folder (--apps)
//   file:///qmf/...                  -> firmware/qmf/... (qb, config pulled from the device)
//   file:///mnt/data/..., /tmp/...   -> data/mnt/data/..., data/tmp/... (writable, starts empty)
//   http://localhost/..., 127.0.0.1  -> the simulated local web server (sim/Http.qml handlers)
//   https://...                      -> tools/netbridge.py when this Qt has no TLS

#include <QQmlAbstractUrlInterceptor>
#include <QQmlNetworkAccessManagerFactory>
#include <QNetworkAccessManager>
#include <QString>
#include <QUrl>

class QQmlEngine;

class PathMap : public QQmlAbstractUrlInterceptor, public QQmlNetworkAccessManagerFactory
{
public:
	static PathMap &instance();
	// dataDir: the writable device folders (/mnt/data, /tmp, ...); default <home>/data
	void configure(const QString &home, const QString &appsDir, const QString &dataDir = QString());
	void install(QQmlEngine *engine);

	// device path ("/mnt/data/tsc/x.json" or a file: URL) -> local file path; empty if not mapped
	QString localPath(const QString &devicePathOrUrl) const;
	QString home() const { return m_home; }
	QString appsDir() const { return m_apps; }
	QString dataDir() const { return m_data; }
	int httpPort() const { return m_httpPort; }
	void setHttpPort(int port) { m_httpPort = port; }
	// https requests go to tools/netbridge.py on this port when Qt has no TLS (0 = off)
	void setHttpsBridgePort(int port) { m_httpsBridgePort = port; }

	QUrl intercept(const QUrl &url, DataType type) override;
	QNetworkAccessManager *create(QObject *parent) override;

	QUrl mapUrl(const QUrl &url) const;

private:
	QString m_home, m_apps, m_data;
	// real folders that look like device paths on Linux (/usr/lib/.../qt5/qml, ...): never mapped
	QStringList m_realPrefixes;
	int m_httpPort = 0;
	int m_httpsBridgePort = 0;
};
