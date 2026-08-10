#include "open_wifi.h"

#include "esphome/core/application.h"
#include "esphome/core/hal.h"
#include "esphome/core/helpers.h"
#include "esphome/core/log.h"
#include "esphome/components/wifi/wifi_component.h"

#if defined(USE_ESP8266)
#include <ESP8266WiFi.h>
#elif defined(USE_ESP32)
#include <WiFi.h>
#endif

namespace esphome {
namespace open_wifi {

static const char *const TAG = "open_wifi";

bool OpenWifiScan::is_blocked_(const std::string &ssid) const {
  for (const auto &b : this->blocklist_) {
    if (b == ssid)
      return true;
  }
  return false;
}

bool OpenWifiScan::is_device_ap_(const std::string &ssid) {
  // Espressif-Default-SoftAPs ("ESP_A1B2C3", "ESP-xxx") und ESPHome-Fallback-APs
  // sind Geraete-APs ohne Uplink -> nie als Ziel brauchbar.
  static const char *const PREFIXES[] = {"ESP_", "ESP-", "ESPHome", "esphome"};
  for (const char *p : PREFIXES) {
    const size_t n = strlen(p);
    if (ssid.size() >= n && ssid.compare(0, n, p) == 0)
      return true;
  }
  return false;
}

std::string OpenWifiScan::current_ssid() const {
  auto *wc = wifi::global_wifi_component;
  if (wc == nullptr || !wc->is_connected())
    return "";
  return wc->wifi_ssid();
}

void OpenWifiScan::blacklist_add_(const std::string &ssid) {
  if (ssid.empty() || this->is_blocked_(ssid))
    return;
  this->blocklist_.push_back(ssid);
  ESP_LOGW(TAG, "'%s' auf Blacklist (kein MQTT)", ssid.c_str());
}

std::string OpenWifiScan::find_best_open_(int *rssi_out) {
  std::string best;
  int best_rssi = -127;
  if (rssi_out != nullptr)
    *rssi_out = -127;

#if defined(USE_ESP8266) || defined(USE_ESP32)
  // ZWINGEND vor dem Scan: ohne STA-Modus liefert scanNetworks() auf dem
  // ESP8266 nichts. Diese Zeile stand im urspruenglichen Bauteil und ging beim
  // Umbau verloren - Folge: jeder Scan meldete "nichts gefunden", das staerkste
  // offene Netz (f7240) wurde nie gesehen und das Board blieb dauerhaft auf dem
  // Fallback haengen. Der Fehler ist von aussen nicht als Fehler erkennbar,
  // weil "kein offenes Netz da" ein voellig plausibler Zustand ist.
  WiFi.mode(WIFI_STA);

  // Blockierender Scan: er muss fertig sein, bevor entschieden wird.
  int n = WiFi.scanNetworks(false, false);
  // Der Scan dauert ueber eine Sekunde. Ohne Fuettern schlaegt auf dem ESP8266
  // der Software-Watchdog zu, sobald der Aufruf nicht aus setup() kommt.
  App.feed_wdt();
  if (n <= 0) {
    ESP_LOGW(TAG, "Scan found nothing");
    WiFi.scanDelete();
    return best;
  }

  int best_any_rssi = -127;
  std::string best_any_ssid;

  for (int i = 0; i < n; i++) {
#if defined(USE_ESP8266)
    bool open = WiFi.encryptionType(i) == ENC_TYPE_NONE;
#else
    bool open = WiFi.encryptionType(i) == WIFI_AUTH_OPEN;
#endif
    std::string ssid(WiFi.SSID(i).c_str());
    int rssi = WiFi.RSSI(i);

    if (this->survey_) {
      // ESPHome selbst loggt nur Netze, die unter wifi: networks: stehen —
      // fuer eine Ausleuchtung des Standorts braucht es alle.
      ESP_LOGI(TAG, "  survey: '%s' Ch=%d RSSI=%d %s", ssid.c_str(), WiFi.channel(i), rssi,
               open ? "OPEN" : "enc");
    }

    if (rssi > best_any_rssi) {
      best_any_rssi = rssi;
      best_any_ssid = ssid;
    }

    // Bewusst keine RSSI-Untergrenze: lieber ein offenes Netz mit schlechtem
    // Empfang als gar keins. Netze ohne Broker-Durchgang faengt der Watchdog ab.
    if (!open || ssid.empty())
      continue;
    if (is_device_ap_(ssid))
      continue;
    if (this->is_blocked_(ssid))
      continue;

    if (rssi > best_rssi) {
      best_rssi = rssi;
      best = ssid;
    }
  }

  ESP_LOGI(TAG, "Scanned %d networks, strongest '%s' RSSI=%d", n, best_any_ssid.c_str(),
           best_any_rssi);
  WiFi.scanDelete();
#endif

  if (rssi_out != nullptr)
    *rssi_out = best_rssi;
  return best;
}

void OpenWifiScan::apply_(const std::string &open_ssid) {
  auto *wc = wifi::global_wifi_component;
  if (wc == nullptr)
    return;

  // Nur bei echter Aenderung anfassen: das Neuaufsetzen der Liste setzt
  // selected_sta_index_ auf -1, ESPHome verwirft daraufhin die laufende
  // Verbindung. Ohne diese Sperre loeste jeder Scan-Durchlauf einen
  // Reconnect aus.
  if (this->applied_ && open_ssid == this->preferred_)
    return;
  this->applied_ = true;
  this->preferred_ = open_ssid;

  // Liste komplett neu aufbauen statt nur anzuhaengen.
  //
  // Grund: Der Codegen erzeugt init_sta(len(wifi.networks)) und fuellt danach
  // jeden Platz. FixedVector::push_back verwirft alles darueber KOMMENTARLOS
  // ("Silently ignores pushes beyond capacity"), ein blosses add_sta() des
  // gefundenen offenen Netzes verpufft also spurlos - das Log meldet trotzdem
  // Erfolg. init_sta() ist public und legt den Vektor neu an, deshalb wird das
  // Fallback hier selbst wieder eingetragen.
  bool same = !this->fallback_ssid_.empty() && this->fallback_ssid_ == open_ssid;
  size_t slots = 0;
  if (!open_ssid.empty())
    slots++;
  if (!this->fallback_ssid_.empty() && !same)
    slots++;
  if (slots == 0)
    return;  // nichts zu tun: kein offenes Netz und kein Fallback konfiguriert

  wc->init_sta(slots);

  if (!open_ssid.empty()) {
    wifi::WiFiAP ap;
    ap.set_ssid(open_ssid);
    // Kein Passwort gesetzt = offenes Netz. ESPHome setzt fuer passwortlose APs
    // threshold.authmode = AUTH_OPEN, min_auth_mode greift hier also nicht.
    ap.set_priority(10);
    wc->add_sta(ap);
    ESP_LOGI(TAG, "Using open '%s'", open_ssid.c_str());
  }

  if (!this->fallback_ssid_.empty() && !same) {
    wifi::WiFiAP fb;
    fb.set_ssid(this->fallback_ssid_);
    if (!this->fallback_password_.empty())
      fb.set_password(this->fallback_password_);
    fb.set_priority(0);
    wc->add_sta(fb);
    ESP_LOGI(TAG, "Fallback: '%s'%s", this->fallback_ssid_.c_str(),
             this->fallback_password_.empty() ? " (offen)" : " (verschluesselt)");
  }
}

void OpenWifiScan::force_reconnect_() {
  auto *wc = wifi::global_wifi_component;
  if (wc == nullptr)
    return;
  // Exakt wie im erprobten ow_prefer() aus waveshare/open_wifi_join.h - nicht
  // mehr und nicht weniger.
  //
  // Hier stand zwischenzeitlich zusaetzlich ein WiFi.disconnect(). Das war
  // dazuerfunden und hat am 10.08.2026 ein Board dauerhaft aus dem Netz
  // geworfen: der Abriss kam aus einem MQTT-Callback, der Verbindungsaufbau
  // lief ins Leere, und danach war weder Ping noch OTA moeglich - es half nur
  // das USB-Kabel. Wo ein Wechsel wirklich erzwungen werden muss, tut das der
  // ausdrueckliche App.safe_reboot() im MQTT-Handler der YAML, sichtbar an
  // der Stelle, an der er gewollt ist.
  wc->disable();
  wc->enable();
}

void OpenWifiScan::setup() {
  // Schalterzustand aus dem Flash holen, bevor entschieden wird.
  this->pref_ = global_preferences->make_preference<bool>(fnv1_hash("open_wifi_enabled"));
  bool stored = true;
  if (this->pref_.load(&stored)) {
    this->enabled_ = stored;
    ESP_LOGI(TAG, "Schalter aus Flash: offene Netze %s",
             this->enabled_ ? "aktiviert" : "deaktiviert");
  }
  if (!this->enabled_) {
    // Wartungsfenster beginnt jetzt - der Zaehler laeuft ab dem Boot.
    this->disabled_since_ = millis();
    ESP_LOGI(TAG, "Wartungsfenster: faellt in %u s auf 'offene Netze' zurueck",
             (unsigned) (this->disable_timeout_ms_ / 1000));
  }

  ESP_LOGI(TAG, "Scanning…");
  int rssi = -127;
  std::string best = this->enabled_ ? this->find_best_open_(&rssi) : std::string();

  if (best.empty()) {
    // Nichts anfassen: die vom Codegen eingetragene Liste (das Fallback)
    // bleibt unveraendert bestehen.
    ESP_LOGI(TAG, "No usable open network — keeping configured networks");
    return;
  }
  ESP_LOGI(TAG, "Best open '%s' RSSI=%d", best.c_str(), rssi);
  this->apply_(best);
}

void OpenWifiScan::loop() {
  // Der Schalter ist eine befristete Wartungsklappe, kein Dauerzustand: das
  // gewuenschte Verhalten ist "immer das beste offene Netz". Vergisst jemand,
  // {"ENABLE":1} nachzuschicken, holt sich das Board den Zustand selbst zurueck.
  if (this->enabled_ || this->disable_timeout_ms_ == 0)
    return;
  if (millis() - this->disabled_since_ < this->disable_timeout_ms_)
    return;

  ESP_LOGI(TAG, "Wartungsfenster abgelaufen — zurueck auf offene Netze");
  // Nur EINMAL ausloesen: set_enabled() scannt blockierend und startet danach
  // ggf. neu. Ohne dieses Zuruecksetzen liefe die Bedingung bis zum Neustart
  // in jedem loop()-Durchlauf erneut an.
  this->disabled_since_ = 0;
  // Ueber defer() statt direkt: der blockierende Scan gehoert nicht in den
  // Hauptloop-Aufruf selbst.
  this->defer([this]() { this->set_enabled(true); });
}

void OpenWifiScan::rescan() {
  if (!this->enabled_) {
    ESP_LOGI(TAG, "Offene Netze deaktiviert — Scan uebersprungen");
    return;
  }
  int rssi = -127;
  std::string best = this->find_best_open_(&rssi);
  if (best.empty()) {
    ESP_LOGI(TAG, "Kein brauchbares offenes Netz gefunden");
    return;
  }

  const std::string have = this->current_ssid();
  this->apply_(best);

  // Nur wenn sich das Ziel wirklich unterscheidet, den Reconnect erzwingen.
  if (have != best) {
    ESP_LOGI(TAG, "Wechsel '%s' -> '%s'", have.c_str(), best.c_str());
    this->bad_since_ = 0;
    this->force_reconnect_();
  }
}

void OpenWifiScan::set_enabled(bool enabled) {
  this->enabled_ = enabled;
  // Sofort persistieren: der Aufrufer startet gleich neu, damit der Wechsel
  // sicher greift. Ohne das waere der Schalter nach dem Neustart wieder "an".
  this->pref_.save(&this->enabled_);
  global_preferences->sync();
  ESP_LOGI(TAG, "Offenes WLAN %s (im Flash gesichert)",
           enabled ? "aktiviert" : "deaktiviert");

  if (enabled) {
    this->disabled_since_ = 0;
    this->rescan();
    return;
  }

  // Ablauf-Uhr auch ohne Neustart starten.
  this->disabled_since_ = millis();

  // Zurueck auf das Fallback und, falls wir gerade an einem offenen Netz
  // haengen, sofort umschalten.
  const std::string have = this->current_ssid();
  this->apply_("");
  if (have != this->fallback_ssid_) {
    this->bad_since_ = 0;
    this->force_reconnect_();
  }
}

bool OpenWifiScan::watchdog(bool mqtt_connected, uint32_t timeout_ms) {
  if (this->preferred_.empty())
    return false;
  if (this->current_ssid() != this->preferred_) {
    this->bad_since_ = 0;
    return false;
  }
  if (mqtt_connected) {
    this->bad_since_ = 0;
    return false;
  }

  const uint32_t now = millis();
  if (this->bad_since_ == 0) {
    this->bad_since_ = now;
    return false;
  }
  if (now - this->bad_since_ < timeout_ms)
    return false;

  this->blacklist_add_(this->preferred_);
  this->bad_since_ = 0;
  this->apply_("");
  this->force_reconnect_();
  return true;
}

void OpenWifiScan::dump_config() {
  ESP_LOGCONFIG(TAG, "Open WiFi Scan:");
  ESP_LOGCONFIG(TAG, "  Enabled: %s", YESNO(this->enabled_));
  ESP_LOGCONFIG(TAG, "  Survey: %s", YESNO(this->survey_));
  ESP_LOGCONFIG(TAG, "  Fallback SSID: %s%s", this->fallback_ssid_.c_str(),
                this->fallback_password_.empty() ? " (offen)" : " (verschluesselt)");
  ESP_LOGCONFIG(TAG, "  Blocked SSIDs: %u", (unsigned) this->blocklist_.size());
}

}  // namespace open_wifi
}  // namespace esphome
