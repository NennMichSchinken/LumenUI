# LumenUI

**A focused UI suite for World of Warcraft (Retail).** Built for Mythic+ and Raid, tuned to healer standards.

> 🚧 **Status: Public Beta** · Interface `120007` (Patch 12.0.7) · current version: see [Releases](../../releases)
> The Raidframes module is complete and battle-tested. More modules are on the roadmap.

## About this project

LumenUI started out of boredom — a little thing for me and a few friends, just to see how
far you can actually get. I'm a **UI/UX designer, not a programmer**: I own the design, UX
and direction, and the Lua is written **with AI — [Claude Code](https://www.anthropic.com/claude-code)
(Anthropic)** — in a tight design-and-iterate loop. It grew into something we genuinely use
in M+ and raid, so it's out as a public Beta. Treat it with the honesty of a hobby project:
solid where it counts, rough at the edges, and better with your bug reports.

---

LumenUI is deliberately **anti-bloat**: a short, curated module list with strong defaults instead of hundreds of switches — only what serious M+ and raid players actually use, done properly. The guiding rule: *what reads well for a healer under pressure works for every role.*

---

## Design principles

Two worlds, kept apart on purpose:

- **In combat** (raidframes, and later unit frames / nameplates) LumenUI stays **close to the WoW original** — class-colored bars, familiar layout, calm defaults. Fast pattern-matching beats stylization when you're under pressure.
- **In the suite** (settings, profiles, branding) it carries its own modern, flat, gold-accented identity.

Everything is freely positionable and builds on WoW's native Edit Mode rather than fighting it.

---

## Features (Beta — Raidframes module)

- WoW-native layout: class-colored health bars + role icons
- Absorb / shield display, including **overshield** at full health
- **Heal prediction** (incoming heals) and **heal absorb** (eats into health from the right)
- **Dispellable debuffs** highlighted, filtered to your class (Magic / Curse / Poison / Disease)
- **Aura indicators** — flexible system for HoTs, defensives & externals, and debuffs; per-spec whitelist (curated for every class/spec), 9 anchor positions, auto-fit sizing, combat-safe icons
- **Aggro warning** — two-stage (yellow/red), border and/or overlay, optional text, tanks excluded
- **Party + Raid** with sortable role / group ordering
- **Mouseover / target highlight** (gold edge)
- **Click-to-Cast** — click-cast + hovercast with a curated action catalog (heals, externals, battle-rez, trinket), bindings saved per spec
- **Status indicators** — dead / ghost / offline / incoming-res center text, ready-check and summon icons
- Hides Blizzard's default raidframes while active (one click to restore)

### Suite

- One settings home — `/lumen` or the **Lumen** button in the ESC menu
- Central profiles (AceDB)
- **Export / Import** — share your whole config as one text code; import is granular (per-module checkboxes) with a separate toggle for layout positions
- English & German localization

### Quality of life

- **Cursor ring** — tintable ring that follows the mouse (optionally combat-only)
- **Vendor automation** — auto repair (optionally on guild funds) + junk selling
- **/pull & Ready/Pull buttons** — native group countdown plus a movable two-button block
- **M+ helpers** — auto keystone insert, instance-reset chat announce
- **Battle-res & Bloodlust trackers** — placeable icons with charges and cooldown
- **Profession-outfit suppression** — keeps cosmetic outfit buffs off your transmog

---

## Installation

**Players:** install via [CurseForge](https://www.curseforge.com/) or [WoWUp](https://wowup.io/) (search for *LumenUI*).

**Manual:** download the latest release and extract the `LumenUI` folder into
`World of Warcraft/_retail_/Interface/AddOns/`.

---

## Development

No build step — the WoW client interprets Lua directly. The repository **is** the addon.

### Local setup (junction)

Point a junction in your AddOns folder at this repo so a `/reload` picks up your edits instantly:

```powershell
$AddOns = "<path>\World of Warcraft\_retail_\Interface\AddOns"
New-Item -ItemType Junction -Path "$AddOns\LumenUI" -Target "<path>\LumenUI"
```

To test a work-in-progress build alongside a released copy, junction it under a separate
name (e.g. `LumenUI_Dev`) with its own `LumenUI_Dev.toc`, and enable only one at a time.

### Linting

All Lua is checked with [luacheck](https://github.com/lunarmodules/luacheck) against the
project `.luacheckrc` (WoW/Ace3 globals whitelisted; `Libs/` and `tools/` excluded):

```powershell
tools\luacheck.exe .
# or
powershell tools\check.ps1
```

### Project structure

| Path | Purpose |
|---|---|
| `LumenUI.toc` | Addon manifest + file load order |
| `embeds.xml` | Loads the Ace3 libraries from `Libs/` |
| `Core.lua` | Ace3 addon, AceDB profiles (`LumenDB`), slash commands |
| `EditMode.lua` | Movable-frame registry hooked into WoW's Edit Mode |
| `Style.lua` | Shared status-bar styling (gradients, depth) |
| `Modules/Raidframes.lua` | The MVP module — secret-safe rendering, auras, aggro, sorting |
| `Modules/ClickCast.lua` | Click-cast + hovercast, secure bindings per spec |
| `Modules/Share.lua` | Export / import codec (sparse export, merge-on-defaults) |
| `Modules/MiniCC.lua` | Optional MiniCC frame-provider bridge (no-op without MiniCC) |
| `Modules/QoL.lua` | Quality-of-life module — cursor ring, vendor, pull timer, M+ helpers, trackers |
| `Shell/` | Suite-shell UI — design tokens, widget toolkit, screens, chrome |
| `Locales/` | Lightweight localization (English default, `deDE` overrides) |
| `Libs/` | Bundled Ace3 libraries + LibDeflate |
| `Fonts/`, `Textures/` | Bundled assets |

### Contributing

Issues and PRs are welcome — this is an open hobby project. A few notes so we stay aligned:

- The identity is **anti-bloat**: features are curated, not maximal. For anything bigger
  than a fix, please open an issue first so we can agree on scope before you build.
- Keep commits small and focused; run `luacheck` (must be 0 warnings / 0 errors) before a PR.
- The code is written in an **AI-assisted loop** — clarity and WoW 12.0 secret-safe patterns
  matter more than cleverness.
- Combat code must stay **secret-safe** (no Lua math or comparisons on secret values). See
  `Modules/Raidframes.lua` for the established rendering patterns.

---

## Releasing

Releases are produced by the [BigWigs Packager](https://github.com/BigWigsMods/packager)
GitHub Action and uploaded to CurseForge. **Pushing a tag publishes — merging to `main`
alone ships nothing.**

1. Merge `dev` → `main`.
2. Bump `## Version:` in `LumenUI.toc`.
3. Push a tag:
   ```bash
   git tag v0.9.105-beta   # tags containing -beta/-alpha go to the beta channel
   git push origin v0.9.105-beta
   ```

Requires a `CF_API_KEY` repository secret (CurseForge API token). `WAGO_API_TOKEN` and
`WOWI_API_TOKEN` are optional for additional distribution targets.

Branch model: **`dev` = work · `main` = stable · tag = publish.**

---

## Roadmap

Module by module, no bloat: the curated **quality-of-life module** shipped in the beta;
next up are **Unit Frames → Nameplates**. Encounter callouts and niche tools are
intentionally out of scope.

---

## Tech stack

Lua + WoW API, built on [Ace3](https://www.wowace.com/projects/ace3)
(AceAddon, AceConsole, AceEvent, AceDB, AceSerializer) plus
[LibDeflate](https://github.com/SafeteeWoW/LibDeflate) for export/import compression.
The settings UI is a custom suite shell (`Shell/`) — not AceConfig.

## Credits & licensing

- Fonts: **Cinzel** and **Hanken Grotesk** — SIL Open Font License (`Fonts/OFL-*.txt`)
- Icons: [Lucide](https://lucide.dev) — ISC License (`Textures/LICENSE-Lucide.txt`)
- Ace3, CallbackHandler, LibStub and LibDeflate — see `Libs/LICENSES.txt`

Addon code © 2026 NennMichSchinken, released under the [MIT License](LICENSE).
Bundled fonts, icons and libraries keep their own licenses (see above).
