#pragma once
// Stand-in for the TSC "FileIO 1.0" plugin on rooted Toons: a file or folder given by a device URL
// (file:///mnt/data/tsc/x.json, file:////qmf/qml/apps/), mapped to the PC by PathMap.

#include <QObject>
#include <QStringList>

class FileIO : public QObject
{
	Q_OBJECT
	Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
	Q_PROPERTY(QStringList dirEntries READ dirEntries NOTIFY sourceChanged)
public:
	explicit FileIO(QObject *parent = nullptr) : QObject(parent) {}

	QString source() const { return m_source; }
	void setSource(const QString &s);
	QStringList dirEntries() const;                             // subfolders of a folder source

	Q_INVOKABLE QString read();
	Q_INVOKABLE bool write(const QString &data);
	Q_INVOKABLE bool exists() const;
	Q_INVOKABLE QStringList entryList(const QStringList &nameFilters) const;   // files in a folder source

signals:
	void sourceChanged();
	void error(const QString &msg);

private:
	QString path() const;
	QString m_source;
};
