-- Z-Perl Forever - API compatibility shims
--
-- The Forever client is Classic based, but Blizzard has said it will carry the
-- retail (Midnight) addon restrictions. Retail also removed a number of old
-- globals that the Z-Perl code base uses as table keys at load time
-- (GetSpellInfo, UnitAura, GetItemInfo ...). If Forever ever does the same, the
-- shims below keep the addon loading. Each one is only defined when the client
-- has removed the original and provides the modern replacement.

-- Frames can invoke their highlight handlers even when Forever has prevented
-- the optional full highlight module from completing. Create the manager early
-- and give it harmless fallbacks; XPerlForever_Highlight.lua replaces these methods
-- with the complete implementation when it loads successfully.
if (not XPerl_Highlight) then
	XPerl_Highlight = CreateFrame("Frame", "XPerl_Highlight")
	local function NoOp() end
	XPerl_Highlight.Register = NoOp
	XPerl_Highlight.SetHighlight = NoOp
	XPerl_Highlight.RemoveHighlight = NoOp
	XPerl_Highlight.ClearAll = NoOp
	XPerl_Highlight.Add = NoOp
	XPerl_Highlight.Remove = NoOp
	XPerl_Highlight.TooltipInfo = NoOp
end

-- Forever's RestrictedExecution environment cannot compile secure snippets
-- because loadstring_untainted is unavailable. Z-Perl uses ordinary event
-- handlers for these visibility updates in this build.
XPerl_ForeverNoSecureSnippets = true

-- XPerl_SpellName(spellID)
-- Spell name for use as a table key. Several Classic spell IDs are missing from
-- the retail spell database; the lookup then returns nil and "[nil] = true" in a
-- table constructor aborts the whole file (which is how XPerlForever.lua died on retail,
-- taking every later XPerl_ function with it). A unique placeholder that can never
-- match a real aura name is returned instead.
function XPerl_SpellName(spellID)
	local name
	if (C_Spell and C_Spell.GetSpellInfo) then
		local info = C_Spell.GetSpellInfo(spellID)
		name = info and info.name
	elseif (GetSpellInfo) then
		name = GetSpellInfo(spellID)
	end
	return name or ("XPerl_NoSpell_"..tostring(spellID))
end

if (not GetSpellInfo and C_Spell and C_Spell.GetSpellInfo) then
	GetSpellInfo = function(spell)
		local info = C_Spell.GetSpellInfo(spell)
		if (info) then
			return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID, info.originalIconID
		end
		-- Embedded Classic libraries use GetSpellInfo directly as a table key.
		-- A stable sentinel prevents a missing Forever spell from aborting load.
		return "XPerl_NoSpell_"..tostring(spell)
	end
end

if (not GetItemInfo and C_Item and C_Item.GetItemInfo) then
	GetItemInfo = C_Item.GetItemInfo
end

if (not GetItemCount and C_Item and C_Item.GetItemCount) then
	GetItemCount = C_Item.GetItemCount
end

if (not UnitAura and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
	UnitAura = function(unit, index, filter)
		-- By-index aura queries raise an error for addons while auras are secret
		if (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) then
			return nil
		end
		local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
		if (a) then
			return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime, a.sourceUnit, a.isStealable, a.nameplateShowPersonal, a.spellId, a.canApplyAura, a.isBossAura, a.isFromPlayerOrPlayerPet, a.nameplateShowAll, a.timeMod
		end
	end
end

if (not UnitBuff and UnitAura) then
	UnitBuff = function(unit, index, filter)
		return UnitAura(unit, index, filter and ("HELPFUL|"..filter) or "HELPFUL")
	end
end

if (not UnitDebuff and UnitAura) then
	UnitDebuff = function(unit, index, filter)
		return UnitAura(unit, index, filter and ("HARMFUL|"..filter) or "HARMFUL")
	end
end

if (not IsAddOnLoaded and C_AddOns and C_AddOns.IsAddOnLoaded) then
	IsAddOnLoaded = C_AddOns.IsAddOnLoaded
end

if (not GetAddOnMetadata and C_AddOns and C_AddOns.GetAddOnMetadata) then
	GetAddOnMetadata = C_AddOns.GetAddOnMetadata
end

if (not GetAddOnInfo and C_AddOns and C_AddOns.GetAddOnInfo) then
	GetAddOnInfo = C_AddOns.GetAddOnInfo
end

if (not LoadAddOn and C_AddOns and C_AddOns.LoadAddOn) then
	LoadAddOn = C_AddOns.LoadAddOn
end

if (not EnableAddOn and C_AddOns and C_AddOns.EnableAddOn) then
	EnableAddOn = C_AddOns.EnableAddOn
end

if (not DisableAddOn and C_AddOns and C_AddOns.DisableAddOn) then
	DisableAddOn = C_AddOns.DisableAddOn
end
