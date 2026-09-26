# toonsim - the Toon on your PC

toonsim runs the real Toon GUI - the firmware's own screens, taken from your Toon - in a window on
Windows (or Linux, section 11), with the Toon's background services simulated: thermostat and boiler, energy meters, the
TSC helper script, ToonStore, the local web server and Toon mobile. Your own apps run in it exactly
as on a rooted Toon, so you can develop and test them without copying every change to a device.

This manual is for developers of Toon apps. You need a rooted Toon (Toon 1 or Toon 2) that you can
log in to with SSH: the simulator does not come with the Toon's firmware, you copy it from your own
Toon once.

## 1. What you need

- Windows 10 or 11, 64-bit.
- A rooted Toon on your network, with SSH access (usually user `root`, password `toon`).
- Internet access, for ToonStore, the Toon mobile site and apps that fetch data.
- An SSH client, to copy from the Toon: the `ssh` that comes with Windows 10/11 is enough.
  [PuTTY](https://www.putty.org/), if installed, is used instead.
Nothing else: Qt, Python and a Unix shell for the apps' own scripts are in the package.

## 2. Installing

1. Unzip `toonsim-<version>-win64.zip` into a folder of your choice, preferably a short path
   without spaces, e.g. `C:\toonsim`.
   If Windows marks the zip as coming from the internet, first right-click it > Properties >
   tick "Unblock" > OK, then unzip.
2. Double-click `toonsim.bat`. The first time, it asks three things:

   ```
   IP address of your Toon: 192.168.1.50
   Login [root]:
   Password [toon]:
   Also copy the apps installed on your Toon, with their settings? (Y/n) [Y]:
   ```

   Press Enter to accept a value in brackets. It copies the Toon's screens (the "firmware"), and if
   you say yes, also your apps into `apps\` and their settings into `data\mnt\data\tsc\`. Then the
   simulator starts. Your Toon is only read, never changed.

That's all. The simulator starts as the model your Toon is (Toon 1 or Toon 2). At its first start
it installs **ToonStore** (unless it came along with your apps) and restarts the GUI once, just like
a freshly rooted Toon. It also installs the **Toon mobile** web site.

After that, `toonsim.bat` just starts the simulator. From a command prompt you can give options:

```
toonsim.bat --size toon1      the Toon 1 screen (800x480), whatever your Toon is
toonsim.bat --size toon2      the Toon 2 screen (1024x600)
```

To copy from the Toon again, or without the questions, use the copy tool directly:

```
tools\pull_firmware.bat 192.168.1.50 root toon --apps --settings
```

`--apps` and `--settings` are optional. What is already on the PC (an app folder, a settings file)
is never overwritten.

## 3. Using the simulator

- **The mouse is your finger.** Click is tap; drag for swiping. The on-screen keyboard appears when a
  field needs text, as on the Toon.
- **Everything behaves like the Toon**: the dim button (top right) and the dim state after a minute,
  the thermostat with its program and presets, the menu, Instellingen, the TSC tab (Restart GUI
  restarts the GUI, a reboot request too), notifications, ToonStore.
- **Toon mobile** is at `http://127.0.0.1:8888/mobile/` in your browser while the simulator runs.
- **Your settings stay**: tile layout, program, presets, app settings, installed apps. They are in
  `data\` (the Toon's `/mnt/data`, `/tmp`, ...). Delete `data\` to start again from scratch.
- **Logs**: `data\toonsim.log` (the GUI: `console.log` of the apps, QML errors) and
  `data\var\log\tsc` (the TSC helper: installs, commands, app scripts).

The simulated house: the room heats while the boiler burns and cools slowly otherwise; the boiler's
flow and return temperatures, setpoint and pressure follow; electricity and gas use follow a typical
Dutch household (about 3000 kWh and 1200 m3 a year, peaks in the morning and evening, more gas in
winter), with a meter history for the graphs, the usage tiles and "Status verbruik". There is no
water meter, smart plugs, smoke detectors or Hue lights.

**Solar panels**: switch them on in Instellingen > TSC > Toon subscription features > "Zon Op Toon"
(the GUI restarts). Then the house has 4000 Wp of panels, some 3600 kWh a year that follow the sun
and the weather: the solar tiles, the graphs' production, the "Zonnepanelen" app and hcb_rrd's solar
loggers all have values.

## 4. Your apps

The `apps\` folder is the Toon's `/qmf/qml/apps`: every app in its own folder, with its
`<Name>App.qml` (e.g. `apps\myapp\MyappApp.qml`). The simulator loads them at the start, like the Toon.

- **Installing from ToonStore** works as on the Toon: select the apps, "Toon Bijwerken"; they are
  downloaded from GitHub and the GUI restarts.
- **Your own app under development**: instead of copying it into `apps\`, link your working folder, so
  every change is in the simulator at its next start (or after TSC > Restart GUI):

  ```
  mklink /J C:\toonsim\apps\myapp C:\projects\myapp
  ```

  Removing such an app with ToonStore only removes the link, never your folder.
- **App settings** that apps save in `/mnt/data/tsc/...` are in `data\mnt\data\tsc\`.
- An app that adds a tile: add it with "Voeg tegel toe" on the home screen, as on the Toon.

Apps can use everything the Toon offers: the Toon's own QML components, `FileIO`, XMLHttpRequest to the
internet and to the Toon's own web server (`http://localhost/...`: thermostat, hcb_rrd loggers,
config, ...), the TSC command file (`/tmp/tsc.command`), notifications.

## 5. Automated tests

The package contains a test runner and example tests (`tests\`):

```
python\python.exe tools\run_tests.py                  all tests, Toon 2 screen
python\python.exe tools\run_tests.py --size toon1     on the Toon 1 screen
python\python.exe tools\run_tests.py myapp            only tests with "myapp" in the name
python\python.exe tools\run_tests.py --show           watch it happen
```

A test is a Python function `test_...(t)` in `tests\test_*.py`; `t` controls the simulator - tap
texts, read what is on the screen, take screenshots, change the simulated devices:

```python
def test_my_tile(t):
    t.wait_for_text("Mijn tegel")
    t.tap_text("Mijn tegel")
    t.wait_for_text("Instellingen")
    t.set_device("happ_thermstat", currentTemp=1650)       # the room at 16.5 degrees
    t.wait_for_text("16,5")                                # your tile shows it
    t.shot("mytile.png")
```

Each test file gets a fresh simulator with its own empty data folder (`data-test\`), so tests do not
touch your settings and your own simulator can keep running. A failing test leaves a screenshot and
its log in `tests\out\`. More in `README.md`, section "Remote control and tests".

## 6. Several simulators, ports

One data folder takes one simulator. For a second one (e.g. a Toon 1 next to a Toon 2) give it its
own data folder and ports:

```
toonsim.bat --size toon1 --data C:\toonsim\data-toon1 --control-port 5556 --web-port 8889
```

Ports: 5555 remote control (`--control-port`, 0 = off), 8888 the Toon's web server and Toon mobile
(`--web-port`, 0 = any free port). If the web port is taken the simulator picks a free one and writes
it in `data\toonsim.log`; the control port it keeps trying for 10 seconds, then goes on without it.

## 7. Apps with their own shell scripts

Some apps (e.g. PostNL) have a shell script that the TSC helper runs on the Toon. The simulator runs
these scripts unchanged, in the BusyBox that comes with the package (`tools\busybox\`, the Windows
build of the same BusyBox the Toon runs), with the Toon's paths pointing to the simulator's folders.
Their output is in `data\var\log\tsc`.

- The usual tools are there: `sh`, `sed`, `awk`, `grep`, `tr`, `date`, `wget`, `hexdump`, ... and
  `curl` (the one in Windows). `http://localhost/...` in a script reaches the simulator.
- Toon commands have stand-ins: `bxt` notifications appear in the GUI, `killall qt-gui` and
  `reboot` restart the simulator's GUI, `opkg` does nothing, and `openssl` covers hashes, base64 and
  random bytes (`dgst`, `base64`, `rand`).
- `shutdown`, `reboot`, `killall` and `pkill` in a script never touch your PC or its programs.
- Scripts that start a program built for the Toon itself, or that need the Toon's hardware, cannot
  run on a PC.

To use another shell (MSYS2's or Git for Windows' `sh.exe`), set the environment variable
`TOONSIM_SH` to its path before starting the simulator.

## 8. Updating the firmware

When your Toon gets new firmware, copy it again: `tools\pull_firmware.bat <address> root <password>`
(or delete the `firmware\` folder and start `toonsim.bat`, which then asks again). The files in
`firmware\` are replaced; your apps and `data\` stay.

## 9. Troubleshooting

| What you see | What to do |
|---|---|
| "That did not work" at the first start | Check the address (on the Toon: Instellingen > Internet), the login and the password, and that SSH works: `ssh root@<address>` in a command prompt. |
| "The Toon firmware could not be copied" | Read the message above it; start `toonsim.bat` again to retry. |
| "no matching host key type" / "Unable to negotiate" | Your Windows ssh refuses the Toon's old SSH server: install PuTTY and try again, it is then used instead. |
| "Host key verification failed" / "REMOTE HOST IDENTIFICATION HAS CHANGED" | The Toon got a new SSH key (e.g. after re-rooting): `ssh-keygen -R <address>` and try again. |
| The simulator shows the wrong model | `toonsim.bat --size toon1` or `--size toon2`; the default comes from `firmware\toon-model.txt`. |
| Windows SmartScreen or the virus scanner blocks `toonsim.exe` | The program is not signed. Unblock the zip before unzipping (section 2), or allow it in the scanner. |
| A second simulator does not start: "in use by another toonsim" | Give it its own `--data` folder (section 6). |
| ToonStore shows no apps / "Verbinding mislukt" | The PC needs internet access to GitHub (raw.githubusercontent.com, api.github.com). |
| An app does not show up | Is its folder name without a `-` and does it have `<Name>App.qml`? Look in `data\toonsim.log` for QML errors of the app. |
| Something else is wrong | `data\toonsim.log` and `data\var\log\tsc` usually say why. |

## 10. Removing

Delete the folder. The simulator writes nothing outside it (no registry, no installation).

## 11. Linux

There is a Linux build too: `toonsim-<version>-linux-x64.tar.gz`. It works as described above, with
the Linux names: `./toonsim.sh` instead of `toonsim.bat`, `tools/pull_firmware.sh`, and paths with
`/`. Unlike the Windows package it does not bring its own Qt: it uses your distribution's Qt 5.15.
Tested on Ubuntu 22.04 (also under WSL 2 on Windows 11, where the window appears on the Windows
desktop); Debian 12 and Ubuntu 24.04 have the same Qt 5.15 packages.

1. Unpack and start:

   ```
   tar xzf toonsim-<version>-linux-x64.tar.gz
   cd toonsim-<version>-linux-x64
   ./toonsim.sh
   ```

2. On Debian and Ubuntu the first start checks for the packages it needs (Qt 5.15 and its QML
   modules, Python 3, ssh - the list is `tools/linux-packages.txt`). If some are missing it names
   them and asks "Install them now with apt? [Y/n]"; Enter installs them (`sudo` asks for your
   password). Then it asks for your Toon, as on Windows (section 2).

   On another distribution install Qt 5.15 with those QML modules with its own package manager;
   `toonsim.sh` says which libraries it cannot find.

Differences from Windows:

- Apps' shell scripts run in the system's `/bin/sh`, with the same stand-ins for the Toon's commands
  (section 7); `shutdown`, `reboot` and `killall` never reach your computer.
- ToonStore links an installed app as `apps/<app> -> <app>-<version>`, a symlink as on the Toon.
- Copying from the Toon uses `ssh` (a password given at the first start is passed to it; otherwise
  it asks). `plink` is not used.
- Building it yourself: `sudo apt install qtbase5-dev qtdeclarative5-dev libqt5svg5-dev`, then
  `tools/build.sh` makes `bin/toonsim`; `python3 tools/run_tests.py` runs the tests.

---

toonsim is not affiliated with Eneco or Quby. The Toon firmware that it runs is Eneco's and stays on
your own PC; do not share the `firmware\` folder.
