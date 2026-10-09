# toonsim - the Toon GUI on a PC

`toonsim` runs the Toon's own GUI - the QML of `qt-gui`, straight from the device's resource files -
in a window on Windows or Linux, with the device's daemons simulated. Your own apps load next to the
built-in ones exactly as on a rooted Toon, so you can develop and test them without copying to a device.

**New here? Installing and first start: [docs/MANUAL.md](docs/MANUAL.md).** This README is the
reference for the details.

**Linux** (manual, section 11): the same sources, built with the system's Qt 5.15 (`tools/build.sh`),
started with `./toonsim.sh`; paths below with `/` instead of `\`. What differs inside:
- src/pathmap.cpp leaves real folders alone that look like device paths there - the simulator's own
  and Qt's (`/usr/lib/.../qt5/qml`); on Windows a device path can never be a real one.
- tsc.py runs apps' scripts in the system's `/bin/sh` (never busybox.exe: under WSL that would run as a
  Windows program with Windows' PATH), links ToonStore apps with a symlink (a junction on Windows), and
  makes the stand-ins in `tools/shims` executable; the stand-ins' own paths are shielded from the
  device-path rewriting (the simulator may live in `/tmp/...`).
- No netbridge (Qt there has OpenSSL), no daylight-saving repair (glibc is right), `python3` for the
  helpers; pull_firmware uses ssh with `tools/askpass.sh`.
- `python3 tools/make_release.py` on Linux builds `dist/toonsim-<version>-linux-x64.tar.gz`.

    toonsim.bat                     the model of your Toon (firmware\toon-model.txt; else Toon 2)
    toonsim.bat --size toon2        Toon 2 (1024x600)
    toonsim.bat --size toon1        Toon 1 (800x480, isNxt false)
    toonsim.bat --data D:\toon2b    a second simulator, with its own settings

To switch a running simulator between the Toon 1 and Toon 2 screen, use **Ctrl+1** / **Ctrl+2**,
or on Windows the window menu (the icon at the top left of the window, or Alt+Space), which shows
the current one with a check mark. It is a restart with the other `--size`, keeping the other
arguments and the settings in `data\`, just like the GUI restart after a ToonStore install.

To check for updates from GitHub (https://github.com/ToonSoftwareCollective/toonsim), use **Ctrl+U**,
select **Controleer op updates...** in the window menu, press **Check for updates** in the TSC Settings app,
or run `toonsim.bat --check-update` (`./toonsim.sh --check-update`). If an update is available, the simulator
offers to download and apply it automatically.

Without firmware (the first start) toonsim.bat runs `tools\pull_firmware.py --setup`: it asks for the
Toon's address, login and password, copies the firmware and optionally the apps and their settings,
then starts the simulator.

Settings, app data and logs go to `data\` (the Toon's `/mnt/data`, `/tmp`, `/var`, `/etc`, ...). One
data folder takes **one simulator at a time**: two would overwrite each other's settings (tile layout,
program) and both tsc helpers would run the same commands, so a second toonsim on the same folder
refuses to start - give it `--data <other folder>`.

As on the Toon, the GUI comes back when it quits: TSC's "Restart GUI" (`Qt.quit()`), a reboot request
and a ToonStore install restart it (the Toon's watchdog / `killall -9 qt-gui`). Closing the window
ends the simulator.

## Your apps

Put each app in its own folder under **`toonsim\apps\`**, as in `/qmf/qml/apps` on the Toon
(`apps\boardgames\BoardgamesApp.qml`, ...). The Toon's TSC loader finds every folder without a `-`
in its name that has a `<Name>App.qml`. Rather than copying, link your working folder, so an edit
shows up at the next start:

    mklink /J toonsim\apps\boardgames ..\boardgames

`--apps DIR` uses another folder instead. Add the tile with "Voeg tegel toe", as on the Toon.
App settings (`file:///mnt/data/tsc/...`) go to `toonsim\data\mnt\data\tsc\`.

## What is simulated

| Part | Where | Notes |
|---|---|---|
| The GUI itself | `firmware\*.rcc` | the device's own files, `tools\pull_firmware.bat <ip> [user] [password] [--apps] [--settings]` refreshes them (`--apps`: also the Toon's custom apps into `apps\`, `--settings`: their `/mnt/data/tsc/*.json`) |
| Translations | `firmware\qb\lang`, `firmware\apps\*\lang` | also pulled from the device; the GUI is Dutch |
| qt-gui's C++ QML modules | `sim\imports\` | BasicUIControls, BxtClient, ScreenStateController, ThermostatUtils, SimpleXmlListModel, ... as QML stand-ins |
| Context properties | `sim\SimContext.qml` | qtUtils, feature flags, wizard state, ... (`isNxt`, scaling, `qdialog`, `qlanguage` in C++) |
| The daemons | `sim\devices\*.js` | one file per daemon, see below |
| Device paths | `src\pathmap.cpp` | `/qmf/qml/apps` -> `apps\`, `/mnt/data`, `/tmp`, `/proc` -> `data\` |

The bxt bus (`sim\imports\BxtClient`) routes the GUI's requests to the simulated devices and sends
their datasets and notifications back. Devices with their own file:

- **hcb_config** - the configuration store: week program, temperature presets, tile layout, screen
  settings. Kept in `data\mnt\data\qmf\config\toonsim_hcb_config.xml` (delete it to start fresh).
  Starts with the program and presets of a real Toon.
- **happ_thermstat** - the thermostat: follows the program, takes setpoint/preset/program changes,
  and simulates the house (burner heats while below the setpoint, cools slowly otherwise).
- **happ_scsync** - product options (gas + electricity), wizard done, feature list.
- **hcb_netcon**, **UpstreamConnection** - online via wifi.
- **hdrv_p1** (meter adapter) - the usage history the graphs and tiles ask for (`rest.RestCall` on
  `/insights/home/...`), the smart meter info, day/night tariff.
- **happ_pwrusage** - live usage (power now, gas today, meter readings), tariffs and yearly estimates
  (`billingInfo`), the "Status verbruik" month figures.
- **happ_thermstat**'s boiler: flow and return temperature, boiler setpoint and pressure follow the
  burner and modulation (heating: the setpoint rises with the modulation, the flow follows it; idle:
  setpoint 6, both drift to just above the room), as the OpenTherm link reports them.
- **hcb_rrd** - the Toon's logger: every minute it logs room temperature, setpoint, boiler flow/return
  temperature, boiler setpoint, pressure, modulation and burner, and answers `getRrdData` in the
  Toon's format (`{ "24-09-2026 12:24:00": 24.50, ...}`; epoch keys without `readableTime`, `null`
  with `nullForNaN`; per hour/day for the longer rra's). Before the simulator started there are no
  samples, as on a Toon that just began logging.
- **happ_usermsg** - the notifications in the bar at the top. Scripts on the Toon send them with
  `/HCBv2/bin/bxt`; here `eval simDevices.createNotification("tsc", "notify", "text")`.

A dataset goes out only when it changed, as on the Toon (apps react to every update).

**Toon mobile** - the TSC mobile web site - is at **http://127.0.0.1:8888/mobile/** while the simulator
runs (`--web-port N` for another port; the log line "local web server ... Toon mobile: ..." shows the
address). tsc installs it from GitHub (ToonSoftwareCollective/mobile) into `data\HCBv2\www\mobile` at the
first start and updates it when there is a newer release, as on the Toon. What it shows and changes is
the simulator's: the thermostat and its presets, current power and gas, the day's use from the meter
readings, the Toon 2 sensors, the solar panels when they are on; no water meter or Z-Wave plugs.

**The Toon's local web server** (`http://localhost/...` and `http://127.0.0.1/...`, for apps and for
their scripts' curl) is simulated too (`src\localweb.cpp`): `/<daemon>?action=...` goes to the
simulated daemon - `happ_thermstat` (getThermostatInfo, getThermostatStates, setSetpoint,
roomSetpoint, changeSchemeState), `hcb_rrd` (getRrdData: the thermostat and boiler loggers, and the
meters elec_quantity_nt/lt and gas_quantity from the household model with full history),
`hcb_config` (getLocale, getObjectConfigTree), `happ_pwrusage` (GetCurrentUsage), `hdrv_zwave` (no
devices) and `/tsc/sensors` - and other paths are files under `/HCBv2/www`, plus TSC's link
`boilerstatus/boilervalues.txt`. A daemon answers a URL by adding it to its `http` table
in `sim\devices\<daemon>.js`; what is not simulated is logged as `toonsim web: no handler for ...`.

The energy figures come from one household model, `sim\devices\energy.js`: about 3000 kWh and
1200 m3 a year, base load with morning and evening peaks, gas heavier in winter. It is deterministic
(the same moment always gives the same value), so graphs look the same every time and tests can rely
on them.

**Solar panels** are there when TSC's *Toon subscription features > Zon Op Toon* is on (the
agreement's `SolarActivated`; the switch reboots), as on a Toon with a solar meter. The model: 4000 Wp
on a south roof at 52 N - the sun's height through the day and the year, a weather per day (clear to
overcast, sunnier in summer) and passing clouds - giving about 3600 kWh a year, peaks around 3.2 kW on
a clear June noon, nothing at night. From it:

- `happ_pwrusage`'s powerUsage: `valueSolar` (W now), `solarProducedToday` (+ savings), `avgDayProduValue`,
  and the smart meter: `meterReading`/`Low` from the grid, `meterReadingProdu`/`LowProdu` back to it
  (use minus solar per hour); `value` stays the house's use, so "Take and return" is the difference.
  `billingInfo`'s `elec_produ`: the expected yield a year (3600 kWh; Instellingen > Meters > Estimated
  generation changes it, `SetStandardYearTargets`), installed 1 January 2024, the electricity price.
- The insights (`electricity/production/...`, flow, quantity, price) for the graphs and the solar app;
  MonthDataDataset's solar targets (the expected yield spread over the months).
- `hcb_rrd`: `elec_solar_flow`, `elec_solar_quantity`, `elec_produ_flow`, `elec_quantity_nt_produ` /
  `_lt_produ` (without solar: unknown logger, as on a Toon without panels); `elec_flow` is the grid draw.
- `GetCurrentUsage`'s `powerProduction` (Toon mobile).

Bigger or smaller panels: `eval simDevices.set("happ_pwrusage", {solarWattPeak: 6000})` (the history
follows). Known simplification: the house uses little by day, so it keeps only about 15% of the yield
itself (real homes 25-30%).

**Features and a Toon without heating.** As on the Toon, happ_scsync's features come from
`/mnt/data/qmf/config/config_happ_scsync.xml` (`data\mnt\data\qmf\config\`; `/qmf/config` is the same
folder, the Toon's link), read at every start and written from the agreement when missing. With
`<feature>noHeating</feature>` in it the GUI runs as a Toon without heating: 6 tiles on the home screen
instead of the large thermostat - handy when there is no boiler to show. thermostatPlus's
"6 Tiles <=> 4 Tiles" switches it (then reboots); by hand: add or remove the line and restart.

**Apps' own web pages** (thermostatPlus's "Web Page"): `/qmf/www` is the web root as on the Toon
(the same folder as `/HCBv2/www`, `data\HCBv2\www`), so a page an app publishes there is at
`http://127.0.0.1:8888/<page>` - e.g. `http://127.0.0.1:8888/Thermostat+.html`. `/qmf/etc` is
`/HCBv2/etc` likewise (lighttpd.user: the mobile login of TSC's settings, which thermostatPlus's page
uses as its key - set it first), and `/etc/default/iptables.conf` starts as a TSC Toon's (apps add
their port; nothing enforces it). A WebSocket server an app opens (QtWebSockets) listens on the PC:
on `0.0.0.0` Windows' firewall asks once whether toonsim may use the network (for 127.0.0.1 it does
not matter). The Toon's IP address that such an app shows comes from `/proc/net/tcp`, which the
simulator does not have (it shows 0.0.0.0): use 127.0.0.1.

**Synchronous requests to localhost.** On the Toon lighttpd is a separate process; here the daemons
answer on the GUI thread. So the GUI's own XMLHttpRequests to `http://localhost/...` are answered on
the spot inside the simulator (`src\localweb.cpp`), never over the socket - a synchronous one would
otherwise wait for itself (thermostatPlus's setSetpoint hung the simulator). Browsers and scripts use
the socket as before.

Every other daemon the GUI looks for exists as an empty device: its datasets arrive empty and its
requests get an empty answer, logged as `toonsim bxt: default answer for ...`. That log is the
to-do list for making more of the GUI come alive: add the daemon's file in `sim\devices\` and list
it in `Devices.qml`.

Change device state while it runs, e.g. from the remote control:

    eval simDevices.set("happ_thermstat", { currentTemp: 1650 })
    eval simDevices.get("happ_thermstat")

## ToonStore and the TSC helper script

Put ToonStore in `apps\toonstore` like any other app. It lists the apps of the ToonSoftwareCollective
repository and installs and removes them the way it does on a Toon: it writes
`/tmp/packages_to_install.txt` / `_delete.txt` and the command `toonstore` into `/tmp/tsc.command`
(here `data\tmp\`), and the TSC helper script does the work.

On the Toon that script is `/usr/bin/tsc` (a copy is in `sim\tsc\tsc.device.sh`). Here it is
**`tools\tsc.py`**, which toonsim starts with the GUI and starts again if it stops, as the Toon's
inittab does (`--no-tsc` leaves it out). Every 5 seconds it runs the commands in the command file:

- `toonstore` - downloads the app's release from GitHub, installs it as `apps\<app>-<version>` with
  the junction `apps\<app>` pointing to it, removes what was selected for removal, and restarts the
  GUI (the Toon's `killall -9 qt-gui`; toonsim's `restart` command starts a fresh toonsim).
- `deletefile` - deletes the files in `/tmp/files_to_delete.txt` from `/mnt/data/tsc/appData`.
- `postnl` and `external-<app>` - run the app's own shell script (`apps\<app>\<app>.sh`), see below.
- `tscupdate`, `flushfirewall`, `restorerootpassword`, `togglebeta` (the buttons in Instellingen > TSC)
  change nothing on a PC, but send the notification the device script sends ("Er is geen TSC update
  gevonden", ...). `toonupdate` is logged and skipped.

**Apps' shell scripts** run unchanged, in the bundled busybox-w32 (`tools\busybox\busybox.exe`, the
Windows build of the BusyBox the Toon runs; version, licence and source in its README.txt) - or in the
shell `TOONSIM_SH` names; without busybox.exe devkitPro's MSYS2, MSYS2 (`C:\msys64`) or Git for
Windows. What runs is a copy (`data\tmp\toonsim-scripts\`) in which:

- the device paths - `/tmp`, `/mnt/data`, `/qmf/qml/apps`, `/var/volatile`, `/HCBv2`, ... - point to
  the simulator's folders (as `C:/...` for BusyBox, `/c/...` for MSYS2; in 8.3 form when the folder
  has spaces, so an unquoted `$DIR` stays one word), also in the script's arguments;
- `/usr/bin/<tool>` and `/bin/<tool>` become `<tool>`, found on the PATH (BusyBox knows `/bin/<applet>`
  only, and Windows' `curl.exe` is no `/usr/bin/curl`);
- `http://localhost` is the simulator's web server.

`tools\shims\` comes first on the PATH with stand-ins for device commands: `bxt` (a notification in
the GUI), `killall qt-gui` and `reboot`/`shutdown`/`poweroff`/`halt` (a GUI restart - never the PC's:
Windows' own `shutdown.exe` takes `-r`), `opkg` and `pkill` (nothing), `openssl` (`dgst`, `base64`,
`rand`, done by tsc.py, as Windows has no openssl). For BusyBox, `BB_OVERRIDE_APPLETS` makes its
killall/pkill applets give way to the stand-ins, and MSYS2/Cygwin folders are left off the PATH: their
programs expand `{..}` in their own arguments when a non-MSYS program starts them (`curl -w
"%{http_code}"` printed `%http_code`). sed, grep, awk, hexdump, ... are BusyBox's, `curl` is Windows'.
The output goes to the tsc log, prefixed with the script's name. What cannot run: scripts that start a
program built for the Toon (an ARM Linux binary, e.g. bekendmakingen's daemon) or that need the
device's hardware.

The rest of Instellingen > TSC works as on the Toon: lock/unlock with a PIN, Restart GUI, the GUI
modification screens, subscription features (saved in `TenantSettings.json`, then a reboot = GUI
restart), change tariff (`happ_pwrusage`, kept across restarts), change max. heat, hot water preheat
off when away, summer mode (all presets to 10 degrees and back). Two warnings there are the
firmware's own: `ToggleNativeFeaturesScreen.qml:24` (TenantSettings.json has no
`appBenchmarkEnabled`) and `customToonLogoLabel is not defined` (a typo in CustomToonLogoScreen).

Removing is safer than on the Toon: a junction is removed without touching what it points to (your
own folder linked into `apps\` stays), and a folder the simulator did not install itself (such as
the ToonStore you copied in) is moved to `data\mnt\data\tsc\removed\` instead of deleted.
Its log is `data\var\log\tsc` and the simulator's log (lines starting with `tsc:`).

ToonStore shows firmware 6.3.30 (the version of the Toon 2 it was taken from): toonsim writes the
opkg control file apps read, `/var/lib/opkg/info/base-nxt-uni.control` (Toon 1:
`/usr/lib/opkg/info/base-qb2-ene.control`).

**https**: this Qt has no OpenSSL (Qt 5.15 needs OpenSSL 1.1, which is no longer distributed), so
toonsim sends the GUI's https requests to **`tools\netbridge.py`**, which makes them with Python's
own TLS. Both helpers need `python` on the PATH and stop by themselves when toonsim is gone.

## Remote control and tests

`toonsim` listens on `127.0.0.1:5555` (`--control-port N`, 0 = off): one command per line, one
JSON answer per line - `tap X Y`, `shot FILE.png`, `items [TEXT]` (visible texts with position),
`eval JS`, `log`, `size`, `hit X Y` (the items under a point, top-most first, with their `state`: what a tap
there reaches), `restart`, `quit`. `tools\toonsim.py` wraps it for Python:

    from toonsim import Toon
    with Toon.start(hidden=True) as t:        # or Toon.connect() to a running one
        t.wait_until_booted()
        t.tap_text("Voeg tegel toe")
        t.shot("chooser.png")

Or from a prompt: `python tools\toonsim.py shot x.png`, `... items`, `... taptext Instellingen`.

`eval` runs in Canvas.qml's context, as app code does: `globals`, `stage`, `CanvasJS.loadedApps`
and the simulator's `simDevices` are all there. The client adds `t.app("graph/GraphApp.qml")`,
`t.open_screen(app, "graphScreenUrl")`, `t.device("happ_thermstat")`, `t.set_device(type, **state)`
and `t.log_mark()` / `t.log_since(mark)`.

With `--hidden` the window is there but fully transparent and click-through (Windows does not render
a window that is hidden or off-screen, and screenshots need it rendered). It cannot take the keyboard
focus, so the on-screen keyboard does not come up there: a test that types needs `--show`.

### Automated tests

    python tools\run_tests.py                 all tests\test_*.py, Toon 2 size
    python tools\run_tests.py --size toon1    the same on the Toon 1 screen
    python tools\run_tests.py graph           only files/tests with "graph" in the name
    python tools\run_tests.py --show          watch it happen

A test is a function `test_...(t)` in `tests\test_*.py` that gets the client and fails by raising.
Each file gets a fresh simulator on port 5556 with its own, emptied data folder `data-test\` - a
simulator you have open (port 5555, `data\`) keeps running undisturbed. After every test the runner
goes back to the home screen. A failure leaves `tests\out\<file>.<test>.png` and the log lines of that
test. `t.wait_restart()` reconnects after something restarted the GUI.
`tests\test_home.py`, `test_graph.py`, `test_toonstore.py` and `test_tsc_settings.py` are examples:
presets, the + button, the room temperature from the simulated thermostat, the usage tile, the graph
views, the ToonStore list (needs internet), tsc commands, the TSC settings tab (buttons, summer mode,
tariffs, all its screens, Restart GUI), the dim button and the notification bar.

## Firmware differences (Qt 5.11 on the Toon, 5.15 here)

A few firmware files need a small change to load under Qt 5.15 (e.g. redeclaring a signal of a C++
base type). They are listed with the reason in `sim\compat\patches.json`; `python tools\build_compat.py`
builds `firmware\compat.rcc`, which is loaded before the firmware. The device files are not changed.
`python tools\rcc.py list|cat|extract FILE.rcc` reads any Toon resource file.

**Local time**: Qt 5.15.2's MinGW build gets daylight saving wrong in JavaScript's `Date` (it hands
`localtime` a 32-bit time as a 64-bit one): `getHours()` was an hour behind in summer. toonsim
repairs that call at startup (`src\main.cpp`, `repairQmlDaylightSaving`), so dates are right in
summer and winter time.

**Dim state**: a touch on a dimmed screen only wakes it up, as on the Toon, except on controls that
work while dimmed (`mouseIsActiveInDimState`).

## Building

Needs Qt 5.15.2 (MinGW) and its MinGW compiler, installed under `%USERPROFILE%\Qt` (e.g. with
`aqtinstall`, which needs no admin rights).
`tools\build.bat` builds `bin\toonsim.exe`; `toonsim.bat` starts it with that Qt on the PATH.
`tools\run_log.ps1` starts it hidden for a few seconds and prints the distinct problems it reports.

## Not done yet

- Wished for: setting the simulated time, to test time-based behaviour. (Switching Toon 1 / Toon 2
  while running is done: Ctrl+1 / Ctrl+2 and the window menu, see the start of this file.)
- Month targets (MonthDataDataset): only solar has them; the graphs' "Ingeschat verbruik" for
  electricity and gas has no values yet, and a changed expected solar yield counts after a restart.
- District heating, water: the model has them at zero or rough values. The meter settings' solar
  screens (Instellingen > Meters: meter adapter configuration) are not simulated.
- Boiler information, smoke detectors, smart plugs, Hue: empty devices.
- More of the local web server: other daemons' URLs, and hcb_rrd's energy loggers (the graphs use
  hdrv_p1's insights instead).

Warnings that are the firmware's own (the device prints them too) and are left alone: the keyboard
style "toon", ThermostatApp's wastecollection settings (the TSC mod expects that app),
ThermostatWeekProgramTab `root is not defined`, EditDayScreen's anchor, ProductFrame's `width of null`.

## Licence

toonsim is released under the [MIT licence](LICENSE). That covers toonsim's own code. It does not
cover:

- **The Toon firmware** (the GUI in `firmware\`): it is Eneco's. It is not part of this repository or
  the release packages; everyone copies it from their own rooted Toon.
- **ToonStore** (`apps\toonstore`) and the **TSC helper script** (`sim\tsc`): they come from the
  [ToonSoftwareCollective](https://github.com/ToonSoftwareCollective) and fall under their terms.
- **Third-party parts of the Windows package:** Qt 5.15 (LGPL), the embeddable Python (PSF licence)
  and busybox-w32 (GPLv2; version, licence and source in `tools\busybox\README.txt`).
