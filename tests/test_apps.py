"""Apps installed in apps/ (skipped when they are not there), and app shell scripts run by tsc."""
import os, shutil, time

HOME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TEST_SCRIPT = """#!/bin/sh
mkdir -p /tmp/shtest
echo hello > /mnt/data/tsc/shtest.txt
/HCBv2/bin/bxt -d :happ_usermsg -s Notification -n CreateNotification -a type -v tsc -a subType -v notify -a text -v "Script meldt: klaar"
opkg list-installed foo
for c in killall pkill shutdown reboot; do command -v $c; done > /tmp/shtest/commands.txt
/usr/bin/curl -s "http://localhost/happ_thermstat?action=getThermostatInfo" > /tmp/shtest/thermostat.json
echo "a,b" | awk -F, '{print $2}' | sed 's/b/ok/' > /tmp/shtest/tools.txt
printf '%s' "toonsim" | openssl dgst -sha256 -binary | openssl base64 > /tmp/shtest/openssl.txt
date > /tmp/shtest/ran.txt
"""


def web(t, path):
    import urllib.request
    return urllib.request.urlopen("http://127.0.0.1:%d%s" % (t.eval("toonsimWebPort"), path), timeout=10).read().decode()


def test_local_web_synchronous_xhr(t):
    # a synchronous XMLHttpRequest to http://localhost from the GUI (thermostatPlus's setSetpoint): the
    # simulator answers it on the GUI thread, so it must not go over the socket - that hung it
    before = t.device("happ_thermstat")["currentSetpoint"]
    t.sock.settimeout(15)
    r = t.eval('(function(){var x=new XMLHttpRequest(); x.open("GET","http://localhost/happ_thermstat?action=setSetpoint&Setpoint=2150",false);'
               ' x.send(); return x.status + " " + x.responseText})()')
    t.sock.settimeout(5)                                   # as Toon._connect has it
    assert r.startswith("200 "), r
    assert t.device("happ_thermstat")["currentSetpoint"] == 2150
    t.set_device("happ_thermstat", currentSetpoint=before)  # the next tests expect a room that is not heating
    r = t.eval('(function(){var x=new XMLHttpRequest(); x.open("GET","http://127.0.0.1/no/such/page",false); x.send(); return x.status})()')
    assert r == 404, r


def test_local_web_thermostat(t):
    # http://localhost/happ_thermstat?action=getThermostatInfo: every value a string, as on the Toon
    import json
    t.set_device("happ_thermstat", currentTemp=1950)
    info = json.loads(web(t, "/happ_thermstat?action=getThermostatInfo"))
    assert info["result"] == "ok" and info["currentTemp"] == "1950", info
    assert all(isinstance(v, str) for v in info.values())


def test_local_web_rrd(t):
    # hcb_rrd getRrdData in the Toon's format: { "dd-mm-yyyy HH:MM:SS": 24.50, ...}, a sample per minute
    import json, re
    frm = time.strftime("%d-%m-%Y%%20%H:%M", time.localtime(time.time() - 300))
    body = web(t, "/hcb_rrd?action=getRrdData&loggerName=thermstat_boilerChPressure&rra=30days&readableTime=1&nullForNaN=1&from=" + frm)
    data = json.loads(body)
    assert data and all(re.match(r"^\d\d-\d\d-\d{4} \d\d:\d\d:00$", k) for k in data), body
    assert [v for v in data.values() if v is not None][-1] == 1.19, body
    assert re.search(r'": \d+\.\d\d[,}]', body), body             # two decimals, as the Toon writes them


def test_mobile_site_endpoints(t):
    # what Toon mobile (/HCBv2/www/mobile) calls, in the Toon's formats
    import json
    tree = json.loads(web(t, "/hcb_config?action=getObjectConfigTree&package=happ_thermstat&internalAddress=thermostatStates"))
    temps = {s["id"][0]: s["tempValue"][0] for s in tree["states"][0]["state"]}
    assert temps["0"] and temps["3"], tree
    usage = json.loads(web(t, "/happ_pwrusage?action=GetCurrentUsage"))
    assert usage["result"] == "ok" and usage["powerUsage"]["value"] > 0, usage
    assert json.loads(web(t, "/hcb_config?action=getLocale"))["locale"] == "nl_NL"
    assert json.loads(web(t, "/hdrv_zwave?action=getDevices.json")) == {}
    assert json.loads(web(t, "/hcb_rrd?action=getRrdData&loggerName=elec_solar_flow&rra=5min"))["error"] == "unknown logger"
    # the meters never go back and rise over the days (labels at UTC midnight, as the Toon); the
    # normal-tariff meter stands still in weekends (all low tariff)
    frm = time.strftime("%d-%m-%Y", time.localtime(time.time() - 4 * 86400))
    days = json.loads(web(t, "/hcb_rrd?action=getRrdData&loggerName=elec_quantity_nt&rra=10yrdays&readableTime=1&nullForNaN=1&from=" + frm))
    values = list(days.values())
    assert len(values) >= 4 and all(b >= a for a, b in zip(values, values[1:])) and values[-1] > values[0], days
    # a setpoint from the site reaches the thermostat
    web(t, "/happ_thermstat?action=roomSetpoint&Setpoint=2150")
    t.wait_for(lambda: t.device("happ_thermstat")["currentSetpoint"] == 2150, timeout=3, what="the new setpoint")


def test_external_app_script(t):
    # "external-<app>" in the command file: tsc runs apps/<app>/<app>.sh in a Unix shell, with the
    # device paths mapped to the simulator's folders, bxt / opkg / killall / shutdown as stand-ins, and
    # http://localhost the simulator's web server
    import json, sys
    sys.path.insert(0, os.path.join(HOME, "tools"))
    import tsc
    if not tsc.find_shell():
        return                                             # no bundled BusyBox, MSYS2 or Git shell
    app = os.path.join(HOME, "apps", "toonsimshtest")      # no ...App.qml, so the GUI does not load it
    os.makedirs(app, exist_ok=True)
    try:
        with open(os.path.join(app, "toonsimshtest.sh"), "w", newline="\n") as f: f.write(TEST_SCRIPT)
        with open(os.path.join(t.data, "tmp", "tsc.command"), "w") as f: f.write("external-toonsimshtest")
        t.wait_for(lambda: os.path.exists(os.path.join(t.data, "tmp", "shtest", "ran.txt")), timeout=30, what="the script to run")   # a first shell start can be slow (virus scanner)
        assert os.path.exists(os.path.join(t.data, "mnt", "data", "tsc", "shtest.txt"))
        out = lambda name: open(os.path.join(t.data, "tmp", "shtest", name), encoding="utf-8").read()
        commands = out("commands.txt").split()
        assert len(commands) == 4 and all("shims" in c for c in commands), commands     # never the PC's own
        assert json.loads(out("thermostat.json"))["result"] == "ok"
        assert out("tools.txt").strip() == "ok"
        import base64, hashlib
        assert out("openssl.txt").strip() == base64.b64encode(hashlib.sha256(b"toonsim").digest()).decode()
        t.wait_for(lambda: any(n["text"] == "Script meldt: klaar" for n in t.device("happ_usermsg")["notifications"]),
                   timeout=5, what="the script's notification")
    finally:
        shutil.rmtree(app, ignore_errors=True)

WASTE = "wastecollection/WastecollectionApp.qml"


def test_wastecollection_settings_fields(t):
    # the screen reads its provider from "wastecollectionProvider.js" - a FileIO source relative to the
    # screen's own QML file - and shows the fields that provider needs (plugin_index.json on GitHub)
    if WASTE not in t.apps():
        return
    t.open_screen(WASTE, "wastecollectionConfigurationScreenUrl")
    info = t.wait_for_text("Actieve plugin:", timeout=30)[0]["text"]
    assert "Plugin voor uitsluitend extra datums" not in info or not t.find("Postcode:"), info
    if "postcode" in info.lower():
        t.wait_for_text("Postcode:", exact=True)
        t.wait_for_text("Huisnr:", exact=True)
