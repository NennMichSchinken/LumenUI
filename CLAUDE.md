# Lumen — Master-Briefing / Übergabe an Claude Code (CLI)

> **📚 Wissens-Verwaltung (WICHTIG):** Alle **historischen Changelogs** (Versionen v0.9.x) und **tiefen Feature-Spezifikationen** werden ab jetzt **zentral und ausschließlich** unter `E:\Github\Wissen-Datenbank\Lumen_Wissen_Index.md` gepflegt — **nicht mehr in dieser Datei**. Diese `CLAUDE.md` bleibt bewusst schlank: Vision, Arbeitsweise, Design-/Architektur-Regeln, Performance-Vorgaben und ein knapper Ist-Zustand. Für Versionshistorie, externe Ressourcen-Links oder Detail-Specs eines Features → **immer zuerst den Wissens-Index lesen**.
> **Stand:** Addon-Version **0.9.83** · Interface **120007** (Retail-Patch 12.0.7, live seit 16.06.2026). MVP-Raidframes-Block KOMPLETT & live bestätigt; Base-Tab-Umbau + Dropdown-Suchfeld (Feature 1/3/4) live; **Feature 2 (Aura-Positionierung: Versatz X/Y, Innen/Außen, Party/Raid-Kontext, `W.Segment`) live-getestet**. **Hauptoberfläche = Suite-Shell**, jetzt auf **`/lumen`** UND dem ESC-Menü-Button „Lumen" (unter „Addons" gruppiert, Cinzel-Gold-Optik); klassische AceConfig nur noch als Backup via **`/lumen ace`**. **Beta-Cleanup (0.9.83):** EllesmereUI-Namedrops aus dem Code raus, `/ldump`-Debug entfernt, tote Tokens weg, Aura-Positions-Cache (SetPoint-Churn); **Blizzard-Standard-Raidframes werden jetzt ausgeblendet, solange Lumens aktiv sind** (Rückweg via Reload-Popup); **optionale MiniCC-Brücke** (`Modules/MiniCC.lua`, FrameProvider). **Offen:** Aura-Filter-/Tracking-Logik geparkt bis 12.1.0.
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

* **Suite-Shell:** EINE Einstellungsseite. Links eine kuratierte Modulliste (Baum, z.B. Gruppen „Kern"/„QoL"), rechts die Einstellungen des gewählten Moduls. Perspektivisch eine **Live-Vorschau**, die zeigt, was sich ändert. Erweiterbar — Module kommen nach und nach dazu, ohne die Liste aufzublähen. (Eigene gerunte „Shell"-Optik unter `Shell/` — Hauptoberfläche auf `/lumen` + ESC-Menü-Button; die alte AceConfig läuft als Backup parallel auf `/lumen ace`. Details §10.11.)
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

**Was gehört in `Base` vs. die Kontext-Tabs? (verbindliche Aufteilung, seit v0.9.68 live):**
* **`Base` = geteilte OPTIK/Funktion**, die in allen Kontexten gleich ist (reine Geschmacks-/Stilwahl): Texturen, Klassenfarbe/Füllfarbe, Hintergrund, Transparenzen, **Text-Farbe + -Umrandung**, Dispel, Aggro, Sortierung.
* **Kontext-Tabs (`Raid`/`Group` bzw. `Player`/`Target`…) = nur, was an der FRAME-GRÖSSE hängt:** Frame-Größe/Position/Ausrichtung, Text-**Größe** + -Position, „Name anzeigen", „HP-Typ".
* **Merksatz:** *Farbe/Stil = geteilt (Base); Größe/Position = pro Kontext.* (Datenmodell: geteilte Felder top-level unter `db.profile.<modul>`, kontextabhängige unter `…<kontext>`.)

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
* **HoT-Platzierung** als flexibles Aura-Indikator-System (`Auras`-Tab). *(Gebaut: v0.9.9 eigene HoTs (live bestätigt); v0.9.11 = **3 Kategorien** (HoTs · Defensives & Externe · Debuffs), HoT-/Defensiv-**Whitelist pro Spec** (kuratiert für alle Klassen/Specs + Signatur-Lernen), echte secret-sichere Icons im Kampf, **Blizzard-Standard-Debuffs** (Filter Raid-relevant/Alle/Dispellbar). 9 Anker, Auto-Zentrierung, Auto-Fit. Siehe §10.8. Offen: Debuff-Live-Test, B4-Whitelist-Editor.)*
* **Mouseover-Indikator** (Goldrand am anvisierten/Mouseover-Frame) — vorhanden.
* **Aggro-Warnung.** *(✓ erledigt v0.9.28, live bestätigt: 2-stufig gelb/rot, pro Stufe Nur-Rand / Rand+Overlay + optional „Aggro"-Text, Tanks ausgenommen. Threat secret-frei über `UnitThreatSituation`. Details §10.9.)*
* **Party + Raid**, Anordnung sortierbar (nach Rolle/Gruppe). *(✓ erledigt v0.9.30, live bestätigt: secure über `groupBy=ASSIGNEDROLE`, frei umsortierbare Rollen-Prioritätsliste, Raid-Opt-out. Details §10.10.)*
* **Gute Defaults**, das Wichtige aber konfigurierbar.
* **Frei positionierbar** (Edit-Mode-tauglich) und an die zentralen Profile angebunden.

**Bewusst draußen (MVP):**
* Riesige Aura-Filter-Engine mit hunderten Optionen (später, kuratiert — Anti-Bloat).
* Tiefe Range-Check-/Aura-Highlight-Frameworks erst nach dem MVP, falls überhaupt.
* Encounter-Ansagen (eigenes, großes Thema, siehe §5).

---

## 8. Offene Entscheidungen & Nächste Schritte

**Erledigt / bestätigt:** Die vollständige Versionshistorie (v0.9.1–v0.9.30: Absorbs, Render, Click-Cast, Export/Import, Aura-Indikatoren Phase 1+2, B4-Whitelist-Editor, Aggro, Sortierung) liegt jetzt im **Wissens-Index** (`E:\Github\Wissen-Datenbank\Lumen_Wissen_Index.md`, Abschnitt 2). Kurzfassung: Name **Lumen** auf **Ace3**; **Raidframes als MVP komplett & live bestätigt** (secret-sicheres Render, Dispel, Layout/Kontexte, Text/Outline, Click-Cast, Export/Import, Auras+Tracking, Aggro, Rolle/Gruppe-Sortierung). Aktiv: Suite-Shell.

**Offen:**
* **Akzentfarbe final** festlegen: aktuell im Code `#D4A34F`, ursprünglich vorgeschlagen `#c9a86a` (siehe §3).
* „Lumen" auf CurseForge/Wago auf Verfügbarkeit prüfen.
* Reihenfolge/Feinschnitt der Module nach den Raidframes (Grobplan steht: Unit Frames → Nameplates → QoL).
* Familien-Verbindung zu einem evtl. zweiten Projekt bewusst NICHT über den Produktnamen (falls später gewünscht: gemeinsames Macher-/Studio-Label).

**Release-Hygiene — ABZUARBEITEN kurz vor dem Public-Gehen (Repo ist aktuell privat):**
> Hintergrund: EllesmereUI dient Lumen ausschließlich als **Lern-/Performance-Benchmark**. Es wird **nichts 1:1 kopiert** — alle Muster sind eigenständig adaptiert/neu geschrieben (Florian + KI). Es besteht daher **keine Attributionspflicht**. Die folgenden Schritte sind reine **Wahrnehmungs-Hygiene** fürs Portfolio: nach außen soll nichts mehr auf EllesmereUI verweisen, damit es bei flüchtigem Lesen nicht „abgekupfert" wirkt. Vor dem Release einmal gebündelt abarbeiten:
> 1. **EllesmereUI-/MiniCC-Verweise aus dem ausgelieferten Code entfernen** — mehrere Dev-Kommentare nennen EllesmereUI/MiniCC (u.a. `EditMode.lua`, `GameMenu.lua`, `Modules/Raidframes.lua` an mehreren Stellen — Aura/Icon/Whitelist/Cast-Event-Notizen). Vor Release per `grep -rin "ellesmere\|minicc\|eui_" *.lua Modules/*.lua` finden und generisch umformulieren („secret-sicheres 12.0-Vorgehen") statt Namedrop. Nur Benchmarks, nichts kopiert (Hintergrund oben).
> 2. **`CLAUDE.md` aus dem öffentlichen Repo nehmen:** `git rm --cached CLAUDE.md` + Eintrag in `.gitignore`. Datei bleibt lokal liegen und wird von Claude Code weiter geladen — nur nicht mehr im Repo.
> 3. **Backup der `CLAUDE.md`:** in ein **separates privates Repo** spiegeln (Vision-Doku bleibt versioniert/abgesichert, ohne im Public-Addon-Repo zu liegen).
> 4. **Optional Git-Historie putzen** (`git filter-repo`), falls auch alte Commits keine `CLAUDE.md`/EllesmereUI-Spur enthalten sollen — sonst genügt das Untracken, weil das Repo bis dahin privat war.
> 5. **Gegencheck:** kein wörtlich kopierter EllesmereUI-Code im Release (Adaption ist fein; 1:1-Kopie ohne Lizenzblick nicht). README ist bereits sauber (kein EllesmereUI).

**Nächste Meilensteine (Arbeitsliste, in Reihenfolge):**
1. **Major CDs — Code-Prüfung & Finalisierung.** Florians selbst hinzugefügten „Major CDs"-Reiter (Auras + Tracking) auf saubere, fehlerfreie und stabile Core-Einbindung prüfen (`Shell/Screens.lua`, `Modules/Raidframes.lua`, `Core.lua`). Spec: Wissens-Index Feature 5.
2. **Transparenzen & Hintergrundfarben im `Base`-Tab.** Freie Hintergrund-Farbwahl, Namensfarbe in Klassenfarbe (Checkbox), separate Opacity-Slider für Background und Healthbar. Spec: Wissens-Index Feature 1.
3. **UX-Kompression für Dropdowns.** Textur-Dropdowns auf 5–8 Zeilen + Scrollbar begrenzen, Echtzeit-Suchfeld am Kopf, Fast-Preview via Mausrad-Hover (visuell-only, Debounce-Speicherung). Danach Vererbung an Schild-/Healabsorb-Dropdowns. Spec: Wissens-Index Feature 3+4.

> Weitere Roadmap-Features (flexibles Aura-Positionierungssystem = Feature 2) sowie Feinschliff (abgerundete Ecken, Overschild-Funke, native Edit-Mode-Vollregistrierung) → erstes Release (BigWigs Packager, Tag als Restore-Punkt). Volle Feature-Specs im **Wissens-Index** (Abschnitt 4).

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

## 10. Aktueller Entwicklungsstand (Ist-Zustand des Codes, v0.9.68)

> Dieser Abschnitt hält nur noch die **aktuelle Dateistruktur** knapp fest. Tiefe Architektur-Details (Render-Stack, Click-Cast, Export/Import, Aura-/Tracking-System, Aggro, Sortierung, Suite-Shell) liegen in den **Memories** (`lumen-*`) und im **Wissens-Index** (`E:\Github\Wissen-Datenbank\Lumen_Wissen_Index.md`). Bei Detailfragen dort nachschlagen, nicht hier nacherzählen.

### 10.1 Dateien im Addon-Ordner `Lumen/`

Lade-Reihenfolge laut `Lumen.toc`: `embeds.xml` → `Core.lua` → `EditMode.lua` → `Style.lua` → `Shell\Tokens.lua` → `Shell\Widgets.lua` → `Shell\Screens.lua` → `Shell\Shell.lua` → `Modules\Raidframes.lua` → `Modules\ClickCast.lua` → `Modules\Share.lua` → `Modules\MiniCC.lua` → `Options.lua` → `GameMenu.lua`.

| Datei | Zweck (knapp) |
|---|---|
| `Lumen.toc` | Addon-Deklaration. `## Interface: 120007`, `## Version: 0.9.68`, `## SavedVariables: LumenDB`, `## Author: NennMichSchinken`. Lade-Reihenfolge siehe oben. |
| `embeds.xml` | Lädt die Ace3-Libs aus `Libs/` in korrekter Reihenfolge (inkl. `AceSerializer-3.0` + `LibDeflate` für Export/Import). |
| `Core.lua` | Ace3-Addon + AceDB (`LumenDB`) mit den Profil-Defaults, Slash-Commands `/lumen` (Suite-Shell = Hauptoberfläche) und `/lumen ace` (klassische AceConfig als Backup), startet die Module. Exponiert `ns.Defaults`. |
| `EditMode.lua` | Generische Registry für verschiebbare Frames: manueller Entsperr-Schalter + Hook in WoWs nativen Edit Mode. Speichert Positionen ins Profil. |
| `Style.lua` | Zentrales Balken-Stilmodul (`Style:ApplyBar`/`SetDepth`), wiederverwendbar für spätere Unit Frames. Gradient-Texturen + Tiefen-Overlays. |
| `Modules/Raidframes.lua` | Das MVP-Modul. Secret-sicheres Render (Leben/Schild/Heilabsorb/Heilvorhersage über StatusBars + Clip-Frames), event-getrieben. `Decorate(host)` für Live (Secure-`SecureGroupHeader`) und Test (Nicht-Secure-Pool). Aura-Indikator-System (`AURA_CATS`-Registry inkl. `hotsOwn`/`defensives`/`major`/`debuffs`, Whitelist + Defaults `HOT_/DEF_/MAJOR_DEFAULTS`, Tracking-Editor-API), Aggro (`f.aggroLayer`), secure Rollen-/Gruppen-Sortierung. |
| `Modules/ClickCast.lua` | Click-Cast (Phase 2): Klick-Attribute pro Secure-Button + Hovercast über globalen Secure-Button & State-Driver; Bindings pro Spec. Liefert auch `GetAuraSpells()` (Zauberbuch + gewählte Talente) für den Tracking-Editor. |
| `Modules/Share.lua` | Export/Import: EIN Textcode via `AceSerializer`+`LibDeflate`, sparse Export + Merge-auf-Defaults, granular pro Modul + getrennter Layout-Schalter. |
| `Modules/MiniCC.lua` | Optionale MiniCC-Brücke: meldet unsere Live-Raidframes via `MiniCCApi.v1:RegisterFrameProvider` als Frame-Provider an, damit MiniCC seine CD-Icons andocken kann. Defensiv (pcall, `OptionalDeps: MiniCC`); ohne MiniCC No-op. Nutzt `Raidframes:GetLiveButtons()` + `:OnFrameChange()`. |
| `Options.lua` | Klassischer AceConfig-Optionsbaum (`/lumen`): `Global` (Base\|Profile) · `Click-Cast` · `Raidframes` (`Base\|Raid\|Group\|Auras\|Tracking`). Benennungskonvention §4.1. |
| `GameMenu.lua` | Fügt im ESC-Menü einen „Lumen"-Button über Blizzards `GameMenuFrame:AddButton`-API hinzu. |
| `Shell/Tokens.lua` | Suite-Shell Design-Tokens (`ns.UI`): Farb-/Gold-Rampen, Schriften/Rollen (`UI:SetFont`), Spacing/Radien, Panel-Maße. **`UI.WIDGET`** = ALLE Widget-Maße zentral, **`UI.ROLE`** = alle Schriftgrößen (der eine Ort zum Feinjustieren). Bau-Primitive `UI.Border/Fill/FS/…`. |
| `Shell/Widgets.lua` | Widget-Toolkit (`ns.W`): wiederverwendbare Builder (Slider/Select/Checkbox/Button/Card/GroupPanel/IconTile/Row, `SpellPicker`, Tooltips, Confirm-Dialog) auf den Tokens — keine Magic Numbers. |
| `Shell/Screens.lua` | Die echten Suite-Shell-Screens (Phase 3) ans `db.profile` verdrahtet: Raidframes Base/Raid/Group/Auras/Tracking. Aura-Kategorien inkl. **„Major CDs"** (`auraCat`/`TRACK_CATS`). |
| `Shell/Shell.lua` | Suite-Shell-Chrome (`ns.Shell`): Singleton-Panel (Header/Nav/Tabs/Footer/Rune-Ecken), `Build/Toggle/SelectSection/SelectTab`. Aufruf `/lumen` + ESC-Menü-Button (AceConfig nur noch via `/lumen ace`). |
| `Fonts/` | Cinzel (Headings/Wordmark) + Hanken Grotesk (Body/Controls), statische TTF inkl. Umlaute, SIL OFL. |
| `Libs/` | Ace3-Bibliotheken + `LibDeflate` (siehe §6). |
| `Textures/` | TGA-Texturen (uncompressed RGBA, ohne Endung referenziert): `lumen-gradient(-soft)`, `lumen-light`/`-shadow`, `shield-combined`, `healabsorb-combined` u.a. |

### 10.2 Profil-Struktur & Architektur (Kurzverweis)

AceDB-Defaults liegen in `Core.lua` (`ns.Defaults`); jedes Modul liest unter `db.profile.<modul>` (aktuell `raidframes` + `clickCast`). Die Raidframe-Settings sind pro Kontext getrennt (`raid`/`party`: Position, Größe, Name-/HP-Text), Aura-Kategorien unter `raidframes.auras.<kategorie>`, Whitelist lazy-geseedet in `raidframes.auras.whitelist[specID]`. Render-Architektur, Secret-Value-Handling und alle Subsysteme: siehe Memories `lumen-*` und Wissens-Index.
