-- ═══════════════════════════════════════════════════════════════════════════
--  wagodb.gassensor — Kalibrierung des MiCS-6814, rechnerisch statt im Chip
--
--  WARUM NICHT IN DEN SENSOR SCHREIBEN
--  Der Co-Prozessor koennte es: CMD_SET_R0_ADC (7) legt eine eigene R0-Basis in
--  seinem EEPROM ab, die Werkswerte blieben daneben erhalten. Trotzdem gehoert
--  die Kalibrierung hierher. Ein EEPROM-Schreibvorgang wirkt nur nach vorn, ist
--  am Geraet nicht nachvollziehbar und macht jede aeltere Zeile der Reihe
--  unvergleichbar mit jeder neueren. Die Tabellen unten wirken dagegen
--  rueckwirkend auf den gesamten Bestand, sind versioniert, und ein besserer
--  Datensatz ersetzt sie mit einem UPDATE - ohne den Sensor anzufassen.
--  Genau dafuer fuehrt gassensor die Rohspalten adc_*/r0_* mit.
--
--  ZWEI SCHRITTE, DIE MAN NICHT VERWECHSELN DARF
--
--  1. R0-BASISLINIE (physikalisch, je KANAL). R0 ist der ADC-Wert des Kanals in
--     der Bezugsluft. Die Werkswerte passen fuer dieses Exemplar nicht: der
--     OX-Kanal steht bei ADC 739, das EEPROM behauptet 155 - ein Verhaeltnis
--     von 13,7 in laendlicher Hintergrundluft, was fuer einen resistiven
--     Sensor nicht plausibel ist. Daher R0 = Median des Ruhefensters.
--
--  2. NIVEAU-ANKER (empirisch, je GAS). k skaliert die jeweilige Seeed-Kurve
--     so, dass das Mittel des Ruhefensters auf einen belegten Referenzwert
--     faellt.
--
--  WARUM DER ANKER AM GAS HAENGT UND NICHT AM KANAL
--  Ein Kanal traegt mehrere Gase (NH3 -> NH3/C3H8/C4H10, RED -> CO/CH4/H2/
--  C2H5OH), aber jedes Gas hat seine EIGENE Potenzkurve mit eigenem Sockel.
--  Ein Anker am Kanal wuerde den NH3-Beleg an Propan und Butan weiterreichen,
--  fuer die es keinen gibt. Deshalb die Kindtabelle: ein Anker, ein Gas, eine
--  Quelle.
--
--  WAS DIESE KALIBRIERUNG NICHT LEISTET - BITTE VOR JEDER AUSWERTUNG LESEN
--  Der Anker richtet das Niveau, sonst nichts. Ein Vergleich der Bewegung
--  gegen die NO2-Referenz (Stundendifferenzen, 2026-08-10/11, n=20) ergab ueber
--  alle Zeitversaetze von -3 h bis +6 h Korrelationen zwischen -0,25 und +0,31,
--  bei einer Signifikanzschwelle von rund 0,42. Der Sensor hat den Gang der
--  Referenz also NICHT mitgemacht, auch nicht verzoegert. Das ist kein Defekt,
--  sondern Physik: der MiCS-6814 ist ab 0,05 ppm NO2 (~96 µg/m³) und ab 1 ppm
--  NH3 (~700 µg/m³) spezifiziert, gemessen wird Luft mit 2..6 µg/m³ NO2 und
--  rund 1,5 µg/m³ NH3 - zwei bis drei Groessenordnungen darunter. Der
--  nachtliche Anstieg des Rohsignals (ADC OX 590 -> 758 zwischen 19 und 04 Uhr)
--  ist Temperatur- und Feuchtegang.
--
--  Nach dem Ankern liegt das Rauschband bei +-0,30 µg/m³ (NO2) bzw. +-0,24
--  µg/m³ (NH3). Diese Zahlen sehen praezise aus und sind es nicht: sie
--  beschreiben die Streuung des Sensors, nicht die der Luft. Verwertbar ist der
--  Betrag der Reihe, nicht ihre Bewegung - und auch der nur unter der jeweils
--  in ref_source genannten Annahme.
--
--  NEU KALIBRIEREN
--  MiCS-Sensoren driften ueber Tage. Diese Epoche steht auf knapp 9 Stunden
--  Ruhefenster nach dem Einlaufen. Sobald mehrere volle Tage vorliegen: neue
--  Zeile in gassensor_cal einsetzen, in der alten valid_to nachtragen, Anker
--  neu rechnen. Die Views ziehen sofort nach, rueckwirkend und ohne
--  Datenverlust.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS gassensor_cal (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  device      VARCHAR(32)  NOT NULL DEFAULT 'gassensor-esp8266',

  -- Gueltigkeitsspanne der Epoche. valid_to NULL heisst "bis auf Weiteres";
  -- neue Messungen werden damit automatisch mitkalibriert.
  valid_from  DATETIME     NOT NULL,
  valid_to    DATETIME     NULL,

  -- Schritt 1: R0-Basislinie je Kanal, in ADC-Zaehlwerten wie adc_*/r0_*.
  r0_nh3      SMALLINT UNSIGNED NOT NULL,
  r0_co       SMALLINT UNSIGNED NOT NULL,
  r0_no2      SMALLINT UNSIGNED NOT NULL,

  -- Herkunft der Basislinie. Ohne diese Spalten ist sie eine Behauptung.
  win_from    DATETIME     NULL,
  win_to      DATETIME     NULL,
  note        VARCHAR(255) NULL,
  created     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (id),
  KEY idx_dev_from (device, valid_from)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Schritt 2: die Anker, einer je Gas ─────────────────────────────────────
--  Ohne Zeile hier bleibt ein Gas ungeankert. Das ist der Normalfall und kein
--  Mangel: fuer sechs der acht Gase gibt es in dieser Gegend schlicht keinen
--  belegbaren Referenzwert.
CREATE TABLE IF NOT EXISTS gassensor_cal_anchor (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  cal_id       INT UNSIGNED NOT NULL,
  gas          VARCHAR(8)   NOT NULL,   -- no2, nh3, co, c3h8, c4h10, ch4, h2, c2h5oh
  k            DOUBLE       NOT NULL,   -- Faktor auf die ppm-Kurve

  -- Der Beleg. ref_low/ref_high halten die Bandbreite der Quelle fest, damit
  -- die Unsicherheit des Ankers nicht in der Rundung verschwindet.
  ref_source   VARCHAR(255) NOT NULL,
  ref_value    FLOAT        NOT NULL,
  ref_unit     VARCHAR(12)  NOT NULL,
  ref_low      FLOAT        NULL,
  ref_high     FLOAT        NULL,
  sensor_value FLOAT        NULL,       -- Sensormittel im Fenster, vor dem Anker
  note         VARCHAR(400) NULL,

  PRIMARY KEY (id),
  UNIQUE KEY uniq_cal_gas (cal_id, gas),
  CONSTRAINT fk_anchor_cal FOREIGN KEY (cal_id) REFERENCES gassensor_cal (id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── Erste Epoche ───────────────────────────────────────────────────────────
--  valid_from liegt bewusst NICHT am Anfang der Reihe. Vor dem 10.08. 23:00
--  lief der Sensor ein (ADC OX 390 -> 730 in 14 Stunden). Diese R0-Basislinie
--  auf die Einlaufphase anzuwenden hiesse, eine Drift als Messwert auszugeben.
--  Die Einlaufzeilen bleiben deshalb unkalibriert - sie sind es auch.
INSERT INTO gassensor_cal
  (device, valid_from, valid_to, r0_nh3, r0_co, r0_no2, win_from, win_to, note)
SELECT 'gassensor-esp8266', '2026-08-10 23:00:00', NULL, 972, 1010, 739,
       '2026-08-10 23:00:00', '2026-08-11 08:15:00',
       'R0 = Median des Ruhefensters nach dem Einlaufen (n=38).'
WHERE NOT EXISTS (SELECT 1 FROM gassensor_cal
                  WHERE device='gassensor-esp8266' AND valid_from='2026-08-10 23:00:00');

-- ── Anker NO2: die Referenzstation, live aus derselben Tabelle ─────────────
INSERT INTO gassensor_cal_anchor
  (cal_id, gas, k, ref_source, ref_value, ref_unit, ref_low, ref_high, sensor_value, note)
SELECT c.id, 'no2', 0.013063,
       'UBA-Luftdaten, Station Andechs/Rothenfeld (DEBY109), laendlicher Hintergrund, 34,4 km; '
       'Stundenwerte im Ruhefenster',
       3.71, 'µg/m³', 3.0, 6.0, 284.33,
       'Annahme: gleiche Luft wie an der Referenzstation. Naeher gelegene Stationen '
       '(Kreuth 9,7 km, Sylvenstein 19,1 km) sind Depositionsmessstellen ohne Gaskonzentrationen; '
       'in Lenggries misst keine Netzstation. n=28.'
FROM gassensor_cal c
WHERE c.device='gassensor-esp8266' AND c.valid_from='2026-08-10 23:00:00'
  AND NOT EXISTS (SELECT 1 FROM gassensor_cal_anchor a WHERE a.cal_id=c.id AND a.gas='no2');

-- ── Anker NH3: Literaturwert, weil es keine Messreihe gibt ────────────────
--  Das UBA misst NH3 an DEBY109 nicht, und im UBA-Luftdatensatz kommt der Stoff
--  ueberhaupt nicht vor. Der Beleg stammt deshalb vom LfU Bayern, das seit 2011
--  NH3 im laendlichen Hintergrund an immissionsoekologischen
--  Dauerbeobachtungsstationen misst - und dabei nach Umgebungstyp trennt.
--  Jahresmittel 2011-2020:
--        naturnah / nur extensiv bewirtschaftet   0,5 .. 2,5 µg/m³
--        ueberwiegend Feldwirtschaft              2,0 .. 3,7 µg/m³
--        intensive Gruenlandbewirtschaftung       4,7 .. 6,3 µg/m³
--        verkehrsnah (Ansbach, Innenstadt)        3,7 .. 5,5 µg/m³
--
--  Gewaehlt ist die erste Klasse, Bandmitte 1,5 µg/m³: gesucht war ausdruecklich
--  ein Tag OHNE Guelleausbringung, also ohne die Duengespitzen, die das LfU als
--  Jahresgang beschreibt (Gruenlandumgebung im Mittel bis 8,2 µg/m³ im Fruehjahr
--  und 8,3 µg/m³ im November). Das LfU haelt fuer die duengefreie Zeit fest,
--  dass selbst in landwirtschaftlicher Umgebung unter 2 µg/m³ eingehalten
--  werden - die Wahl liegt also innerhalb dessen, was die Quelle fuer einen
--  unbelasteten Tag hergibt.
--
--  Die Bandbreite ist ehrlich gross: 0,5 statt 2,5 µg/m³ ergaebe ein k, das um
--  den Faktor 5 abweicht. ref_low/ref_high halten das fest.
INSERT INTO gassensor_cal_anchor
  (cal_id, gas, k, ref_source, ref_value, ref_unit, ref_low, ref_high, sensor_value, note)
SELECT c.id, 'nh3', 0.00275182,
       'LfU Bayern, Ammoniak-Immissionsmessungen an immissionsoekologischen '
       'Dauerbeobachtungsstationen, Jahresmittel 2011-2020, Klasse "naturnah oder nur '
       'extensiv bewirtschaftet" (0,5-2,5 µg/m³); gewaehlt: Bandmitte',
       1.5, 'µg/m³', 0.5, 2.5, 545.09,
       'Annahme laut Auftrag: Tag ohne Guelleaustrag, also ohne die Duengespitzen des '
       'LfU-Jahresgangs (Gruenland bis 8,2/8,3 µg/m³ im Fruehjahr bzw. November). '
       'Literaturwert, keine gleichzeitige Messung - schwaecher belegt als der NO2-Anker. n=28.'
FROM gassensor_cal c
WHERE c.device='gassensor-esp8266' AND c.valid_from='2026-08-10 23:00:00'
  AND NOT EXISTS (SELECT 1 FROM gassensor_cal_anchor a WHERE a.cal_id=c.id AND a.gas='nh3');

-- ── Anker C3H8: troposphaerischer Hintergrund aus der Literatur ───────────
--  Propan hat keinen Immissionsgrenzwert und wird in keinem Luftmessnetz der
--  Gegend gefuehrt. Belegbar ist nur der troposphaerische Hintergrund: an der
--  WMO-GAW-Station Monte Cimone (2165 m, Italien) lagen die Stundenmittel
--  2011-2023 im Winter bei 620..651 ppt und im Sommer bei 150..210 ppt.
--  Gewaehlt ist das Sommerband, Mitte 180 ppt - die Messung faellt in den
--  August.
--
--  ZWEI EINSCHRAENKUNGEN, die schwerer wiegen als beim NO2-Anker:
--
--  1. Monte Cimone ist eine Bergstation mit Anteil freier Troposphaere. Ein
--     Talstandort mit Ortschaft liegt darueber. 180 ppt ist damit eher eine
--     Untergrenze als ein Ortswert, und der Anker zieht die Reihe entsprechend
--     zu tief.
--  2. C3H8 und NH3 teilen sich den NH3-Kanal. Beide Kurven sind monotone
--     Umformungen DESSELBEN ADC-Werts (Exponent -1,67 gegen -2,518). Zwei
--     geankerte Gase auf einem Kanal ergeben zwei Zahlen, die genau eine
--     Messung enthalten - sie koennen einander nie widersprechen. Wer beide
--     Reihen nebeneinander plottet, sieht zweimal dieselbe Kurve.
--
--  Der Faktor betraegt rund 1:3,9 Millionen. Das ist kein Rechenfehler,
--  sondern die Entfernung zwischen dem spezifizierten Bereich der Kurve
--  (C3H8 ab etwa 1000 ppm) und der Wirklichkeit (0,00018 ppm).
INSERT INTO gassensor_cal_anchor
  (cal_id, gas, k, ref_source, ref_value, ref_unit, ref_low, ref_high, sensor_value, note)
SELECT c.id, 'c3h8', 2.59450047779e-07,
       'Mancinelli et al., Atmos. Chem. Phys. 26, 4105-4129, 2026 (doi:10.5194/acp-26-4105-2026): '
       'C3H8 an der WMO-GAW-Station '
       'Monte Cimone (2165 m), Stundenmittel 2011-2023, Sommerband 150-210 ppt; gewaehlt: Bandmitte',
       0.00018, 'ppm', 0.00015, 0.00021, 693.8,
       'Bergstation mit Anteil freier Troposphaere - fuer einen Talstandort eher Untergrenze. '
       'Teilt sich den ADC mit NH3: beide Reihen enthalten zusammen genau eine Messung. n=28.'
FROM gassensor_cal c
WHERE c.device='gassensor-esp8266' AND c.valid_from='2026-08-10 23:00:00'
  AND NOT EXISTS (SELECT 1 FROM gassensor_cal_anchor a WHERE a.cal_id=c.id AND a.gas='c3h8');

-- ── Anker C4H10: EMEP-Hintergrundstationen, gemessen statt modelliert ─────
--  Der beste Beleg der vier: keine Bergstation, keine Literaturklasse, sondern
--  Jahresmittel echter deutscher EMEP-Hintergrundstationen (DE0002R, DE0007R,
--  DE0009R) fuer 2018 und 2019, Spalten NC4H10_T und IC4H10_T (Obs):
--        n-Butan   0,263 .. 0,298 ppb, Mittel 0,2812
--        i-Butan   0,169 .. 0,185 ppb, Mittel 0,1743
--  Angesetzt ist die SUMME beider Isomere (0,4555 ppb): die Seeed-Kurve kennt
--  nur "C4H10" und trennt die Isomere nicht, ein Gasfeuerzeug uebrigens auch
--  nicht. Wer nur n-Butan ansetzen will, findet dessen Wert in ref_low.
--
--  EINSCHRAENKUNG, spiegelbildlich zum C3H8-Anker: das sind JAHRESmittel.
--  Butan hat eine OH-Lebensdauer von gut drei Tagen und dadurch ein
--  ausgepraegtes Wintermaximum bei Sommerminimum - im August liegt die
--  Wirklichkeit unter dem Jahresmittel. Der C3H8-Anker (Bergstation) zieht die
--  Reihe zu tief, dieser hier zieht sie zu hoch.
INSERT INTO gassensor_cal_anchor
  (cal_id, gas, k, ref_source, ref_value, ref_unit, ref_low, ref_high, sensor_value, note)
SELECT c.id, 'c4h10', 9.72127323244e-07,
       'Ge et al., Atmos. Chem. Phys. 24, 7699-7729, 2024 (doi:10.5194/acp-24-7699-2024), '
       'Supplement Tab. S4/S5: Jahresmittel 2018/2019 '
       'an den deutschen EMEP-Hintergrundstationen DE0002R, DE0007R, DE0009R; '
       'Summe n-Butan (0,2812 ppb) + i-Butan (0,1743 ppb)',
       0.0004555, 'ppm', 0.000263, 0.000475, 468.6,
       'Jahresmittel, nicht Sommerwert - Butan hat Wintermaximum bei rund 3 Tagen OH-Lebensdauer, '
       'im August liegt die Wirklichkeit darunter. ref_low = nur n-Butan, ref_high = Summe im '
       'staerksten Stationsjahr. Dritter Anker auf dem NH3-ADC. n=28.'
FROM gassensor_cal c
WHERE c.device='gassensor-esp8266' AND c.valid_from='2026-08-10 23:00:00'
  AND NOT EXISTS (SELECT 1 FROM gassensor_cal_anchor a WHERE a.cal_id=c.id AND a.gas='c4h10');

-- Fuer CO, CH4, H2 und C2H5OH bewusst KEIN Anker: es gibt in dieser Gegend
-- keinen belegbaren Referenzwert, und der RED-Kanal klebt ausserdem mit ADC
-- 1010 am Anschlag 1023 (ein Zaehlwert aendert das Verhaeltnis um rund 8 %).
--
-- DAMIT HAENGEN DREI DER VIER ANKER AM NH3-KANAL (NH3, C3H8, C4H10). Sie
-- stammen aus EINEM ADC-Wert und sind monotone Umformungen voneinander. Drei
-- Reihen, eine Messung: sie koennen nie gegeneinander laufen, und wer aus
-- ihrem Gleichlauf auf Bestaetigung schliesst, sitzt einem Zirkelschluss auf.

-- ═══════════════════════════════════════════════════════════════════════════
--  Schicht 1: Verhaeltnisse und Anker je Gas
--
--  Getrennte View, weil MariaDB innerhalb eines SELECT nicht auf die eigenen
--  Spaltenaliase zurueckgreifen kann. Ohne diese Zwischenschicht muesste der
--  Verhaeltnisausdruck in jeder der acht Gaskurven wortgleich wiederholt
--  werden - acht Stellen, die beim naechsten Eingriff auseinanderlaufen.
--
--  Die Schutzbedingungen sind dieselben wie in gas_mics6814_v2.h: A0 = 0 oder
--  ein Kanal am Anschlag (>= 1023) macht das Verhaeltnis undefiniert. Dort
--  ergibt das NAN, hier NULL.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW gassensor_ratio AS
SELECT
  s.ts, s.device, c.id AS cal_id,
  s.adc_nh3, s.adc_co, s.adc_no2,
  c.r0_nh3, c.r0_co, c.r0_no2,
  a.k_nh3, a.k_co, a.k_no2, a.k_c3h8, a.k_c4h10, a.k_ch4, a.k_h2, a.k_c2h5oh,
  CASE WHEN s.adc_nh3 BETWEEN 1 AND 1022 AND c.r0_nh3 BETWEEN 1 AND 1022
       THEN (s.adc_nh3 / c.r0_nh3) * (1023 - c.r0_nh3) / (1023 - s.adc_nh3) END AS ratio_nh3,
  CASE WHEN s.adc_co  BETWEEN 1 AND 1022 AND c.r0_co  BETWEEN 1 AND 1022
       THEN (s.adc_co  / c.r0_co ) * (1023 - c.r0_co ) / (1023 - s.adc_co ) END AS ratio_co,
  CASE WHEN s.adc_no2 BETWEEN 1 AND 1022 AND c.r0_no2 BETWEEN 1 AND 1022
       THEN (s.adc_no2 / c.r0_no2) * (1023 - c.r0_no2) / (1023 - s.adc_no2) END AS ratio_no2,
  -- Ab ADC 1000 springt das Verhaeltnis je Schritt; dieselbe Schwelle wie
  -- ADC_WARN in gas.php. Alle Gase eines Kanals sind dann gemeinsam wertlos.
  (s.adc_nh3 < 1000) AS ok_nh3,
  (s.adc_co  < 1000) AS ok_co,
  (s.adc_no2 < 1000) AS ok_no2
FROM gassensor s
LEFT JOIN gassensor_cal c
  ON  c.device = s.device
  AND s.ts >= c.valid_from
  AND (c.valid_to IS NULL OR s.ts < c.valid_to)
-- Die Anker liegen zeilenweise vor, gebraucht werden sie spaltenweise. Das
-- Pivot steht hier und nicht in der oberen Schicht, damit gassensor_kal nur
-- noch rechnet und nicht mehr sucht.
LEFT JOIN (
  SELECT cal_id,
         MAX(CASE WHEN gas='nh3'    THEN k END) AS k_nh3,
         MAX(CASE WHEN gas='co'     THEN k END) AS k_co,
         MAX(CASE WHEN gas='no2'    THEN k END) AS k_no2,
         MAX(CASE WHEN gas='c3h8'   THEN k END) AS k_c3h8,
         MAX(CASE WHEN gas='c4h10'  THEN k END) AS k_c4h10,
         MAX(CASE WHEN gas='ch4'    THEN k END) AS k_ch4,
         MAX(CASE WHEN gas='h2'     THEN k END) AS k_h2,
         MAX(CASE WHEN gas='c2h5oh' THEN k END) AS k_c2h5oh
  FROM gassensor_cal_anchor GROUP BY cal_id
) a ON a.cal_id = c.id
WHERE s.source = 'sensor' AND s.stale = 0;

-- ═══════════════════════════════════════════════════════════════════════════
--  Schicht 2: kalibrierte Gaswerte
--
--  Kurven 1:1 aus gas_mics6814_v2.h (dort aus Seeed-Studio/Mutichannel_Gas_-
--  Sensor, Zweig 2 == __version). Molmassen und Bezugsbedingungen 1:1 aus
--  gassensor_triggers.sql, damit kalibrierte und rohe Reihe in derselben
--  Einheit stehen und unmittelbar vergleichbar sind.
--
--  COALESCE(k, 1) heisst: ohne Anker bleibt es bei der reinen R0-Basislinie.
--  Dieser Wert ist NICHT als Messwert brauchbar - bei ratio ~ 1 liefern die
--  Seeed-Kurven ihren Sockel (NH3 0,68 ppm, CO 4,4 ppm, C3H8 ueber 500 ppm),
--  ein Artefakt der Kurvenanpassung weit unterhalb des spezifizierten
--  Bereichs. Wer die View auswertet, muss anker_* pruefen; die Weboberflaeche
--  gibt fuer ungeankerte Gase bewusst gar nichts aus.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW gassensor_kal AS
SELECT
  r.ts, r.device, r.cal_id,
  r.adc_nh3, r.adc_co, r.adc_no2,
  r.r0_nh3, r.r0_co, r.r0_no2,
  r.ratio_nh3, r.ratio_co, r.ratio_no2,
  r.ok_nh3, r.ok_co, r.ok_no2,
  (r.k_nh3    IS NOT NULL) AS anker_nh3,
  (r.k_co     IS NOT NULL) AS anker_co,
  (r.k_no2    IS NOT NULL) AS anker_no2,
  (r.k_c3h8   IS NOT NULL) AS anker_c3h8,
  (r.k_c4h10  IS NOT NULL) AS anker_c4h10,
  (r.k_ch4    IS NOT NULL) AS anker_ch4,
  (r.k_h2     IS NOT NULL) AS anker_h2,
  (r.k_c2h5oh IS NOT NULL) AS anker_c2h5oh,

  -- ppm, kalibriert
  POWER(r.ratio_no2,  1.007) / 6.855   * COALESCE(r.k_no2,    1) AS no2,
  POWER(r.ratio_nh3, -1.67 ) / 1.47    * COALESCE(r.k_nh3,    1) AS nh3,
  POWER(r.ratio_co,  -1.179) * 4.385   * COALESCE(r.k_co,     1) AS co,
  POWER(r.ratio_nh3, -2.518) * 570.164 * COALESCE(r.k_c3h8,   1) AS c3h8,
  POWER(r.ratio_nh3, -2.138) * 398.107 * COALESCE(r.k_c4h10,  1) AS c4h10,
  POWER(r.ratio_co,  -4.363) * 630.957 * COALESCE(r.k_ch4,    1) AS ch4,
  POWER(r.ratio_co,  -1.8  ) * 0.73    * COALESCE(r.k_h2,     1) AS h2,
  POWER(r.ratio_co,  -1.552) * 1.622   * COALESCE(r.k_c2h5oh, 1) AS c2h5oh,

  -- UBA-Einheiten bei 20 °C und 1013 hPa (24,055 l/mol)
  POWER(r.ratio_no2,  1.007) / 6.855   * COALESCE(r.k_no2,    1) * 46.0055 / 24.055 * 1000 AS no2_ugm3,
  POWER(r.ratio_nh3, -1.67 ) / 1.47    * COALESCE(r.k_nh3,    1) * 17.031  / 24.055 * 1000 AS nh3_ugm3,
  POWER(r.ratio_co,  -1.179) * 4.385   * COALESCE(r.k_co,     1) * 28.010  / 24.055        AS co_mgm3,
  POWER(r.ratio_nh3, -2.518) * 570.164 * COALESCE(r.k_c3h8,   1) * 44.096  / 24.055        AS c3h8_mgm3,
  POWER(r.ratio_nh3, -2.138) * 398.107 * COALESCE(r.k_c4h10,  1) * 58.122  / 24.055        AS c4h10_mgm3,
  POWER(r.ratio_co,  -4.363) * 630.957 * COALESCE(r.k_ch4,    1) * 16.043  / 24.055        AS ch4_mgm3,
  POWER(r.ratio_co,  -1.8  ) * 0.73    * COALESCE(r.k_h2,     1) * 2.016   / 24.055        AS h2_mgm3,
  POWER(r.ratio_co,  -1.552) * 1.622   * COALESCE(r.k_c2h5oh, 1) * 46.068  / 24.055        AS c2h5oh_mgm3
FROM gassensor_ratio r;
