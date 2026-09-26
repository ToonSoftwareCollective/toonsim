"""happ_scsync's features, from /mnt/data/qmf/config/config_happ_scsync.xml (/qmf/config/... on the Toon)."""
import os, time


def config(t):
    return os.path.join(t.data, "mnt", "data", "qmf", "config", "config_happ_scsync.xml")


def test_config_file_written(t):
    # written from the agreement at the first start, with the fields apps edit (thermostatPlus)
    text = open(config(t), encoding="utf-8").read()
    assert "<commissionState>" in text and "SolarActivated" in text, text[:300]
    assert t.eval("globals.heatingMode") == "central"
    # /qmf/config is the same folder, as the link on the Toon
    r = t.eval('(function(){var x=new XMLHttpRequest(); x.open("GET","file:///qmf/config/config_happ_scsync.xml",false);'
               ' x.send(); return x.responseText.length})()')
    assert r > 100, r


def test_no_heating_gives_six_tiles(t):
    # <feature>noHeating</feature> + a reboot: a Toon without heating, no large thermostat on the home screen
    text = open(config(t), encoding="utf-8").read()
    with open(config(t), "w", encoding="utf-8") as f:
        f.write(text.replace("</commissionState>", "</commissionState><features><feature>noHeating</feature></features>", 1))
    t.eval("toonsimControl.restart(), true")
    t.wait_restart()
    assert t.eval("globals.heatingMode") == "none"
    assert t.eval("globals.features.noHeating") is True
