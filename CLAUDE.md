# Lumen — Master-Briefing / Übergabe an Claude Code (CLI)

> Stand: Addon-Version **0.9.5**, Interface **120005** (Retail-Patch 12.0.7).
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
* **Vor jedem Commit/Build:** alle `.lua` syntaktisch prüfen. (Im bisherigen Workflow lief das über `luaparser` in Python; im Terminal genügt `luac -p` bzw. ein Linter wie `luacheck`.)
* **Interface-Nummer** in der `.toc` ändert sich pro Patch — beim Packaging prüfen (aktuell `120005`).

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
* **Export (Konzept, noch zu bauen):** EIN Textcode für alles (Prinzip wie WeakAuras/ElvUI), zum Kopieren/Verschicken — via `AceSerializer` + `LibDeflate`.
* **Import — granular (Konzept, noch zu bauen):** Dialog mit **Häkchen pro Modul** — nur Gewähltes wird eingemischt, abgewählte Module bleiben beim Empfänger unverändert (z.B. „will nur deine Unit Frames, nicht die Raidframes"). Dazu eine separate Ja/Nein-Frage „**Layout-Positionen mitimportieren**" (aus → die aktuellen Positionen des Empfängers bleiben). Damit der granulare Import geht, werden die Settings im Export **pro Modul getrennt** abgelegt; **Layout-Positionen liegen nochmal getrennt**.

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
  * **Noch NICHT eingebunden, aber für Export/Import vorgesehen:** `LibDeflate` + `AceSerializer-3.0`. Für externe Schriften/Texturen optional `LibSharedMedia-3.0` (wird, falls vorhanden, via `LibStub(...,true)` genutzt; nicht zwingend gebündelt).
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
* **HoT-Platzierung** konfigurierbar gedacht: eigene HoTs an fester Stelle, fremde getrennt. *(Noch nicht implementiert — geplantes Feature.)*
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
* Profil-/Export-/Import-Konzept (Architektur steht, Code für Export/Import folgt).
* Gradient-Balkenstil bestätigt (zwei Varianten: „Lumen Gradient" kräftig = Default, „Lumen Soft" dezent).
* **Overschild-Backfill** umgesetzt (v0.9.1).

**Offen:**
* **Akzentfarbe final** festlegen: aktuell im Code `#D4A34F`, ursprünglich vorgeschlagen `#c9a86a` (siehe §3).
* „Lumen" auf CurseForge/Wago auf Verfügbarkeit prüfen.
* Reihenfolge/Feinschnitt der Module nach den Raidframes (Grobplan steht: Unit Frames → Nameplates → QoL).
* Familien-Verbindung zu einem evtl. zweiten Projekt bewusst NICHT über den Produktnamen (falls später gewünscht: gemeinsames Macher-/Studio-Label).

**Nächste Schritte (konkret, in Reihenfolge):**
1. **Live-Verifikation** des aktuellen Render-Stands durch Florians Screenshots (Testmodus + echter Kampf) — siehe „Baustelle" in §10. Eventuelle Render-Fehler fixen.
2. **Frames anklickbar/targetbar/Click-to-Cast** machen (Secure-Header) — der nächste große Schritt zur echten Nutzbarkeit (siehe §10).
3. Export/Import bauen (`AceSerializer` + `LibDeflate`, granular pro Modul + Layout-Schalter).
4. Danach Feinschliff (abgerundete Ecken als Toggle, Streifen-Tiling, native Edit-Mode-Vollregistrierung) und erstes Release.

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

---

## 10. Aktueller Entwicklungsstand (Ist-Zustand des Codes, v0.9.1)

### 10.1 Dateien im Addon-Ordner `Lumen/`

| Datei | Zweck (aktueller Stand) |
|---|---|
| `Lumen.toc` | Deklariert Addon. `## Interface: 120005`, `## SavedVariables: LumenDB`, `## Author: NennMichSchinken`, `## Version: 0.9.1`. Lädt in Reihenfolge: `embeds.xml`, `Core.lua`, `EditMode.lua`, `Style.lua`, `Modules\Raidframes.lua`, `Options.lua`, `GameMenu.lua`. |
| `embeds.xml` | Lädt die Ace3-Libs aus `Libs/` in korrekter Reihenfolge (LibStub → CallbackHandler → AceAddon/Console/Event/Timer → AceDB → AceGUI → AceConfig → AceDBOptions). |
| `Core.lua` | Erzeugt das Ace3-Addon, initialisiert AceDB (`LumenDB`) mit den Defaults, registriert `/lumen` und `/lu`, startet das Raidframes-Modul. Details unten. |
| `EditMode.lua` | Generische Registry für verschiebbare Frames. Manueller Schalter („Rahmen entsperren") **und** Hook in WoWs nativen Edit Mode (über `PLAYER_LOGIN`-Hook auf `EditModeManagerFrame` Enter/Exit). Gold-Overlays mit Label; speichert Position via Callback ins Profil. |
| `Style.lua` | **Zentrales** Balken-Stilmodul (bewusst zentral/wiederverwendbar für spätere Unit Frames/Target/Focus). Hält `Style.barTexture` (lumen-gradient) und `Style.barTextureSoft`. `Style:ApplyBar(statusbar, overlayParent)` setzt die Gradient-Textur und legt Licht-/Schatten-Tiefen-Overlays an. `Style:SetDepth(overlayParent, strength)` regelt die Tiefen-Deckkraft (1.0 Standard, 0.55 Soft, 0 aus). |
| `Modules/Raidframes.lua` | Das MVP-Modul. Secret-sicheres Rendering von Leben/Schild/Heilabsorb/Heilvorhersage über StatusBars + Clip-Frames. Event-getrieben. Test- und Live-Pfad geteilt. Details unten. |
| `Options.lua` | AceConfig-Optionsbaum (`childGroups="tree"`): linker Baum = **`Global`** (Edit-Mode-Schalter, Positionen zurücksetzen), **`Profile`** (AceDBOptions), **`Raidframes`**. Der Raidframes-Knoten nutzt `childGroups="tab"` → Tabs **`Base`** (Aktiviert, Lebensbalken-Textur/Klassenfarbe/Füllfarbe, Heilvorhersage, Dispel, Name-/HP-Text inkl. Outline, Test) · **`Raid`** und **`Group`** (je Breite/Höhe/Abstand/Ausrichtung; eigene Position **und eigene Name-/HP-Text-Einstellungen**). Benennung gemäß §4.1. `Raid`/`Group` lesen/schreiben in `rf().raid`/`rf().party`. |
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

Pro Einheit existiert **ein** `Frame` mit dieser Schichtung (Frame-Level relativ zur Erzeugungs-Basis `base`):

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
* Klassenfarben; Dispel-Umfärbung (im Testmodus / außer Kampf); Größen-Slider; Profile.
* Testmodus 5/20/40; Verschieben (manueller Schalter + nativer WoW-Edit-Mode); Name-Text-Optionen; HP-Text (Keine/Aktuell/Prozent).
* Gradient-Stil (Standard + Soft); Schilde und Heilabsorb **im Testmodus** scharf und korrekt skaliert; Heilvorhersage im Testmodus sichtbar.

### 10.5 Wo die Arbeit gerade abbricht — die exakte Baustelle für Claude Code

**Stand:** v0.9.1 ist gebaut und gepackt. Der **große secret-sichere Render-Umbau** (StatusBars + Calculator + Dual-Clip) inkl. **Overschild-Backfill** ist fertig im Code — aber **im echten Kampf noch UNBESTÄTIGT**. Es gibt aktuell keine bekannten Fehler, aber Florians Live-Screenshots stehen aus.

**Unmittelbar offen (Priorität 1 — Verifikation):**
* Florians Feedback einholen (Testmodus + echter Kampf) anhand der Checkliste: Sind Schild (frei + Overschild bei vollem Leben), Heilabsorb (von rechts) und Heilvorhersage **live** korrekt? Sitzt der Übergang Forward↔Backfill nahtlos, wenn Leben sinkt/steigt? Falls Render-Fehler: zuerst am Dual-Clip/Anker-Setup ansetzen, Referenz `EllesmereUIRaidFrames.lua`.

**Nächster großer Baustein (Priorität 2 — der eigentliche nächste Code-Schritt):**
* **Frames anklickbar / targetbar / Click-to-Cast machen.** Aktuell sind die Unit-Frames reine **Anzeige** (`CreateFrame("Frame", …)`), keine sicheren Unit-Buttons. Für echtes Heilen müssen sie auf einen **Secure-Unit-Button / SecureGroupHeader** umgestellt werden (geschützte Attribute, Click-to-Cast, korrektes `unit`-Attribut), inklusive sauberer Behandlung von `InCombatLockdown` (Secure-Frames dürfen im Kampf nicht umgebaut werden — Layout/Roster-Änderungen müssen außerhalb des Kampfes bzw. über sichere Header passieren). Das ist die größte Architektur-Weiche und sollte **vor** dem OK mit Florian abgestimmt werden. Referenz dafür: wie EllesmereUI seine Raid-Buttons als Secure-Header aufbaut.

**Bekannte, akzeptierte Grenzen (für den MVP bewusst so):**
* **Dispel-Anzeige** funktioniert jetzt **auch im Kampf** (secret-sicher): Erkennung über Blizzards Filter `"HARMFUL|RAID_PLAYER_DISPELLABLE"` (bzw. `"HARMFUL"` + `dispelName ~= nil` für „alle"), Farbe typ-genau über `C_UnitAuras.GetAuraDispelTypeColor` + Color-Curve (`C_CurveUtil`). Zwei Modi: `recolor` (Balken einfärben) und `overlay` (Rand + Füllung, Klassenfarbe bleibt). Fallback auf generische Magic-Farbe, falls die Curve-API fehlt.
* **Kein weiches Interpolieren** der Balken — sie springen pro Event (secret-Werte lassen sich in Lua nicht interpolieren).
* **Overschild-Kantenfunke** (wie EllesmereUIs Spark) ist nicht umgesetzt — nur der Backfill. Kann später ergänzt werden (secret-sicherer „overshield"-Bool über `GetDamageAbsorbs` 2. Rückgabe mit `MissingHealth`-Clamp).
* **Streifen-Tiling**: aktuell skalieren die Streifen in Schild/Heilabsorb mit dem Balken (Textur in der StatusBar) statt nativ zu kacheln — bewusst erst nach Live-Bestätigung feinzuschleifen.

**Spätere Bausteine (nach Priorität 1–2):** abgerundete Ecken (Toggle + Stärke, via Mask-Textur), volle native Edit-Mode-Registrierung, Heilabsorb-Überlaufkante wieder aktivieren, Sortierung nach Rolle/Gruppe, HoT-Platzierung, Aggro-Warnung, Export/Import (granular, `AceSerializer`+`LibDeflate`), eigene gerunte Suite-Shell-Optik, dann Modul 2 (Unit Frames).

---

*Ende des Master-Briefings. Bei Architektur-/API-Unsicherheiten zuerst `E:\Github\EllesmereUI` analysieren (siehe §9), dann bauen — und bei nicht-trivialen Weichen vorher kurz mit Florian rückkoppeln.*