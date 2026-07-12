# Security Policy

## Supported versions

Only the **latest release** (CurseForge / the matching GitHub tag) is supported.
Older versions receive no fixes — please update before reporting.

## Scope

LumenUI is a World of Warcraft interface addon. It runs inside WoW's sandboxed
Lua environment: it cannot read or write files on your machine, open network
connections, or execute external programs. Settings are stored in WoW's
SavedVariables (`LumenDB`); no data is collected or transmitted.

Security-relevant topics for an addon of this kind:

- **Taint / secure-code issues** — anything that lets LumenUI break protected
  Blizzard functionality (blocked actions, taint spreading into the Blizzard UI).
- **Import-string handling** — profile import codes are deserialized data
  (AceSerializer + LibDeflate). Anything a crafted import string can do beyond
  "import fails cleanly" is a bug we want to know about.
- **Secure-binding problems** — stuck keyboard or mouse states caused by the
  click-cast / hovercast system.

## Reporting a vulnerability

Open a [GitHub issue](../../issues). For anything you'd rather not post
publicly, use GitHub's private
[vulnerability report](../../security/advisories/new) instead.

Please include the addon version, the WoW build, and reproduction steps
(fresh profile plus the exact import string, if one is involved).

You can expect a first response within a week. Confirmed issues are fixed in
the next release. This is a hobby project — there is no bug-bounty program.
