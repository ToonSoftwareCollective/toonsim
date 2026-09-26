"""Solar panels: TSC's "Zon Op Toon" switches them on (agreement SolarActivated, then a reboot), and
from then on happ_pwrusage, the insights, hcb_rrd and the solar app have the panels' values."""
import json, time, urllib.request

TSC = 'CanvasJS.loadedApps["tscSettings/TscSettingsApp.qml"]'


def web(t, path):
    return urllib.request.urlopen("http://127.0.0.1:%d%s" % (t.eval("toonsimWebPort"), path), timeout=30).read().decode()


def dataset(t, name):
    return t.eval('simDevices.dataset("sim-happ_pwrusage-0001", "%s").toXml()' % name)


def field(xml, name):
    return float(xml.split("<%s>" % name)[1].split("<")[0])


def test_no_solar_by_default(t):
    assert t.eval("globals.productOptions.solar") in (0, "0")
    assert field(dataset(t, "powerUsage"), "valueSolar") == 0
    assert "<error>notSet</error>" in dataset(t, "billingInfo").split("elec_produ")[1]
    assert json.loads(web(t, "/hcb_rrd?action=getRrdData&loggerName=elec_solar_quantity&rra=10yrdays"))["error"] == "unknown logger"


def test_zon_op_toon_switches_solar_on(t):
    t.eval(TSC + ".toggleSolarSubscription(), true")          # what the toggle in the TSC screen does
    time.sleep(1)
    t.eval(TSC + ".rebootToon(), true")
    t.wait_restart()
    assert t.eval("globals.productOptions.solar") in (1, "1")
    assert t.eval('CanvasJS.loadedApps["graph/GraphApp.qml"].hasSolar') is True
    t.wait_for(lambda: t.eval('CanvasJS.loadedApps["solar/SolarApp.qml"].doneLoading') is True, timeout=30,
               what="the solar app to load")


def test_solar_values(t):
    pu = dataset(t, "powerUsage")
    assert field(pu, "valueSolar") >= 0 and field(pu, "solarProducedToday") > 0 and field(pu, "avgDayProduValue") > 0
    assert field(pu, "meterReadingProdu") > 0 and field(pu, "meterReadingLowProdu") > 0
    produ = dataset(t, "billingInfo").split("<type>elec_produ</type>")[1]
    assert "notSet" not in produ and field(produ, "usage") == 3600000 and field(produ, "installedDate") > 0
    usage = json.loads(web(t, "/happ_pwrusage?action=GetCurrentUsage"))
    assert usage["powerProduction"]["avgValue"] > 0


def test_solar_yield_a_year(t):
    # the panels' kWh meter over last year: about 0.9 kWh per Wp, 4000 Wp by default
    year = time.localtime().tm_year - 1
    days = json.loads(web(t, "/hcb_rrd?action=getRrdData&loggerName=elec_solar_quantity&rra=10yrdays&readableTime=1"
                             "&from=31-12-%d&to=02-01-%d" % (year - 1, year + 1)))
    first = [v for k, v in days.items() if k.startswith("01-01-%d" % year)][0]
    last = [v for k, v in days.items() if k.startswith("01-01-%d" % (year + 1))][0]
    kwh = (last - first) / 1000
    assert 3000 < kwh < 4200, kwh
    for logger in ("elec_solar_flow", "elec_produ_flow", "elec_quantity_nt_produ", "elec_quantity_lt_produ"):
        assert "error" not in json.loads(web(t, "/hcb_rrd?action=getRrdData&loggerName=%s&rra=5min" % logger)), logger


def test_solar_app(t):
    app = 'CanvasJS.loadedApps["solar/SolarApp.qml"]'
    t.wait_for(lambda: (t.eval(app + ".totalProduced") or 0) > 0, timeout=20, what="the total produced")
    assert t.eval(app + ".expectedProduced") > 0                # from the months' targets (MonthDataDataset)
    t.open_screen("solar/SolarApp.qml", "solarScreenUrl", {"isYield": True, "isUsage": True, "intervalType": 0})
    t.wait_for_text("In totaal geproduceerd", timeout=15)
    t.wait_for_text("Hiervan teruggeleverd")


def test_bigger_panels(t):
    # simDevices.set changes the size; the day's yield scales with it
    before = field(dataset(t, "powerUsage"), "solarProducedToday")
    t.set_device("happ_pwrusage", solarWattPeak=8000)
    after = field(dataset(t, "powerUsage"), "solarProducedToday")
    t.set_device("happ_pwrusage", solarWattPeak=4000)
    assert abs(after - 2 * before) <= 0.01 * after, (before, after)      # W rounded per sample
