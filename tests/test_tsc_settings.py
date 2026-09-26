"""Instellingen > TSC (the TSC settings app of the firmware): its buttons, toggles and screens."""
import time


def home(t):
    """the home screen, awake (a minute without a touch dims it) and without the notification bar,
    which would cover the menu and dim buttons"""
    t.eval("screenStateController.wakeup(), stage.navigateHome(), true")
    t.eval("notificationBar.hide(), true")
    time.sleep(0.5)


def tsc_tab(t):
    home(t)
    t.tap(int(t.size()["w"] * 0.054), int(t.size()["h"] * 0.058))       # the menu button, top left
    t.tap_text("Instellingen", exact=True)
    t.wait_for_text("TSC", exact=True)
    t.tap_text("TSC", exact=True)
    t.wait_for_text("Restart GUI", exact=True)


def notified(t, text):
    return t.wait_for(lambda: any(n["text"] == text for n in t.device("happ_usermsg")["notifications"]),
                      timeout=12, what="notification %r" % text)


def test_check_for_updates(t):
    tsc_tab(t)
    t.tap_text("Check for updates", exact=True)
    notified(t, "Er is geen TSC update gevonden")


def test_flush_firewall(t):
    tsc_tab(t)
    t.tap_text("Flush firewall rules", exact=True)
    notified(t, "Firewall regels verwijderd")


def test_restore_password(t):
    tsc_tab(t)
    t.tap_text("Restore password", exact=True)
    notified(t, "Root password restored to 'toon'")


def test_summer_mode(t):
    tsc_tab(t)
    before = t.device("happ_thermstat")["stateTemps"]
    # both toggles line up right of the longer hot water text, 20 px + half a toggle further
    dhw = t.find("Disable hot water preheating")[0]
    toggle = t.find("Summer mode")[0]
    x = dhw["x"] + dhw["w"] + 20 + 30
    t.tap(x, toggle["cy"])
    # all presets to 10 degrees, the old ones saved
    t.wait_for(lambda: all(v == 1000 for k, v in t.device("happ_thermstat")["stateTemps"].items() if k != "4"),
               timeout=10, what="presets at 10 degrees")
    notified(t, "Summer mode selected. All setpoints now at 10 degrees.")
    t.tap(x, toggle["cy"])
    t.wait_for(lambda: t.device("happ_thermstat")["stateTemps"] == before, timeout=10, what="presets restored")


def test_change_tariff(t):
    t.eval('stage.openFullscreen(%s.changeTariffScreenUrl), true' % t.app("tscSettings/TscSettingsApp.qml"))
    t.wait_for_text("Elec normal:")
    # the screen sends what is in its fields; set them as the keyboard would
    app = t.app("tscSettings/TscSettingsApp.qml")
    t.eval("%s.setTariff('0.25', '0.22', false, '1.10'), true" % app)
    t.wait_for(lambda: t.device("happ_pwrusage")["elecPrice"] == 0.25 and t.device("happ_pwrusage")["gasPrice"] == 1.1,
               timeout=5, what="the new tariffs")


def test_screens_open(t):
    app = t.app("tscSettings/TscSettingsApp.qml")
    mark = t.log_mark()
    for url in ("guiModScreenUrl", "rotateTilesScreenUrl", "toggleNativeFeaturesScreenUrl", "changeMaxHeatingScreenUrl",
                "credentialsMobileAppScreenUrl", "changeTariffScreenUrl", "hideToonLogoScreenUrl",
                "hideErrorSystrayScreenUrl", "customToonLogoScreenUrl"):
        t.eval("stage.openFullscreen(%s.%s), true" % (app, url))
        time.sleep(0.8)
        t.eval("stage.navigateHome(), true")
    # the firmware's own, the Toon has them too: TenantSettings.json has no appBenchmarkEnabled, and
    # CustomToonLogoScreen uses customToonLogoLabel where it means customToonLogoURLLabel
    known = ("ToggleNativeFeaturesScreen.qml:24:", "customToonLogoLabel is not defined")
    errors = [l for l in t.log_since(mark, "warning") if ("Error" in l or "rror:" in l) and not any(k in l for k in known)]
    assert not errors, "\n".join(errors)


def test_notification_bar_close(t):
    home(t)
    t.eval('simDevices.createNotification("tsc", "notify", "Een test")')
    t.eval("notifications.show(false), true")
    t.wait_for(lambda: t.eval("notificationBar.state") == "shown", timeout=5, what="the notification bar")
    time.sleep(0.6)                                       # it slides in (300 ms); before that the dim button is there
    t.tap(int(t.size()["w"] * 0.944), int(t.size()["h"] * 0.095))     # its close button, right
    t.wait_for(lambda: t.eval("notificationBar.state") == "hidden", timeout=5, what="the bar to close")


def test_dim_button(t):
    # the button top right of the home screen: dim now, a touch wakes up
    home(t)
    w = t.size()["w"]
    t.tap(int(w * 0.965), int(t.size()["h"] * 0.058))
    t.wait_for(lambda: t.eval("canvas.dimState") is True, timeout=3, what="the dim state")
    t.tap(w // 2, t.size()["h"] // 2)
    t.wait_for(lambda: t.eval("canvas.dimState") is False, timeout=3, what="waking up")


def test_wake_tap_does_not_click(t):
    # a tap on a dimmed screen only wakes it: tapping where the dim button is must not dim it again
    home(t)
    x, y = int(t.size()["w"] * 0.965), int(t.size()["h"] * 0.058)
    t.tap(x, y)
    t.wait_for(lambda: t.eval("canvas.dimState") is True, timeout=3, what="the dim state")
    t.tap(x, y)
    time.sleep(1)
    assert t.eval("canvas.dimState") is False


def test_restart_gui(t):
    # the last test of this file: the GUI restarts (the Toon's watchdog), the client connects to the new one
    tsc_tab(t)
    t.tap_text("Restart GUI", exact=True)
    t.wait_restart()
    assert "tscSettings/TscSettingsApp.qml" in t.apps()
