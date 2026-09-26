#pragma once
// qt-gui's image providers:
//   image://scaled/<path>              the image at the display's scale (Toon 2: x1.28, drawn for Toon 1)
//   image://colorized/<colour>/<path>  the same, every visible pixel painted in <colour> (alpha kept)
// <path> is a qrc path (/apps/x/drawables/a.svg, images/b.svg) or a device path (/qmf/qml/apps/...).

#include <QQuickImageProvider>

class ToonImageProvider : public QQuickImageProvider
{
public:
	ToonImageProvider(bool colorize, qreal scale)
		: QQuickImageProvider(QQuickImageProvider::Image), m_colorize(colorize), m_scale(scale) {}
	QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
	bool m_colorize;
	qreal m_scale;
};
