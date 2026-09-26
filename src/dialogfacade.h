#pragma once
// The context property "qdialog". QML cannot declare properties that start with a capital, and the
// Toon's QML reads qdialog.SizeSmall/SizeMedium/SizeLarge - so this thin C++ object carries those
// constants and forwards everything else to the QML implementation (qdialogImpl in SimContext.qml).

#include <QObject>
#include <QVariant>
#include <QJSValue>
#include <QQmlEngine>
#include <QQmlContext>
#include <QQmlComponent>
#include <QQuickItem>
#include <QDebug>

class DialogFacade : public QObject
{
	Q_OBJECT
	Q_PROPERTY(int SizeSmall READ sizeSmall CONSTANT)
	Q_PROPERTY(int SizeMedium READ sizeMedium CONSTANT)
	Q_PROPERTY(int SizeLarge READ sizeLarge CONSTANT)
	Q_PROPERTY(QObject *context READ context NOTIFY contextChanged)
public:
	DialogFacade(QObject *impl, QObject *parent) : QObject(parent), m_impl(impl)
	{
		connect(impl, SIGNAL(contextChanged()), this, SIGNAL(contextChanged()));
	}
	int sizeSmall() const { return 0; }
	int sizeMedium() const { return 1; }
	int sizeLarge() const { return 2; }
	QObject *context() const { return qvariant_cast<QObject *>(m_impl->property("context")); }

	// Home.qml creates the dialog itself (DialogPopup { id: dialogContainer }) and hands it over here:
	// that instance is the one showDialog() fills and shows
	Q_INVOKABLE void init(QObject *dialogPopup)
	{
		if (!dialogPopup) { qWarning("toonsim qdialog: init without a DialogPopup"); return; }
		QMetaObject::invokeMethod(m_impl, "attach", Q_ARG(QVariant, QVariant::fromValue(dialogPopup)));
	}
	Q_INVOKABLE void reset() { call("reset", {}); }
	Q_INVOKABLE void buttonHeaderRightClicked() { call("buttonHeaderRightClicked", {}); }
	Q_INVOKABLE void setClosePopupCallback(const QVariant &cb) { call("setClosePopupCallback", { cb }); }
	Q_INVOKABLE void showDialog(const QVariant &size, const QVariant &title = QVariant(), const QVariant &content = QVariant(),
	                            const QVariant &b1 = QVariant(), const QVariant &cb1 = QVariant(),
	                            const QVariant &b2 = QVariant(), const QVariant &cb2 = QVariant())
	{
		call("showDialog", { size, title, content, b1, cb1, b2, cb2 });
	}

signals:
	void contextChanged();

private:
	void call(const char *method, const QVariantList &args)
	{
		QVariant a[7];
		for (int i = 0; i < args.size() && i < 7; ++i) a[i] = args[i];
		switch (args.size()) {
		case 0: QMetaObject::invokeMethod(m_impl, method); break;
		case 1: QMetaObject::invokeMethod(m_impl, method, Q_ARG(QVariant, a[0])); break;
		default:
			QMetaObject::invokeMethod(m_impl, method, Q_ARG(QVariant, a[0]), Q_ARG(QVariant, a[1]), Q_ARG(QVariant, a[2]),
			                          Q_ARG(QVariant, a[3]), Q_ARG(QVariant, a[4]), Q_ARG(QVariant, a[5]), Q_ARG(QVariant, a[6]));
		}
	}
	QObject *m_impl;
};
