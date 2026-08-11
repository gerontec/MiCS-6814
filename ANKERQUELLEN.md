# Kalibrierung des MiCS-6814 — Verfahren und Ankerquellen

Der Seeed Grove Multichannel Gas Sensor (MiCS-6814 + ATmega168-Koprozessor)
liefert ab Werk Zahlen, die mit der Wirklichkeit nichts zu tun haben: beim
Einbau am 10.08.2026 meldete er 971 µg/m³ NO₂, die nächstgelegene
Referenzstation zur selben Stunde 3 µg/m³. Später wuchs der Abstand auf über
600. Dieses Dokument beschreibt, wie daraus brauchbare Zahlen werden, woher die
Bezugswerte stammen — und vor allem, was die Kalibrierung **nicht** leistet.

Die Rechnung liegt vollständig in `db/gassensor_cal.sql`.

## Warum in der Datenbank und nicht im Chip

Der Koprozessor könnte es selbst: `CMD_SET_R0_ADC` (Kommando 7) legt eine eigene
R0-Basis in seinem EEPROM ab, die Werkswerte bleiben an eigenen Adressen daneben
erhalten. Trotzdem steht die Kalibrierung hier und nicht dort.

Ein EEPROM-Schreibvorgang wirkt nur nach vorn, ist am Gerät nicht
nachvollziehbar und macht jede ältere Zeile der Messreihe unvergleichbar mit
jeder neueren. Die Tabellen wirken dagegen rückwirkend auf den gesamten Bestand,
sind versioniert, und ein besserer Datensatz ersetzt sie mit einem `UPDATE` —
ohne den Sensor anzufassen. Voraussetzung dafür ist, dass die Rohwerte
mitlaufen: `gassensor` führt `adc_*` und `r0_*` genau deshalb mit.

## Die zwei Schritte

**1. R0-Basislinie — physikalisch, je Kanal.** R0 ist der ADC-Wert des Kanals in
der Bezugsluft. Die Werkswerte passen für dieses Exemplar nicht: der OX-Kanal
steht bei ADC 739, das EEPROM behauptet 155. Ein Verhältnis von 13,7 in
ländlicher Hintergrundluft ist für einen resistiven Sensor nicht plausibel.
Angesetzt wird deshalb der Median eines Ruhefensters nach dem Einlaufen.

**2. Niveau-Anker — empirisch, je Gas.** `k` skaliert die jeweilige Potenzkurve
so, dass das Mittel des Ruhefensters auf einen belegten Referenzwert fällt.

Der zweite Schritt ist nötig, weil die R0-Basislinie allein nicht genügt: bei
einem Verhältnis von rund 1 liefern die Seeed-Kurven nicht null, sondern ihren
Sockel — NH₃ 0,68 ppm, CO 4,4 ppm, C₃H₈ über 500 ppm. Das sind Artefakte der
Kurvenanpassung weit unterhalb des spezifizierten Bereichs, keine Messwerte.

## Warum der Anker am Gas hängt und nicht am Kanal

Der Sensor hat drei Kanäle, aus denen acht Gase abgeleitet werden:

| Kanal | Gase |
|---|---|
| OX | NO₂ |
| NH3 | NH₃, C₃H₈, C₄H₁₀ |
| RED | CO, CH₄, H₂, C₂H₅OH |

Alle Gase eines Kanals stammen aus **derselben** Messgröße, nur mit anderer
Potenzkurve — und jede dieser Kurven hat ihren eigenen Sockel. Ein Anker am
Kanal würde den NH₃-Beleg an Propan und Butan weiterreichen, für die er nicht
gilt. Deshalb `gassensor_cal_anchor`: ein Anker, ein Gas, eine Quelle.

## Die vier Anker

Epoche 1, gültig ab 2026-08-10 23:00, Ruhefenster bis 2026-08-11 08:15 (n=38),
R0 = 972 / 1010 / 739 (NH3 / RED / OX).

### NO₂ — k = 0,013063

| | |
|---|---|
| Referenz | 3,71 µg/m³ (Band 3–6) |
| Sensor vorher | 284,33 µg/m³ |
| Quelle | UBA-Luftdaten, Station Andechs/Rothenfeld (DEBY109), Stundenwerte im Ruhefenster, n=28 |

Der einzige Anker aus einer **gleichzeitigen** Messung, damit der belastbarste.
DEBY109 ist eine ländliche Hintergrundstation in 34,4 km Entfernung. Näher
gelegene Stationen liefern nichts Brauchbares: Kreuth (9,7 km) und Sylvenstein
(19,1 km) sind Depositionsmessstellen ohne Gaskonzentrationen, und in Lenggries
misst überhaupt keine Netzstation — eine Abfrage der UBA-Stationsliste liefert
für den Standort als nächsten messenden Nachbarn Andechs, danach erst München.
Angenommen wird, dass die Luft hier dieselbe ist wie dort.

Quelle: <https://www.umweltbundesamt.de/api/air_data/v3/> (Komponente NO₂,
Stundenmittel, Station 529 / DEBY109)

### NH₃ — k = 0,00275182

| | |
|---|---|
| Referenz | 1,5 µg/m³ (Band 0,5–2,5) |
| Sensor vorher | 545,09 µg/m³ |
| Quelle | LfU Bayern, Ammoniak-Immissionsmessungen an immissionsökologischen Dauerbeobachtungsstationen, Jahresmittel 2011–2020 |

Ammoniak kommt im UBA-Luftdatensatz nicht vor und wird an DEBY109 nicht
gemessen. Der Beleg stammt deshalb vom Bayerischen Landesamt für Umwelt, das
seit 2011 NH₃ im ländlichen Hintergrund misst und dabei nach Umgebungstyp
trennt — Jahresmittel 2011–2020:

| Umgebung | NH₃ |
|---|---|
| naturnah oder nur extensiv bewirtschaftet | 0,5–2,5 µg/m³ |
| überwiegend Feldwirtschaft | 2,0–3,7 µg/m³ |
| intensive Grünlandbewirtschaftung | 4,7–6,3 µg/m³ |
| verkehrsnah (Ansbach, Innenstadt) | 3,7–5,5 µg/m³ |

Gewählt ist die erste Klasse, Bandmitte 1,5 µg/m³: gesucht war ausdrücklich ein
Tag **ohne** Gülleausbringung, also ohne die Düngespitzen, die das LfU als
Jahresgang beschreibt (Grünlandumgebung im Mittel bis 8,2 µg/m³ im Frühjahr und
8,3 µg/m³ im November). Das LfU hält für die düngefreie Zeit fest, dass selbst
in landwirtschaftlicher Umgebung unter 2 µg/m³ eingehalten werden — die Wahl
liegt damit innerhalb dessen, was die Quelle für einen unbelasteten Tag hergibt.

Die Bandbreite ist ehrlich groß: 0,5 statt 2,5 µg/m³ ergäbe ein `k`, das um den
Faktor 5 abweicht. `ref_low`/`ref_high` halten das fest.

Quelle: <https://www.lfu.bayern.de/luft/schadstoffe_luft/eutrophierung_versauerung/ergebnisse/index.htm>

### C₃H₈ — k = 2,5945e-07

| | |
|---|---|
| Referenz | 180 ppt (Band 150–210) |
| Sensor vorher | 693,8 ppm |
| Quelle | Mancinelli et al., Atmos. Chem. Phys. **26**, 4105–4129, 2026 |

Propan hat keinen Immissionsgrenzwert und wird in keinem Luftmessnetz der Gegend
geführt. Belegbar ist nur der troposphärische Hintergrund: an der
WMO-GAW-Station Monte Cimone (2165 m) lagen die Stundenmittel 2011–2023 im
Winter bei 620–651 ppt, im Sommer bei 150–210 ppt. Gewählt ist das Sommerband,
Mitte 180 ppt — die Messung fällt in den August.

Einschränkung: Monte Cimone ist eine Bergstation mit Anteil freier Troposphäre.
Ein Talstandort mit Ortschaft liegt darüber, 180 ppt ist damit eher eine
Untergrenze. Der Anker zieht die Reihe zu tief.

DOI: [10.5194/acp-26-4105-2026](https://doi.org/10.5194/acp-26-4105-2026)

### C₄H₁₀ — k = 9,7213e-07

| | |
|---|---|
| Referenz | 0,4555 ppb (Band 0,263–0,475) |
| Sensor vorher | 468,6 ppm |
| Quelle | Ge et al., Atmos. Chem. Phys. **24**, 7699–7729, 2024, Supplement Tab. S4/S5 |

Der beste Beleg der vier: keine Bergstation, keine Literaturklasse, sondern
gemessene Jahresmittel (Spalten `NC4H10_T`/`IC4H10_T`, Obs) an drei deutschen
EMEP-Hintergrundstationen für 2018 und 2019.

| Station | n-Butan 2018/2019 | i-Butan 2018/2019 |
|---|---|---|
| DE0002R | 0,263 / 0,292 ppb | 0,174 / 0,171 ppb |
| DE0007R | 0,287 / 0,284 ppb | 0,185 / 0,169 ppb |
| DE0009R | 0,263 / 0,298 ppb | 0,170 / 0,177 ppb |
| Mittel | **0,2812 ppb** | **0,1743 ppb** |

Angesetzt ist die **Summe beider Isomere** (0,4555 ppb): die Seeed-Kurve kennt
nur „C4H10" und trennt die Isomere nicht — ein Gasfeuerzeug übrigens auch nicht.
Wer nur n-Butan ansetzen will, findet dessen Wert in `ref_low`.

Einschränkung, spiegelbildlich zum Propan-Anker: das sind **Jahres**mittel.
Butan hat eine OH-Lebensdauer von gut drei Tagen und dadurch ein ausgeprägtes
Wintermaximum bei Sommerminimum; im August liegt die Wirklichkeit darunter.
Dieser Anker zieht die Reihe zu hoch, während der Propan-Anker sie zu tief
zieht.

DOI: [10.5194/acp-24-7699-2024](https://doi.org/10.5194/acp-24-7699-2024)

### Ohne Anker: CO, CH₄, H₂, C₂H₅OH

Für sie gibt es in dieser Gegend keinen belegbaren Referenzwert. Der RED-Kanal
klebt zusätzlich mit ADC 1010 am Anschlag 1023 — ein einzelner Zählwert ändert
das Verhältnis um rund 8 %, der Wert ist Rauschen. Die Weboberfläche gibt für
diese Gase deshalb **gar nichts** aus statt einer Zahl. Ein fehlender Wert fällt
auf, ein falscher nicht.

## Was diese Kalibrierung nicht leistet

**Der Anker richtet den Betrag, nicht die Bewegung.** Ein Vergleich der
Stundendifferenzen gegen die NO₂-Referenz (2026-08-10/11, n=20) ergab über alle
Zeitversätze von −3 h bis +6 h Korrelationen zwischen −0,25 und +0,31, bei einer
Signifikanzschwelle von rund 0,42. Der Sensor hat den Gang der Referenz also
nicht mitgemacht, auch nicht verzögert.

Das ist kein Defekt, sondern Physik. Der MiCS-6814 ist ab 0,05 ppm NO₂
(~96 µg/m³) und ab 1 ppm NH₃ (~700 µg/m³) spezifiziert, die Kohlenwasserstoffe
erst ab etwa 1000 ppm. Gemessen wird Luft mit 2–6 µg/m³ NO₂, rund 1,5 µg/m³ NH₃
und 0,0005 ppm Butan — zwei bis sechs Größenordnungen darunter. Der nächtliche
Anstieg des Rohsignals (ADC OX 590 → 758 zwischen 19 und 04 Uhr) ist
Temperatur- und Feuchtegang, keine Chemie.

**Drei der vier Anker hängen am selben ADC.** NH₃, C₃H₈ und C₄H₁₀ stammen aus
einem einzigen Messwert und sind monotone Umformungen voneinander (Exponenten
−1,67, −2,518, −2,138). Drei Reihen, eine Messung: sie können nie gegeneinander
laufen. Wer aus ihrem Gleichlauf auf Bestätigung schließt, sitzt einem
Zirkelschluss auf.

**Das Rauschband täuscht Präzision vor.** Nach dem Ankern liegt es bei ±0,30
µg/m³ (NO₂) und ±0,24 µg/m³ (NH₃). Diese Zahlen beschreiben die Streuung des
Sensors, nicht die der Luft.

Verwertbar ist damit die Größenordnung der Reihe, nicht ihr Verlauf — und auch
die nur unter der jeweils in `ref_source` genannten Annahme.

## Neu kalibrieren

MiCS-Sensoren driften über Tage. Epoche 1 steht auf knapp 9 Stunden Ruhefenster
nach dem Einlaufen; die Einlaufphase davor (ADC OX 390 → 730 in 14 Stunden)
bleibt bewusst unkalibriert und liefert NULL, weil eine Drift kein Messwert ist.

Sobald mehrere volle Tage vorliegen: neue Zeile in `gassensor_cal` einsetzen, in
der alten `valid_to` nachtragen, Anker neu rechnen. Die Views ziehen sofort
nach, rückwirkend und ohne Datenverlust.

Ein Test mit Butan aus dem Feuerzeug ist kein Anker — die Konzentration ist
unbekannt — wohl aber der einzige Weg, den Sensor überhaupt in seinen
spezifizierten Bereich zu bringen. Er verschiebt allerdings die Basislinie für
Stunden und macht die laufende Epoche damit ungültig.

## Dateien

| Datei | Inhalt |
|---|---|
| `db/gassensor_table.sql` | Tabelle `gassensor`, 15-min-Reihe aus MQTT |
| `db/gassensor_units.sql` | Spalten für die UBA-Einheiten |
| `db/gassensor_triggers.sql` | ppm → µg/m³ bzw. mg/m³, in der Datenbank statt im Logger |
| `db/gassensor_cal.sql` | Kalibrierung: Epochen, Anker, Views |
| `gassensor-esp8266.yaml` | ESPHome-Firmware |
| `gas_mics6814_v2.h` | v2-Protokoll und Kurven, aus der Seeed-Bibliothek portiert |
