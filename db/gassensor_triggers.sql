-- ═══════════════════════════════════════════════════════════════════════════
--  wagodb.gassensor — Umrechnung ppm -> UBA-Einheiten in der Datenbank
--
--  Vorher rechnete gassensor_logger.py die Einheiten aus. Das war die falsche
--  Stelle: die Umrechnung ist eine Eigenschaft der Tabelle, nicht eines
--  einzelnen Schreibers. Ein zweiter Schreiber (oder ein manuelles INSERT beim
--  Nachtragen) haette die Spalten leer gelassen oder mit einem abweichenden
--  Faktor gefuellt, ohne dass es auffaellt.
--
--  WARUM TRIGGER UND KEINE GENERIERTEN SPALTEN
--  Generierte Spalten waeren die naheliegende Wahl, sind hier aber nicht
--  moeglich: in dieselbe Tabelle schreibt der UBA-Abgleich
--  (device='UBA-DEBY109'), und der liefert no2_ugm3 direkt aus der API, ganz
--  ohne ppm-Rohwert. Eine generierte Spalte waere fuer ihn nicht beschreibbar.
--  Die Trigger rechnen deshalb nur dann, wenn ein ppm-Wert vorliegt, und
--  lassen einen direkt gelieferten Messwert unangetastet.
--
--  UMRECHNUNG bei 20 °C und 1013 hPa (molares Volumen 24,055 l/mol) - die
--  Bezugsbedingungen der EU-Luftqualitaetsrichtlinie fuer gasfoermige
--  Schadstoffe und damit die der UBA-Werte:
--        mg/m³ = ppm × M / 24,055
--        µg/m³ = ppm × M / 24,055 × 1000
--  Die Molmassen stehen im Klartext in der Formel, damit jeder Wert ohne
--  Nachschlagen pruefbar ist.
--
--  BEIDE Richtungen noetig: BEFORE INSERT deckt den Normalfall ab, BEFORE
--  UPDATE den Upsert-Zweig des Loggers (ON DUPLICATE KEY UPDATE), der eine
--  bestehende Zeile im selben 15-min-Slot korrigiert.
-- ═══════════════════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS gassensor_units_bi;
DROP TRIGGER IF EXISTS gassensor_units_bu;

DELIMITER $$

CREATE TRIGGER gassensor_units_bi BEFORE INSERT ON gassensor
FOR EACH ROW
BEGIN
  -- Nur eigene Sensorzeilen ableiten. Fuer source='uba' kommt no2_ugm3 direkt
  -- aus der API und hat gar keinen ppm-Rohwert - der Trigger muss die Finger
  -- davon lassen.
  --
  -- Innerhalb des Zweigs bewusst ohne IF ... IS NOT NULL: in SQL ergibt jede
  -- Rechnung mit NULL wieder NULL. Damit raeumt eine Zeile, die spaeter zur
  -- stale-Zeile wird (ppm faellt auf NULL), ihre Einheiten-Spalten von selbst
  -- mit ab. Mit einer IS-NOT-NULL-Bedingung bliebe dort der alte Wert stehen
  -- und behauptete eine Messung, die es nicht mehr gibt.
  IF NEW.source = 'sensor' THEN
    SET NEW.no2_ugm3    = NEW.no2    * 46.0055 / 24.055 * 1000;
    SET NEW.nh3_ugm3    = NEW.nh3    * 17.031  / 24.055 * 1000;
    SET NEW.co_mgm3     = NEW.co     * 28.010  / 24.055;
    SET NEW.c3h8_mgm3   = NEW.c3h8   * 44.096  / 24.055;
    SET NEW.c4h10_mgm3  = NEW.c4h10  * 58.122  / 24.055;
    SET NEW.ch4_mgm3    = NEW.ch4    * 16.043  / 24.055;
    SET NEW.h2_mgm3     = NEW.h2     * 2.016   / 24.055;
    SET NEW.c2h5oh_mgm3 = NEW.c2h5oh * 46.068  / 24.055;
  END IF;
END$$

CREATE TRIGGER gassensor_units_bu BEFORE UPDATE ON gassensor
FOR EACH ROW
BEGIN
  -- Nur eigene Sensorzeilen ableiten. Fuer source='uba' kommt no2_ugm3 direkt
  -- aus der API und hat gar keinen ppm-Rohwert - der Trigger muss die Finger
  -- davon lassen.
  --
  -- Innerhalb des Zweigs bewusst ohne IF ... IS NOT NULL: in SQL ergibt jede
  -- Rechnung mit NULL wieder NULL. Damit raeumt eine Zeile, die spaeter zur
  -- stale-Zeile wird (ppm faellt auf NULL), ihre Einheiten-Spalten von selbst
  -- mit ab. Mit einer IS-NOT-NULL-Bedingung bliebe dort der alte Wert stehen
  -- und behauptete eine Messung, die es nicht mehr gibt.
  IF NEW.source = 'sensor' THEN
    SET NEW.no2_ugm3    = NEW.no2    * 46.0055 / 24.055 * 1000;
    SET NEW.nh3_ugm3    = NEW.nh3    * 17.031  / 24.055 * 1000;
    SET NEW.co_mgm3     = NEW.co     * 28.010  / 24.055;
    SET NEW.c3h8_mgm3   = NEW.c3h8   * 44.096  / 24.055;
    SET NEW.c4h10_mgm3  = NEW.c4h10  * 58.122  / 24.055;
    SET NEW.ch4_mgm3    = NEW.ch4    * 16.043  / 24.055;
    SET NEW.h2_mgm3     = NEW.h2     * 2.016   / 24.055;
    SET NEW.c2h5oh_mgm3 = NEW.c2h5oh * 46.068  / 24.055;
  END IF;
END$$

DELIMITER ;

-- Bestandszeilen nachziehen. Trigger wirken nur auf neue Schreibvorgaenge;
-- ohne das haetten alte Zeilen weiterhin die vom Logger gerechneten Werte
-- (oder gar keine). Das UPDATE loest den BEFORE-UPDATE-Trigger aus, der die
-- eigentliche Rechnung macht - deshalb genuegt hier eine Scheinzuweisung.
UPDATE gassensor SET no2 = no2 WHERE no2 IS NOT NULL;
