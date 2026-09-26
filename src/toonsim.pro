QT += quick qml network gui svg
CONFIG += c++17 console
TARGET = toonsim
DESTDIR = $$PWD/../bin
SOURCES += main.cpp pathmap.cpp fileio.cpp control.cpp imageprovider.cpp localweb.cpp
HEADERS += pathmap.h fileio.h control.h imageprovider.h dialogfacade.h language.h localweb.h
