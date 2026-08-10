#pragma once

#include "esphome/core/component.h"
#include "esphome/core/preferences.h"

#include <cstdint>
#include <string>
#include <vector>

namespace esphome {
namespace open_wifi {

// Scannt vor dem Verbindungsaufbau nach offenen (passwortfreien) Netzen und
// stellt das staerkste der ESPHome-Netzwerkliste voran. Findet sich keins,
// bleibt es bei den unter `wifi: networks:` konfigurierten Netzen.
//
// Diese Komponente ist der EINE Mechanismus fuer alle ESP8266-Boards hier
// (kyrein9a_esp8266, gassensor-esp8266). Bewusst keine zweite Variante per
// `includes:` daneben: per includes eingebundene Components werden nie
// registriert, ihr setup() laeuft nie - und zwei Wege fuer dieselbe Aufgabe
// heisst, jede Aenderung zweimal machen zu muessen.
//
// Laufzeit-API (aus ESPHome-Lambdas heraus aufrufbar, z.B. per MQTT-Kommando):
//   set_enabled(false)  -> zurueck auf das Fallback-Netz
//   rescan()            -> sofort neu suchen und anwenden
//   watchdog(mqtt_ok, ms) -> offenes Netz ohne Broker-Zugang verwerfen
class OpenWifiScan : public Component {
 public:
  // Nach der Hardware (800), aber vor der WiFiComponent (300): die Liste muss
  // stehen, bevor ESPHome sich zu verbinden versucht.
  float get_setup_priority() const override { return 350.0f; }

  void setup() override;
  void loop() override;
  void dump_config() override;

  void set_survey(bool survey) { this->survey_ = survey; }
  // Survey-Entscheidung per MQTT dokumentieren. Topic leer = Report aus.
  void set_report_topic(const std::string &topic) { this->report_topic_ = topic; }
  void set_report_delay(uint32_t ms) { this->report_delay_ms_ = ms; }
  void set_fallback_ssid(const std::string &ssid) { this->fallback_ssid_ = ssid; }
  // Fallback darf verschluesselt sein. Ohne das liesse sich als Rueckfallebene
  // nur ein weiteres offenes Netz angeben - genau die Bauart, die einen bei
  // einem abgeschotteten Gast-WLAN endgueltig aussperrt.
  void set_fallback_password(const std::string &pw) { this->fallback_password_ = pw; }
  void add_blocked_ssid(const std::string &ssid) { this->blocklist_.push_back(ssid); }
  // Nach dieser Zeit faellt ein per MQTT gesetztes "aus" von selbst wieder auf
  // "an" zurueck. 0 schaltet den Ablauf ab (dauerhafter Schalter).
  void set_disable_timeout(uint32_t ms) { this->disable_timeout_ms_ = ms; }

  // ── Laufzeit ──────────────────────────────────────────────────────────────
  // Offene Netze bevorzugen an/aus. false wendet sofort das Fallback an.
  void set_enabled(bool enabled);
  bool enabled() const { return this->enabled_; }

  // Neu suchen und das Ergebnis anwenden.
  void rescan();

  // Haengt das Board am offenen AP, ohne dass MQTT durchkommt (Captive Portal,
  // Geraete-AP, abgeschottetes Subnetz), wird die SSID nach timeout_ms auf die
  // RAM-Blacklist gesetzt und das Fallback uebernimmt. Gibt true zurueck, wenn
  // umgeschaltet wurde. Ersetzt eine statische Blocklist: die muesste man
  // pflegen, das hier merkt es selbst.
  bool watchdog(bool mqtt_connected, uint32_t timeout_ms);

  // Aktuell verbundene SSID ("" wenn nicht verbunden).
  std::string current_ssid() const;

 protected:
  bool is_blocked_(const std::string &ssid) const;
  // Espressif-Default-SoftAPs und ESPHome-Fallback-APs haben nie einen Uplink.
  static bool is_device_ap_(const std::string &ssid);
  // Bester offener AP; "" wenn keiner brauchbar ist.
  std::string find_best_open_(int *rssi_out);
  // Survey-Puffer nach report_delay als Retained-Nachricht rausgeben.
  void try_report_();
  bool publish_survey_();
  // STA-Liste neu bauen: offener AP zuerst, danach das Fallback.
  void apply_(const std::string &open_ssid);
  void blacklist_add_(const std::string &ssid);
  // Assoziation wirklich loesen, damit ESPHome die neue Liste auswertet.
  void force_reconnect_();

  // Ein Eintrag der Survey: alles, was die Entscheidung begruendet.
  struct SurveyEntry {
    std::string ssid;
    int rssi{0};
    uint8_t channel{0};
    bool open{false};
    const char *why{nullptr};  // "best", "open", "enc", "devap", "blocked"
  };

  bool survey_{true};
  std::string fallback_ssid_;
  std::string fallback_password_;
  std::vector<std::string> blocklist_;

  bool enabled_{true};
  // Der Schalter liegt im Flash, nicht nur im RAM.
  //
  // Grund: das Umschalten per MQTT wirkt auf dem ESP8266 nur zuverlaessig ueber
  // einen Neustart - disable()/enable() loest die bestehende Assoziation nicht.
  // Laege der Schalter im RAM, waere er nach genau diesem Neustart wieder auf
  // "an", das Board naehme sofort wieder das staerkste offene Netz und das
  // Kommando bliebe folgenlos. Die Blacklist bleibt dagegen bewusst fluechtig:
  // sie ist eine Beobachtung, kein Wunsch des Betreibers.
  ESPPreferenceObject pref_;
  // Ablauf des Schalters. Der Zaehler laeuft ab dem Boot bzw. ab dem
  // Umschalten - nach einem Neustart also von vorn, was genau gewollt ist:
  // das Wartungsfenster beginnt, wenn das Board auf dem Fallback ankommt.
  uint32_t disable_timeout_ms_{600000};
  uint32_t disabled_since_{0};

  // Survey-Report. Der Puffer wird nach dem Publish NICHT freigegeben: der
  // naechste Scan ueberschreibt die Eintraege und die String-Buffer werden
  // dabei wiederverwendet (kein Alloc-Churn auf dem ESP8266-Heap). Der
  // High-Water-Mark bleibt liegen, bis er gebraucht wird - "Cache statt
  // Freigeben" auf einem System ohne Garbage Collector.
  std::vector<SurveyEntry> survey_buf_;
  bool report_pending_{false};
  uint32_t survey_at_{0};
  uint32_t report_delay_ms_{10000};
  std::string report_topic_;
  int scanned_{0};
  int hidden_{0};
  std::string chosen_;
  int chosen_rssi_{-127};
  // Aktuell bevorzugter offener AP ("" = nur Fallback).
  std::string preferred_;
  bool applied_{false};
  // millis() seit MQTT weg (0 = alles gut).
  uint32_t bad_since_{0};
};

}  // namespace open_wifi
}  // namespace esphome
