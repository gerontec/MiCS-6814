-- ═══════════════════════════════════════════════════════════════════════════
--  wagodb.gassensor — 15-Minuten-Reihe des MiCS-6814-Gassensors
--
--  Quelle: MQTT-Topic gassensor/info (retained JSON), geschrieben von
--          gassensor_logger.py auf dem Pi kellertreppe, cron alle 15 min.
--
--  ts wird in LOKALER Zeit gespeichert - so wie die uebrigen wagodb-Tabellen.
--  Grafana liest MySQL-DATETIME als UTC, im Panel deshalb CONVERT_TZ nutzen
--  und den Zeitfilter ohne das $__timeFilter-Makro schreiben.
--
--  Warum die Rohwerte (adc_*, r0_*) mitlaufen: die ppm-Werte sind reine
--  Potenzkurven auf dem Verhaeltnis An/A0. Faellt spaeter auf, dass die
--  Werkskalibrierung des Sensors nicht passt, lassen sich alle ppm-Werte aus
--  adc_* und r0_* rueckwirkend neu rechnen - aus ppm allein ginge das nicht.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS gassensor (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  ts         DATETIME     NOT NULL,
  device     VARCHAR(32)  NOT NULL DEFAULT 'gassensor-esp8266',

  -- Zustand der Messung. stale=1 heisst: es lag nur eine alte retained
  -- Nachricht vor (uptime_ms unveraendert seit der letzten Zeile), die
  -- Gasspalten sind dann NULL statt eines fortgeschriebenen Altwerts.
  online     TINYINT(1)   NULL,
  stale      TINYINT(1)   NOT NULL DEFAULT 0,

  -- Gaskonzentrationen in ppm
  nh3        FLOAT NULL,
  co         FLOAT NULL,
  no2        FLOAT NULL,
  c3h8       FLOAT NULL,
  c4h10      FLOAT NULL,
  ch4        FLOAT NULL,
  h2         FLOAT NULL,
  c2h5oh     FLOAT NULL,

  -- Rohwerte: aktueller ADC je Kanal und die kalibrierte Basis R0
  adc_nh3    SMALLINT UNSIGNED NULL,
  adc_co     SMALLINT UNSIGNED NULL,
  adc_no2    SMALLINT UNSIGNED NULL,
  r0_nh3     SMALLINT UNSIGNED NULL,
  r0_co      SMALLINT UNSIGNED NULL,
  r0_no2     SMALLINT UNSIGNED NULL,

  -- Betriebsdaten
  rssi       SMALLINT     NULL,
  ssid       VARCHAR(32)  NULL,
  ip         VARCHAR(45)  NULL,
  uptime_ms  BIGINT UNSIGNED NULL,
  fw         VARCHAR(16)  NULL,

  PRIMARY KEY (id),
  -- Schuetzt gegen Doppeleintraege, wenn ein cron-Lauf verspaetet nachzieht.
  UNIQUE KEY uniq_dev_ts (device, ts),
  KEY idx_ts (ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
