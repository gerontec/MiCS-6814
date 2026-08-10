"""open_wifi — verbindet sich bevorzugt mit dem staerksten OFFENEN WLAN.

Ersetzt das frueher per `includes:` eingebundene open_wifi_scan.h. Der Grund
fuer den Umbau: ein in einem Include global angelegtes Component-Objekt wird
zwar konstruiert, aber nie bei App registriert — sein setup() lief deshalb nie.
Als externe Komponente uebernimmt cg.register_component() genau das.

Verwendung:

    external_components:
      - source: components

    open_wifi:
"""

import esphome.codegen as cg
import esphome.config_validation as cv
from esphome.const import CONF_ID

DEPENDENCIES = ["wifi"]

CONF_SSID_BLOCKLIST = "ssid_blocklist"
CONF_SURVEY = "survey"
CONF_REPORT_TOPIC = "report_topic"
CONF_REPORT_DELAY = "report_delay"
CONF_FALLBACK_SSID = "fallback_ssid"
CONF_FALLBACK_PASSWORD = "fallback_password"
CONF_DISABLE_TIMEOUT = "disable_timeout"

open_wifi_ns = cg.esphome_ns.namespace("open_wifi")
OpenWifiScan = open_wifi_ns.class_("OpenWifiScan", cg.Component)

CONFIG_SCHEMA = cv.Schema(
    {
        cv.GenerateID(): cv.declare_id(OpenWifiScan),
        # Bewusst keine RSSI-Untergrenze: lieber ein offenes Netz mit
        # schlechtem Empfang als gar keins.
        # SSIDs, die nie genommen werden sollen (z.B. Gastnetze von Nachbarn).
        cv.Optional(CONF_SSID_BLOCKLIST, default=[]): cv.ensure_list(cv.string),
        # Loggt JEDES gefundene Netz - ESPHome selbst zeigt nur die
        # konfigurierten. Standard an: die Umgebungsmessung kostet nichts
        # extra (der Scan laeuft ohnehin) und fehlt sonst genau dann, wenn
        # man sie braucht.
        cv.Optional(CONF_SURVEY, default=True): cv.boolean,
        # MQTT-Topic fuer die dokumentierte Survey-Entscheidung (retained).
        # Leer = Report aus. Der Scan passiert beim Boot VOR der MQTT-
        # Verbindung; der Puffer ueberbrueckt das und publiziert, sobald
        # der Broker erreichbar ist - erst danach gilt er als vergessen.
        cv.Optional(CONF_REPORT_TOPIC, default=""): cv.string,
        cv.Optional(CONF_REPORT_DELAY, default="10s"): cv.positive_time_period_milliseconds,
        # Offenes Fallback-Netz. Muss hier stehen und nicht nur unter
        # wifi: networks:, weil die Komponente die Liste neu aufbaut -
        # der Codegen fuellt sonst jeden Platz und FixedVector::push_back
        # verwirft das gefundene offene Netz kommentarlos.
        cv.Optional(CONF_FALLBACK_SSID, default=""): cv.string,
        # Passwort des Fallback-Netzes. Leer = offenes Netz. Erst damit taugt
        # ein WPA2-Netz als Rueckfallebene; ohne das koennte man nur ein
        # weiteres offenes Netz angeben.
        cv.Optional(CONF_FALLBACK_PASSWORD, default=""): cv.string,
        # Ein per MQTT gesetztes "aus" faellt nach dieser Zeit von selbst
        # zurueck auf "an". Der Wunschzustand ist "immer das beste offene
        # Netz"; das Abschalten ist ein Wartungsfenster (z.B. fuer OTA aus
        # einem erreichbaren Subnetz) und soll nicht versehentlich zum
        # Dauerzustand werden. 0 = kein Ablauf.
        cv.Optional(CONF_DISABLE_TIMEOUT, default="600s"): cv.positive_time_period_milliseconds,
    }
).extend(cv.COMPONENT_SCHEMA)


async def to_code(config):
    var = cg.new_Pvariable(config[CONF_ID])
    await cg.register_component(var, config)
    cg.add(var.set_survey(config[CONF_SURVEY]))
    cg.add(var.set_report_topic(config[CONF_REPORT_TOPIC]))
    cg.add(var.set_report_delay(config[CONF_REPORT_DELAY]))
    cg.add(var.set_fallback_ssid(config[CONF_FALLBACK_SSID]))
    cg.add(var.set_fallback_password(config[CONF_FALLBACK_PASSWORD]))
    cg.add(var.set_disable_timeout(config[CONF_DISABLE_TIMEOUT]))
    for ssid in config[CONF_SSID_BLOCKLIST]:
        cg.add(var.add_blocked_ssid(ssid))
