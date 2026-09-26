"""ToonStore (apps/toonstore) and the simulator's tsc (tools/tsc.py). The first test needs internet:
the store reads its repository from GitHub (through tools/netbridge.py, as this Qt has no TLS).

Installing and removing is not tested here, as it downloads from GitHub and changes apps/; to try
it by hand: select an app in the store, "Toon Bijwerken", and watch data/var/log/tsc."""
import os

STORE = "toonstore/ToonstoreApp.qml"


def test_store_lists_repository(t):
    if STORE not in t.apps():
        return                                            # ToonStore not in apps/: nothing to test
    t.open_screen(STORE, "fullScreenUrl")
    head = t.wait_for_text("Apps in de ToonStore", timeout=40)[0]["text"]
    assert int(head.split()[0]) > 10, head
    t.wait_for_text("Firmware: 6.3.30")


def test_more_than_three_installs_refused(t):
    if STORE not in t.apps():
        return
    app = t.app(STORE)
    t.open_screen(STORE, "fullScreenUrl")
    t.wait_for_text("Apps in de ToonStore", timeout=40)
    t.wait_for_text("Bijgewerkt:", timeout=40)            # the list from GitHub is in: no redraw mid-test
    for p in ("autoreboot-1.0.6", "calendar-1.2.1", "sonos-1.3.5", "schaak-1.0.0"):
        t.eval("%s.selectForInstall('%s'), true" % (app, p))
    t.wait_for_text("Toon Bijwerken (4)", exact=True)
    t.tap_text("Toon Bijwerken (4)", exact=True)
    t.wait_for_text("U kunt niet meer dan drie apps tegelijkertijd installeren")
    assert not os.path.exists(os.path.join(t.data, "tmp", "tsc.command"))     # nothing sent to tsc
    t.tap_text("Sluiten", exact=True)
    t.wait_for(lambda: not t.find("niet meer dan drie"), timeout=3, what="the dialog to close")
    t.eval("%s.updatesToBeApplied = [], true" % app)


def test_select_and_deselect(t):
    # the + button: selected it is "up" (green), deselected "down" again (it stayed green once: the
    # simulator passed on the "exited" that ends every touch)
    if STORE not in t.apps():
        return
    app = t.app(STORE)
    t.open_screen(STORE, "fullScreenUrl")
    t.wait_for_text("Apps in de ToonStore", timeout=40)
    t.wait_for_text("Bijgewerkt:", timeout=40)            # the list from GitHub is in: no redraw mid-test
    row = next((r for r in t.find("Beschikbaar:")), None)
    assert row, "no app that can be installed"
    x, y = int(t.size()["w"] * 0.817), row["cy"] + int(t.size()["h"] * 0.05)
    selected = lambda: t.eval("%s.updatesToBeApplied.length" % app)
    button = lambda: [h.get("state") for h in t.cmd("hit %d %d" % (x, y)) if h["type"] == "IconButton"]
    t.tap(x, y)
    if t.find("Sluiten", exact=True):
        t.tap_text("Sluiten", exact=True)                  # the explanation shown the first time
    t.wait_for(lambda: selected() == 1, timeout=3, what="the app selected")
    assert button() == ["up"], button()
    t.tap(x, y)
    t.wait_for(lambda: selected() == 0, timeout=3, what="the app deselected")
    assert button() == ["down"], button()


def test_tsc_runs_command_file(t):
    # the "deletefile" command: remove files named in /tmp/files_to_delete.txt from /mnt/data/tsc/appData
    data = lambda *p: os.path.join(t.data, *p)
    victim = data("mnt", "data", "tsc", "appData", "toonsim-test.txt")
    os.makedirs(os.path.dirname(victim), exist_ok=True)
    with open(victim, "w") as f: f.write("x")
    with open(data("tmp", "files_to_delete.txt"), "w") as f: f.write("toonsim-test.txt")
    with open(data("tmp", "tsc.command"), "w") as f: f.write("deletefile")
    t.wait_for(lambda: not os.path.exists(victim), timeout=12, what="tsc to delete the file (it looks every 5 s)")
    assert not os.path.exists(data("tmp", "tsc.command"))


def test_tsc_command_sends_notification(t):
    # "Check for updates" writes tscupdate; the device script answers with a notification
    with open(os.path.join(t.data, "tmp", "tsc.command"), "w") as f: f.write("tscupdate")
    t.wait_for(lambda: any(n["text"] == "Er is geen TSC update gevonden"
                           for n in t.device("happ_usermsg")["notifications"]), timeout=12, what="the notification")
