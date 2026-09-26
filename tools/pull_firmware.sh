#!/bin/sh
# Copies the Toon GUI's resources from your (rooted) Toon into ../firmware - see pull_firmware.py.
#   pull_firmware.sh <toon-ip> [user] [password] [--apps] [--settings]    (default user: root)
#   pull_firmware.sh --setup                            asks for them (toonsim.sh's first start)
exec python3 "$(dirname "$0")/pull_firmware.py" "$@"
