---
status: accepted
date: 2026-08-21
---
# Prognosen werden als statische Seiten ausgeliefert; shinyapps.io-Deploy-Pfad entfernt

Bis August 2026 hat der Scheduler nach jeder Ergebnisänderung die komplette Shiny-App per `rsconnect::deployApp()` zu shinyapps.io hochgeladen — 5,4 KB neue Daten durch einen vollständigen App-Redeploy, bis zu ~240-mal pro Spieltag. Posit stellt shinyapps.io zum 31.03.2027 ein. Die App hat keine echte Reaktivität (ein Dropdown, Daten werden beim Prozessstart geladen), also kauft ein Shiny-Laufzeitsystem nichts, was drei statische Seiten nicht auch können.

Entschieden (Design 26.07.2026, bestätigt 21.08.2026 beim Umzug auf den eigenen Server): Der Scheduler rendert nach jedem Lauf drei HTML-Seiten plus PNG-Heatmaps in ein Volume; Caddy liefert sie als statische Dateien unter fussball.csdatascience.de aus. Der shinyapps.io-Pfad wird **entfernt statt hinter einen Schalter gelegt** — ein Rückweg ist nicht gewollt, ungenutzter Deploy-Code mit eigenem Secrets-Handling wäre ungetestet, und `rsconnect` verlängert den Image-Build. Der Token (einst im Git-Verlauf, Commit ab158a1) wird entwertet. Rollback während des Umzugs ist der weiterlaufende alte Container im Homelab, nicht der Code.

Verworfen: Connect Cloud (gleiche Kosten, OAuth-Migration; Spec vom 26.07. als überholt markiert); Shiny selbst hosten per `runApp()` + `reactiveFileReader` (R-Prozess im Dauerbetrieb, WebSocket-Sessions, Lastgrenze an Forum-Tagen — für null Reaktivität); `PUBLISH_TARGET`-Schalter.
