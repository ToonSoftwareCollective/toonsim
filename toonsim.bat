@echo off
rem Starts the Toon simulator. All options are passed on, see "toonsim.bat --help":
rem   --size toon2|toon1     Toon 2 (1024x600, isNxt) or Toon 1 (800x480); default: your Toon's model
rem   --apps DIR             custom apps folder, like /qmf/qml/apps (default: toonsim\apps)
rem   --data DIR             settings and data folder (default: toonsim\data); one simulator per folder
rem   --web-port N           the Toon's local web server, Toon mobile at http://127.0.0.1:N/mobile/ (8888)
rem   --control-port N       remote control port (default 5555, 0 = off)
rem   --hidden               no window (automated tests)
rem The first start copies the Toon's GUI (and optionally its apps and their settings) from your Toon.
setlocal
set PY=%~dp0python\python.exe
if not exist "%PY%" set PY=python
if "%~1"=="--check-update" (
	"%PY%" "%~dp0tools\updater.py" --check
	exit /b %ERRORLEVEL%
)
if "%~1"=="--update" (
	"%PY%" "%~dp0tools\updater.py" --update
	exit /b %ERRORLEVEL%
)
if not exist "%~dp0firmware\resources-static-base.rcc" (
	"%PY%" "%~dp0tools\pull_firmware.py" --setup
	if errorlevel 1 (
		echo.
		echo The Toon firmware could not be copied. Try again by starting toonsim.bat again, or see docs\MANUAL.md.
		pause
		exit /b 1
	)
)
rem Starts as the model the firmware came from; a --size you give wins, being later on the command line.
set MODEL=toon2
if exist "%~dp0firmware\toon-model.txt" set /p MODEL=<"%~dp0firmware\toon-model.txt"
rem The release package has Qt next to toonsim.exe; a development build uses the Qt it was built with.
if not exist "%~dp0bin\Qt5Core.dll" (
	set QT_PLUGIN_PATH=%USERPROFILE%\Qt\5.15.2\mingw81_64\plugins
	set QML2_IMPORT_PATH=%USERPROFILE%\Qt\5.15.2\mingw81_64\qml
	set "PATH=%USERPROFILE%\Qt\5.15.2\mingw81_64\bin;%USERPROFILE%\Qt\Tools\mingw810_64\bin;%PATH%"
)
"%~dp0bin\toonsim.exe" --size %MODEL% %*
