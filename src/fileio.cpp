#include "fileio.h"
#include "pathmap.h"

#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QTextStream>
#include <QUrl>
#include <QQmlContext>
#include <QQmlEngine>

void FileIO::setSource(const QString &s)
{
	if (s == m_source) return;
	m_source = s;
	emit sourceChanged();
}

QString FileIO::path() const
{
	QString src = m_source;
	// a relative source ("wastecollectionProvider.js") is relative to the QML file that uses it, as on
	// the Toon (wastecollection reads its provider script so)
	if (!src.isEmpty() && QUrl(src).isRelative() && !src.startsWith("/")) {
		if (QQmlContext *ctx = qmlContext(this)) src = ctx->resolvedUrl(QUrl(src)).toString();
	}
	if (src.startsWith("qrc:")) return ":" + src.mid(4);        // qrc:/apps/ -> :/apps/ (Globals.qml lists the apps so)
	const QString mapped = PathMap::instance().localPath(src);
	if (!mapped.isEmpty()) return mapped;
	return src.startsWith("file:") ? QUrl(src).toLocalFile() : src;
}

QString FileIO::read()
{
	QFile f(path());
	if (!f.open(QIODevice::ReadOnly)) {
		emit error("cannot read " + m_source);
		return QString();
	}
	return QString::fromUtf8(f.readAll());
}

bool FileIO::write(const QString &data)
{
	const QString p = path();
	QDir().mkpath(QFileInfo(p).absolutePath());
	QFile f(p);
	if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
		emit error("cannot write " + m_source);
		return false;
	}
	f.write(data.toUtf8());
	return true;
}

bool FileIO::exists() const
{
	return QFileInfo::exists(path());
}

QStringList FileIO::dirEntries() const
{
	return QDir(path()).entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
}

QStringList FileIO::entryList(const QStringList &nameFilters) const
{
	return QDir(path()).entryList(nameFilters, QDir::Files, QDir::Name);
}
