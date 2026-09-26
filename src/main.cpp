// toonsim - runs the Toon's own GUI (qt-gui's QML from the device's .rcc files) on a PC.
//
// The C++ part only does what QML cannot: register the device's resource files, map device paths
// (file:///qmf/..., file:///mnt/data/..., http://localhost/...) to folders and simulated services on
// the PC, provide the TSC FileIO plugin, and set the context properties qt-gui sets. Everything that
// simulates the device itself (bxt bus, happ_thermstat, screen state, ...) is QML/JS under sim/.

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlComponent>
#include <QQuickWindow>
#include <QResource>
#include <QCommandLineParser>
#include <QDir>
#include <QFileInfo>
#include <QMetaProperty>
#include <QDebug>

#include "pathmap.h"
#include "fileio.h"
#include "control.h"
#include "imageprovider.h"
#include "dialogfacade.h"
#include "language.h"
#include "localweb.h"

#include <QMouseEvent>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QTcpServer>
#include <QSslSocket>
#include <QLockFile>
#include <QQuickItem>
#include <algorithm>

#ifdef Q_OS_WIN
#include <windows.h>
#include <ctime>
#include <cstring>
#endif

namespace {
#ifdef Q_OS_WIN
// Qt 5.15.2's JavaScript Date gets daylight saving wrong in MinGW builds (qv4dateobject.cpp,
// DaylightSavingTA): it hands localtime a pointer to a 32-bit long as a 64-bit time_t, so localtime
// reads 4 bytes of garbage along with the time - it fails or not depending on what is on the stack.
// getHours() was an hour behind in summer, new Date(y, m, d, h) sometimes an hour off the other way.
// That localtime is MinGW's localtime_r -> localtime_s, which finds msvcrt's _localtime64_s at run time
// with GetProcAddress. Qt5Qml.dll's GetProcAddress is pointed at a wrapper that hands out, for that
// name, a _localtime64_s reading the 32-bit value it is really given: then daylight saving is right for
// every date (times fit in 32 bits until 2038).
typedef int (__cdecl *Localtime64s)(struct tm *, const __time64_t *);
Localtime64s g_realLocaltime64s = nullptr;

int __cdecl fixedLocaltime64s(struct tm *out, const __time64_t *t)
{
	const __time64_t v = static_cast<__time64_t>(*reinterpret_cast<const qint32 *>(t));
	return g_realLocaltime64s(out, &v);
}

FARPROC (WINAPI *g_realGetProcAddress)(HMODULE, LPCSTR) = nullptr;

FARPROC WINAPI qmlGetProcAddress(HMODULE module, LPCSTR name)
{
	FARPROC p = g_realGetProcAddress(module, name);
	if (p && reinterpret_cast<quintptr>(name) > 0xffff && std::strcmp(name, "_localtime64_s") == 0) {
		g_realLocaltime64s = reinterpret_cast<Localtime64s>(p);
		return reinterpret_cast<FARPROC>(&fixedLocaltime64s);
	}
	return p;
}

// replaces Qt5Qml.dll's import 'function' from 'dll' with 'replacement'; returns the original
void *patchQmlImport(const char *dll, const char *function, void *replacement)
{
	BYTE *base = reinterpret_cast<BYTE *>(GetModuleHandleW(L"Qt5Qml.dll"));
	if (!base) return nullptr;
	auto *nt = reinterpret_cast<IMAGE_NT_HEADERS *>(base + reinterpret_cast<IMAGE_DOS_HEADER *>(base)->e_lfanew);
	const IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
	for (auto *imp = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR *>(base + dir.VirtualAddress); imp->Name; ++imp) {
		if (_stricmp(reinterpret_cast<char *>(base + imp->Name), dll) != 0) continue;
		auto *thunk = reinterpret_cast<IMAGE_THUNK_DATA *>(base + imp->FirstThunk);
		auto *names = reinterpret_cast<IMAGE_THUNK_DATA *>(base + (imp->OriginalFirstThunk ? imp->OriginalFirstThunk : imp->FirstThunk));
		for (; names->u1.AddressOfData; ++names, ++thunk) {
			if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
			auto *byName = reinterpret_cast<IMAGE_IMPORT_BY_NAME *>(base + names->u1.AddressOfData);
			if (std::strcmp(reinterpret_cast<char *>(byName->Name), function) != 0) continue;
			DWORD old;
			VirtualProtect(&thunk->u1.Function, sizeof(ULONG_PTR), PAGE_READWRITE, &old);
			void *orig = reinterpret_cast<void *>(thunk->u1.Function);
			thunk->u1.Function = reinterpret_cast<ULONG_PTR>(replacement);
			VirtualProtect(&thunk->u1.Function, sizeof(ULONG_PTR), old, &old);
			return orig;
		}
	}
	return nullptr;
}

bool repairQmlDaylightSaving()
{
	g_realGetProcAddress = reinterpret_cast<decltype(g_realGetProcAddress)>(
		patchQmlImport("KERNEL32.dll", "GetProcAddress", reinterpret_cast<void *>(&qmlGetProcAddress)));
	return g_realGetProcAddress != nullptr;
}
#endif

// A Python helper in tools/ that runs next to the GUI, as a daemon runs next to qt-gui on the Toon:
// tsc.py (the TSC helper script /usr/bin/tsc) and netbridge.py (https). Like inittab's "respawn"
// it is started again when it stops; it stops itself when toonsim is gone (--parent). Its output
// goes to the log, prefixed with its name.
class Helper : public QObject
{
public:
	Helper(const QString &name, const QStringList &args, QObject *parent)
		: QObject(parent), m_name(name), m_args(args)
	{
		// the Python in the Windows release package (python\ next to bin\) first, else the one on the PATH
		// (python3 on Linux, where it comes with the system)
		const QString bundled = QDir(QCoreApplication::applicationDirPath() + "/../python").absoluteFilePath("python.exe");
		if (QFileInfo::exists(bundled)) m_python = bundled;
		if (m_python.isEmpty()) m_python = QStandardPaths::findExecutable("python3");
		if (m_python.isEmpty()) m_python = QStandardPaths::findExecutable("python");
		if (m_python.isEmpty()) m_python = QStandardPaths::findExecutable("py");
		if (m_python.isEmpty()) {
			qWarning("toonsim: no python on the PATH, so no %s (see README)", qPrintable(name));
			return;
		}
		m_args << "--parent" << QString::number(QCoreApplication::applicationPid());
		connect(&m_proc, &QProcess::readyReadStandardOutput, this, [this]() {
			while (m_proc.canReadLine())
				qInfo().noquote() << m_name + ":" << QString::fromUtf8(m_proc.readLine()).trimmed();
		});
		connect(&m_proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, [this](int code) {
			if (m_stopping) return;
			qWarning("toonsim: %s stopped (exit %d), starting it again in 5 s", qPrintable(m_name), code);
			QTimer::singleShot(5000, this, [this]() { start(); });
		});
		connect(qApp, &QCoreApplication::aboutToQuit, this, [this]() {
			m_stopping = true;
			m_proc.kill();
			m_proc.waitForFinished(2000);
		});
		m_proc.setProcessChannelMode(QProcess::MergedChannels);
		start();
	}
private:
	void start()
	{
		QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
		env.insert("PYTHONUNBUFFERED", "1");
		env.insert("PYTHONIOENCODING", "utf-8");
		m_proc.setProcessEnvironment(env);
		m_proc.start(m_python, m_args);
	}
	QProcess m_proc;
	QString m_name, m_python;
	QStringList m_args;
	bool m_stopping = false;
};

int freePort()
{
	QTcpServer s;
	return s.listen(QHostAddress::LocalHost, 0) ? s.serverPort() : 0;
}

// the opkg control file with the firmware version that apps read (ToonStore shows it and checks app
// compatibility with it): a Toon 2 has base-nxt-uni in /var/lib/opkg, a Toon 1 base-qb2-ene in /usr/lib/opkg
void writeFirmwareVersion(const QString &home, const QString &data, bool nxt)
{
	// the version of the Toon the firmware was pulled from (tools/pull_firmware.bat writes it)
	QString version = "6.3.30";
	QFile vf(home + "/firmware/firmware-version.txt");
	if (vf.open(QIODevice::ReadOnly)) {
		const QString v = QString::fromUtf8(vf.readAll()).trimmed().section('-', 0, 0);
		if (!v.isEmpty()) version = v;
	}
	const QString nxtFile = data + "/var/lib/opkg/info/base-nxt-uni.control";
	const QString qb2File = data + "/usr/lib/opkg/info/base-qb2-ene.control";
	const QString file = nxt ? nxtFile : qb2File;
	QFile::remove(nxt ? qb2File : nxtFile);
	QDir().mkpath(QFileInfo(file).absolutePath());
	QFile f(file);
	if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) return;
	f.write(QString("Architecture: %1\nPackage: %2\nVersion: %3-0\n")
	        .arg(nxt ? "nxt" : "qb2", nxt ? "base-nxt-uni" : "base-qb2-ene", version).toUtf8());
}

// calls screenStateController.wakeup() on every press
//
// As qt-gui: a touch on a dimmed (or dark) screen only wakes it up - press, moves and release go
// nowhere - unless it lands on a control that works while dimmed (mouseIsActiveInDimState, e.g. the
// thermostat buttons of the dim panel). Otherwise the release would tap what is there once the screen
// is awake: tapping the dim button's spot to wake up dimmed the screen again.
class WakeupFilter : public QObject
{
public:
	WakeupFilter(QObject *controller, QObject *parent) : QObject(parent), m_ctl(controller) {}
protected:
	bool eventFilter(QObject *obj, QEvent *ev) override
	{
		QQuickWindow *win = qobject_cast<QQuickWindow *>(obj);
		if (!win) return false;
		const QEvent::Type t = ev->type();
		if (t == QEvent::MouseButtonPress) {
			const bool active = m_ctl->property("screenState").toInt() == 1;       // ScreenActive
			bool dimControl = false;
			if (!active) {
				const QPointF pos = static_cast<QMouseEvent *>(ev)->windowPos();
				for (QQuickItem *it = mouseItemAt(win->contentItem(), pos); it; it = it->parentItem())
					if (it->property("mouseIsActiveInDimState").toBool()) { dimControl = true; break; }
			}
			QMetaObject::invokeMethod(m_ctl, "wakeup");
			m_swallow = !active && !dimControl;
			return m_swallow;
		}
		if (m_swallow && (t == QEvent::MouseMove || t == QEvent::MouseButtonRelease || t == QEvent::MouseButtonDblClick)) {
			if (t == QEvent::MouseButtonRelease) m_swallow = false;
			return true;
		}
		return false;
	}
private:
	// the top-most visible, enabled item that takes the mouse at a scene position
	static QQuickItem *mouseItemAt(QQuickItem *item, const QPointF &scenePos)
	{
		if (!item->isVisible() || !item->isEnabled() || item->opacity() <= 0.0) return nullptr;
		QList<QQuickItem *> kids = item->childItems();
		QList<QQuickItem *> order;
		for (int i = kids.size() - 1; i >= 0; --i) order << kids[i];
		std::stable_sort(order.begin(), order.end(), [](QQuickItem *a, QQuickItem *b) { return a->z() > b->z(); });
		for (QQuickItem *k : order)
			if (QQuickItem *hit = mouseItemAt(k, scenePos)) return hit;
		if (item->acceptedMouseButtons() == Qt::NoButton) return nullptr;
		const QPointF p = item->mapFromScene(scenePos);
		return (p.x() >= 0 && p.y() >= 0 && p.x() < item->width() && p.y() < item->height()) ? item : nullptr;
	}
	QObject *m_ctl;
	bool m_swallow = false;
};
}

int main(int argc, char *argv[])
{
	// Toon apps read and write their settings with XMLHttpRequest on file: URLs, which Qt 5.11 allowed
	// and Qt 5.15 only allows when asked to
	qputenv("QML_XHR_ALLOW_FILE_READ", "1");
	qputenv("QML_XHR_ALLOW_FILE_WRITE", "1");
	// the Toon's on-screen keyboard (Canvas.qml's InputPanel) is Qt's virtual keyboard
	qputenv("QT_IM_MODULE", "qtvirtualkeyboard");
	// Qt 5.15 remarks on the firmware's old-style Connections handlers (fine under Qt 5.11): not our problem
	qputenv("QT_LOGGING_RULES", "qt.qml.connections=false");
	QGuiApplication app(argc, argv);
	QGuiApplication::setApplicationName("toonsim");

	QCommandLineParser cli;
	cli.setApplicationDescription("Toon simulator: the Toon GUI from the device's resource files, on a PC");
	cli.addHelpOption();
	QCommandLineOption sizeOpt("size", "toon2 (1024x600, isNxt) or toon1 (800x480)", "size", "toon2");
	QCommandLineOption homeOpt("home", "simulator folder (firmware/, sim/, data/); default: next to the exe's parent", "dir");
	QCommandLineOption appsOpt("apps", "folder with custom apps (each app a subfolder, like /qmf/qml/apps)", "dir");
	QCommandLineOption portOpt("control-port", "TCP port for the remote control (0 = off)", "port", "5555");
	QCommandLineOption hiddenOpt("hidden", "do not show the window (automated tests; screenshots still work)");
	QCommandLineOption noTscOpt("no-tsc", "do not start tools/tsc.py (the TSC helper: ToonStore installs, command file)");
	QCommandLineOption dataOpt("data", "folder for the device's writable folders (/mnt/data, /tmp, ...); default: data/ in the simulator folder", "dir");
	QCommandLineOption restartedOpt("restarted", "(set by a GUI restart: wait for the previous toonsim to end)");
	restartedOpt.setFlags(QCommandLineOption::HiddenFromHelp);
	QCommandLineOption webPortOpt("web-port", "port of the Toon's local web server (http://127.0.0.1:<port>/mobile/ is Toon mobile; 0 = any)", "port", "8888");
	cli.addOptions({ sizeOpt, homeOpt, appsOpt, portOpt, hiddenOpt, noTscOpt, dataOpt, restartedOpt, webPortOpt });
	cli.process(app);

	const bool nxt = cli.value(sizeOpt) != "toon1";
	QString home = cli.value(homeOpt);
	if (home.isEmpty()) home = QDir(QCoreApplication::applicationDirPath() + "/..").canonicalPath();
	PathMap::instance().configure(home, cli.value(appsOpt), cli.value(dataOpt));
	const QString data = PathMap::instance().dataDir();

	// one simulator per data folder: two would overwrite each other's settings (tile layout, program)
	// and both tsc helpers would run the same commands. A restart waits for the previous one to end.
	QLockFile lock(data + "/toonsim.lock");
	lock.setStaleLockTime(0);
	if (!lock.tryLock(cli.isSet(restartedOpt) ? 15000 : 500)) {
		qint64 pid = 0; QString host, appName;
		lock.getLockInfo(&pid, &host, &appName);
		fprintf(stderr, "toonsim: %s is in use by another toonsim (pid %lld); start this one with --data <other folder>\n",
		        qPrintable(QDir::toNativeSeparators(data)), pid);
		return 4;
	}

	Control::installLogHandler(data + "/toonsim.log");      // also what the "log" command returns
#ifdef Q_OS_WIN
	if (!repairQmlDaylightSaving())
		qWarning("toonsim: could not repair the JavaScript Date's daylight saving (Qt5Qml.dll): local times may be an hour off in summer");
#endif
	writeFirmwareVersion(home, data, nxt);

	// the compatibility patches first (tools/build_compat.py; the first registered file wins for a
	// path), then the device's resource files: qrc:/Canvas.qml, qrc:/qb/..., qrc:/apps/..., drawables
	if (QFileInfo::exists(home + "/firmware/compat.rcc")) QResource::registerResource(home + "/firmware/compat.rcc");
	for (const QString &rcc : { QString("resources-static-base.rcc"), QString("drawables-base.rcc") }) {
		const QString path = home + "/firmware/" + rcc;
		if (!QResource::registerResource(path))
			qCritical() << "toonsim: cannot register" << path << "- run tools/pull_firmware.bat first";
	}

	QQmlApplicationEngine engine;
	PathMap::instance().install(&engine);
	// no OpenSSL for this Qt: https goes through tools/netbridge.py
	if (!QSslSocket::supportsSsl()) {
		const int bridgePort = freePort();
		PathMap::instance().setHttpsBridgePort(bridgePort);
		new Helper("netbridge", { home + "/tools/netbridge.py", "--port", QString::number(bridgePort) }, &app);
	}
	engine.addImportPath("qrc:/");                         // the device's own modules: qrc:/qb/..., qrc:/themes, qrc:/apps/...
	engine.addImportPath(home + "/sim/imports");           // stand-ins for qt-gui's C++ QML modules
	qmlRegisterType<FileIO>("FileIO", 1, 0, "FileIO");

	// qt-gui's context properties, defined in QML so they stay editable without a rebuild: every
	// property of sim/SimContext.qml becomes a context property of the same name
	engine.rootContext()->setContextProperty("isNxt", nxt);
	// the Toon's QML is laid out for the Toon 1 (800x480) and scales by these on the Toon 2
	const qreal hScale = nxt ? 1024.0 / 800.0 : 1.0, vScale = nxt ? 600.0 / 480.0 : 1.0;
	engine.rootContext()->setContextProperty("horizontalScaling", hScale);
	engine.rootContext()->setContextProperty("verticalScaling", vScale);
	engine.addImageProvider("scaled", new ToonImageProvider(false, hScale));
	engine.addImageProvider("colorized", new ToonImageProvider(true, hScale));
	QQmlComponent ctxComp(&engine, QUrl::fromLocalFile(home + "/sim/SimContext.qml"));
	QObject *ctx = ctxComp.create(engine.rootContext());
	if (!ctx) {
		qCritical().noquote() << "toonsim: sim/SimContext.qml failed:" << ctxComp.errorString();
		return 2;
	}
	const QMetaObject *mo = ctx->metaObject();
	for (int i = QObject::staticMetaObject.propertyCount(); i < mo->propertyCount(); ++i) {
		const QMetaProperty p = mo->property(i);
		engine.rootContext()->setContextProperty(QString::fromLatin1(p.name()), p.read(ctx));
	}
	engine.rootContext()->setContextProperty("toonsim", ctx);
	// the Toon's http://localhost (lighttpd): the simulated daemons and /HCBv2/www
	int webPort = 0;
	if (QObject *devices = qvariant_cast<QObject *>(ctx->property("simDevices"))) {
		webPort = (new LocalWeb(devices, &app))->listen(cli.value(webPortOpt).toInt());
		PathMap::instance().setHttpPort(webPort);
	}
	engine.rootContext()->setContextProperty("toonsimWebPort", webPort);     // for tests: eval toonsimWebPort
	if (QObject *impl = qvariant_cast<QObject *>(ctx->property("qdialogImpl")))
		engine.rootContext()->setContextProperty("qdialog", new DialogFacade(impl, ctx));
	// translations (lang_<locale>.qm) as qt-gui loads them; replaces the plain qlanguage of SimContext.qml
	engine.rootContext()->setContextProperty("qlanguage", new Language(&engine, ctx));

	// every touch wakes the screen and restarts the dim timer, as qt-gui's C++ controller does
	if (QObject *ssc = qvariant_cast<QObject *>(ctx->property("screenStateController")))
		app.installEventFilter(new WakeupFilter(ssc, &app));

	Control control(&engine, ctx);
	engine.rootContext()->setContextProperty("toonsimControl", &control);
	// the Toon's watchdog: qt-gui that quits (TSC's "Restart GUI" button is Qt.quit()) is started again.
	// Closing the window or the control port's "quit" still end the simulator.
	QObject::disconnect(&engine, &QQmlEngine::quit, nullptr, nullptr);
	QObject::disconnect(&engine, &QQmlEngine::exit, nullptr, nullptr);
	QObject::connect(&engine, &QQmlEngine::quit, &control, &Control::restart);
	QObject::connect(&engine, &QQmlEngine::exit, &control, [&control](int) { control.restart(); });
	const int port = cli.value(portOpt).toInt();
	if (port > 0) control.listen(port);
	if (!cli.isSet(noTscOpt))
		new Helper("tsc", { home + "/tools/tsc.py", "--home", home, "--apps", PathMap::instance().appsDir(),
		                    "--data", data, "--port", QString::number(port), "--http-port", QString::number(webPort) }, &app);

	engine.load(QUrl("qrc:/Canvas.qml"));
	if (engine.rootObjects().isEmpty()) return 3;
	if (QQuickWindow *w = qobject_cast<QQuickWindow *>(engine.rootObjects().first())) {
		w->setTitle(nxt ? "Toon 2 (1024x600)" : "Toon 1 (800x480)");
		w->resize(nxt ? QSize(1024, 600) : QSize(800, 480));
		control.setWindow(w);
		// hidden: shown fully transparent, ignoring the mouse and without a taskbar entry. A window that is
		// not shown, or shown off-screen, is never rendered and grabWindow() (the "shot" command) comes back
		// empty; the control port's taps go to the scene directly, so they still work.
		if (cli.isSet(hiddenOpt)) {
			w->setFlags(w->flags() | Qt::Tool | Qt::FramelessWindowHint | Qt::WindowTransparentForInput
			            | Qt::WindowDoesNotAcceptFocus | Qt::WindowStaysOnBottomHint);
			w->setOpacity(0.0);
		}
		w->show();
	}
	return app.exec();
}
