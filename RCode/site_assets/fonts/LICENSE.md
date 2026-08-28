# Schriftlizenzen

Alle drei hier abgelegten Schriftfamilien stehen unter der
**SIL Open Font License, Version 1.1** (https://openfontlicense.org).
Die OFL erlaubt Nutzung, Studium, Veränderung und Weitergabe – auch für
kommerzielle Zwecke – solange die Schriften nicht separat unter eigenem
Namen verkauft werden. Der vollständige Lizenztext liegt bei jeder Familie
auf der jeweiligen Google-Fonts-Seite bei.

## Quelle und Abrufdatum

Bezogen von der Google Fonts CSS2-API (`fonts.googleapis.com/css2`,
Auslieferung über `fonts.gstatic.com`) am **2026-08-28**.

| Datei | Familie | Achsen | Google-Fonts-Version |
|---|---|---|---|
| `source-serif-4-latin.woff2` | Source Serif 4 | `wght` 200–900, `opsz` 8–60 | v14 |
| `inter-tight-latin.woff2` | Inter Tight | `wght` 100–900 | v9 |
| `jetbrains-mono-latin.woff2` | JetBrains Mono | `wght` 100–800 | v24 |

Jede Datei ist eine selbst gehostete Variable-Font-Instanz im `latin`-Subset
(`unicode-range` deckt U+0000–00FF sowie gängige Interpunktion/Sonderzeichen
ab). Das latin-Subset enthält Umlaute (ä/ö/ü/Ä/Ö/Ü), ß sowie die deutschen
Anführungszeichen „…" (U+201E/U+201C) und Gedankenstrich (U+2013) –
stichprobenartig mit `fontTools` geprüft (`fvar`-Tabelle vorhanden,
Zeichenabdeckung über `getBestCmap()` bestätigt).

## Bewusst ausgelassen: Kursivschnitte

Es werden nur die aufrechten (`normal`) Schnitte ausgeliefert. Die Seite
verwendet aktuell keine kursive Auszeichnung; sollte das später gebraucht
werden, müssen die `italic`-Varianten separat über dieselbe CSS2-API
nachgezogen werden.
