# Lumen — Master-Briefing / Übergabe an Claude Code (CLI)

> Stand: Addon-Version **0.9.9**, Interface **120007** (Retail-Patch 12.0.7, live seit 16.06.2026).
> Sprache der Zusammenarbeit: **Deutsch**. Öffentliche Texte (CurseForge/Wago, Changelogs): **Englisch**.
> Dieses Dokument ist die nahtlose Fortführung des bisherigen Konzept-/Entwicklungs-Chats. Es ist die einzige Quelle der Wahrheit für Vision, Absprachen und Ist-Zustand. Claude Code soll hier starten.

---

## 1. Was ist Lumen? (Vision)

Lumen ist eine **fokussierte, moderne UI-Suite für World of Warcraft (Retail)** — Tagline: „a focused UI suite". Der Name ist reine Marke; „UI"/„Suite" stehen nur als Beschreibung dahinter, nicht im Namen.

Kernidee ist **Anti-Bloat**: nur das, was praktisch jeder ernsthafte M+/Raid-Spieler wirklich braucht — dafür richtig gut, sauber und zeitgemäß (Stand 2026). Das ist die bewusste Abgrenzung zu ElvUI und EllesmereUI, die über Jahre mit Optionen für jede Nische zugewachsen sind und die der Durchschnittsspieler nur zu einem Bruchteil nutzt. Lumen will **gute Defaults statt hunderter Schalter**, eine kurze kuratierte Modulliste statt einer Optionswüste.

* **Zielgruppe / Content:** Mythic+ und Raid, gedacht in **Healer-Qualität**. Leitsatz: Was für Healer unter Druck gut lesbar funktioniert, funktioniert auch für alle anderen Rollen.
* **Verteilung:** offiziell über CurseForge und/oder Wago — kein graues Drittanbieter-Repo nötig (WoW erlaubt solche Addons regulär).
* **Offenes TODO vor Veröffentlichung:** Namen „Lumen" auf CurseForge/Wago auf Verfügbarkeit prüfen.
* **Portfolio-Hinweis:** Das Projekt dient Florian auch als Bewerbungsreferenz (Ausbildung Fachinformatiker). Ehrliche Einordnung: Design, Projektverantwortung, Releases, Git/Versionsverwaltung — **nicht** als eigene Programmierkompetenz darstellen (der Code entsteht mit KI-Unterstützung).

---

## 2. Arbeitsweise / Prozess-Regeln (WICHTIG)

* **Florian** (GitHub: `NennMichSchinken`, In-Game u.a. „Owlday") ist ausgebildeter **UI/UX-Designer**, kein Coder (kennt etwas HTML/CSS). Er gibt Konzept, Design und UX/UI komplett vor und dirigiert. **Die KI schreibt allen Lua-Code.**
* **Die KI kann nicht im Spiel testen.** Florian testet in-game und meldet mit **Screenshots** zurück. Das ist die zentrale Feedback-Schleife — ohne seine Rückmeldung ist Live-Verhalten unbestätigt.
* **Vor nicht-trivialen Änderungen** kurz auflisten, was verstanden wurde / was gebaut wird, und OK abholen. Bei klar spezifizierten Sachen: Plan nennen + bauen ist okay. Bei Heiklem (Daten-/Profil-Reset, größere Architektur-Weichen) vorher bestätigen lassen.
* **Mockups bei Designfragen:** Visuelle Vorschläge helfen Florian enorm bei Auswahl/Justierung. Hat im Konzept-Chat sehr gut funktioniert.
* **Bei jeder Lieferung:** Änderungen knapp erklären + eine kurze deutsche **Test-Checkliste** mitgeben.
* **Ton:** warm, knapp, deutsch, ehrlich über Grenzen/Unsicherheit. Keine Schönfärberei, wenn etwas unsicher oder ungetestet ist.
* **Changelogs** schlicht/sachlich, kein Marketing-Sprech.

### Git / GitHub / Commits (ab Umzug zu Claude Code)
* Repository wird auf GitHub geführt (`github.com/NennMichSchinken/...`).
* **Commit-Stil:** kleine, thematisch saubere Commits; Nachricht knapp und sachlich (Englisch ist ok), z.B. `raidframes: add overshield backfill bar`. Kein Marketing, keine Romane.
* **Versionierung:** `## Version:` in der `.toc` bei jedem ausgelieferten Stand hochziehen (SemVer-artig, aktuell 0.9.x im Vor-Release).
* **Releases/Packaging:** Standard ist der **BigWigs Packager** (GitHub Action: Release-Tag → gepacktes Zip → Upload zu CurseForge/Wago). Zuverlässige Baseline bleibt der manuelle Zip-Upload. Die `Libs/` werden mitgepackt (oder via `.pkgmeta`/externals gezogen — beim Einrichten der Action entscheiden).
* **Vor jedem Commit/Build:** alle `.lua` syntaktisch prüfen. **Eingerichtet:** `luacheck` (v1.2.0, Standalone-Binary unter `tools/luacheck.exe`, via `.gitignore` aus dem Repo gehalten) mit projektweiter `.luacheckrc` (WoW-/Ace3-Globals whitelisted, `Libs/`+`tools/` ausgeschlossen). Aufruf: `tools\luacheck.exe .` oder das Helfer-Skript `powershell tools\check.ps1`.
* **Interface-Nummer** in der `.toc` ändert sich pro Patch — beim Packaging prüfen (aktuell `120007`, Patch 12.0.7).

---

## 3. Design-Prinzipien (Kern der Identität)

**Der wichtigste Leitsatz: zwei Ebenen strikt trennen.**

1. **Im-Kampf / Gameplay** (Raidframes, Unit Frames, Nameplates, Cast Bars): **nah am WoW-Original** bleiben. Unter Druck pattern-matched das Auge am schnellsten auf Vertrautes; zu viel Stilisierung kostet Lesbarkeit und Immersion. Hier gilt: „die beste Version des WoW-Looks", **nicht** „fremde App über WoW". Klassenfarbene Balken, vertraute Anordnung, ruhige Defaults.
2. **Meta / Suite** (Einstellungsseite, Branding, Profil-Dialoge): Hier lebt die eigene, moderne Identität voll aus. Das schaut man nie mitten im Kampf an.

Weitere Prinzipien:
* **Flach/modern, aber unverkennbar WoW:** WoWs Wärme/Materialität aufgreifen, die schweren 3D-Glanz-Verläufe rausnehmen, Richtung flat/2026. **Kein generisches Neon-Teal** (die typische Falle beim „custom gehen", siehe EllesmereUI/Ellesmere).
* **Anti-Bloat:** kuratierte, kurze Modulliste; gute Defaults statt hunderter Optionen. „Nur was man wirklich braucht" ist die Identität, nicht ein Reskin.
* **Frei verschiebbar:** alles positionierbar, auf WoWs Edit Mode **aufbauen** statt dagegen. Jeder ordnet es so an, wie er es kennt.
* **Akzentfarbe — WoW-Gold (statt Neon).** Passt zum Namen Lumen (Licht/Gold) und hält näher an WoW.
  * **Im aktuellen Code verwendet:** `#D4A34F` (Maus-Rand der Frames als `SetColorTexture(0.83, 0.64, 0.31, 1)`, der `/lumen`-Print und der ESC-Menü-Button `|cffD4A34F…|r`).
  * **Ursprünglich im Konzept vorgeschlagen:** `#c9a86a`.
  * Beide sind warmes WoW-Gold; **final zu bestätigen** (siehe §8). Wenn final `#c9a86a` gewählt wird, an genau diesen drei Stellen (Style/Edges, Core-Print, GameMenu) angleichen.

---

## 4. Architektur / Aufbau

* **Suite-Shell:** EINE Einstellungsseite. Links eine kuratierte Modulliste (Baum, z.B. Gruppen „Kern"/„QoL"), rechts die Einstellungen des gewählten Moduls. Perspektivisch eine **Live-Vorschau**, die zeigt, was sich ändert. Erweiterbar — Module kommen nach und nach dazu, ohne die Liste aufzublähen. (Aktuell als AceConfig-Baum umgesetzt; eine eigene gerunte „Shell"-Optik ist späteres Thema.)
* **Zentrale Profile** in einem „Allgemein"/Profile-Tab (NICHT pro Modul verstreut): an einem Ort wird alles gespeichert. Läuft über **AceDB** (`LumenDB`).
* **Export (gebaut — v0.9.8, live bestätigt):** EIN Textcode für alles (Prinzip wie WeakAuras/ElvUI), zum Kopieren/Verschicken — via `AceSerializer` + `LibDeflate`. Umgesetzt in `Modules/Share.lua`; UI unten im `Global → Profile`-Tab. Details §10.7.
* **Import — granular (gebaut — v0.9.8, live bestätigt):** Dialog mit **Häkchen pro Modul** — nur Gewähltes wird eingemischt, abgewählte Module bleiben beim Empfänger unverändert (z.B. „will nur deine Unit Frames, nicht die Raidframes"). Dazu eine separate Ja/Nein-Frage „**Layout-Positionen mitimportieren**" (aus → die aktuellen Positionen des Empfängers bleiben). Damit der granulare Import geht, werden die Settings im Export **pro Modul getrennt** abgelegt; **Layout-Positionen liegen nochmal getrennt**. (Umsetzung: sparse Export + Merge-auf-Defaults beim Import; siehe §10.7.)

### 4.1 Strikte UI-Benennungskonvention (Anti-Bloat & Hierarchie-Klarheit)
Um eine absolut intuitive, konsistente und schlanke Benutzeroberfläche zu garantieren, gilt für alle Module (Raidframes, Unit Frames, Nameplates) eine strikte Trennung der Begriffe über die UI-Ebenen hinweg. Es dürfen niemals identische oder redundante Begriffe auf unterschiedlichen Ebenen verwendet werden.

* **Linke Navigationsebene (Der Haupt-Baum in AceConfig):**
    * Der suite-weite Einstellungsbereich für globale Optionen heißt zwingend **`Global`** (NICHT *General* oder *Allgemein*). Dies signalisiert dem Nutzer, dass Änderungen hier das gesamte Addon über alle Module hinweg betreffen.
* **Rechte Navigationsebene (Die Tabs innerhalb eines Moduls):**
    * Der erste Tab eines jeden Moduls heißt zwingend **`Base`** (NICHT *Basic*, *Core* oder *Base Settings*). Hier liegen alle grundlegenden, funktionalen und optischen Fundamente des jeweiligen Moduls (z.B. Farben, Texturen, Dispel-Filter).
    * Das Wort „Settings" ist auf Tabs absolut tabu (Redundanz-Vermeidung).
    * Auf den `Base`-Tab folgen kontext- oder layoutspezifische Tabs, die ebenfalls maximal kurz gehalten werden.

**Skalierungs-Muster für zukünftige Module (Zwingend einzuhalten):**
* **Modul Raidframes:** `Base` | `Raid` | `Group`
* **Modul Nameplates:** `Base` | `Enemy` | `Friendly`
* **Modul Unit Frames:** `Base` | `Player` | `Target` | `Focus`

---

## 5. Scope / Modul-Roadmap

* **MVP = Raidframes (Healer-Qualität).** Eigenständig nutzbar neben bestehenden Addons. Damit wird zuerst die Identität aufgebaut, dann Modul für Modul erweitert.
* **Reihenfolge nach den Raidframes:** **Unit Frames → Nameplates (mit Encounter-Kontext) → QoL** (z.B. M+ Loot-Vorschau, CC-Tracker, kontextsensitive Quick-Actions à la Plumber).
* **Bewusst (vorerst) draußen / erst sehr viel später:**
  * **Encounter-Ansagen** (BigWigs/ExBoss-Klasse) — extrem pflegeintensiv, jede Boss-Mechanik einzeln gewartet. Eigenes Riesenthema, klar nicht MVP.
  * **Auktionshaus-Tools, Groupfinder-Flags** u.ä. — zu nischig für „jeder braucht das".
* **Ehrliche Größenordnung:** Das ist deutlich größer als ein einzelnes Plugin — jedes Modul ist praktisch ein eigenes, oft großes Addon. Deshalb **strikt MVP-first**, ein Modul nach dem anderen sauber fertig.

---

## 6. Tech-Stack & Setup

* **Sprache:** Lua + WoW-API (+ optional XML für Frames). **Kein Build-Schritt** — der WoW-Client interpretiert Lua direkt.
* **Basis-Bibliotheken (Ace3, bereits eingebunden, liegen in `Lumen/Libs/`):**
  * `LibStub`, `CallbackHandler-1.0`
  * `AceAddon-3.0`, `AceConsole-3.0` (Slash-Commands), `AceEvent-3.0` (Events), `AceTimer-3.0`
  * `AceDB-3.0` (SavedVariables + Profile), `AceDBOptions-3.0`
  * `AceGUI-3.0`, `AceConfig-3.0` / `AceConfigDialog-3.0` (Options-Baum)
  * **Eingebunden (v0.9.8) für Export/Import:** `AceSerializer-3.0` (in `Libs/AceSerializer-3.0/`) + `LibDeflate` (1.0.2, Single-File `Libs/LibDeflate/LibDeflate.lua`, via `<Script>` in `embeds.xml`; beide registrieren über LibStub). Für externe Schriften/Texturen optional `LibSharedMedia-3.0` (wird, falls vorhanden, via `LibStub(...,true)` genutzt; nicht zwingend gebündelt).
* **Einbindung der Libs:** über `embeds.xml` (lädt die Lib-XMLs in korrekter Reihenfolge), das in der `.toc` zuerst geladen wird.
* **Addon-Struktur im WoW-Verzeichnis:**
  `World of Warcraft/_retail_/Interface/AddOns/Lumen/`
* **Lade-/Testschleife für Florian:** Addon-Ordner ersetzen → im Spiel `/reload` → testen → Screenshots schicken. (Für Fehler: `/console scriptErrors 1`.)
* **Distribution:** CurseForge und/oder Wago, siehe §2 (BigWigs Packager bzw. manueller Zip-Upload).

---

## 7. Raidframes — MVP-Feature-Liste

**Drin (MVP):**
* Layout am WoW-Original (vertrauter Look: klassenfarbene Balken, Rollen-Icon, Buff/Debuff/HoT-Reihen) — sauber, mit den Optionen unten. **Kein Reskin.**
* **HP-Defizit** klar lesbar gedacht (aktuell sind die Textmodi „Keine / Aktuell / Prozent" umgesetzt; ein dedizierter Defizit-Modus „−X" kann ergänzt werden).
* **Absorb-/Schild-Anzeige** (moderne, flach gehaltene Layer) — **inkl. Overschild bei vollem Leben** (siehe §10).
* **Heilvorhersage** (eingehende Heilung rechts vom Leben).
* **Heilabsorb** (frisst von rechts ins gefüllte Leben).
* **Dispellbare Debuffs** hervorgehoben — gefiltert nach der eigenen Klasse (Magie/Fluch/Gift/Krankheit). (Aktuell als Umfärbung des Lebensbalkens; siehe Grenzen in §10.)
* **HoT-Platzierung** als flexibles Aura-Indikator-System (`Auras`-Tab). *(Phase 1 gebaut + live bestätigt — v0.9.9: eigene HoTs, 9 Anker, Auto-Zentrierung, Auto-Fit, Testmodus-Vorschau; siehe §10.8. Phase 2 offen: exakte Whitelist per Signatur + weitere Kategorien.)*
* **Mouseover-Indikator** (Goldrand am anvisierten/Mouseover-Frame) — vorhanden.
* **Aggro-Warnung.** *(Noch nicht implementiert — geplant.)*
* **Party + Raid**, Anordnung sortierbar (nach Rolle/Gruppe). *(Aktuell einfache Rohrein-/Spalten-Anordnung; Sortierung nach Rolle/Gruppe steht noch aus.)*
* **Gute Defaults**, das Wichtige aber konfigurierbar.
* **Frei positionierbar** (Edit-Mode-tauglich) und an die zentralen Profile angebunden.

**Bewusst draußen (MVP):**
* Riesige Aura-Filter-Engine mit hunderten Optionen (später, kuratiert — Anti-Bloat).
* Tiefe Range-Check-/Aura-Highlight-Frameworks erst nach dem MVP, falls überhaupt.
* Encounter-Ansagen (eigenes, großes Thema, siehe §5).

---

## 8. Offene Entscheidungen & Nächste Schritte

**Erledigt / bestätigt:**
* Name = **Lumen** („a focused UI suite", Marke pur).
* **Ace3** als Basis.
* **Raidframes als MVP**.
* Profil-/Export-/Import-Konzept (Architektur steht; **Export/Import gebaut + live bestätigt — v0.9.8**, siehe §10.7).
* Gradient-Balkenstil bestätigt (zwei Varianten: „Lumen Gradient" kräftig = Default, „Lumen Soft" dezent).
* **Overschild-Backfill** umgesetzt (v0.9.1).
* **Secret-sicheres Render live bestätigt** (Schild/Overschild/Heilabsorb/Heilvorhersage) — v0.9.1.
* **Schild/Heilabsorb-Texturen** final: Blizzard-Texturen (`blizzard-shield`/`blizzard-absorb`) per **manuellem TexCoord-Tiling** (kein `SetHorizTile`) + Clip-Frames an die Absorb-Füllung. Naht/Stauchung gelöst — v0.9.2/.3. (Details + Sackgassen: Memory `lumen-absorb-rendering`.)
* **Layout:** feste 5er-Gruppen + Ausrichtung Vertikal/Horizontal (statt freiem „pro Spalte"-Slider) — v0.9.2.
* **Text-Outline** (Keine/Outline/Dick) für Name & HP — v0.9.3.
* **Dispel im Kampf zuverlässig** (Blizzard-Filter + `GetAuraDispelTypeColor`+Curve), Modi recolor/overlay, Farbe pro Typ — v0.9.3.
* **Settings-Restruktur** live: linker Knoten **`Global`**, Raidframes-Tabs **`Base | Raid | Group`** (Konvention §4.1). Layout, **Position UND Name-/HP-Text getrennt pro Kontext** (raid/party) inkl. einmaliger Profil-Migration — v0.9.4/.5.
* **Git:** läuft über GitHub (`NennMichSchinken/Lumen`); PR #1 (Addon+Absorbs) und PR #2 (Kontexte/Dispel/Layout/Text) gemergt. **v0.9.6** = Click-to-Cast Phase 1 (Secure-Header) + luacheck-Setup.
* **Click-Cast Phase 2 live bestätigt — v0.9.7:** eigenes Modul `Modules/ClickCast.lua` + eigener Options-Knoten **`Click-Cast`**. Klick-Bindings (Maustaste + optionaler Modifier-Schalter Shift/Strg/Alt) und **Hovercast** (Taste auf `@mouseover` via globalem Secure-Button + `SecureHandlerStateTemplate`-Driver). Typen Ziel/Menü/Spell/Dispel/Rez, **pro Spec** (Spec-Auswahl-Dropdown im Panel, entkoppelt von der Live-Spec; folgt automatisch der aktiven Spec). Spell-Liste mit Icon, Suche + Filter „nur hilfreiche Zauber" (Default an). Settings-Baum jetzt: **`Global` (Tabs Base|Profile) · `Click-Cast` · `Raidframes`**. Details §10.6.
  * **Wichtige Gotcha (live geklärt):** Funktioniert SHIFT-Klick nicht, obwohl Strg/Alt gehen → meist WoWs **Selbstzauber-/Fokus-Zauber-Taste = Shift** (Optionen→Kampf) oder eine harte Tastenbelegung. Kein Lumen-Bug.
* **Export/Import live bestätigt — v0.9.8:** eigenes Modul `Modules/Share.lua`, UI unten im `Global → Profile`-Tab (Profil-Verwaltung + Teilen bewusst an einem Ort). EIN Code via `AceSerializer`+`LibDeflate`, granular pro Modul (Häkchen) + getrennter Schalter „Layout-Positionen mitimportieren". Sparse Export + Merge-auf-Defaults beim Import (robust gegen AceDB-Lazy-Defaults + versions-tolerant). Details §10.7. **Offen:** echter Transfer-Test an Zweitchar/Freund (Florian testet später, meldet Feedback). Gleicher Patch: Click-Cast-Spec-Dropdown füllt sich jetzt auch beim allerersten Öffnen (war vor dem Login blank).
* **Aura-Indikatoren / `Auras`-Tab live bestätigt — v0.9.9 (Phase 1 von 2):** flexibles Icon-System als neuer Raidframes-Tab (`Base | Raid | Group | Auras`), Vorbild EllesmereUIs Aura-Tab, kuratiert. Phase 1 = eigene HoTs: 9 Anker + Wachstumsrichtung, **Auto-Zentrierung** bei mittigen Ankern (anhand echter Icon-Zahl), **Auto-Fit** (Größe aus Frame-Höhe, gedeckelt an Breite/Höhe → kein Überlauf), Cooldown-Swipe (secret-sicher via Duration-Objekt), **Testmodus-Vorschau** (Florians Anforderung). Erkennung über `HELPFUL|PLAYER`-Filter (zeigt Phase 1 ALLE eigenen Hilfsauren). Gleicher Patch: Healabsorb-Overlay kachelt jetzt auch vertikal in fester Pixelgröße (kein Strecken auf hohen Frames); Schild bleibt vertikal geclampt (256×40 = keine Zweierpotenz → vertikales REPEAT zeigte eine Naht). Details §10.8. **Phase 2 offen:** exakte HoT-Whitelist per Spec-Signatur (Kampf-Präzision) + weitere Kategorien (fremde HoTs / Defensives / Debuffs / CDs).

**Offen:**
* **Akzentfarbe final** festlegen: aktuell im Code `#D4A34F`, ursprünglich vorgeschlagen `#c9a86a` (siehe §3).
* „Lumen" auf CurseForge/Wago auf Verfügbarkeit prüfen.
* Reihenfolge/Feinschnitt der Module nach den Raidframes (Grobplan steht: Unit Frames → Nameplates → QoL).
* Familien-Verbindung zu einem evtl. zweiten Projekt bewusst NICHT über den Produktnamen (falls später gewünscht: gemeinsames Macher-/Studio-Label).

**Release-Hygiene — ABZUARBEITEN kurz vor dem Public-Gehen (Repo ist aktuell privat):**
> Hintergrund: EllesmereUI dient Lumen ausschließlich als **Lern-/Performance-Benchmark**. Es wird **nichts 1:1 kopiert** — alle Muster sind eigenständig adaptiert/neu geschrieben (Florian + KI). Es besteht daher **keine Attributionspflicht**. Die folgenden Schritte sind reine **Wahrnehmungs-Hygiene** fürs Portfolio: nach außen soll nichts mehr auf EllesmereUI verweisen, damit es bei flüchtigem Lesen nicht „abgekupfert" wirkt. Vor dem Release einmal gebündelt abarbeiten:
> 1. **EllesmereUI-Verweise aus dem ausgelieferten Code entfernen** — aktuell 4 Kommentare: `EditMode.lua:7`, `GameMenu.lua:7`, `Modules/Raidframes.lua:4` und `:6`. Generisch umformulieren („secret-sicheres 12.0-Vorgehen") statt Namedrop.
> 2. **`CLAUDE.md` aus dem öffentlichen Repo nehmen:** `git rm --cached CLAUDE.md` + Eintrag in `.gitignore`. Datei bleibt lokal liegen und wird von Claude Code weiter geladen — nur nicht mehr im Repo.
> 3. **Backup der `CLAUDE.md`:** in ein **separates privates Repo** spiegeln (Vision-Doku bleibt versioniert/abgesichert, ohne im Public-Addon-Repo zu liegen).
> 4. **Optional Git-Historie putzen** (`git filter-repo`), falls auch alte Commits keine `CLAUDE.md`/EllesmereUI-Spur enthalten sollen — sonst genügt das Untracken, weil das Repo bis dahin privat war.
> 5. **Gegencheck:** kein wörtlich kopierter EllesmereUI-Code im Release (Adaption ist fein; 1:1-Kopie ohne Lizenzblick nicht). README ist bereits sauber (kein EllesmereUI).

**Nächste Schritte (konkret, in Reihenfolge):**
1. ~~Frames anklickbar/targetbar/Click-to-Cast~~ **✓ Phase 1 erledigt (v0.9.6, live bestätigt):** Frames laufen auf `SecureGroupHeader`/`SecureUnitButtonTemplate`; Linksklick=Ziel, Rechtsklick=WoW-Menü (12.0.7-Secure-Proxy), klick-/targetbar auch im Kampf. Architektur-Details siehe §10.3/§10.5.
2. ~~**Click-Cast Phase 2 — volle Bindings-Seite**~~ **✓ erledigt (v0.9.7, live bestätigt):** Klick + Hovercast, per-Spec, Typen Ziel/Menü/Spell/Dispel/Rez. Siehe §10.6. **Offen/später (in eigener Suite-Shell):** echte Typeahead-Spell-Suche (AceConfig kann nur Suchfeld-filtert-Dropdown bei Enter, kein Live-Combobox); optional Item-/Makro-/Smart-Rez-Bindings; Mount-/Vehicle-Guard auf Hovercast.
3. ~~Export/Import bauen~~ **✓ erledigt (v0.9.8, live bestätigt):** EIN Code via `AceSerializer`+`LibDeflate`, granular pro Modul + getrennter Layout-Schalter; UI im `Global → Profile`-Tab. Modul `Modules/Share.lua`. Siehe §10.7. **Offen:** echter Transfer-Test an Zweitchar/Freund.
4. **HoT-Platzierung Phase 1 ✓ erledigt (v0.9.9, live bestätigt):** Aura-Indikator-System (`Auras`-Tab), eigene HoTs — siehe §10.8. **← HIER GEHT ES WEITER:** restliche kleine MVP-Features (Sortierung nach Rolle/Gruppe · Aggro-Warnung) **und HoT-Phase 2** (exakte Whitelist per Signatur + weitere Aura-Kategorien). Konzept Sortierung/Aggro mit Florian schon vorbesprochen: Sortierung = **Kategorie-Prioritätsliste** (secure-konform; freies Drag&Drop erst in der Shell); Aggro = **Rand + Overlay + „Aggro"-Text** (Vollmodus) bzw. nur Rand (schlank), Idee 2-stufig gelb/rot. *(Alternativ/parallel: Start der eigenen Suite-Shell-Optik — Florian hat ein Click-Cast-Mockup als Zielbild. Empfehlung: erst die kleinen MVP-Lücken, dann die Shell als fokussierter Design-Block.)*
5. Feinschliff (abgerundete Ecken als Toggle, Overschild-Kantenfunke, native Edit-Mode-Vollregistrierung, EditMode-Grabfläche im Live-Header) → erstes Release (BigWigs Packager, Tag/Release als Restore-Punkt).

---

## 9. Code- & Performance-Richtlinien (Strikte, autonome Vorgaben für die KI)

Lumen ist als **Anti-Bloat-/Hochleistungs-UI** konzipiert. Der generierte Lua-Code MUSS höchsten Performance- und Sauberkeitsansprüchen genügen. Halte dich strikt an Folgendes (Stand WoW Retail 2026, „The War Within" und neuer):

1. **Striktes lokales Scoping.** Jede Variable, Funktion und Bibliotheks-Referenz wird als `local` deklariert. Häufig genutzte Globals/API-Funktionen als `local` upvalues an den Dateikopf ziehen (`local UnitHealth = UnitHealth`). **Globale Variablen sind tabu** (verhindert Memory-Leaks und Namenskonflikte mit anderen Addons).
2. **Event-getrieben statt OnUpdate-Polling.** Nutze gezielte Unit-Events (`UNIT_HEALTH`, `UNIT_MAXHEALTH`, `UNIT_ABSORB_AMOUNT_CHANGED`, `UNIT_HEAL_ABSORB_AMOUNT_CHANGED`, `UNIT_HEAL_PREDICTION`, `UNIT_AURA` …) statt pro Frame zu pollen. **Kein Code-Spamming in `OnUpdate`** — der läuft mit der Framerate (oft 100–200×/s). Wenn `OnUpdate` unvermeidbar ist, throttle hart (Akkumulator) und halte den Body minimal.
3. **Keine Garbage-Erzeugung in heißen Pfaden.** In häufig feuernden Handlern (`COMBAT_LOG_EVENT_UNFILTERED`, Frame-Updates) NIEMALS temporäre Tabellen `{}` oder neue Frames dynamisch erzeugen. Tabellen **wiederverwenden** (recyceln/poolen). Closures in Hot-Loops vermeiden (sie allokieren).
4. **Frames poolen, nicht ständig neu erstellen.** Unit-Frames einmal anlegen und wiederverwenden (so macht es Lumen bereits: `frames[i]`-Pool, überzählige werden `:Hide()`-t).
5. **SetPoint-/Layout-Churn vermeiden.** Statische Anker einmal beim Erstellen setzen, nicht pro Update neu. Wenn sich Layout nur bei Größen-/Positionsänderung ändert, per „dirty"-Flag/Cache neu setzen (EllesmereUI cached z.B. Position/Höhe via `_lpPos/_lpH`).
6. **Moderne API nutzen.** `C_Timer.After`/`C_Timer.NewTicker` statt selbstgebauter Frame-Ticker. Aktuelle Namespaces bevorzugen. Bei Unklarheit über eine API-Funktion **nachfragen oder in EllesmereUI nachsehen**, statt veralteten Code zu schreiben.
7. **Secret Values (12.0) korrekt behandeln.** In WoW 12.0 sind viele Werte im Kampf „secret" (u.a. `UnitHealth`, `UnitHealthMax`, `UnitGetTotalAbsorbs`, `UnitGetTotalHealAbsorbs`, `UnitGetIncomingHeals`, Aura-`dispelName`). **Niemals Lua-Arithmetik oder Vergleiche auf secret-Werten** (wirft Fehler). Stattdessen: secret-Werte direkt an C++-APIs geben, die sie akzeptieren (`StatusBar:SetValue`, `SetMinMaxValues`), und Geometrie/Positionierung über **Clip-Frames** lösen. `maxHealth` immer über den **HealPrediction-Calculator** holen (nicht `UnitHealthMax`). Secret-berührende Aufrufe defensiv in `pcall` kapseln.
8. **Sauberes Aufräumen.** Event-Registrierungen und Hooks bedacht setzen; keine doppelten Registrierungen. Keine `:SetFrameLevel`-Eingriffe an Unit-Frames **nach** dem Erstellen, wenn interne Bar-Ebenen relativ zur Erzeugungs-Basis gesetzt wurden (das zerschießt die Schichtung — in Lumen bewusst beachtet).
9. **OOP nur wo nötig.** Ace3-OOP (Module/Mixins) ist okay für die Architektur. In den **heißen Pfaden** (Render/Update) flach und linear bleiben; Metatables/`__index`-Lookups dort meiden.

**EllesmereUI als Benchmark — verbindlicher Hinweis für die neue KI:**

> Wir nutzen **EllesmereUI** als absolute Benchmark für Performance und elegante Code-Lösungen. Der Nutzer hat das Repository lokal auf seiner Festplatte unter `E:\Github\EllesmereUI` geklont. Wenn du (Claude Code) bei komplexen Architekturfragen unsicher bist, die WoW-API hakt oder du nach der effizientesten Lösung für ein Problem suchst, greife bitte direkt auf diesen lokalen Ordner zu. Analysiere dort, wie Ellesmere die entsprechenden Herausforderungen gelöst hat, und adaptiere diese Best Practices für unseren Lumen-Code.

*Konkrete, bereits genutzte Referenzdateien in diesem Repo:* `EllesmereUIRaidFrames/EllesmereUIRaidFrames.lua` (das Dual-Clip-Absorb-System, der HealPrediction-Calculator, Heilabsorb-Reverse-Fill — die Basis unseres aktuellen Render-Codes), `EllesmereUI.lua` (ESC-Menü-Button-Integration), `EllesmereUINameplates/*` (Calculator-Nutzung auf Nameplates für später).

**Zweite Referenzquelle — WoW-Addon-Dev-Guide (12.0.5):** Lokal geklont unter `E:\Github\WoWAddonDevGuide` (Repo: `Amadeus-/WoWAddonDevGuide`, Branch `master`). Eine aus den WoW-Quelldateien generierte Wissensdatenbank. **Achtung Stand:** Der Guide ist auf **12.0.5**, der Live-Patch ist seit 16.06.2026 **12.0.7** (Interface 120007) — also **eine Minor-Version hinterher**. Für unsere Themen (Secret-Values, Ace3, Render) sind die Patterns weiterhin gültig, aber bei brandneuen 12.0.6/12.0.7-API-Details lieber gegen das Warcraft-Wiki (`Patch_12.0.7/API_changes`) gegenprüfen und per `git -C E:\Github\WoWAddonDevGuide pull` aktualisieren, sobald der Guide nachzieht. Nutze sie als API-/Pattern-Nachschlagewerk, wenn die WoW-API hakt oder du eine 12.0-Secret-/Taint-Frage klären musst (EllesmereUI bleibt die Benchmark für *konkreten Render-Code*; dieser Guide ist die Benchmark für *API-Korrektheit*). Wichtigste Dateien für uns: `12a_Secret_Safe_APIs.md` (komplette Secret-Values-Referenz — unser Kernthema), `09a_Ace3_Library_Guide.md` (unser Stack), `03_UI_Framework.md` und Blizzards `SecureTemplates.lua`-Verweise (relevant für den nächsten großen Schritt: Click-to-Cast/Secure-Buttons), `12_API_Migration_Guide.md`. Beim Lesen die Blöcke zwischen `<!-- CLAUDE_SKIP_START -->` und `<!-- CLAUDE_SKIP_END -->` überspringen (menschen-orientiert). Das mitgelieferte `/wow`-Command + `WoWAddon-Expert`-Agent-Setup (Ordner „Claude AI Commands (optional)") nutzen wir bewusst **nicht** — unser direkter Workflow mit dieser CLAUDE.md als Single Source of Truth ersetzt den Coordinator/Worker-Umweg (Anti-Bloat). Bei Bedarf später per `git -C E:\Github\WoWAddonDevGuide pull` aktualisieren.

---

## 10. Aktueller Entwicklungsstand (Ist-Zustand des Codes, v0.9.9)

### 10.1 Dateien im Addon-Ordner `Lumen/`

| Datei | Zweck (aktueller Stand) |
|---|---|
| `Lumen.toc` | Deklariert Addon. `## Interface: 120007`, `## SavedVariables: LumenDB`, `## Author: NennMichSchinken`, `## Version: 0.9.9`. Lädt in Reihenfolge: `embeds.xml`, `Core.lua`, `EditMode.lua`, `Style.lua`, `Modules\Raidframes.lua`, `Modules\ClickCast.lua`, `Modules\Share.lua`, `Options.lua`, `GameMenu.lua`. |
| `embeds.xml` | Lädt die Ace3-Libs aus `Libs/` in korrekter Reihenfolge (LibStub → CallbackHandler → AceAddon/Console/Event/Timer → AceDB → AceGUI → AceConfig → AceDBOptions → **AceSerializer** → **LibDeflate**). |
| `Core.lua` | Erzeugt das Ace3-Addon, initialisiert AceDB (`LumenDB`) mit den Defaults, registriert `/lumen` und `/lu`, startet das Raidframes-Modul. Details unten. |
| `EditMode.lua` | Generische Registry für verschiebbare Frames. Manueller Schalter („Rahmen entsperren") **und** Hook in WoWs nativen Edit Mode (über `PLAYER_LOGIN`-Hook auf `EditModeManagerFrame` Enter/Exit). Gold-Overlays mit Label; speichert Position via Callback ins Profil. |
| `Style.lua` | **Zentrales** Balken-Stilmodul (bewusst zentral/wiederverwendbar für spätere Unit Frames/Target/Focus). Hält `Style.barTexture` (lumen-gradient) und `Style.barTextureSoft`. `Style:ApplyBar(statusbar, overlayParent)` setzt die Gradient-Textur und legt Licht-/Schatten-Tiefen-Overlays an. `Style:SetDepth(overlayParent, strength)` regelt die Tiefen-Deckkraft (1.0 Standard, 0.55 Soft, 0 aus). |
| `Modules/Raidframes.lua` | Das MVP-Modul. Secret-sicheres Rendering von Leben/Schild/Heilabsorb/Heilvorhersage über StatusBars + Clip-Frames. Event-getrieben. Render in `Decorate(host)` faktorisiert: **Live** = Secure-Buttons über `SecureGroupHeader` (klick-/targetbar, Phase 1), **Test** = Nicht-Secure-Preview-Pool. Default-Klicks (Links=Ziel, Rechts=Menü-Proxy) als `ns.RF_ApplyDefaultClicks`/`ns.RF_GetMenuProxy` exponiert (ClickCast stellt sie bei „deaktiviert" wieder her). **Seit v0.9.9:** Aura-Indikator-System (Icon-Pool je Frame, `AURA_CATS`-Registry, `layoutAuraCat`/`positionAuraIcons`/`RenderAurasLive`/`RenderAurasFake`) — Details §10.8. Details unten (§10.5). |
| `Modules/ClickCast.lua` | **Click-Cast (Phase 2).** Setzt pro Secure-Button die Klick-Attribute (Maustaste+Modifier → `type/spell/macrotext`, OOC, kampf-aufgeschoben) und betreibt **Hovercast** über einen globalen Secure-Button (`LumenCCHover`) + `SecureHandlerStateTemplate`-Driver (`[@mouseover,exists]` routet Tasten via `SetBindingClick`). Spell/Dispel/Rez laufen IMMER über `@mouseover`-Makros (ein Pfad für Klick UND Hover); Ziel/Menü über die `click`-Proxys. Bindings **pro Spec** in `db.profile.clickCast.specs[specID]`. API u.a. `ns.CC_RegisterButton` (Naht), `CC:ApplyBindings`, `CC:GetBindings/AddBinding/RemoveBinding(specID,…)`, `CC:GetClassSpells/GetSpecList/KeyParts/BuildKey`. Details §10.6. |
| `Modules/Share.lua` | **Export/Import (v0.9.8).** Codec `AceSerializer:Serialize → LibDeflate:CompressDeflate → EncodeForPrint` (und zurück; Decode strippt Whitespace, prüft `addon=="Lumen"`). Payload `{ v=1, addon, modules={raidframes,clickCast}, layout={raidframes={raid,party = {point,x,y}}} }`. Modul-Registry `MODULES` (`{key,label}`) → Options baut Import-Häkchen dynamisch via `Share:GetModules()`. `Share:Export()` (sparse — nur abweichende Werte, da AceDB Defaults lazy hält), `Share:Decode(str)`, `Share:Import(payload, selected, withLayout)` (merged auf frische `ns.Defaults`-Kopie → füllt fehlende Felder; Positionen nur bei `withLayout`, sonst eigene behalten; danach `Lumen:RefreshAll()`). Details §10.7. |
| `Options.lua` | AceConfig-Optionsbaum (`childGroups="tree"`): linker Baum = **`Global`** · **`Click-Cast`** · **`Raidframes`**. **`Global`** ist `childGroups="tab"` → Tabs **`Base`** (Edit-Mode-Schalter, Positionen zurücksetzen) und **`Profile`** (AceDBOptions + unten der Export/Import-Bereich aus `ns.Share`: Export-Knopf+Textbox, Import-Textbox mit dynamischen Modul-Häkchen + Layout-Schalter + „Import ausführen" mit Bestätigung). **`Click-Cast`** = dynamische, in-place neu gebaute Binding-Zeilen (`rebuildCC`+`AceConfigRegistry:NotifyChange`): Aktiviert-Toggle, Spec-Auswahl, „nur hilfreiche Zauber"-Filter, je Zeile (inline-group) Maustaste/Modifier bzw. `keybinding`, Aktion, Spell (Suche+Icon), OOC, Freund/Feind (Hovercast). **`Raidframes`** `childGroups="tab"` → **`Base`** · **`Raid`** · **`Group`** · **`Auras`** (`rf().raid`/`rf().party`; `Auras` über `auraGetSet("hotsOwn")` auf `rf().auras[catKey]`, §10.8). Benennung §4.1. |
| `GameMenu.lua` | Fügt im ESC-Menü einen „Lumen"-Button hinzu — über Blizzards eigene `GameMenuFrame:AddButton`-API (per `InitButtons`-Hook), damit es konfliktfrei neben EllesmereUI sitzt. Öffnet die Config; respektiert `InCombatLockdown`. |
| `Libs/` | Ace3-Bibliotheken (siehe §6). |
| `Textures/` | TGA-Texturen (uncompressed RGBA, **ohne Endung referenziert**). Wichtig: `lumen-gradient` / `lumen-gradient-soft` (Balken), `lumen-light` / `lumen-shadow` (Tiefe), `shield-combined` (Schild = Füllung+Streifen in einer Textur), `healabsorb-combined` (Heilabsorb = Füllung+Kreuze). Zusätzlich Einzel-/Altbestände: `shield-fill`, `shield-overlay`, `shield-overshield`, `absorb-fill`, `raidframeabsorboverlay`, `absorb-overabsorb` (Overschild-Kante derzeit ungenutzt, für späteres Re-Enable behalten). |

### 10.2 Ace3- und AceDB-Initialisierung (exakte Struktur)

`Core.lua` legt das Addon als Ace3-Objekt an und mischt `AceConsole` + `AceEvent` ein:

```lua
local ADDON, ns = ...

local Lumen = LibStub("AceAddon-3.0"):NewAddon("Lumen", "AceConsole-3.0", "AceEvent-3.0")
ns.Lumen = Lumen
```

Die **Defaults-Tabelle** ist die maßgebliche Struktur des Profils. Alle Module lesen ihre Settings unter `self.db.profile.<modul>`. Aktuell existiert nur `raidframes`:

```lua
local defaults = {
    profile = {
        raidframes = {
            enabled        = true,

            -- Layout + Position PRO KONTEXT (siehe Tabs Base/Raid/Group). Gruppengröße
            -- fest 5. orientation: "vertical"=Mitglieder untereinander/Gruppen nebeneinander
            -- (Standard) | "horizontal"=umgekehrt. raid=Schlachtzug, party=5er/Dungeon.
            -- Migration kopiert alte flache Werte einmalig in raid+party (Core.migrateLayout).
            -- Enthält außerdem die Name-/HP-Text-Felder PRO KONTEXT (showName, nameSize,
            -- namePoint/X/Y, nameColor, nameOutline, healthTextType/Size/Point/X/Y/Color/Outline),
            -- da Frames je Kontext unterschiedlich groß sind. Migration (Core.migrateLayout, v2).
            raid  = { width=114, height=60, ..., point="CENTER", x=0, y=-120, showName=true, ... },
            party = { width=114, height=60, ..., point="CENTER", x=0, y=-120, showName=true, ... },

            -- Lebensbalken (geteilt)
            healthTexture  = "Lumen Gradient",   -- "Lumen Gradient" | "Lumen Soft" | "Blizzard" | "Classic Raid" | LSM-Texturen
            useClassColor  = true,
            fillColor      = { r = 0.20, g = 0.60, b = 0.30 },
            healPrediction = true,

            -- Schilde (eigene Texturen; immer sichtbar bei Schild, inkl. Overschild)
            absorbStyle     = "Blizzard",        -- (Altbestand im Profil; wird vom aktuellen Render NICHT mehr gelesen)
            healAbsorbStyle = "Blizzard",        -- (Altbestand; ungenutzt)
            healAbsorbColor = { r = 1, g = 1, b = 1 }, -- (Altbestand; ungenutzt)

            -- Text: Name
            showName  = true,
            nameSize  = 12,
            namePoint = "TOPLEFT",
            nameX     = 4,
            nameY     = -3,
            nameColor = { r = 1, g = 1, b = 1 },

            -- Text: HP-Anzeige
            healthTextType  = "Aktuell",         -- "Keine" | "Aktuell" | "Prozent"
            healthTextSize  = 16,
            healthTextPoint = "CENTER",
            healthTextX     = 0,
            healthTextY     = 0,
            healthTextColor = { r = 1, g = 1, b = 1 },

            -- Dispel (secret-sicher: Blizzard-Filter + Color-Curve, funktioniert im Kampf)
            dispelEnabled = true,
            dispelMode    = "recolor",   -- "recolor" (Balken einfärben) | "overlay" (Rand+Overlay, Klassenfarbe bleibt)
            dispelShowAll = false,        -- false = nur eigene dispellbare; true = alle
            dispelAlpha   = 0.30,         -- Overlay-Deckkraft (nur "overlay")
            dispelColors  = { Magic=..., Curse=..., Disease=..., Poison=... },  -- pro Typ, {r,g,b}

            -- (Position liegt jetzt pro Kontext in raid/party oben — kein flaches point/x/y mehr.)

            -- Aura-Indikatoren (v0.9.9; Phase 1: eigene HoTs). Layout geteilt über raid/party,
            -- nur die Größe ist kontextabhängig (autoFit aus L.height + Breiten/Höhen-Deckel).
            auras = {
                hotsOwn = { enabled=true, anchor="BOTTOMLEFT", grow="RIGHT", spacing=2,
                            maxIcons=5, autoFit=true, sizeRaid=16, sizeParty=22,
                            showSwipe=true, hideTooltips=false },  -- Details §10.8
            },

            -- Test / Beispielgruppe
            testMode = false,
            testSize = 5,
        },
    },
}
```

> **Hinweis für Claude Code:** `absorbStyle` / `healAbsorbStyle` / `healAbsorbColor` sind **Altlasten** im Profil — der aktuelle Render-Code liest sie nicht mehr (Schild/Heilabsorb nutzen feste kombinierte Texturen). Sie können bei einer Profilbereinigung entfernt werden; sie schaden aber nicht.

Initialisierung in `OnInitialize` (AceDB + Optionen + Profil-Callbacks + Slash-Commands):

```lua
function Lumen:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("LumenDB", defaults, true)  -- true = Default-Profil pro Charakter
    if ns.SetupOptions then ns.SetupOptions() end

    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshAll")
    self.db.RegisterCallback(self, "OnProfileCopied",  "RefreshAll")
    self.db.RegisterCallback(self, "OnProfileReset",   "RefreshAll")

    self:RegisterChatCommand("lumen", "OpenConfig")
    self:RegisterChatCommand("lu",    "OpenConfig")

    self:Print("geladen. |cffD4A34F/lumen|r öffnet die Einstellungen.")
end
```

`OnEnable` startet das Modul, `RefreshAll` reagiert auf Profilwechsel, `OpenConfig` öffnet den AceConfig-Dialog:

```lua
function Lumen:OnEnable()
    if ns.Raidframes then
        ns.Raidframes:Setup()
        if self.db.profile.raidframes.enabled then
            ns.Raidframes:Enable()
        end
    end
end

function Lumen:RefreshAll()
    if not ns.Raidframes then return end
    if self.db.profile.raidframes.enabled then
        ns.Raidframes:Enable()
        ns.Raidframes:UpdateLayout()
    else
        ns.Raidframes:Disable()
    end
end

function Lumen:OpenConfig()
    LibStub("AceConfigDialog-3.0"):Open("Lumen")
end
```

Module hängen sich über die Datei-Upvalue `ns` ein (`ns.Raidframes`, `ns.Style`, `ns.EditMode`, `ns.SetupOptions`). Jede Modul-Datei beginnt mit `local ADDON, ns = ...`.

### 10.3 Raidframes-Render-Architektur (das Herzstück, secret-sicher)

> **Seit v0.9.6** sitzt dieser Stack über `Decorate(host)` auf zwei Host-Typen: dem **Secure-Button** (Live, vom `SecureGroupHeader`) und dem **Nicht-Secure-Preview-Frame** (Test). Die folgende Schichtung gilt für beide identisch — nur Show/Hide steuert bei Secure-Buttons der Header (siehe §10.5).

Pro Einheit dekoriert `Decorate(host)` den Host mit dieser Schichtung (Frame-Level relativ zur Erzeugungs-Basis `base`):

* `f.bg` — dunkler Hintergrund (`#1c1c1c` artig).
* `f.health` (StatusBar, `base+2`) — der **Lebensbalken** (Gradient-Textur, getönt per Klassen-/Dispel-/Füllfarbe). Seine **Fülltextur** (`GetStatusBarTexture()`) steuert die Anker aller Clips.
* `f.missClip` (Frame, `base+3`, `SetClipsChildren`) — **Fehl-Bereich** rechts vom aktuellen Leben. Verankert: `TOPLEFT = hpTex TOPRIGHT (-1,0)`, `BOTTOMRIGHT = f.health BOTTOMRIGHT`. Enthält:
  * `f.predictBar` (StatusBar) — **Heilvorhersage** (grün), ankert links an der Leben-Kante, füllt nach rechts.
  * `f.shieldBar` (StatusBar) — **Schild FORWARD**, ankert links an der Leben-Kante, füllt in den freien Platz.
* `f.curClip` (Frame, `base+4`, `SetClipsChildren`) — **Füll-Bereich** (gefülltes Leben). Verankert: `TOPLEFT = f.health TOPLEFT`, `BOTTOMRIGHT = hpTex BOTTOMRIGHT`. Enthält:
  * `f.backfillBar` (StatusBar, **Reverse-Fill**, `SetAllPoints(f.health)`) — **Schild BACKFILL/Overschild**: legt den Schild bei (fast) vollem Leben von rechts übers Leben.
* `f.healClip` (Frame, `base+5`, `SetClipsChildren`) — ebenfalls Füll-Bereich, über dem Schild-Backfill. Enthält:
  * `f.healAbsorbBar` (StatusBar, **Reverse-Fill**, rechtsbündig an `hpTex`) — **Heilabsorb**, frisst von rechts ins gefüllte Leben.
* `f.overlay` (Frame, `base+6`) — Tiefen-Overlay (über `Style`), Name-Text, HP-Text, Mouseover-Goldränder.

**Das secret-sichere Kernprinzip (von EllesmereUI übernommen):** Alle Bars teilen die Skala `0..maxHealth` und bekommen **rohe** (ggf. secret) Werte via `SetValue`. Es wird **nie** Lua-Arithmetik auf secret-Werten gemacht — die **Clip-Frames erledigen die Geometrie** (`min(absorb, leben)` und `max(0, absorb-leben)` rein visuell). Forward- und Backfill-Schild bekommen denselben rohen Absorb; die zwei Clips teilen ihn automatisch korrekt über die Leben-Kante auf → **Schild ist immer sichtbar, auch bei vollem Leben.**

Zentrale Wertzuweisung (vereinfacht):

```lua
local function setSegments(f, maxH, healthVal, incoming, absorb, healAbsorb)
    f.health:SetMinMaxValues(0, maxH);        f.health:SetValue(healthVal)
    f.predictBar:SetMinMaxValues(0, maxH);    f.predictBar:SetValue(incoming or 0)
    f.shieldBar:SetMinMaxValues(0, maxH);     f.shieldBar:SetValue(absorb or 0)
    f.backfillBar:SetMinMaxValues(0, maxH);   f.backfillBar:SetValue(absorb or 0)
    f.healAbsorbBar:SetMinMaxValues(0, maxH); f.healAbsorbBar:SetValue(healAbsorb or 0)
end
```

Live-Werte (secret-sicher): `maxHealth` kommt aus dem Calculator, die übrigen Werte roh:

```lua
-- ein wiederverwendeter Calculator, je Einheit gefüttert:
UnitGetDetailedHealPrediction(u, nil, calc)        -- in pcall
calc:SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)
local maxH     = calc:GetMaximumHealth()           -- NICHT UnitHealthMax (secret!)
local incoming = UnitGetIncomingHeals(u)           -- roh, ggf. secret
local absorb   = UnitGetTotalAbsorbs(u)            -- roh
local healAbs  = UnitGetTotalHealAbsorbs(u)        -- roh
setSegments(f, maxH, UnitHealth(u), incoming, absorb, healAbs)
```

Testmodus speist dieselben Bars/Clips mit Fake-Zahlen (kein secret) — identischer Pfad, daher gilt: was im Test korrekt aussieht, stimmt live mit hoher Wahrscheinlichkeit auch.

Event-getrieben: `container` registriert `UNIT_HEALTH/MAXHEALTH/ABSORB_AMOUNT_CHANGED/HEAL_ABSORB_AMOUNT_CHANGED/HEAL_PREDICTION/AURA` + Roster-Events; ein `unitToFrame`-Mapping leitet Unit-Events ans richtige Frame. Kein `OnUpdate`-Polling.

### 10.4 Was bereits fehlerfrei funktioniert (von Florian bestätigt)

* Addon lädt ohne Fehler; `/lumen`, `/lu` und ESC-Menü-Button („Lumen") öffnen die Optionen, konfliktfrei neben EllesmereUI.
* **Secret-sicheres Render LIVE bestätigt:** Schild (frei + Overschild bei vollem Leben), Heilabsorb (von rechts), Heilvorhersage — auch im Kampf korrekt; Forward↔Backfill nahtlos. Texturen über manuelles TexCoord-Tiling + Clip-Frames (keine Naht/Stauchung mehr).
* **Dispel im Kampf** zuverlässig (Blizzard-Filter + `GetAuraDispelTypeColor`+Curve); Modi recolor/overlay; Farbe pro Typ.
* Klassenfarben; Profile; Größen; **Ausrichtung Vertikal/Horizontal** bei festen 5er-Gruppen.
* Testmodus 5/20/40; Verschieben (manueller Schalter + nativer WoW-Edit-Mode), **getrennte Position pro Kontext**.
* **Name-/HP-Text pro Kontext** (Raid/Group) inkl. Outline-Option (Keine/Outline/Dick).
* Options-Struktur: linker Baum **`Global` (Tabs Base|Profile) / `Click-Cast` / `Raidframes`**; Raidframes-Tabs **`Base | Raid | Group`**.
* **Click-Cast (v0.9.7):** Klick-Bindings + Hovercast, per-Spec, Spell-Suche+Icon+Hilfreich-Filter, Spec-Auswahl folgt der aktiven Spec (§10.6); Spec-Dropdown füllt sich seit v0.9.8 auch beim ersten Öffnen (vor dem Login).
* **Export/Import (v0.9.8):** EIN Code, granular pro Modul + Layout-Schalter, im `Global → Profile`-Tab (§10.7).

### 10.5 Aktueller Stand & nächster Schritt für Claude Code

**Stand:** **v0.9.9**. Render, Dispel, Layout/Ausrichtung, Text/Outline und die Base/Raid/Group-Tab-Struktur sind gebaut + live bestätigt. **v0.9.6:** Click-to-Cast **Phase 1** (Secure-Unit-Buttons über `SecureGroupHeader`, Links=Ziel/Rechts=Menü, auch im Kampf) + `luacheck`. **v0.9.7 (live bestätigt):** Click-to-Cast **Phase 2** — eigenes Modul + Options-Knoten, Klick- und Hovercast-Bindings pro Spec (§10.6). **v0.9.8 (live bestätigt):** Export/Import (`Modules/Share.lua`, §10.7) + Spec-Dropdown-Blank-Fix. **v0.9.9 (live bestätigt):** Aura-Indikatoren / `Auras`-Tab Phase 1 (eigene HoTs; §10.8) + Healabsorb-Overlay-Tiling-Fix. Keine bekannten offenen Fehler. **Nächster Schritt: HoT-Phase 2 (Signatur-Whitelist) / weitere Aura-Kategorien, restliche MVP-Features (Sortierung/Aggro) und/oder Suite-Shell-Design** (siehe §8, Punkt 4).

**Architektur Phase 1 (Ist-Zustand, `Modules/Raidframes.lua`):**
* Render-Stack faktorisiert in **`Decorate(host)`** — dekoriert sowohl Nicht-Secure-Preview-Frames (Test) als auch Secure-Buttons (Live), ein gemeinsamer Render-Code.
* **Live** = `SecureGroupHeaderTemplate` (`LumenRaidHeader`, `template=SecureUnitButtonTemplate`): Blizzard verwaltet Roster/Sortierung/In-Kampf. Funktionen `buildHeader`/`styleSecureButton`/`applyDefaultClicks`(+`getMenuProxy`)/`applyHeaderLayout`/`configureSecureButtons`/`LayoutLive`. Orientierung↔Header-Attribute (`point`/`columnAnchorPoint`/`unitsPerColumn=5`/`maxColumns=8`). Routing via `OnAttributeChanged(unit)` → `unitToButton`.
* **Klick:** `type1="target"` (+`*type1`); Rechtsklick-Menü über versteckten `SecureActionButton`-Proxy (`*type2="click"`+`*clickbutton2`, `useparent-unit`) — 12.0.7-sicher (sonst Taint bei „Fokus setzen"). Muster aus EllesmereUI `EllesmereUI_Kick.lua`.
* **In-Kampf-Disziplin:** `secureLayoutDirty`-Flag + `PLAYER_REGEN_ENABLED`-Flush; Header/Buttons werden im Kampf nicht umgebaut. Sortierung Phase-1 = `INDEX`.
* **Test/Preview** = bisheriger Nicht-Secure-Pool (`LayoutPreview`/`HidePreview`), nur bei `testMode`. **Zukunfts-Naht** `ns.CC_RegisterButton(button)` je Button für Phase 2.
* Bekannte Mini-Grenze: EditMode-Grabfläche im Live-Modus deckt evtl. nicht den ganzen Header (Container behält feste Größe) — Feinschliff später.

**Nächster großer Baustein (Priorität 1):**
* ~~Export/Import~~ **✓ erledigt (v0.9.8, live bestätigt)** — `AceSerializer`+`LibDeflate` jetzt eingebunden, Modul `Modules/Share.lua`, Details §10.7.
* **← HIER GEHT ES WEITER:** kleinere MVP-Features (Sortierung nach Rolle/Gruppe · HoT-Platzierung · Aggro-Warnung) und/oder Start der eigenen **Suite-Shell-Optik** (Florian hat ein Click-Cast-**Mockup** als Zielbild — beim Wiedereinstieg danach fragen). Empfehlung steht in §8/Nächste Schritte Punkt 4: erst die kleinen MVP-Lücken (machen die Raidframes wirklich fertig), dann die Shell als ein fokussierter Design-Block.

**Danach (Reihenfolge siehe §8):** Click-Cast-Politur (echte Typeahead-Suche in der Suite-Shell, Item/Makro/Smart-Rez, Hovercast-Mount-Guard) · Feinschliff (abgerundete Ecken, Overschild-Funke, Live-EditMode-Grabfläche) → erstes Release.

**Bekannte, akzeptierte Grenzen (für den MVP bewusst so):**
* **Dispel-Anzeige** funktioniert jetzt **auch im Kampf** (secret-sicher): Erkennung über Blizzards Filter `"HARMFUL|RAID_PLAYER_DISPELLABLE"` (bzw. `"HARMFUL"` + `dispelName ~= nil` für „alle"), Farbe typ-genau über `C_UnitAuras.GetAuraDispelTypeColor` + Color-Curve (`C_CurveUtil`). Zwei Modi: `recolor` (Balken einfärben) und `overlay` (Rand + Füllung, Klassenfarbe bleibt). Fallback auf generische Magic-Farbe, falls die Curve-API fehlt.
* **Kein weiches Interpolieren** der Balken — sie springen pro Event (secret-Werte lassen sich in Lua nicht interpolieren).
* **Overschild-Kantenfunke** (wie EllesmereUIs Spark) ist nicht umgesetzt — nur der Backfill. Kann später ergänzt werden (secret-sicherer „overshield"-Bool über `GetDamageAbsorbs` 2. Rückgabe mit `MissingHealth`-Clamp).
* **Streifen-Tiling: GELÖST** — Schild/Heilabsorb kacheln in fester Pixelgröße (manuelles TexCoord-Tiling, Texturen über das Frame gespannt + Clip-Frames an die Absorb-Füllung). `SetHorizTile` auf StatusBar-Füllungen funktioniert NICHT (streckt) — nicht erneut versuchen. **v0.9.9:** Healabsorb (256×128, Zweierpotenz) kachelt jetzt auch **vertikal** in fester Pixelgröße (`REPEAT/REPEAT`, TexCoord `h/128`) → kein Strecken des X-Musters auf hohen Frames; Schild (256×40, KEINE Zweierpotenz) bleibt vertikal `CLAMP`, weil vertikales `REPEAT` dort eine Naht zeigte (Memory `lumen-absorb-rendering`).

**Spätere Bausteine (nach Priorität 1–2):** abgerundete Ecken (Toggle + Stärke, via Mask-Textur), volle native Edit-Mode-Registrierung, Heilabsorb-Überlaufkante wieder aktivieren, Sortierung nach Rolle/Gruppe, HoT-Platzierung, Aggro-Warnung, Export/Import (granular, `AceSerializer`+`LibDeflate`), eigene gerunte Suite-Shell-Optik, dann Modul 2 (Unit Frames).

### 10.6 Click-Cast (Phase 2, `Modules/ClickCast.lua`) — Ist-Zustand (v0.9.7, live bestätigt)

**Datenmodell:** `db.profile.clickCast = { enabled, helpfulOnly, specs = { [specID] = { binding, … } } }`. Eine Binding: `{ key, type, enabled, oocOnly, hovercast, spell, spellID, hoverFriendly, hoverEnemy }`. `type` ∈ `target|menu|spell|dispel|rez`. Klick- und Hovercast-Bindings liegen in DERSELBEN Liste, getrennt über `binding.hovercast`. Eine frisch betretene Spec wird einmalig mit `BUTTON1=target`, `BUTTON2=menu` vorbelegt (entspricht Phase-1-Verhalten).

**Kernidee (taint-/secret-sicher):** Spell/Dispel/Rez laufen IMMER als `@mouseover`-Makro — beim Klick liegt die Maus über der Unit, beim Hover sowieso → EIN Resolver (`resolveBinding`) für beide Pfade. `target`/`menu` sind in 12.0.7 gegatet → über die UN-gated `click`-Action an versteckte `SecureActionButton`-Proxys geroutet (`getProxy`/Raidframes' Menü-Proxy). Bindings werden NUR außer Kampf geschrieben; im Kampf via `applyDirty` + `PLAYER_REGEN_ENABLED` nachgeholt.

**Klick-Pfad:** `ns.CC_RegisterButton(button)` (Naht aus `styleSecureButton`) sammelt die Secure-Buttons. `applyToButton` → bei aktiviert `applyEnabled` (Wildcards neutralisieren, ungebundene Tasten auf inert `none`, dann je aktiver Maus-Binding `applyClick` mit `[mod]type/spell/macrotext`-Attributen + Proxys); bei deaktiviert `ns.RF_ApplyDefaultClicks` (Phase-1 zurück). Gesetzte Attributnamen werden je Button in `_ccApplied` getrackt und vor jedem Rebuild gecleart.

**Hovercast-Pfad:** globaler `SecureActionButton` `LumenCCHover` (Attribute `type-/macrotext-/unit-<suffix>`) + `SecureHandlerStateTemplate`-Driver `LumenCCDriver`. State-Driver `[@mouseover,exists] 1; 0`: auf „1" routet `hover_set` (gebaut aus `SetBindingClick(true, key, "LumenCCHover", suffix)`) die Tasten auf den Hover-Button; auf „0" `self:ClearBindings()`. Dadurch wirkt die Taste nur beim Hovern, sonst normal. (Mini-Latenz beim Ankommen akzeptiert; Mount-/Vehicle-Guard noch offen.)

**Events:** eigenes Frame in ClickCast auf `PLAYER_ENTERING_WORLD`/`PLAYER_SPECIALIZATION_CHANGED`/`SPELLS_CHANGED` → `ApplyBindings`; `PLAYER_REGEN_ENABLED` → aufgeschobenes Apply. `Core.RefreshAll` ruft `ApplyBindings` bei Profilwechsel.

**Options (`Click-Cast`-Knoten):** dynamisch via `rebuildCC` (wipe + refill `ccArgs` in place) + `AceConfigRegistry:NotifyChange("Lumen")`. Maustaste (Dropdown 5 Tasten) + Modifier (Schalter→Shift/Strg/Alt) ODER `keybinding` (Hover). `CC:KeyParts/BuildKey` kodieren beides in `binding.key` (`"SHIFT-BUTTON1"`). Spell-Dropdown mit Icon + Suchfeld (filtert bei Enter) + Filter „nur hilfreiche Zauber" (`C_SpellBook.IsSpellBookItem{Helpful,Harmful}`, Default an). Spec-Auswahl-Dropdown entkoppelt von der Live-Spec; ein eigener `PLAYER_SPECIALIZATION_CHANGED`-Watcher in Options stellt es auf die aktive Spec. **AceConfig-Grenze:** kein Live-Typeahead (Input committet erst bei Enter, Dropdown nicht tippbar) → echtes Combobox-Suchfeld erst mit der eigenen Suite-Shell.

**Gotcha (live geklärt):** SHIFT-Klick scheint nicht zu casten, Strg/Alt schon → fast immer WoWs **Selbstzauber-/Fokus-Zauber-Taste = Shift** (Optionen→Kampf) oder harte Tastenbelegung. Code behandelt alle Modifier identisch — kein Lumen-Bug.

---

### 10.7 Export/Import (`Modules/Share.lua`) — Ist-Zustand (v0.9.8, live bestätigt)

Ein Textcode fürs ganze Setup (Prinzip WeakAuras/ElvUI), granular pro Modul + getrennter Layout-Schalter. UI **unten im `Global → Profile`-Tab** (Profil-Verwaltung + Teilen bewusst an einem Ort — Florians Entscheidung). Punkte 1–6 der Test-Checkliste live bestätigt; **offen: echter Transfer an Zweitchar/Freund** (testet Florian später).

**Libs (neu eingebunden):** `Libs/AceSerializer-3.0/` (aus Ace3) + `Libs/LibDeflate/LibDeflate.lua` (SafeteeWoW 1.0.2, Single-File via `<Script>` in `embeds.xml`). Beide via LibStub (`LibStub("LibDeflate")` / `LibStub("AceSerializer-3.0")`). Lagen vorher NICHT lokal — aus offiziellen Quellen geholt.

**Codec-Pipeline:** `AceSerializer:Serialize` → `LibDeflate:CompressDeflate` → `LibDeflate:EncodeForPrint` (Decode invers; strippt Whitespace, prüft `payload.addon=="Lumen"` + `payload.modules`).

**Payload-Form:** `{ v=1, addon="Lumen", modules={ raidframes=…, clickCast=… }, layout={ raidframes={ raid={point,x,y}, party={point,x,y} } } }`. Modul-Registry `MODULES` (`{key,label}`) in Share.lua — neue Module dort eintragen; Options baut die Import-Häkchen dynamisch aus `Share:GetModules()`.

**Zwei nicht-offensichtliche Architektur-Entscheidungen (wichtig für künftige Arbeit):**

1. **Layout getrennt halten.** Positionen (`point/x/y`) liegen bei Lumen verschränkt in `raidframes.raid`/`.party` (mit Größe/Text). Export zieht sie per `extractLayout`/`stripLayout` in den eigenen `layout`-Block → der Schalter „Layout-Positionen mitimportieren" wirkt unabhängig. Import: `withLayout` an → Absender-Positionen; aus → eigene aktuelle Positionen bleiben (`keepPos`-Snapshot vor dem Ersetzen).

2. **Sparse Export + Merge-auf-Defaults beim Import.** AceDB hält UNVERÄNDERTE Werte nur in der Defaults-Metatable, `pairs()` sieht sie nicht → Export ist bewusst sparse (nur Abweichungen). Import darf daher NICHT `p[mod] = incoming` setzen (Lücken → nil-Reads), sondern: `merged = deepcopy(ns.Defaults.profile[mod])` (Core.lua exponiert `ns.Defaults`), dann `deepmerge(merged, incoming)`. Füllt fehlende Felder mit Lumen-Standards, ist dadurch versions-tolerant. Ausgewählte Module so ersetzt, abgewählte unangetastet; danach `Lumen:RefreshAll()`.

**API:** `Share:Export()`, `Share:Decode(str)` (→ payload | nil,err), `Share:Import(payload, selected, withLayout)`, `Share:GetModules()`, `Share:Encode(payload)`. Options-UI-Flow wie Click-Cast: Multiline-`input` dekodiert im `set` (committet beim Wegklicken/Okay), Häkchen/Schalter/Knopf sind statische Args mit dynamischem `hidden`/`get`/`set` auf Closure-State, Live-Update via `AceConfigRegistry:NotifyChange("Lumen")`.

### 10.8 Aura-Indikatoren / „Auras"-Tab (Raidframes) — Ist-Zustand (v0.9.9, live bestätigt)

**Phase 1 von 2.** Flexibles Icon-Indikator-System als neuer Raidframes-Tab **`Auras`** (Tab-Leiste jetzt `Base | Raid | Group | Auras`). Vorbild EllesmereUIs Aura-Tab, **kuratiert** (Anti-Bloat). HoTs sind eine Kategorie im selben System (kein separater HoT-Editor wie bei Ellesmere). Florians Designwunsch: pro **Anker-Position** wählt man, welche Kategorie dort erscheint.

**Datenmodell:** `db.profile.raidframes.auras = { [catKey] = {...} }`. Phase 1 hat eine Kategorie `hotsOwn`. Felder: `enabled, anchor` (einer der 9 WoW-Punkte `TOPLEFT…BOTTOMRIGHT`), `grow` (`RIGHT|LEFT|UP|DOWN`), `spacing, maxIcons, autoFit, sizeRaid, sizeParty, showSwipe, hideTooltips`. **Layout (Anker/Wachstum/Toggles) ist über raid/party GETEILT — nur die Größe ist kontextabhängig.**

**Render (`Modules/Raidframes.lua`):** Kategorien-Registry `AURA_CATS = { {key, filter} }` (filter = Blizzard-Aura-Filter). Icon-Pool je Frame in `Decorate` (`f.auraHolders[catKey]` = Holder mit `.icons`-Pool; jedes Icon = Frame + ARTWORK-Textur + `CooldownFrameTemplate`). `layoutAuraCat` (in `ApplyConfig`, nur OOC) erzeugt/größt den Pool und merkt Anker/Wachstum/Größe am Holder. **Positioniert wird render-zeitig** über `positionAuraIcons` — es kennt erst dann die echte Icon-Zahl → **Auto-Zentrierung** bei mittigen Ankern (Unten/Oben/Mitte/Links/Rechts) anhand der tatsächlichen Anzahl. `RenderAurasLive` scannt `C_UnitAuras.GetAuraDataByIndex(u, i, "HELPFUL|PLAYER")` (secret-sicher; „PLAYER" = selbst gewirkt → eigene HoTs), Swipe via `cd:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration(u, iid))` (das EINZIGE Cooldown-Setter, der secret verträgt; Icon-/iid-Felder mit `issecretvalue` geguardet). `RenderAurasFake` speist Fake-HoT-Texturen für den **Testmodus** (Florians Anforderung: solange es keine Live-Vorschau in den Settings gibt, MUSS der Testmodus die Auren zeigen). Beide laufen im selben `Decorate`-Pfad → Test = Live.

**Größe — Auto-Fit (Default):** `auraIconSize` leitet die Icon-Größe aus der Frame-Höhe (~30%) ab UND deckelt sie an der Frame-Breite (horizontales Wachstum) bzw. -Höhe (vertikales) → die volle Reihe/Spalte passt immer in den Frame, **kein Überlauf** über den Rand. Auto-Fit aus → explizite `sizeRaid`/`sizeParty`.

**Options (`Auras`-Tab):** Get/Set-Closure `auraGetSet("hotsOwn")` auf `rf().auras[catKey]`. Regler: Anzeigen, Position (`POINTS`), Wachstumsrichtung (`GROW`), Abstand, Max. Icons, Cooldown-Swipe, Auto-Fit + (wenn aus) Größe Raid/Gruppe. Neue Kategorien später: in `AURA_CATS` (Render) + eigener Get/Set + Tab-Block ergänzen.

**Phase-1-Grenzen (bewusst so, mit Florian abgestimmt):**
* Live zeigt **ALLE eigenen Hilfsauren** (nicht nur HoTs) — Dauerbuffs können mitlaufen. Exakte Whitelist kommt in **Phase 2**.
* `hideTooltips` liegt im Profil, greift erst, wenn Icons mouseover-interaktiv sind (Phase 2).
* **Keine eigene „Mitte"-Wachstumsrichtung** — symmetrisches Wachstum springt (einmal links/rechts) → bewusst verworfen; mittige Anker zentrieren bereits.

**Phase 2 (offen, nächster Schritt):**
* **Exakte HoT-Whitelist per Spec-Signatur.** Im Kampf ist `aura.spellId` secret → nicht per ID filterbar. Lösung = Filter-Fingerprint pro Spec (mehrere `IsAuraFilteredOutByInstanceID`-Checks → Signatur; außer Kampf `Signatur↔SpellID` lernen, im Kampf über die Signatur erkennen). Muster: EllesmereUI `EUI_RaidFrames_BuffManager.lua` (`specSignatures`, `BM_IdentifySecretAura`, `MatchSecretAura`).
* **Weitere Kategorien** im selben System: fremde HoTs, Defensives & Externe, Debuffs, CDs.

---

*Ende des Master-Briefings. Bei Architektur-/API-Unsicherheiten zuerst `E:\Github\EllesmereUI` analysieren (siehe §9), dann bauen — und bei nicht-trivialen Weichen vorher kurz mit Florian rückkoppeln.*