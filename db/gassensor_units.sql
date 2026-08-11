-- ═══════════════════════════════════════════════════════════════════════════
--  wagodb.gassensor — Erweiterung auf UBA-Einheiten + Referenzstation
--
--  Das Umweltbundesamt fuehrt NO2/NH3 in µg/m³ und CO in mg/m³. Der Sensor
--  rechnet intern in ppm. Beides steht jetzt nebeneinander: ppm bleibt der
--  Rohwert (aus adc_*/r0_* jederzeit nachrechenbar), die *_ugm3/*_mgm3-Spalten
--  sind die vergleichbare Groesse.
--
--  Umrechnung bei 20 °C und 1013 hPa (molares Volumen 24,055 l/mol) - das sind
--  die Bezugsbedingungen der EU-Luftqualitaetsrichtlinie fuer gasfoermige
--  Schadstoffe, also genau die, in denen die UBA-Werte vorliegen:
--      µg/m³ = ppm × M / 24,055 × 1000
--
--  Bewusst KEINE generierten Spalten: in dieselbe Tabelle schreibt auch der
--  UBA-Abgleich (device='UBA-DEBY109'), und der liefert µg/m³ direkt ohne
--  ppm-Rohwert. Eine generierte Spalte waere dort nicht beschreibbar.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE gassensor
  ADD COLUMN source     VARCHAR(16) NOT NULL DEFAULT 'sensor' AFTER device,
  ADD COLUMN no2_ugm3   FLOAT NULL AFTER c2h5oh,
  ADD COLUMN nh3_ugm3   FLOAT NULL AFTER no2_ugm3,
  ADD COLUMN co_mgm3    FLOAT NULL AFTER nh3_ugm3,
  ADD COLUMN c3h8_mgm3  FLOAT NULL AFTER co_mgm3,
  ADD COLUMN c4h10_mgm3 FLOAT NULL AFTER c3h8_mgm3,
  ADD COLUMN ch4_mgm3   FLOAT NULL AFTER c4h10_mgm3,
  ADD COLUMN h2_mgm3    FLOAT NULL AFTER ch4_mgm3,
  ADD COLUMN c2h5oh_mgm3 FLOAT NULL AFTER h2_mgm3,
  ADD KEY idx_source_ts (source, ts);
