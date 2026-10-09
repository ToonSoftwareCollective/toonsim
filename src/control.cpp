#include "control.h"

#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlExpression>
#include <QQuickWindow>
#include <QQuickItem>
#include <QTcpServer>
#include <QTcpSocket>
#include <QGuiApplication>
#include <QMouseEvent>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJSValue>
#include <QImage>
#include <QFile>
#include <QMutex>
#include <QDateTime>
#include <QTextStream>
#include <QTimer>
#include <QThread>
#include <QProcess>
#include <QDir>
#include <cstdio>
#include "pathmap.h"

namespace {
QMutex g_logLock;
QStringList g_logPending;       // lines not yet fetched with "log"
QFile *g_logFile = nullptr;

void logHandler(QtMsgType type, const QMessageLogContext &, const QString &msg)
{
	static const char *kinds[] = { "debug", "warning", "critical", "fatal", "info" };
	const QString line = QDateTime::currentDateTime().toString("HH:mm:ss.zzz") + " "
		+ kinds[type < 5 ? type : 0] + " " + msg;
	QMutexLocker lock(&g_logLock);
	g_logPending << line;
	if (g_logPending.size() > 5000) g_logPending.removeFirst();
	fprintf(stderr, "%s\n", line.toLocal8Bit().constData());
	fflush(stderr);
	if (g_logFile) { g_logFile->write(line.toUtf8() + "\n"); g_logFile->flush(); }
}

QJsonValue toJson(const QVariant &v)
{
	if (v.canConvert<QJSValue>()) return QJsonValue::fromVariant(v.value<QJSValue>().toVariant());
	if (v.canConvert<QObject *>() && v.value<QObject *>()) {
		QObject *o = v.value<QObject *>();
		return QString("%1(%2)").arg(o->metaObject()->className(), o->objectName());
	}
	return QJsonValue::fromVariant(v);
}

QByteArray reply(const QJsonObject &o)
{
	return QJsonDocument(o).toJson(QJsonDocument::Compact) + "\n";
}

QByteArray ok(const QJsonValue &result = QJsonValue())
{
	QJsonObject o{ { "ok", true } };
	if (!result.isUndefined() && !result.isNull()) o["result"] = result;
	return reply(o);
}

QByteArray fail(const QString &why)
{
	return reply({ { "ok", false }, { "error", why } });
}
}

void Control::installLogHandler(const QString &logFile)
{
	g_logFile = new QFile(logFile);
	if (!g_logFile->open(QIODevice::WriteOnly | QIODevice::Truncate)) { delete g_logFile; g_logFile = nullptr; }
	qInstallMessageHandler(logHandler);
}

Control::Control(QQmlApplicationEngine *engine, QObject *simContext) : m_engine(engine), m_sim(simContext) {}

void Control::listen(int port)
{
	m_server = new QTcpServer(this);
	// after a restart the previous toonsim may still hold the port for a moment: retry for 10 s
	for (int attempt = 0; !m_server->listen(QHostAddress::LocalHost, port); attempt++) {
		if (attempt >= 40) {
			qWarning("toonsim: control port %d not available", port);
			return;
		}
		QThread::msleep(250);
	}
	qInfo("toonsim: control on 127.0.0.1:%d", port);
	connect(m_server, &QTcpServer::newConnection, this, [this]() {
		while (QTcpSocket *s = m_server->nextPendingConnection()) {
			connect(s, &QTcpSocket::readyRead, s, [this, s]() {
				while (s->canReadLine()) {
					const QString line = QString::fromUtf8(s->readLine()).trimmed();
					if (!line.isEmpty()) s->write(handle(line));
				}
			});
			connect(s, &QTcpSocket::disconnected, s, &QObject::deleteLater);
		}
	});
}

void Control::restart() { restartAs(QString()); }

void Control::restartAs(const QString &size)
{
	if (m_restarting) return;
	m_restarting = true;
	QTimer::singleShot(200, qApp, [this, size]() {
		qInfo("toonsim: restarting the GUI%s", size.isEmpty() ? "" : qPrintable(" as " + size));
		if (m_server) m_server->close();
		QStringList args = QCoreApplication::arguments().mid(1);
		if (!size.isEmpty()) {
			for (int i = args.size() - 1; i >= 0; --i) {
				if (args[i] == "--size" || args[i] == "-size") { args.removeAt(i); if (i < args.size()) args.removeAt(i); }
				else if (args[i].startsWith("--size=")) args.removeAt(i);
			}
			args << "--size" << size;
		}
		if (!args.contains("--restarted")) args << "--restarted";
		QProcess::startDetached(QCoreApplication::applicationFilePath(), args);
		qApp->quit();
	});
}

void Control::checkUpdates(bool manual)
{
	Q_UNUSED(manual);
	const QString cmdPath = PathMap::instance().dataDir() + "/tmp/tsc.command";
	QDir().mkpath(QFileInfo(cmdPath).absolutePath());
	QFile f(cmdPath);
	if (f.open(QIODevice::WriteOnly | QIODevice::Append)) {
		f.write("tscupdate\n");
		f.close();
	}
}

void Control::mouse(int type, int x, int y)
{
	const QPointF p(x, y);
	const Qt::MouseButtons buttons = (type == QEvent::MouseButtonRelease) ? Qt::NoButton : Qt::LeftButton;
	QMouseEvent ev(QEvent::Type(type), p, p, m_window->mapToGlobal(p.toPoint()), Qt::LeftButton, buttons, Qt::NoModifier);
	QGuiApplication::sendEvent(m_window, &ev);
}

void Control::collectItems(QQuickItem *item, const QString &filter, QVariantList &out) const
{
	if (!item || !item->isVisible() || item->opacity() <= 0.0) return;
	const QVariant text = item->property("text");
	if (text.isValid() && text.type() == QVariant::String && !text.toString().isEmpty()
			&& (filter.isEmpty() || text.toString().contains(filter, Qt::CaseInsensitive))) {
		const QRectF r = item->mapRectToScene(QRectF(0, 0, item->width(), item->height()));
		// on screen only: the keyboard, for one, waits visible below the bottom edge
		const QRectF screen(0, 0, m_window ? m_window->width() : 1e6, m_window ? m_window->height() : 1e6);
		if (r.intersects(screen) || (r.isEmpty() && screen.contains(r.topLeft()))) out << QVariantMap{ { "text", text.toString() }, { "x", int(r.x()) }, { "y", int(r.y()) },
		                    { "w", int(r.width()) }, { "h", int(r.height()) },
		                    { "cx", int(r.center().x()) }, { "cy", int(r.center().y()) },
		                    { "type", QString(item->metaObject()->className()).section('_', 0, 0) } };
	}
	for (QQuickItem *child : item->childItems()) collectItems(child, filter, out);
}

QByteArray Control::handle(const QString &line)
{
	const QString cmd = line.section(' ', 0, 0);
	const QString rest = line.section(' ', 1);
	const QStringList args = rest.split(' ', Qt::SkipEmptyParts);

	if (cmd == "log") {
		QMutexLocker lock(&g_logLock);
		const QStringList lines = g_logPending;
		g_logPending.clear();
		return ok(QJsonArray::fromStringList(lines));
	}
	if (cmd == "quit") {
		QMetaObject::invokeMethod(qApp, "quit", Qt::QueuedConnection);
		return ok();
	}
	if (cmd == "update" || cmd == "check_update") {
		checkUpdates(true);
		return ok();
	}
	// the GUI restart the Toon does with "killall -9 qt-gui" (tsc after a ToonStore install): a new
	// toonsim with the same arguments, this one quits; the new one waits for the control port
	if (cmd == "restart") {
		restart();
		return ok();
	}
	if (cmd == "eval") {
		QObject *root = m_engine->rootObjects().isEmpty() ? nullptr : m_engine->rootObjects().first();
		// in Canvas.qml's own context: its ids (canvas, stage, ...), imports (CanvasJS.loadedApps) and
		// globals are visible, as in app code
		QQmlContext *ctx = root ? qmlContext(root) : nullptr;
		QQmlExpression expr(ctx ? ctx : m_engine->rootContext(), root, rest);
		const QVariant v = expr.evaluate();
		if (expr.hasError()) return fail(expr.error().toString());
		return ok(toJson(v));
	}
	if (!m_window) return fail("no window yet");
	if (cmd == "size") return ok(QJsonObject{ { "w", m_window->width() }, { "h", m_window->height() },
	                                         { "isNxt", m_engine->rootContext()->contextProperty("isNxt").toBool() } });
	if ((cmd == "tap" || cmd == "press" || cmd == "move" || cmd == "release") && args.size() >= 2) {
		const int x = args[0].toInt(), y = args[1].toInt();
		if (cmd == "tap") { mouse(QEvent::MouseButtonPress, x, y); mouse(QEvent::MouseButtonRelease, x, y); }
		else if (cmd == "press") mouse(QEvent::MouseButtonPress, x, y);
		else if (cmd == "move") mouse(QEvent::MouseMove, x, y);
		else mouse(QEvent::MouseButtonRelease, x, y);
		return ok();
	}
	if (cmd == "shot" && !rest.isEmpty()) {
		const QImage img = m_window->grabWindow();
		if (img.isNull() || !img.save(rest, "PNG")) return fail("screenshot failed");
		return ok(rest);
	}
	// what is under a point, top-most first: type, objectName/text, and for mouse areas whether they take it
	if (cmd == "hit" && args.size() >= 2) {
		const QPointF pt(args[0].toDouble(), args[1].toDouble());
		QVariantList out;
		std::function<void(QQuickItem *, int)> walk = [&](QQuickItem *it, int depth) {
			if (!it->isVisible() || it->opacity() <= 0.0) return;
			// hit order: higher z first, and within equal z the later sibling first
			QList<QQuickItem *> order;
			const QList<QQuickItem *> kids = it->childItems();
			for (int i = kids.size() - 1; i >= 0; --i) order << kids[i];
			std::stable_sort(order.begin(), order.end(), [](QQuickItem *a, QQuickItem *b) { return a->z() > b->z(); });
			for (QQuickItem *k : order) walk(k, depth + 1);
			const QPointF local = it->mapFromScene(pt);
			if (!(local.x() >= 0 && local.y() >= 0 && local.x() < it->width() && local.y() < it->height())) return;
			QString cls = QString(it->metaObject()->className()).section('_', 0, 0);
			QVariantMap m{ { "type", cls }, { "depth", depth } };
			if (!it->objectName().isEmpty()) m["name"] = it->objectName();
			const QVariant text = it->property("text");
			if (text.type() == QVariant::String && !text.toString().isEmpty()) m["text"] = text.toString().left(60);
			if (it->acceptedMouseButtons() != Qt::NoButton) m["mouse"] = it->isEnabled();
			if (!it->state().isEmpty()) m["state"] = it->state();
			out << m;
		};
		if (m_window) walk(m_window->contentItem(), 0);
		return ok(QJsonArray::fromVariantList(out));
	}
	if (cmd == "items") {
		QVariantList out;
		collectItems(m_window->contentItem(), rest, out);
		return ok(QJsonArray::fromVariantList(out));
	}
	return fail("unknown command: " + cmd);
}
