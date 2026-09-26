"""The home screen and the thermostat panel, driven through the GUI and checked against the simulated
thermostat (sim/devices/happ_thermstat.js). Run with: python tools/run_tests.py"""


def test_clock_is_local_time(t):
    # JS local time as the PC's, daylight saving included (Qt 5.15.2's MinGW build left it out)
    import time
    offset = t.eval("new Date().getTimezoneOffset()")
    assert offset == -(time.localtime().tm_gmtoff // 60), offset
    assert t.eval("new Date().getHours()") == time.localtime().tm_hour


def test_home_shows_presets(t):
    for name in ("Weg", "Thuis", "Slapen", "Comfort"):
        t.wait_for_text(name, exact=True)


def test_room_temperature_from_device(t):
    # freeze the simulated house so the value stays put, then set the room temperature
    t.set_device("happ_thermstat", currentTemp=1650, heatRate=0, coolRate=0)
    t.wait_for_text("16,5°", exact=True)


def test_preset_button_changes_setpoint(t):
    t.tap_text("Comfort", exact=True)
    t.wait_for(lambda: t.device("happ_thermstat")["currentSetpoint"] == 2000, what="setpoint 20.0")
    t.tap_text("Weg", exact=True)
    t.wait_for(lambda: t.device("happ_thermstat")["currentSetpoint"] == 1200, what="setpoint 12.0")
    t.wait_for_text("12,0°")


def test_plus_button_raises_setpoint(t):
    before = t.device("happ_thermstat")["currentSetpoint"]
    # the + is an icon: tap it by position, right of the room temperature and level with it
    w, h = t.size()["w"], t.size()["h"]
    plus = (int(w * 0.91), int(h * 0.33))
    # the first tap opens the setpoint editor, every next one adds 0.5 degree
    t.tap(*plus)
    t.tap(*plus)
    # 3 s after the last tap the panel sends the new setpoint
    t.wait_for(lambda: t.device("happ_thermstat")["currentSetpoint"] == before + 50, timeout=8, what="setpoint +0.5")
    t.wait_for_text(("%.1f°" % ((before + 50) / 100)).replace(".", ","))


def test_status_usage_tile(t):
    # happ_pwrusage's month status: the tile says how much less (or more) than estimated
    # its page depends on the tile layout (the installed apps' tiles come first): page through
    w, h = t.size()["w"], t.size()["h"]
    for page in range(6):
        try:
            t.wait_for(lambda: t.find("minder") or t.find("meer"), timeout=3, what="the status usage tile")
            return
        except Exception:
            t.tap(int(w * 0.6), int(h * 0.927))           # the "next page" arrow under the tiles
    raise AssertionError("no status usage tile on any page")
