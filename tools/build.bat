@echo off
rem Builds bin\toonsim.exe with the local Qt 5.15.2 (MinGW) from aqtinstall. Start it with ..\toonsim.bat,
rem which puts that Qt on PATH (no copy of the Qt DLLs next to the exe).
setlocal
set QTDIR=%USERPROFILE%\Qt\5.15.2\mingw81_64
set PATH=%QTDIR%\bin;%USERPROFILE%\Qt\Tools\mingw810_64\bin;%SystemRoot%\System32
cd /d "%~dp0..\src"
if not exist build mkdir build
cd build
qmake ..\toonsim.pro -spec win32-g++ CONFIG+=release || exit /b 1
mingw32-make -j8 || exit /b 1
echo built %~dp0..\bin\toonsim.exe
