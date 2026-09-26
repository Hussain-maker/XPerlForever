# X-Perl Forever 1.0.2 – fixes and an optional Buff Blacklist module

Hi! These are some fixes and one new optional module for X-Perl Forever 1.0.2, made while using it on
retail (Midnight, 12.0.x). They're offered for you to merge or adapt however you like – everything is
GPLv3 like the addon.

Everything was tested in game on retail with BugGrabber running (no Lua errors). Each change is a
separate patch, so you can take any subset.

## What's in this repository

- The full addon (all `XPerlForever*` folders) with the changes below applied. Use **Code → Download ZIP**
  and copy the `XPerlForever*` folders into `Interface\AddOns` to try it.
- The history starts with unmodified 1.0.2 as distributed on CurseForge, followed by one commit per change –
  open a commit to see exactly what it changes.
- `patches/` – the same four changes as patch files against unmodified 1.0.2
  (apply with `git am`, or read them as diffs).

## The changes

### 1. Player power bar keeps the wrong colour after shapeshifting (bug fix)
`XPerlForever/XPerlForever.lua`, `XPerl_SetManaBarType` – **+9 lines**

X-Perl only has colours for mana, rage, focus and energy. For any other power type it leaves the bar as it
was. Example: a Balance Druid shifts to Bear (bar turns red for rage), then back to caster form – the bar
stays red because Astral Power has no X-Perl colour. The fix falls back to Blizzard's `PowerBarColor` for
power types X-Perl doesn't define (Astral Power, Runic Power, Insanity, Maelstrom, Fury, …). X-Perl's own
colours are still used for mana/rage/focus/energy.

### 2. Combo points on the Personal Resource Display don't count (bug fix)
`XPerlForever/XPerlForever.lua`, `XPerl_BlizzFrameDisable` – **+3 / −1 lines**

On retail (Midnight), `PlayerFrame.classPowerBar` also drives the Personal Resource Display's class
resource. `XPerl_BlizzFrameDisable(PlayerFrame)` unregistered that bar's events, so combo points on the
Personal Resource Display (or moved onto the target nameplate by nameplate addons) appeared but never lit
up. The fix leaves only that bar's events registered; the Blizzard player frame is still hidden and its
other parts are still disabled. Found by testing each part of `XPerl_BlizzFrameDisable` one at a time in game.

### 3. Options: optional modules can add their own tab (small extension point)
`XPerlForever_Options/XPerlForever_FrameOptions.lua` (+91) and `.xml` (+4) – additions only

A module appends `{key = "MyModule", title = "My Tab", create = function(page) ... end}` to the global list
`XPerl_OptionsExtraTabs`. On the options window's first show, each entry gets a tab after the last built-in
tab and a page with the same area and scale as the built-in pages; `create(page)` fills it on first show.

- The window's width, scale and saved size are **never changed** – the tab uses the free space already in
  the tab row (the width formula budgets more padding per tab than the tabs use). If a title doesn't fit it
  is shortened, with the full title as a tooltip.
- With no entries the function returns immediately, so the options window is exactly as before.
- Errors from an extra tab are reported via `geterrorhandler()` and can't stop the window's setup.

### 4. New optional module: `XPerlForever_AuraBlacklist` (feature)
New folder (TOC, `localization.lua`, main file) plus **two optional hooks** in `XPerlForever/XPerlForever.lua`.

Hides chosen buffs on the **target, focus, target-of-target and focus-target** frames – e.g. food,
flasks, weather and other clutter.

- **"Buff Blacklist" options tab** (uses change 3): enable toggle, add by spell ID or exact name, remove,
  and a per-spell **"show if mine"** option (hide it when others cast it, show it when you did).
- **Import from BetterBlizzFrames** (optional): one-click *merge* of BetterBlizzFrames' aura blacklist, read
  only. The module's own list starts **empty** and is stored account-wide in `XPerlAuraBlacklistDB`.
- **Buffs only**; debuffs and the player/party/pet/raid frames are untouched. Hidden buffs leave no gaps and
  don't count toward the buff limits.
- **Midnight-safe:** a buff is only hidden when its spell ID is readable (`XPerl_CanAccess`); unreadable →
  shown. While aura data is restricted (`XPerl_AurasSecret()`: arena, rated PvP, M+, raid combat) X-Perl
  shows buffs through Blizzard's AuraContainer, and the module passes the list to that group via
  `SetAuraGroupCandidateFilters(key, {excludeSpellIDs = set})` – all listed IDs for friendly/player units,
  only never-secret IDs otherwise. It only reconfigures a live group when
  `XPerl_AuraContainer_SafeToReconfigure()` allows it. "Show if mine" can't apply in that mode.

**Core hooks** (both are nil without the module, so behaviour is unchanged):
- `XPerl_BuffFilter(frame, unit, spellID, auraInstanceID, isPlayer)` in `XPerl_Unit_UpdateBuffs`, called for
  buffs that would be shown; return true to hide.
- `XPerl_BuffContainerFilter(frame, container, groupKey, filter)` in `XPerl_AuraContainer_Create`, called once
  for each new aura group before it is live.

**Known limitations**
- In restricted-aura mode, after a target/focus change the new unit keeps the previous unit's filter set
  until reconfiguring is safe again (X-Perl doesn't rebuild containers while auras are secret).
- The restricted-aura path follows how BetterBlizzFrames uses `SetAuraGroupCandidateFilters`; the normal
  path is fully tested, the arena path less so.

## Totals

| Change | Files | Lines |
|---|---|---|
| 1. Power bar colour | XPerlForever.lua | +9 |
| 2. Combo points | XPerlForever.lua | +3 / −1 |
| 3. Options extra tabs | XPerlForever_Options (lua, xml) | +95 |
| 4. Buff Blacklist | XPerlForever.lua (hooks) + new module | +715 / −1 |

Thanks for keeping X-Perl alive!
