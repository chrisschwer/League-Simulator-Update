// Runner fuer die Client-JS-Tests (Stufe 4.6, #212). Kein Test: die
// testthat-Dateien rufen ihn ueber js_szenario() (helper-js.R) auf.
//
//   node js-runner.mjs <html-datei> <szenario> [json-args]
//
// Laedt die Seite in jsdom, fuehrt die Inline-Skripte aus und gibt das
// Ergebnis des Szenarios als EINE JSON-Zeile auf stdout aus. Fehler: Meldung
// auf stderr, Exit-Status 1. Skriptfehler der Seite landen nicht als Abbruch,
// sondern im Feld `fehler` (jsdomError), damit die Tests sie pruefen koennen.
//
// Szenarien: stale (Veraltet-Hinweis), sort (Ligatabelle), tooltip (Kuerzel), verlauf (ELO-Verlauf).

import { readFileSync } from "node:fs";
import { JSDOM, VirtualConsole } from "jsdom";

const szenarien = {
  // args: { now } -- Date.now in ms, vor dem Parsen eingefroren, weil das
  // Stale-Skript beim Laden laeuft.
  stale({ window, fehler }) {
    const s = window.document.getElementById("stale");
    const h = window.document.getElementById("stale-hours");
    return {
      verborgen: s.hidden,
      stunden: h ? h.textContent : null,
      fehler,
    };
  },

  // args: { klicks: [key, ...] } -- je Klick auf `th button[data-key=key]` ein
  // Schritt mit dem Zustand danach; `vorher` ist der Zustand vor dem ersten.
  sort({ window, args, fehler }) {
    const doc = window.document;
    const table = doc.getElementById("ligatabelle");
    const zustand = (key) => ({
      zonen: table.getAttribute("data-zonen"),
      plaetze: Array.from(table.tBodies[0].rows, (r) => r.dataset.platz),
      werte: key ? Array.from(table.tBodies[0].rows, (r) => r.dataset[key]) : null,
      aria: Array.from(table.querySelectorAll("th button[aria-sort]"), (b) => ({
        key: b.dataset.key,
        wert: b.getAttribute("aria-sort"),
      })),
    });
    const vorher = zustand(null);
    const schritte = args.klicks.map((key) => {
      const btn = table.querySelector(`th button[data-key="${key}"]`);
      btn.click();
      return { key, dir: btn.dataset.dir, ...zustand(key) };
    });
    return { vorher, schritte, fehler };
  },

  // args: { schritte: [{ art, index? }, ...] } mit art = klick | daneben |
  // escape | scroll | resize | enter; index zaehlt die abbr.kz in Dokumentreihenfolge.
  // `titel` nennt den title der abbr.kz, auf die ein Schritt zielt.
  tooltip({ window, args, fehler }) {
    const doc = window.document;
    const kz = Array.from(doc.querySelectorAll("abbr.kz"));
    const zustand = () => {
      const tip = doc.querySelector(".kz-tip");
      return {
        vorhanden: tip !== null,
        rolle: tip ? tip.getAttribute("role") : null,
        verborgen: tip ? tip.hidden : null,
        text: tip ? tip.textContent : null,
      };
    };
    const titel = [];
    const schritte = args.schritte.map((s) => {
      const ziel = s.index === undefined ? null : kz[s.index];
      if (ziel) titel.push(ziel.getAttribute("title"));
      switch (s.art) {
        case "klick":
          ziel.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
          break;
        case "daneben":
          doc.body.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
          break;
        case "escape":
          doc.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
          break;
        case "scroll":
          window.dispatchEvent(new window.Event("scroll"));
          break;
        case "resize":
          window.dispatchEvent(new window.Event("resize"));
          break;
        case "enter":
          ziel.dispatchEvent(new window.KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
          break;
        default:
          throw new Error(`unbekannte Aktion: ${s.art}`);
      }
      return zustand();
    });
    return { schritte, titel, fehler };
  },

  // args: { schritte: [{ art, wert?, index?, n? }, ...] } mit art =
  // modus (wert: spiel|datum, Klick auf den Umschalter) | zeile (Klick auf
  // tr[data-i=index] der Tabelle) | zeige (window.eloVerlauf.zeigeSpiel(index, n))
  // | loesche (window.eloVerlauf.loesche()). jsdom kennt kein Layout, deshalb
  // laeuft der Tooltip ueber die Schnittstelle statt ueber Zeigerkoordinaten.
  verlauf({ window, args, fehler }) {
    const doc = window.document;
    const zustand = () => {
      const svg = doc.querySelector("#verlauf-box svg");
      const tip = doc.getElementById("verlauf-tip");
      const gruppen = svg ? Array.from(svg.querySelectorAll("g.team")) : [];
      const xs = (g) => Array.from(g.querySelectorAll(".punkt"), (c) => Number(c.getAttribute("cx")));
      return {
        hat_svg: svg !== null,
        linien: gruppen.length,
        an: gruppen.filter((g) => g.classList.contains("on")).map((g) => Number(g.dataset.i)),
        gedimmt: gruppen.filter((g) => g.classList.contains("dim")).length,
        zeilen_an: Array.from(doc.querySelectorAll("#verlauf-tab tbody tr.on"), (r) => Number(r.dataset.i)),
        gedrueckt: Array.from(doc.querySelectorAll(".modes button"), (b) => b.getAttribute("aria-pressed")),
        tip_sichtbar: tip ? tip.classList.contains("show") : false,
        tip_text: tip ? tip.textContent : null,
        label_y: svg ? Array.from(svg.querySelectorAll(".endkuerzel"), (t) => Number(t.getAttribute("y"))) : [],
        erste_x: Object.fromEntries(gruppen.map((g) => [g.dataset.i, xs(g)[0]])),
        letzte_x: Object.fromEntries(gruppen.map((g) => [g.dataset.i, xs(g)[xs(g).length - 1]])),
        pause: svg ? svg.querySelector(".pause") !== null : false,
        pfad_kaputt: svg
          ? Array.from(svg.querySelectorAll("path.linie"), (p) => p.getAttribute("d")).some((d) => /NaN|Infinity/.test(d))
          : false,
      };
    };
    const api = window.eloVerlauf;
    const vorher = zustand();
    const schritte = (args.schritte || []).map((s) => {
      switch (s.art) {
        case "modus":
          doc.querySelector(`.modes button[data-mode="${s.wert}"]`).click();
          break;
        case "zeile":
          doc.querySelector(`#verlauf-tab tbody tr[data-i="${s.index}"]`)
            .dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
          break;
        case "zeige":
          api.zeigeSpiel(s.index, s.n);
          break;
        case "loesche":
          api.loesche();
          break;
        default:
          throw new Error(`unbekannte Aktion: ${s.art}`);
      }
      return zustand();
    });
    return { vorher, schritte, api: typeof api, fehler };
  },
};

function main() {
  const [, , datei, name, json] = process.argv;
  if (!datei || !name || !(name in szenarien)) {
    throw new Error(
      `Aufruf: node js-runner.mjs <html-datei> <${Object.keys(szenarien).join("|")}> [json-args]`
    );
  }
  const args = json ? JSON.parse(json) : {};
  const fehler = [];
  const virtualConsole = new VirtualConsole();
  virtualConsole.on("jsdomError", (e) => fehler.push(e.message));

  const dom = new JSDOM(readFileSync(datei, "utf8"), {
    runScripts: "dangerously",
    url: "https://example.test/",
    virtualConsole,
    beforeParse(window) {
      if (args.now !== undefined) window.Date.now = () => args.now;
    },
  });
  const ergebnis = szenarien[name]({ window: dom.window, args, fehler });
  process.stdout.write(JSON.stringify(ergebnis) + "\n");
  dom.window.close();
}

try {
  main();
} catch (e) {
  process.stderr.write(`js-runner: ${e.stack || e}\n`);
  process.exit(1);
}
