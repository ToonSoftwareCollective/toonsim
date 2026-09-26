#pragma once
// The context property "qlanguage": loads the Toon's translations (lang_<locale>.qm) the way qt-gui
// does. loadLanguagePackage("qb/lang") reads firmware/qb/lang, "apps/<app>/lang" reads
// firmware/apps/<app>/lang (built-in apps, from tools/pull_firmware.bat) or the custom app's own
// lang folder. The texts on screen follow at once (QQmlEngine::retranslate).

#include <QObject>
#include <QTranslator>
#include <QCoreApplication>
#include <QQmlEngine>
#include <QFileInfo>
#include <QDebug>
#include "pathmap.h"

class Language : public QObject
{
	Q_OBJECT
	Q_PROPERTY(QString locale READ locale NOTIFY localeChanged)
public:
	Language(QQmlEngine *engine, QObject *parent) : QObject(parent), m_engine(engine) {}
	QString locale() const { return m_locale; }

	Q_INVOKABLE void setLocale(const QString &locale)
	{
		if (locale == m_locale) return;
		m_locale = locale;
		// a new language replaces all loaded packages
		for (QTranslator *t : m_translators) { QCoreApplication::removeTranslator(t); t->deleteLater(); }
		m_translators.clear();
		for (const QString &p : m_packages) load(p);
		emit localeChanged();
		m_engine->retranslate();
	}

	Q_INVOKABLE void loadLanguagePackage(const QString &path)
	{
		if (!m_packages.contains(path)) m_packages << path;
		if (load(path)) m_engine->retranslate();
	}

signals:
	void localeChanged();

private:
	bool load(const QString &path)
	{
		if (m_locale.isEmpty()) return false;
		const PathMap &map = PathMap::instance();
		const QString file = "lang_" + m_locale + ".qm";
		QStringList dirs { map.home() + "/firmware/" + path };
		if (path.startsWith("apps/")) dirs << map.appsDir() + "/" + path.mid(5);     // a custom app's own lang folder
		for (const QString &d : dirs) {
			if (!QFileInfo::exists(d + "/" + file)) continue;
			QTranslator *t = new QTranslator(this);
			if (t->load(file, d)) {
				QCoreApplication::installTranslator(t);
				m_translators << t;
				return true;
			}
			delete t;
		}
		return false;
	}

	QQmlEngine *m_engine;
	QString m_locale;
	QStringList m_packages;
	QList<QTranslator *> m_translators;
};
