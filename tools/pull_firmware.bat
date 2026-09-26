@echo off
rem Copies the Toon GUI's resources from your (rooted) Toon into ..\firmware - see pull_firmware.py.
rem   pull_firmware.bat <toon-ip> [user] [password] [--apps] [--settings]    (default user: root)
rem   pull_firmware.bat --setup                            asks for them (toonsim.bat's first start)
setlocal
set PY=%~dp0..\python\python.exe
if not exist "%PY%" set PY=python
"%PY%" "%~dp0pull_firmware.py" %*
