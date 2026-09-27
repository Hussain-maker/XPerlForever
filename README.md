# X-Perl Forever 1.0.2 – Midnight fixes, arena improvements and an optional Buff Blacklist module

Hi! These are fixes, arena/combat improvements and one new optional module for X-Perl Forever 1.0.2,
made while using it on retail (Midnight, 12.0.x), mostly in arena. They're offered for you to merge or adapt however you like – everything is
GPLv3 like the addon.

Everything was tested in game on retail with BugGrabber running (no Lua errors). Each change is a
separate patch, so you can take any subset. New options are **off by default**, so X-Perl behaves as before
unless they are ticked.

## What's in this repository

- The full addon (all `XPerlForever*` folders) with the changes below applied. Use **Code → Download ZIP**
  and copy the `XPerlForever*` folders into `Interface\AddOns` to try it.
- The history starts with unmodified 1.0.2 as distributed on CurseForge, followed by one commit per change –
  open a commit to see exactly what it changes.
- `patches/` – the same changes as numbered patch files against unmodified 1.0.2, in order
  (apply with `git am patches/*.patch`, or read them as diffs).

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

### 5. Target/focus: option "Buffs First" (option, off by default)
`XPerlForever_Target`, options (xml + localization) – **+44 / −2**

Enemies always showed debuffs in the first row and buffs after them. The new option keeps buffs first for
every unit, in both the normal layout and the restricted-aura (AuraContainer) layout.

### 6. Empty first aura row no longer leaves a gap (bug fix)
`XPerlForever.lua` (`XPerl_Unit_BuffPositions`), `XPerlForever_Target` – **+10 / −2**

With no buffs (or, on enemies, no debuffs) the empty first row stayed reserved, so the other row started a
row lower. The second row now moves up; in the restricted-aura layout the second group is anchored below
the first group's icons instead of a fixed lower half.

### 7. Restricted-aura (combat) layout matches X-Perl's normal layout (fix + option)
`XPerlForever.lua`, `XPerlForever_Target`, options, `XPerlForever_AuraBlacklist` – **+195 / −32**

While aura data is secret (arena, rated PvP, M+, raid combat) target/focus show auras through Blizzard's
AuraContainer, which ignored most of X-Perl's aura settings. Now:
- **Filters apply** with the normal layout's rules (castable buffs, "only my buffs" on friends, "only my
  debuffs" on enemies, curable debuffs on friends) – Blizzard applies them, so they work while secret.
- **Countdown**: "Buff Countdown" shows an X-Perl-style countdown (yellow, whole seconds) drawn by the game
  via `SetDurationText`, hidden above "Countdown Start" by a step colour curve on the remaining duration.
  Falls back to Blizzard's countdown numbers styled like X-Perl's if that API is missing.
- **Wrapping** at the frame's full width like the normal layout, and **"Target Buff Rows"** caps the icons.
- **Debuff borders**: X-Perl's debuff border, coloured by dispel type by the game (`AddDispelTypeTexture`).
- New option **"Key Enemy Buffs"** (off by default): enemies show only important buffs, then purgeable ones
  (`HELPFUL|IMPORTANT`, then `HELPFUL|DISPELLABLE|!IMPORTANT`).
- Core: `XPerl_AuraContainer_AddGroup` (one group with X-Perl's button setup; `XPerl_AuraContainer_Create`
  gains an optional `maxCount`). The buff blacklist handles every buff group of a container.

Note: `XPerl_DispelColourCurve` gave Magic the "none" colour for us in combat, which suggests the dispel type
IDs it uses may not match the client's; the borders therefore use Blizzard's colours by type name.

### 8. Arena enemies showed as Death Knights (bug fix)
`XPerlForever_Target` – **+27 / −3**

When a unit's class is secret, `XPerl_ClassPos` falls back to coordinates that are the Death Knight square, so
every arena enemy showed a DK icon. The class is now taken from the arena opponent's spec
(`UnitIsUnit(unit, "arenaN")` and `GetArenaOpponentSpec` are not secret), keeping X-Perl's normal icon.

### 9. Druid mana bar: "attempt to compare number with nil" (bug fix)
`XPerlForever_Player` – **+3 / −1**

`UnitPowerType` can return nothing while options are applied; only a readable value is compared now.

### 10. Unit tooltips: GameTooltip_UnitColor error on secret units (bug fix)
`XPerlForever.lua` (`XPerl_PlayerTip`) – **+6 / −2**

Called from addon code, `GameTooltip_UnitColor` errors on enemies in combat ("execution tainted by
XPerlForever_..."). `SetUnit` already colours the name, so the recolour is attempted with `pcall`.

### 11. Less aura clutter (options, off by default)
`XPerlForever.lua`, `XPerlForever_Target`, `XPerlForever_TargetTarget`, options – **+53 / −6**

- "Key Enemy Buffs" also applies in the normal layout (`C_UnitAuras.IsAuraFilteredOutByInstanceID` with the
  IMPORTANT and DISPELLABLE filters; unreadable answers keep the buff shown).
- New focus option **"CC Debuffs Only"**: the focus shows only crowd control (`HARMFUL|CROWD_CONTROL`) from
  anyone, in both layouts.
- Target-of-target / focus-target restricted-aura layout wraps at the frame's width and honours the row limit.

### 12. Arena enemy portraits were blank (bug fix)
`XPerlForever.lua` (`XPerl_Unit_UpdatePortrait`), `XPerlForever_Target` – **+42 / −13**

The 3D portrait model never loads for enemy units in arena, so their portraits were empty. Arena enemies now
get the 2D portrait (class icon if even that is missing). New helper `XPerl_UnitClassFile(unit)` returns the
class also when it is secret (via the arena opponent's spec); the class icon uses it too.

### 13. SetPortraitToTexture no longer exists (bug fix)
`XPerlForever.lua` – **+22 / −14**

The "Class Portrait" option errored ("attempt to call a nil value"). New `XPerl_SetClassPortrait` draws the
round class icon (`UI-Classes-Circles`); the normal portrait resets texture coordinates first.

## Totals

| Change | Files | Lines |
|---|---|---|
| 1. Power bar colour | XPerlForever.lua | +9 |
| 2. Combo points | XPerlForever.lua | +3 / −1 |
| 3. Options extra tabs | XPerlForever_Options (lua, xml) | +95 |
| 4. Buff Blacklist | XPerlForever.lua (hooks) + new module | +715 / −1 |
| 5. Buffs First option | Target, Options | +44 / −2 |
| 6. Empty first aura row | XPerlForever.lua, Target | +10 / −2 |
| 7. Combat layout matches normal layout | XPerlForever.lua, Target, Options, AuraBlacklist | +195 / −32 |
| 8. Arena class icons | Target | +27 / −3 |
| 9. Druid mana bar nil compare | Player | +3 / −1 |
| 10. Tooltip recolour on secret units | XPerlForever.lua | +6 / −2 |
| 11. Less aura clutter | XPerlForever.lua, Target, TargetTarget, Options | +53 / −6 |
| 12. Arena enemy portraits | XPerlForever.lua, Target | +42 / −13 |
| 13. SetPortraitToTexture removed | XPerlForever.lua | +22 / −14 |

Thanks for keeping X-Perl alive!
