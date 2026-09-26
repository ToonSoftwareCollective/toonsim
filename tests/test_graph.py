"""The graph app with the simulated energy data (sim/devices/energy.js via hdrv_p1's insights)."""

GRAPH = "graph/GraphApp.qml"


def open_graph(t):
    t.open_screen(GRAPH, "graphScreenUrl", {"agreementType": "electricity", "unitType": "energy", "intervalType": "days"})
    t.wait_for_text("Dagen", exact=True)


def test_graph_app_loaded(t):
    assert GRAPH in t.apps()
    assert t.eval(Toon_app(GRAPH) + ".doneLoading") is True


def test_days_view(t):
    open_graph(t)
    t.wait_for_text("maandag")
    t.wait_for_text("(wk ")                          # the date selector shows the week


def test_hours_view_power(t):
    open_graph(t)
    t.tap_text("Uren", exact=True)
    t.wait_for_text("Watt", exact=True)


def test_gas_months(t):
    open_graph(t)
    t.tap_text("Gas", exact=True)
    t.tap_text("Maanden", exact=True)
    t.wait_for_text("m³")
    t.wait_for_text("jan.")


def test_no_errors_while_browsing(t):
    mark = t.log_mark()
    open_graph(t)
    for tab in ("Uren", "Weken", "Maanden", "Jaren", "Dagen"):
        t.tap_text(tab, exact=True)
    t.tap_text("€", exact=True)
    errors = [l for l in t.log_since(mark, "warning") if "Error" in l]
    assert not errors, "\n".join(errors)


def Toon_app(path):
    return 'CanvasJS.loadedApps["%s"]' % path
