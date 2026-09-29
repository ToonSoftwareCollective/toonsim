#pragma once
// Remote control on a local TCP port, for development and automated tests. One command per line,
// one JSON reply per line:
//   tap X Y | press X Y | move X Y | release X Y     touch input in window pixels
//   shot FILE                                       screenshot as PNG
//   eval JS                                         evaluate JavaScript in the GUI's root context
//   items [TEXT]                                    visible items with a text (containing TEXT)
//   log                                             console lines since the previous "log"
//   size                                            window size and isNxt
//   restart                                         restart the GUI (a new toonsim, same arguments)
// (Ctrl+1 / Ctrl+2 and, on Windows, the window menu restart it as a Toon 1 / Toon 2: restartAs.)
//   quit
// tools/toonsim.py wraps this for Python tests.

#include <QObject>
#include <QStringList>
#include <QPointer>
#include <QQuickWindow>

class QQmlApplicationEngine;
class QTcpServer;
class QTcpSocket;
class QQuickItem;

class Control : public QObject
{
	Q_OBJECT
public:
	Control(QQmlApplicationEngine *engine, QObject *simContext);
	void listen(int port);
	void setWindow(QQuickWindow *w) { m_window = w; }

	static void installLogHandler(const QString &logFile);

	// the GUI restart the Toon does after "killall -9 qt-gui" (its watchdog starts qt-gui again): a new
	// toonsim with the same arguments, this one quits. Also QML's toonsimControl.restart().
	Q_INVOKABLE void restart();
	// the same with another screen: "toon1" or "toon2" replaces the --size argument
	Q_INVOKABLE void restartAs(const QString &size);

private:
	QByteArray handle(const QString &line);
	void mouse(int type, int x, int y);
	void collectItems(QQuickItem *item, const QString &filter, QVariantList &out) const;

	QQmlApplicationEngine *m_engine;
	QObject *m_sim;
	QPointer<QQuickWindow> m_window;
	QTcpServer *m_server = nullptr;
	bool m_restarting = false;
};
