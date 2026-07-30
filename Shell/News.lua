local ADDON, ns = ...

-- ===========================================================================
--  Lumen — What's new (release notes data)
--
--  The table the Shell shows in its sidebar news card and on the "What's new"
--  screen. It is written BY HAND for every release; the source are the patch
--  notes we write anyway. That is a permanent extra release step, not a
--  one-off — plan for it when tagging.
--
--  Rules that keep the screen honest:
--   * NEWEST version first. `version` matches the released tag (without -beta).
--   * `summary` = the two lines the sidebar card shows for that release. Keep
--     it to two lines; the card truncates rather than growing. Roughly 80
--     characters fit — past that the line ends mid-word, which reads like a
--     defect even though it is the intended cap.
--   * `text` = ONE plain sentence per entry. No marketing.
--   * `kind` = "new" | "fixed" | "changed".
--   * A jump target is OPTIONAL: set `section`/`tab` (and `card`, only for a
--     key a screen really registers via Shell:RegisterJumpCard) when there is
--     a setting behind the line. Entries WITHOUT a target stay quiet — no
--     path, no chevron, no hover. A row that jumps nowhere reads as broken,
--     so bug fixes usually carry no target at all.
--   * `date` is the release date, shown muted next to the version. Fix it up
--     when the tag actually goes out if it was written ahead of time.
--
--  Registered card keys today:
--   Raidframes › Raid / Group: power-bar, text-name, text-hp, icon-role, icon-lead
--   Raidframes › Base: health-bar, text-style
--   Raidframes › Auras: aura-hotsOwn, aura-defensives, aura-major, aura-debuffs
--     (the key also PRESELECTS that category when the jump lands)
--   Global › Base: accent, whatsnew, font
--   QoL › Base: qol-windows, qol-invites
--  A key is what makes the target card FLASH on arrival. A jump without one
--  only opens the tab and nothing lights up — so give every jumping entry a
--  key, and register a new one (regJump in Screens.lua) if the card lacks it.
--
--  Strings stay ENGLISH here — they are the localization keys; T() is applied
--  when the row is drawn and Locales/deDE.lua carries the translations.
-- ===========================================================================

ns.News = {
	{
		version = "0.9.291",
		date = "2026-07-30",
		summary = "Aura settings now live on their own tab, with a preview and a copy dialog.",
		entries = {
			{ kind = "new",
			  text = "Aura indicators have their own tab: pick a category, edit it below the preview, and switch between Raid and Group with one control.",
			  section = "Raidframes", tab = "Auras", card = "aura-hotsOwn" },
			{ kind = "new",
			  text = "Copy settings from one category or context to another — the dialog shows every destination as a grid, so you pick exactly where they land.",
			  section = "Raidframes", tab = "Auras" },
			{ kind = "changed",
			  text = "Which spells are tracked moved into the same tab, so a category is set up in one place instead of three; the separate Tracking tab is gone.",
			  section = "Raidframes", tab = "Auras" },
			{ kind = "changed",
			  text = "All options of a category are visible at once — the \"More options\" link on the aura cards is gone." },
			{ kind = "changed",
			  text = "The preview is now anchored at the top of every raid frame tab and grows with its content; the separate preview window and its sidebar button are gone.",
			  section = "Raidframes", tab = "Base" },
			{ kind = "fixed",
			  text = "The role and leader icons drew over the aura icons, so an icon could hide a debuff behind it." },
			{ kind = "fixed",
			  text = "Where two aura rows share a corner, the order is now fixed — debuffs, defensives, major cooldowns, then HoTs — instead of depending on which category you switched on first." },
			{ kind = "changed",
			  text = "The sample size above the raid preview is a segmented switch now, like every other either/or choice in the settings." },
			{ kind = "changed",
			  text = "Search and text fields sit a step lighter than the surface around them, so they read as something you can type into." },
			{ kind = "changed",
			  text = "The line under a card title is a little larger and thinner — it was smaller than the hints belonging to single controls inside the card." },
		},
	},
	{
		version = "0.9.290",
		date = "2026-07-28",
		summary = "Lumen's own font on the frames, and aura icons that stay off the resource bar.",
		entries = {
			{ kind = "new",
			  text = "The frames can use Lumen's own font instead of WoW's — it reads better at the small sizes the frame texts run at.",
			  section = "Global", tab = "Base", card = "font" },
			{ kind = "fixed",
			  text = "Aura icons covered the resource bar: a bottom row now sits on the health bar, and auto-fit shrinks the icons instead of letting them overflow." },
			{ kind = "fixed",
			  text = "Both Delves windows could never be moved — the window list carried a wrong addon name all along.",
			  section = "QoL", tab = "Base", card = "qol-windows" },
			{ kind = "fixed",
			  text = "The settings search did not find the mode switches — HP display, outline, dispel, aggro and fill colour were all missing from it." },
			{ kind = "changed",
			  text = "Raid frames do noticeably less work per aura update, which tells the most in a full raid." },
			{ kind = "changed",
			  text = "Imported profiles are checked before they are applied, so a shared code cannot smuggle extra macro commands into a click-cast binding.",
			  section = "Global", tab = "Profile" },
			{ kind = "changed",
			  text = "Prepared for patch 12.1, where a group member's class can arrive as a protected value." },
		},
	},
	{
		version = "0.9.289",
		date = "2026-07-27",
		summary = "The sidebar now shows what an update changed — and every note jumps to the setting behind it.",
		entries = {
			{ kind = "new",
			  text = "What's new: after an update the sidebar carries a news card, and every note jumps to the setting behind it.",
			  section = "Global", tab = "Base", card = "whatsnew" },
			{ kind = "changed",
			  text = "The two sidebar actions are flat rows with icons now, and the module list carries its icons again." },
		},
	},
	{
		version = "0.9.287",
		date = "2026-07-26",
		summary = "A rebuilt settings window with a free accent colour and a search — plus resource bars on the raid frames.",
		entries = {
			{ kind = "new",
			  text = "An accent colour of your choice — seven presets or a free colour picker, saved account-wide.",
			  section = "Global", tab = "Base", card = "accent" },
			{ kind = "new",
			  text = "A search field above the module list finds a setting across every module and jumps straight to it." },
			{ kind = "new",
			  text = "A resource bar at the bottom of each frame — the other healers' mana at a glance.",
			  section = "Raidframes", tab = "Raid", card = "power-bar" },
			{ kind = "new",
			  text = "Smooth bars: health and resources glide to their new value instead of jumping.",
			  section = "Raidframes", tab = "Base", card = "health-bar" },
			{ kind = "new",
			  text = "Augmentation Evoker aura defaults — Prescience, Ebon Might, Shifting Sands and the rest of the kit.",
			  -- Retargeted in 0.9.291: the Tracking tab is gone and the spell lists
			  -- live in the Auras editor now. OpenTo skips an unknown tab silently, so
			  -- this row used to land on whatever tab was remembered and flash nothing.
			  section = "Raidframes", tab = "Auras", card = "aura-hotsOwn" },
			{ kind = "new",
			  text = "Accept group invites from friends and guild members automatically, while you are alone and outside an instance.",
			  section = "QoL", tab = "Base", card = "qol-invites" },
			{ kind = "changed",
			  text = "Settings window rebuilt: calmer monochrome surfaces, quieter text, bigger and rounder controls." },
			{ kind = "changed",
			  text = "Texture dropdowns need Shift or Ctrl before the mouse wheel previews, so scrolling no longer changes a setting by accident.",
			  section = "Raidframes", tab = "Base", card = "health-bar" },
			{ kind = "changed",
			  text = "Name and HP text have their own preview eyes instead of one shared toggle.",
			  section = "Raidframes", tab = "Raid", card = "text-name" },
			{ kind = "fixed",
			  text = "The role icon stayed hidden whenever no group role was assigned — solo, or in a group that never went through a role check." },
			{ kind = "changed",
			  text = "Smaller download: the bundled font is subset to Western Latin and 19 unused textures are gone." },
		},
	},
}

-- ---------------------------------------------------------------------------
--  Read state. "Read up to" is stored as the newest NEWS version, never as the
--  addon version: local dev builds report "dev" as their version, and a user
--  who skips a release must still see the releases in between. Account-wide
--  (db.global), like the accent — news is not a per-profile matter.
-- ---------------------------------------------------------------------------
local function store()
	local db = ns.Lumen and ns.Lumen.db
	return db and db.global
end

-- Compare two version strings by their numeric parts ("0.9.9" < "0.9.10").
-- Anything unparseable (a "dev" build) sorts as 0 and therefore counts as
-- older than every real release.
local function parts(v)
	local t = {}
	for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
	return t
end
function ns.NewsCompare(a, b)
	local pa, pb = parts(a), parts(b)
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return (x < y) and -1 or 1 end
	end
	return 0
end

function ns.NewsLatestVersion()
	local first = ns.News[1]
	return first and first.version
end

-- The releases the user has not seen yet, newest first. No stored version =
-- everything we ship notes for (an existing install meeting the feature for
-- the first time); a FRESH install is silenced in Core instead, by marking it
-- read before the first login print.
function ns.NewsUnread()
	local g = store()
	local seen = g and g.lastSeenVersion
	local out = {}
	for _, block in ipairs(ns.News) do
		if seen and ns.NewsCompare(block.version, seen) <= 0 then break end -- table is sorted: the rest is older too
		out[#out + 1] = block
	end
	return out
end

function ns.NewsEnabled()
	local g = store()
	return not g or g.showWhatsNew ~= false
end

function ns.NewsMarkRead()
	local g = store()
	if g then g.lastSeenVersion = ns.NewsLatestVersion() end
end
