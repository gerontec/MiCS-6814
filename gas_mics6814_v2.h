#pragma once
#include "esphome.h"
#include <Wire.h>
#include <math.h>

// ─────────────────────────────────────────────────────────────────────────────
//  gas_mics6814_v2 — Seeed Grove Multichannel Gas Sensor v1 (MiCS-6814)
//                    mit ATmega168-Co-Prozessor, Co-Firmware Version 2
//
//  Portiert aus Seeed-Studio/Mutichannel_Gas_Sensor (MIT), Zweig `2 == __version`
//  in calcGas(). Die Originalbibliothek laesst sich nicht direkt verwenden: ihr
//  Header bricht auf allem ausser AVR/SAMD mit #error "Architecture not matched"
//  ab. Uebernommen sind daher Protokoll und Kurven, nicht der Code.
//
//  Gegenprobe am Geraet: die Originalfirmware meldete beim Booten
//  "Firmware Version = 2" — das ist getVersion(), also ein echter I2C-Read des
//  ATmega-EEPROMs mit Vergleich auf 1126. Der Bus stand also schon vorher.
//
//  Pins: die Bibliothek ruft Wire.begin() ohne Argumente; unter Arduino-ESP8266
//  sind das SDA=GPIO4, SCL=GPIO5. Hier explizit gesetzt, damit es nicht von
//  einer Core-Version abhaengt.
//
//  Bewusst KEINE esphome i2c:-Komponente: die wuerde Wire ein zweites Mal
//  initialisieren. Hier gibt es genau einen Bus-Besitzer.
// ─────────────────────────────────────────────────────────────────────────────

static const uint8_t MICS_ADDR = 0x04;  // DEFAULT_I2C_ADDR
static const uint8_t MICS_SDA = 4;      // GPIO4 / D2
static const uint8_t MICS_SCL = 5;      // GPIO5 / D1

// Registerkommandos der Co-Prozessor-Firmware v2
static const uint8_t CH_VALUE_NH3 = 1;
static const uint8_t CH_VALUE_CO = 2;
static const uint8_t CH_VALUE_NO2 = 3;
static const uint8_t CMD_READ_EEPROM = 6;
static const uint8_t CMD_CONTROL_LED = 10;
static const uint8_t CMD_CONTROL_PWR = 11;

// EEPROM-Adressen der kalibrierten R0-ADC-Werte
static const uint8_t ADDR_IS_SET = 0;
static const uint8_t ADDR_USER_ADC_NH3 = 8;
static const uint8_t ADDR_USER_ADC_CO = 10;
static const uint8_t ADDR_USER_ADC_NO2 = 12;

struct MicsReading {
  bool ok{false};
  uint16_t adc_nh3{0}, adc_co{0}, adc_no2{0};  // aktuelle Rohwerte (An)
  uint16_t r0_nh3{0}, r0_co{0}, r0_no2{0};     // kalibrierte Basis (A0)
  float ratio_nh3{NAN}, ratio_co{NAN}, ratio_no2{NAN};
  float nh3{NAN}, co{NAN}, no2{NAN};
  float c3h8{NAN}, c4h10{NAN}, ch4{NAN}, h2{NAN}, c2h5oh{NAN};
};

static MicsReading mics_last;

inline void mics_write2_(uint8_t a, uint8_t b) {
  Wire.beginTransmission(MICS_ADDR);
  Wire.write(a);
  Wire.write(b);
  Wire.endTransmission();
}

// Ein-Byte-Kommando, 2 Byte Antwort (big endian).
//
// Das Original schleift bei cnt==0 per `goto START` endlos weiter. Hier statt
// dessen ein Fehlerrueckgabewert: eine haengende Endlosschleife im ESPHome-Loop
// wuerde den Watchdog ausloesen und das Geraet reihum neu starten — genau die
// Falle, in der die Originalfirmware mit ihrem blockierenden MQTT-reconnect()
// steckte.
inline bool mics_read16_(uint8_t reg, uint16_t &out) {
  Wire.beginTransmission(MICS_ADDR);
  Wire.write(reg);
  if (Wire.endTransmission() != 0)
    return false;
  delay(2);
  if (Wire.requestFrom((uint8_t) MICS_ADDR, (uint8_t) 2) != 2)
    return false;
  uint16_t hi = Wire.read();
  uint16_t lo = Wire.read();
  out = (hi << 8) | lo;
  return true;
}

// Zwei-Byte-Kommando (Kommando + Adresse), 2 Byte Antwort.
inline bool mics_read16_(uint8_t reg, uint8_t arg, uint16_t &out) {
  Wire.beginTransmission(MICS_ADDR);
  Wire.write(reg);
  Wire.write(arg);
  if (Wire.endTransmission() != 0)
    return false;
  delay(2);
  if (Wire.requestFrom((uint8_t) MICS_ADDR, (uint8_t) 2) != 2)
    return false;
  uint16_t hi = Wire.read();
  uint16_t lo = Wire.read();
  out = (hi << 8) | lo;
  return true;
}

inline void mics_led(bool on) { mics_write2_(CMD_CONTROL_LED, on ? 1 : 0); }
inline void mics_power_on() { mics_write2_(CMD_CONTROL_PWR, 1); }

// true, wenn der Co-Prozessor mit Firmware v2 antwortet (EEPROM[0] == 1126).
inline bool mics_is_v2() {
  uint16_t v = 0;
  return mics_read16_(CMD_READ_EEPROM, ADDR_IS_SET, v) && v == 1126;
}

// Kein Wire.begin() hier: den Bus setzt die esphome i2c:-Komponente auf
// (setup_priority BUS, laeuft lange vor diesem on_boot mit Prioritaet 250).
// Ein zweites Wire.begin() wuerde die Pins erneut umkonfigurieren.
inline void mics_begin() {
  delay(10);
  bool v2 = mics_is_v2();
  ESP_LOGI("mics6814", "Bus SDA=%u SCL=%u, Adresse 0x%02X, Co-Firmware %s", MICS_SDA, MICS_SCL,
           MICS_ADDR, v2 ? "v2 (erkannt)" : "NICHT erkannt");
  mics_power_on();  // Heizer an - entspricht powerOn() der Originalfirmware
}

// Bus absuchen; nuetzlich, falls der Sensor doch auf einer anderen Adresse sitzt.
inline void mics_scan() {
  int found = 0;
  for (uint8_t a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      ESP_LOGI("mics6814", "  I2C-Geraet auf 0x%02X", a);
      found++;
    }
  }
  ESP_LOGI("mics6814", "I2C-Scan: %d Geraet(e)", found);
}

// Eine vollstaendige Messung. Kurven und Verhaeltnisformel 1:1 aus calcGas().
inline MicsReading mics_measure() {
  MicsReading r;

  mics_led(true);  // wie im Original: LED an waehrend der Messung

  bool ok = true;
  ok &= mics_read16_(CMD_READ_EEPROM, ADDR_USER_ADC_NH3, r.r0_nh3);
  ok &= mics_read16_(CMD_READ_EEPROM, ADDR_USER_ADC_CO, r.r0_co);
  ok &= mics_read16_(CMD_READ_EEPROM, ADDR_USER_ADC_NO2, r.r0_no2);
  ok &= mics_read16_(CH_VALUE_NH3, r.adc_nh3);
  ok &= mics_read16_(CH_VALUE_CO, r.adc_co);
  ok &= mics_read16_(CH_VALUE_NO2, r.adc_no2);

  mics_led(false);

  if (!ok) {
    ESP_LOGW("mics6814", "I2C-Lesefehler");
    return r;
  }

  // Division durch Null vermeiden: A0 == 0 (unkalibriert) oder An == 1023
  // (Kanal am Anschlag) machen das Verhaeltnis undefiniert.
  auto ratio = [](uint16_t an, uint16_t a0) -> float {
    if (a0 == 0 || a0 >= 1023 || an >= 1023)
      return NAN;
    return (float) an / (float) a0 * (1023.0f - (float) a0) / (1023.0f - (float) an);
  };

  r.ratio_nh3 = ratio(r.adc_nh3, r.r0_nh3);
  r.ratio_co = ratio(r.adc_co, r.r0_co);
  r.ratio_no2 = ratio(r.adc_no2, r.r0_no2);

  // ratio0 = NH3-Kanal, ratio1 = CO-Kanal (RED), ratio2 = NO2-Kanal (OX)
  r.nh3 = powf(r.ratio_nh3, -1.67f) / 1.47f;
  r.co = powf(r.ratio_co, -1.179f) * 4.385f;
  r.no2 = powf(r.ratio_no2, 1.007f) / 6.855f;
  r.c3h8 = powf(r.ratio_nh3, -2.518f) * 570.164f;
  r.c4h10 = powf(r.ratio_nh3, -2.138f) * 398.107f;
  r.ch4 = powf(r.ratio_co, -4.363f) * 630.957f;
  r.h2 = powf(r.ratio_co, -1.8f) * 0.73f;
  r.c2h5oh = powf(r.ratio_co, -1.552f) * 1.622f;

  r.ok = true;
  mics_last = r;

  ESP_LOGI("mics6814", "ADC An=[%u,%u,%u] A0=[%u,%u,%u] ratio=[%.3f,%.3f,%.3f]", r.adc_nh3,
           r.adc_co, r.adc_no2, r.r0_nh3, r.r0_co, r.r0_no2, r.ratio_nh3, r.ratio_co, r.ratio_no2);
  ESP_LOGI("mics6814", "NH3=%.2f CO=%.2f NO2=%.3f C3H8=%.1f C4H10=%.1f CH4=%.1f H2=%.2f C2H5OH=%.2f ppm",
           r.nh3, r.co, r.no2, r.c3h8, r.c4h10, r.ch4, r.h2, r.c2h5oh);
  return r;
}
