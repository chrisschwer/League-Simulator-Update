// ELO-Verlauf je Liga (Issue #184). Zeichnet aus #verlauf-daten ein SVG mit
// einer Linie je Verein. Vorlage: docs/designs/elo-verlauf-2bl-2024-25.html
// (Entwurf 8.9.2026); Spec docs/superpowers/specs/2026-10-10-elo-verlauf-design.md.
//
// Gestaltung nach Tufte: alle Linien leise grau, genau eine hervorgehoben;
// direkte Beschriftung an den Linienenden statt Legende; wenige Hilfslinien.
(function () {
  "use strict";
  const datenEl = document.getElementById("verlauf-daten");
  const box = document.getElementById("verlauf-box");
  if (!datenEl || !box) return;

  const DATEN = JSON.parse(datenEl.textContent);
  const teams = DATEN.teams;
  const tip = document.getElementById("verlauf-tip");

  const W = 1080, H = 640, M = { t: 16, r: 80, b: 26, l: 52 };
  const INNEN = W - M.l - M.r;
  const TAG_MS = 864e5;
  const ABSTAND = 12.5;
  const PAUSE_MIN_TAGE = 18;
  const MON = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."];
  const TAG = ["So.", "Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa."];
  let modus = "spiel";
  let aktiv = null;

  // --- Skalen ---------------------------------------------------------------
  const alleElo = teams.flatMap((t) => t.punkte.map((p) => p.nach));
  const eloMin = Math.min(...alleElo), eloMax = Math.max(...alleElo);
  const pad = Math.max((eloMax - eloMin) * 0.06, 10);
  // Oben schliesst das Diagramm wie im Entwurf mit einer Hilfslinie ab: Liegt
  // die naechste 50er-Linie ueber den Daten nah genug, wird sie zur Oberkante,
  // statt einen leeren Streifen ueber der obersten Hilfslinie zu lassen.
  const eloUnten = eloMin - pad;
  const kappe = Math.ceil((eloMax + pad / 3) / 50) * 50;
  const eloOben = kappe - (eloMax + pad) <= (eloMax - eloMin) * 0.1 ? kappe : eloMax + pad;
  const y = (v) => M.t + (H - M.t - M.b) * (1 - (v - eloUnten) / (eloOben - eloUnten));

  const tag = (d) => new Date(d + "T12:00:00Z").getTime();
  const alleTage = [...new Set(teams.flatMap((t) => t.punkte.filter((p) => p.datum).map((p) => p.datum)))].sort();
  // Saisonstart-Punkt (n = 0) liegt eine Woche vor dem ersten Spiel.
  const tStart = alleTage.length ? tag(alleTage[0]) - 7 * TAG_MS : 0;
  const tEnde = DATEN.achse_datum_ende ? tag(DATEN.achse_datum_ende) : tStart + TAG_MS;
  const xDatum = (t) => M.l + INNEN * ((t - tStart) / (tEnde - tStart));
  const xOf = (p) => (modus === "spiel"
    ? M.l + INNEN * (p.n / DATEN.achse_spiele_max)
    : xDatum(p.datum ? tag(p.datum) : tStart));

  // Winterpause: groesste Luecke zwischen aufeinanderfolgenden Spieltagen.
  let pause = null;
  for (let i = 1; i < alleTage.length; i++) {
    const a = tag(alleTage[i - 1]), b = tag(alleTage[i]);
    if (!pause || b - a > pause.d) pause = { a, b, d: b - a };
  }
  const pauseSichtbar = () => modus === "datum" && pause !== null && pause.d > PAUSE_MIN_TAGE * TAG_MS;

  // --- Formate --------------------------------------------------------------
  const nz1 = (n) => n.toFixed(1).replace(".", ",");
  const vz = (n) => {
    const r = Math.round(n * 10) / 10;
    return (r > 0 ? "+" : r < 0 ? "−" : "±") + nz1(Math.abs(r));
  };
  const pct = (x) => String(Math.round(x * 100));
  const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const fmtDatum = (iso) => {
    const d = new Date(iso + "T12:00:00Z");
    return TAG[d.getUTCDay()] + " " + d.getUTCDate() + ". " + MON[d.getUTCMonth()] + " " + d.getUTCFullYear();
  };

  // --- Zeichnen -------------------------------------------------------------
  function zeichne() {
    const titel = `ELO-Verlauf aller ${teams.length} Vereine – ${DATEN.liga} ${DATEN.saison}`;
    let s = `<svg class="verlauf" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(titel)}">`;

    if (pauseSichtbar()) {
      const xa = xDatum(pause.a), xb = xDatum(pause.b);
      s += `<rect class="pause" x="${xa.toFixed(1)}" y="${M.t}" width="${(xb - xa).toFixed(1)}" height="${H - M.t - M.b}"/>`;
      s += `<text class="pauselabel" x="${((xa + xb) / 2).toFixed(1)}" y="${M.t + 12}" text-anchor="middle">Winterpause</text>`;
    }

    // Wenige waagerechte Hilfslinien im 50er-Schritt.
    const von = Math.ceil(eloUnten / 50) * 50, bis = Math.floor(eloOben / 50) * 50;
    for (let v = von; v <= bis; v += 50) {
      s += `<line class="gridline" x1="${M.l}" y1="${y(v).toFixed(1)}" x2="${W - M.r}" y2="${y(v).toFixed(1)}"/>`;
      s += `<text class="axislabel" x="${M.l - 8}" y="${(y(v) + 3.2).toFixed(1)}" text-anchor="end">${v}</text>`;
    }

    const yAchse = H - M.b + 14;
    if (modus === "spiel") {
      // Wie im Entwurf: 1., dann Fuenferschritte, zuletzt das Achsenende --
      // dieses nur, wenn es nicht zu dicht an der letzten Marke steht.
      const max = DATEN.achse_spiele_max;
      const marken = [];
      for (let k = 1; k <= max; k = max <= 10 ? k + 1 : (k === 1 ? 5 : k + 5)) marken.push(k);
      if (marken[marken.length - 1] !== max) {
        if (max - marken[marken.length - 1] < 2 && marken.length > 1) marken.pop();
        marken.push(max);
      }
      s += `<text class="axislabel" x="${M.l}" y="${yAchse}" text-anchor="middle">Start</text>`;
      marken.forEach((k) => {
        s += `<text class="axislabel" x="${(M.l + INNEN * (k / max)).toFixed(1)}" y="${yAchse}" text-anchor="middle">${k}.</text>`;
      });
    } else if (alleTage.length) {
      // Ohne gespieltes Spiel gibt es keine Kalenderachse (tStart waere 1970).
      const d0 = new Date(tStart);
      for (let jahr = d0.getUTCFullYear(), m = d0.getUTCMonth(); ;) {
        const t = Date.UTC(jahr, m, 1, 12);
        if (t > tEnde) break;
        const inPause = pauseSichtbar() && t > pause.a && t < pause.b;
        if (t >= tStart && !inPause) {
          s += `<text class="axislabel" x="${xDatum(t).toFixed(1)}" y="${yAchse}" text-anchor="middle">${MON[m]}</text>`;
        }
        m++;
        if (m > 11) { m = 0; jahr++; }
      }
    }

    // Endbeschriftungen entzerren: Etiketten duerfen sich nicht ueberdecken.
    const geo = teams.map((t, ti) => {
      const pts = t.punkte.map((p) => [xOf(p), y(p.nach)]);
      return { ti, pts, ende: pts[pts.length - 1], ly: 0 };
    });
    // Alle Etiketten stehen in einer Spalte hinter dem am weitesten rechts
    // liegenden Linienende -- auch wenn ein Verein ein Spiel weniger hat und
    // seine Linie frueher endet; sonst laege sein Etikett im Liniengewirr.
    const xSpalte = Math.max(...geo.map((g) => g.ende[0]));
    const sortiert = [...geo].sort((a, b) => a.ende[1] - b.ende[1]);
    sortiert.forEach((g, k) => {
      g.ly = g.ende[1];
      if (k && g.ly < sortiert[k - 1].ly + ABSTAND) g.ly = sortiert[k - 1].ly + ABSTAND;
    });
    const unten = H - M.b - 2;
    for (let k = sortiert.length - 1; k >= 0; k--) {
      if (sortiert[k].ly > unten) sortiert[k].ly = unten;
      if (k < sortiert.length - 1 && sortiert[k].ly > sortiert[k + 1].ly - ABSTAND) {
        sortiert[k].ly = sortiert[k + 1].ly - ABSTAND;
      }
    }

    geo.forEach((g) => {
      const t = teams[g.ti];
      const d = g.pts.map((c, i) => (i ? "L" : "M") + c[0].toFixed(1) + " " + c[1].toFixed(1)).join(" ");
      s += `<g class="team" data-i="${g.ti}">`;
      s += `<path class="linie" d="${d}"/><path class="hit" d="${d}"/>`;
      g.pts.forEach((c, i) => {
        s += `<circle class="punkt" data-p="${i}" cx="${c[0].toFixed(1)}" cy="${c[1].toFixed(1)}" r="2.6"/>`;
      });
      // Kuerzere Linie: gepunktete Waagerechte bis zur Etikettenspalte; gepunktet,
      // damit sie nicht als gleichbleibende Staerke gelesen wird.
      if (xSpalte - g.ende[0] > 1.2) {
        s += `<line class="fuehrung waag" x1="${(g.ende[0] + 2).toFixed(1)}" y1="${g.ende[1].toFixed(1)}" x2="${(xSpalte + 2).toFixed(1)}" y2="${g.ende[1].toFixed(1)}"/>`;
      }
      if (Math.abs(g.ly - g.ende[1]) > 1.2) {
        s += `<line class="fuehrung" x1="${(xSpalte + 2).toFixed(1)}" y1="${g.ende[1].toFixed(1)}" x2="${(xSpalte + 7).toFixed(1)}" y2="${g.ly.toFixed(1)}"/>`;
      }
      s += `<text class="endkuerzel" x="${(xSpalte + 9).toFixed(1)}" y="${(g.ly + 3.4).toFixed(1)}">${esc(t.kuerzel)}</text>`;
      s += `<text class="endlabel" x="${(xSpalte + 40).toFixed(1)}" y="${(g.ly + 3.4).toFixed(1)}">${Math.round(t.aktuell)}</text>`;
      s += "</g>";
    });
    s += "</svg>";

    const alt = box.querySelector("svg");
    if (alt) alt.remove();
    box.insertAdjacentHTML("afterbegin", s);
    verdrahte();
    if (aktiv !== null) setzeAktiv(aktiv);
  }

  // --- Auswahl und Tooltip ----------------------------------------------------
  function setzeAktiv(i) {
    aktiv = i;
    box.querySelectorAll("g.team").forEach((g) => {
      const an = Number(g.dataset.i) === i;
      g.classList.toggle("on", an);
      g.classList.toggle("dim", i !== null && !an);
      if (an) g.parentNode.appendChild(g);
    });
    document.querySelectorAll("#verlauf-tab tbody tr").forEach((tr) => {
      tr.classList.toggle("on", Number(tr.dataset.i) === i);
    });
  }

  function loesche() {
    aktiv = null;
    box.querySelectorAll("g.team").forEach((g) => g.classList.remove("on", "dim"));
    box.querySelectorAll(".punkt").forEach((c) => c.classList.remove("aktiv"));
    document.querySelectorAll("#verlauf-tab tbody tr").forEach((tr) => tr.classList.remove("on"));
    if (tip) tip.classList.remove("show");
  }

  // Linkslastig: das letzte Spiel, dessen x-Position hoechstens am Zeiger liegt.
  function spielAn(t, mx) {
    let best = 0;
    for (let i = 1; i < t.punkte.length; i++) {
      if (xOf(t.punkte[i]) <= mx + 4) best = i; else break;
    }
    return best;
  }

  function zeigeTip(ti, pi) {
    const t = teams[ti], p = t.punkte[pi];
    const svg = box.querySelector("svg");
    if (!tip || !svg || !p || !p.datum) { if (tip) tip.classList.remove("show"); return; }
    const heim = p.heim ? t.name : p.gegner_name, gast = p.heim ? p.gegner_name : t.name;
    tip.innerHTML =
      `<p class="tdate">${fmtDatum(p.datum)} · ${p.runde}. Spieltag${p.nachhol ? " · Nachholspiel" : ""}</p>` +
      `<p class="tpair">${esc(heim)}<span class="dash">–</span>${esc(gast)} ` +
      `<span class="tres">${p.tore_heim}:${p.tore_gast}</span></p>` +
      `<p class="terw">Das Modell gab ${esc(t.kuerzel)} vorher ${pct(p.p_sieg)} % Sieg, ${pct(p.p_remis)} % Remis.</p>` +
      `<p class="telo">ELO ${nz1(p.vor)} → ${nz1(p.nach)} ` +
      `<span class="tdelta ${p.delta >= 0 ? "pos" : "neg"}">${vz(p.delta)}</span></p>`;
    const g = svg.querySelector(`g.team[data-i="${ti}"]`);
    g.querySelectorAll(".punkt").forEach((c) => c.classList.toggle("aktiv", Number(c.dataset.p) === pi));
    const r = svg.getBoundingClientRect(), br = box.getBoundingClientRect();
    const px = xOf(p) * (r.width / W) + (r.left - br.left) + box.scrollLeft;
    const py = y(p.nach) * (r.height / H) + (r.top - br.top);
    tip.classList.add("show");
    const tw = tip.offsetWidth, th = tip.offsetHeight;
    let L = px + 14;
    if (L + tw > box.scrollLeft + br.width - 4) L = px - tw - 14;
    if (L < 2) L = 2;
    let T = py - th - 12;
    if (T < 2) T = py + 16;
    tip.style.left = L + "px";
    tip.style.top = T + "px";
  }

  function zeigerX(svg, e) {
    const r = svg.getBoundingClientRect();
    return r.width ? (e.clientX - r.left) * (W / r.width) : 0;
  }

  function verdrahte() {
    const svg = box.querySelector("svg");
    svg.querySelectorAll("g.team").forEach((g) => {
      const ti = Number(g.dataset.i);
      const hit = g.querySelector(".hit");
      hit.addEventListener("pointermove", (e) => {
        if (e.pointerType === "touch") return;
        setzeAktiv(ti);
        zeigeTip(ti, spielAn(teams[ti], zeigerX(svg, e)));
      });
      hit.addEventListener("pointerleave", (e) => {
        if (e.pointerType !== "touch") loesche();
      });
      // Klick und Antippen: waehlen und Tooltip zeigen; erneut hebt auf.
      hit.addEventListener("click", (e) => {
        if (aktiv === ti && tip && tip.classList.contains("show")) { loesche(); return; }
        setzeAktiv(ti);
        zeigeTip(ti, spielAn(teams[ti], zeigerX(svg, e)));
      });
    });
    svg.addEventListener("pointerleave", (e) => {
      if (e.pointerType !== "touch") loesche();
    });
  }

  // --- Tabelle und Umschalter -----------------------------------------------
  document.querySelectorAll("#verlauf-tab tbody tr").forEach((tr) => {
    const i = Number(tr.dataset.i);
    tr.addEventListener("mouseenter", () => setzeAktiv(i));
    tr.addEventListener("mouseleave", () => { if (aktiv === i) loesche(); });
    tr.addEventListener("click", () => (aktiv === i ? loesche() : setzeAktiv(i)));
  });

  function setzeModus(m) {
    modus = m;
    document.querySelectorAll("#verlauf .modes button").forEach((b) => {
      b.setAttribute("aria-pressed", String(b.dataset.mode === m));
    });
    if (tip) tip.classList.remove("show");
    zeichne();
  }
  document.querySelectorAll("#verlauf .modes button").forEach((b) => {
    b.addEventListener("click", () => setzeModus(b.dataset.mode));
  });
  window.addEventListener("resize", () => { if (tip) tip.classList.remove("show"); });

  // Schnittstelle: dieselben Funktionen, die die Ereignisse rufen (Tests in
  // jsdom, das kein Layout kennt).
  window.eloVerlauf = {
    modus: setzeModus,
    waehle: (i) => (i === null ? loesche() : setzeAktiv(i)),
    zeigeSpiel: (i, n) => {
      const pi = teams[i].punkte.findIndex((p) => p.n === n);
      setzeAktiv(i);
      zeigeTip(i, pi);
    },
    loesche,
  };

  zeichne();
})();
