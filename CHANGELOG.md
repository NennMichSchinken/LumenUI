# LumenUI

Release notes, newest first. This file IS the published changelog: `.pkgmeta` points
`manual-changelog` at it, so the BigWigs packager uses it for the GitHub release body
and the CurseForge file changelog instead of generating one from commit messages.

**Every release adds a section here.** It is the same text that goes into
`Shell/News.lua` for the in-game "What's new" screen, only grouped by feature area
instead of one sentence per entry. Keep the format: `## <version>` heading,
`### <feature area>` sections, bullets starting with `- Fixed:` / `- New:` or a plain
sentence for reworks. Plain and factual, no marketing.

## 0.9.292-beta

### Live preview
- Fixed: switching a layout between vertical and horizontal, or moving the width, height and spacing sliders, left the preview at the height it had reserved for the old layout — the frames rendered outside it, over the header and the tab strip. It only corrected itself once you touched the sample size. Affects the Raid and the Group tab alike.
- A tall preview no longer squeezes the settings underneath it. It takes at most half the available room; anything past that is clipped and scrolls with the mouse wheel, with a scrollbar on the right while there is more to see. The frames keep their true on-screen size — that is the point of the preview, so it is never scaled down to fit.
- Fixed: the frames sat on the line naming the preview underneath them. There is a guard between the two now, and at full scroll the last frame stops exactly above it.

### Aura settings
- Fixed: the dialog for copying settings between categories opened with "Appearance" already ticked. Nothing is preselected now — Copy stays unavailable until you pick both what to copy and where it goes.
- Fixed: the destination cells read as switched off. Each carries a real checkbox now, the same one the list above it uses, and the source column shows a greyed checkbox with an X so it is clear it cannot be a destination.
- Fixed: clicking a spot in that dialog that was not a control — a caption, a gap between rows, the source cell — closed the whole dialog.
- The dialog is a little narrower now that the source cell no longer has to hold a caption.

## 0.9.291-beta

### Aura indicators
- New: aura indicators have their own tab. Pick a category from the chips, edit it right under the preview, and switch between Raid and Group with one control.
- New: copy settings from one category or context to another. The dialog shows every destination as a grid, so you pick exactly where they land — and it warns you when copying placement would stack two icon rows in the same corner.
- Which spells are tracked moved into that same tab, so a category is set up in one place instead of three. The separate Tracking tab is gone.
- All options of a category are visible at once — the "More options" link on the aura cards is gone.
- Fixed: the role and leader icons drew over the aura icons, so an icon could hide a debuff behind it. Auras render above them now.
- Fixed: where two aura rows share a corner, the order is fixed — debuffs, defensives, major cooldowns, then HoTs — instead of depending on which category you switched on first.

### Live preview
- The preview is anchored at the top of every raid frame tab. It stays put while the settings scroll and grows with its content instead of scaling down.
- The separate preview window is gone, along with its dragging and its button in the sidebar. If you had moved it somewhere, that position is simply no longer used.
- The sample size above the raid preview is a segmented switch, like every other either/or choice in the settings.
- Fixed: the eye popover beside the preview jumped away from the cursor every time you toggled something in it.

### Settings window
- Search and text fields sit a step lighter than the surface around them, so they read as something you can type into. It shows most on the search box inside a dropdown, which previously had no contrast at all against the menu holding it.
- The line under a card title is a little larger and thinner. It used to be smaller than the hints belonging to single controls inside the card, which had the hierarchy the wrong way round.
- Switches and buttons are rounded rectangles instead of capsules. The tab row stays a capsule, because it is navigation sitting one level above the content.
- Fixed: a release note in "What's new" that pointed at a setting which has since moved landed on the wrong tab instead of the one it names.
