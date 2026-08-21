# shinyapps.io Umzugsbanner

Die letzte Fassung der App unter `chrisschwer.shinyapps.io/FussballPrognosen`:
nur ein Hinweis mit Link auf <https://fussball.csdatascience.de>. Keine Daten,
kein Rechenlauf, kein Auto-Redirect.

## Einmaliges Deploy (vom Entwicklerrechner)

Voraussetzung: R mit `shiny` und `rsconnect` (ist **nicht** mehr Teil des
Produktions-Images). Token und Secret aus dem shinyapps.io-Dashboard
(*Account → Tokens*); nicht ins Repo, nicht in die Shell-History.

```bash
Rscript -e '
  rsconnect::setAccountInfo(name = "chrisschwer",
                            token = Sys.getenv("SHINYAPPS_IO_TOKEN"),
                            secret = Sys.getenv("SHINYAPPS_IO_SECRET"))
  rsconnect::deployApp("tools/shinyapps-umzugsbanner",
                       appName = "FussballPrognosen", forceUpdate = TRUE)
'
```

Lokale Vorschau: `Rscript -e 'shiny::runApp("tools/shinyapps-umzugsbanner")'`.

## Danach

1. Im Browser prüfen, dass die App den Hinweis zeigt.
2. Im shinyapps.io-Dashboard den **Token entwerten** (er ist nicht mehr
   nötig; eine frühere Fassung lag einmal im Git-Verlauf, Commit ab158a1).
3. Plan auf *Free* herabstufen; die App nach etwa einem Monat archivieren
   (geplant: 21.09.2026); Konto vor dem 31.03.2027 schließen (Ende von
   shinyapps.io).

Hintergrund: [ADR 0001](../../docs/adr/0001-statische-seiten-statt-gehostetem-shiny.md).
