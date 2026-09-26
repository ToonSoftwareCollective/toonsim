#!/bin/sh
# ssh's SSH_ASKPASS for tools/pull_firmware.py on Linux: the password it was given (askpass.bat on Windows)
exec "$TOONSIM_ASKPY" -c 'import os; print(os.environ["TOONSIM_PW"])'
