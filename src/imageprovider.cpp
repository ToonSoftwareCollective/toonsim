#include "imageprovider.h"
#include "pathmap.h"

#include <QImageReader>
#include <QFileInfo>
#include <QColor>
#include <QPainter>
#include <QUrl>
#include <QDebug>

static QString resolve(QString path)
{
	path = QUrl::fromPercentEncoding(path.toUtf8());
	while (path.startsWith("//")) path = path.mid(1);
	const QString rel = path.startsWith('/') ? path.mid(1) : path;
	if (QFileInfo::exists(":/" + rel)) return ":/" + rel;                  // qrc:/apps/..., qrc:/images/...
	const QString local = PathMap::instance().localPath("/" + rel);         // /qmf/qml/apps/..., /mnt/data/...
	if (!local.isEmpty() && QFileInfo::exists(local)) return local;
	if (QFileInfo::exists(path)) return path;                               // a Windows path (file:///C:/...)
	return QString();
}

QImage ToonImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
	QString path = id;
	QColor colour;
	if (m_colorize) {
		// "<colour>/<path>" or "<colour><path>": the colour is a name (white) or #rgb/#rrggbb/#aarrggbb
		int cut = id.indexOf('/');
		QString c = id.left(cut < 0 ? id.length() : cut);
		colour = QColor(c);
		path = cut < 0 ? QString() : id.mid(cut);
	}

	const QString file = resolve(path);
	if (file.isEmpty()) {
		qWarning().noquote() << "toonsim image: not found:" << id;
		return QImage();
	}

	QImageReader reader(file);
	QSize natural = reader.size();
	QSize target = requestedSize.isValid() && !requestedSize.isEmpty() ? requestedSize
		: (natural.isValid() ? QSize(qRound(natural.width() * m_scale), qRound(natural.height() * m_scale)) : QSize());
	if (target.isValid() && reader.supportsOption(QImageIOHandler::ScaledSize)) reader.setScaledSize(target);
	QImage img = reader.read();
	if (img.isNull()) {
		qWarning().noquote() << "toonsim image: cannot read" << file << reader.errorString();
		return QImage();
	}
	if (target.isValid() && img.size() != target) img = img.scaled(target, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);

	if (m_colorize && colour.isValid()) {
		img = img.convertToFormat(QImage::Format_ARGB32_Premultiplied);
		QPainter p(&img);
		p.setCompositionMode(QPainter::CompositionMode_SourceIn);
		p.fillRect(img.rect(), colour);
	}
	if (size) *size = img.size();
	return img;
}
