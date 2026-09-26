#!/bin/sh
# Starts the Toon simulator on Linux (toonsim.bat on Windows). All options are passed on, see "./toonsim.sh --help":
#   --size toon2|toon1     Toon 2 (1024x600, isNxt) or Toon 1 (800x480); default: your Toon's model
#   --apps DIR             custom apps folder, like /qmf/qml/apps (default: toonsim/apps)
#   --data DIR             settings and data folder (default: toonsim/data); one simulator per folder
#   --web-port N           the Toon's local web server, Toon mobile at http://127.0.0.1:N/mobile/ (8888)
#   --control-port N       remote control port (default 5555, 0 = off)
#   --hidden               no window (automated tests)
# The first start installs what it needs from the distribution (Debian/Ubuntu: Qt 5.15 and its QML
# modules, tools/linux-packages.txt - apt, after asking), then copies the Toon's GUI (and optionally its
# apps and their settings) from your Toon.
HOME_DIR="$(cd "$(dirname "$0")" && pwd)"

if command -v dpkg-query >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
	MISSING=""
	for p in $(grep -v '^#' "$HOME_DIR/tools/linux-packages.txt"); do
		dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || MISSING="$MISSING $p"
	done
	if [ -n "$MISSING" ]; then
		echo "toonsim runs with the system's Qt 5.15. These packages are not installed yet:"
		echo " $MISSING"
		printf "Install them now with apt (sudo asks for your password)? [Y/n] "
		read -r ANSWER
		case "$ANSWER" in
			[nN]*) echo "Not installed: install them yourself and start toonsim.sh again (docs/MANUAL.md, section 11)."; exit 1 ;;
		esac
		SUDO=sudo
		[ "$(id -u)" = 0 ] && SUDO=
		if ! { $SUDO apt-get update && $SUDO apt-get install -y $MISSING; }; then
			echo "apt could not install them: see docs/MANUAL.md, section 11."
			exit 1
		fi
	fi
elif ldd "$HOME_DIR/bin/toonsim" 2>/dev/null | grep -q "not found"; then
	# another distribution: say what is missing
	echo "toonsim needs Qt 5.15 with its QML modules (see tools/linux-packages.txt and docs/MANUAL.md, section 11). Missing:"
	ldd "$HOME_DIR/bin/toonsim" | grep "not found"
	exit 1
fi

if [ ! -f "$HOME_DIR/firmware/resources-static-base.rcc" ]; then
	if ! python3 "$HOME_DIR/tools/pull_firmware.py" --setup; then
		echo
		echo "The Toon firmware could not be copied. Try again by starting toonsim.sh again, or see docs/MANUAL.md."
		exit 1
	fi
fi
# starts as the model the firmware came from; a --size you give wins, being later on the command line
MODEL=toon2
[ -f "$HOME_DIR/firmware/toon-model.txt" ] && MODEL="$(tr -d '\r\n' < "$HOME_DIR/firmware/toon-model.txt")"
exec "$HOME_DIR/bin/toonsim" --size "$MODEL" "$@"
