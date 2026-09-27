-- Z-Perl UnitFrames
-- Author: Resike
-- License: GNU GPL v3, 18 October 2014

local conf
local percD	= "%d"..PERCENT_SYMBOL
local perc1F = "%.1f"..PERCENT_SYMBOL

XPerl_RequestConfig(function(New)
	conf = New
end, "$Revision: 9c0697ce7ea46b29e24c894c5db60c3d931f5bdd $")
XPerl_SetModuleRevision("$Revision: 9c0697ce7ea46b29e24c894c5db60c3d931f5bdd $")

local IsRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local IsPandaClassic = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
local IsVanillaClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC
local IsClassic = WOW_PROJECT_ID >= WOW_PROJECT_CLASSIC

------------------------------------------------------------------------------
-- Z-Perl Forever: restricted API support
--
-- The Forever client is expected to use the Midnight style "secret values".
-- A secret cannot be compared, used in maths, used as a table key or tested as
-- a boolean; it can only be handed to Blizzard widget methods. Everything in
-- this file that touches unit health, power, auras, names or cast times goes
-- through the helpers below, and the new Blizzard helper APIs are only used
-- when the running client actually provides them. On a Classic Era client all
-- of these switches are off and the original code paths run unchanged.
--
-- The whole block is scoped with do/end so the file's main chunk stays under
-- Lua's limit of 200 active local variables. Only the globals defined in here
-- are used by the rest of the file and by the other modules.
do
local issecretvalue = issecretvalue
local canaccessvalue = canaccessvalue

-- XPerl_CanAccess(v) - true when addon code may read, compare or index v
function XPerl_CanAccess(v)
	if (v == nil) then
		return false
	end
	if (canaccessvalue) then
		return canaccessvalue(v)
	end
	if (issecretvalue) then
		return not issecretvalue(v)
	end
	return true
end
local XPerl_CanAccess = XPerl_CanAccess

-- XPerl_IsSecret(v) - true when v exists but addon code may not look inside it
function XPerl_IsSecret(v)
	return v ~= nil and not XPerl_CanAccess(v)
end
local XPerl_IsSecret = XPerl_IsSecret

-- Feature switches, evaluated once at load
local XPerl_HasHealthPercent = type(UnitHealthPercent) == "function" and CurveConstants ~= nil
local XPerl_HasPowerPercent = type(UnitPowerPercent) == "function" and CurveConstants ~= nil
local XPerl_HasColorCurves = C_CurveUtil ~= nil and type(C_CurveUtil.CreateColorCurve) == "function"
local XPerl_HasBooleanCurves = C_CurveUtil ~= nil and type(C_CurveUtil.EvaluateColorValueFromBoolean) == "function"
local XPerl_HasAuraAPI = C_UnitAuras ~= nil and type(C_UnitAuras.GetUnitAuras) == "function"
-- Detected the same way as the SecureAuraHeaderTemplate probe already used by
-- XPerlForever_PlayerBuffs.lua: ask the client whether it knows the template name at
-- all, rather than assuming from an interface/version number.
local XPerl_HasAuraContainer = C_XMLUtil ~= nil and type(C_XMLUtil.GetTemplateInfo) == "function" and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") ~= nil
-- XPerl_EventValid(event)
-- Retail treats some removed events (the combat log) as *forbidden*: even a
-- pcall-wrapped RegisterEvent/UnregisterEvent raises ADDON_ACTION_FORBIDDEN and
-- taints the addon. So the client is asked first and such events are never touched.
function XPerl_EventValid(event)
	-- C_EventUtils.IsEventValid still says "valid" for the combat log on Midnight
	-- because the engine keeps it for Blizzard code. Any client that has the
	-- secret-value API withholds it from addons, so never touch it there.
	if (event == "COMBAT_LOG_EVENT_UNFILTERED" and issecretvalue) then
		return false
	end
	if (C_EventUtils and C_EventUtils.IsEventValid) then
		return C_EventUtils.IsEventValid(event) and true or false
	end
	return true
end
local XPerl_HasCombatLog = XPerl_EventValid("COMBAT_LOG_EVENT_UNFILTERED")

-- XPerl_SafeBool(v, default)
-- A boolean that may be secret cannot be tested or combined; return default then
function XPerl_SafeBool(v, default)
	if (not XPerl_CanAccess(v)) then
		return default
	end
	return v
end

-- Shared with the other modules
XPerl_ForeverAPI = {
	healthPercent = XPerl_HasHealthPercent,
	powerPercent = XPerl_HasPowerPercent,
	colorCurves = XPerl_HasColorCurves,
	booleanCurves = XPerl_HasBooleanCurves,
	auras = XPerl_HasAuraAPI,
	auraContainer = XPerl_HasAuraContainer,
	combatLog = XPerl_HasCombatLog,
	castDurations = type(UnitCastingDuration) == "function",
	auraSecrecy = C_Secrets ~= nil and type(C_Secrets.ShouldAurasBeSecret) == "function",
	-- Retail folded UNIT_HEALTH_FREQUENT into UNIT_HEALTH; Classic still has both
	healthEvent = XPerl_EventValid("UNIT_HEALTH_FREQUENT") and "UNIT_HEALTH_FREQUENT" or "UNIT_HEALTH",
}

-- XPerl_RegisterEventSafe / XPerl_UnregisterEventSafe / XPerl_RegisterUnitEventSafe
-- Register/unregister that never errors on an event the client no longer has
function XPerl_RegisterEventSafe(frame, event)
	if (not XPerl_EventValid(event)) then
		return false
	end
	return pcall(frame.RegisterEvent, frame, event)
end

function XPerl_UnregisterEventSafe(frame, event)
	if (not XPerl_EventValid(event)) then
		return false
	end
	return pcall(frame.UnregisterEvent, frame, event)
end

function XPerl_RegisterUnitEventSafe(frame, event, ...)
	if (not XPerl_EventValid(event)) then
		return false
	end
	return pcall(frame.RegisterUnitEvent, frame, event, ...)
end

-- XPerl_SetAlphaFromBoolean(region, value, alphaTrue, alphaFalse)
-- Shows/dims a region from a boolean that may be secret
function XPerl_SetAlphaFromBoolean(region, value, alphaTrue, alphaFalse)
	if (not region) then
		return
	end
	if (region.SetAlphaFromBoolean and XPerl_IsSecret(value)) then
		region:SetAlphaFromBoolean(value, alphaTrue, alphaFalse)
	elseif (value and XPerl_CanAccess(value)) then
		region:SetAlpha(alphaTrue)
	else
		region:SetAlpha(alphaFalse)
	end
end

-- XPerl_GetPowerPercent(unit, powerType, cur, max)
-- Returns a 0..100 value for text display only. Secret on restricted clients.
function XPerl_GetPowerPercent(unit, powerType, cur, max)
	if (XPerl_CanAccess(cur) and XPerl_CanAccess(max)) then
		if (cur > 0 and max == 0) then
			return 100
		elseif (max == 0) then
			return 0
		end
		return 100 * cur / max
	end
	if (XPerl_HasPowerPercent and unit) then
		return UnitPowerPercent(unit, powerType, false, CurveConstants.ScaleTo100)
	end
	return 0
end

-- XPerl_GetHealthPercent(unit, hp, max)
-- Returns a 0..1 value. Secret on restricted clients.
function XPerl_GetHealthPercent(unit, hp, max)
	if (XPerl_CanAccess(hp) and XPerl_CanAccess(max)) then
		if (hp > 0 and max == 0) then
			return 1
		elseif (max == 0) then
			return 0
		end
		return min(1, hp / max)
	end
	if (XPerl_HasHealthPercent and unit) then
		return UnitHealthPercent(unit)
	end
	return 0
end

-- Aura enumeration -----------------------------------------------------------
-- XPerl_UnitAuraByIndex(unit, index, filter)
-- Same return values as UnitAura() plus auraInstanceID and isFromPlayerOrPlayerPet.
-- Uses C_UnitAuras.GetUnitAuras when the client has it. The vector is cached for
-- the current frame so index loops do not re-query the client each step.
local auraCacheUnit, auraCacheFilter, auraCacheTime, auraCacheList

-- XPerl_UnitAuraCache_Invalidate()
-- The auraCacheFrame below clears the cache on UNIT_AURA, but it's a separate
-- frame and WoW guarantees no ordering between two frames' handlers for the same
-- event -- a reader can win and get the stale pre-change list. Callers invalidate
-- synchronously instead. Needs to be a function: auraCacheList is block-local.
function XPerl_UnitAuraCache_Invalidate()
	auraCacheList = nil
end

-- XPerl_AurasSecret()
-- True while the client hides aura data from addons (combat, encounters, M+, PvP).
-- Since 12.1 every by-index / by-instance aura query raises a Lua error for addon
-- code in that state, so callers must not even ask.
local ShouldAurasBeSecret = C_Secrets and C_Secrets.ShouldAurasBeSecret
function XPerl_AurasSecret()
	return ShouldAurasBeSecret ~= nil and ShouldAurasBeSecret() == true
end

if (XPerl_HasAuraAPI) then
	-- Drop the cached vector as soon as any aura changes
	local auraCacheFrame = CreateFrame("Frame")
	auraCacheFrame:RegisterEvent("UNIT_AURA")
	auraCacheFrame:SetScript("OnEvent", function()
		auraCacheList = nil
	end)
end
function XPerl_UnitAuraByIndex(unit, index, filter)
	if (XPerl_AurasSecret()) then
		auraCacheList = nil
		return nil
	end

	if (not XPerl_HasAuraAPI) then
		local name, icon, applications, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, index, filter)
		return name, icon, applications, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId
	end

	local now = GetTime()
	if (auraCacheUnit ~= unit or auraCacheFilter ~= filter or auraCacheTime ~= now or not auraCacheList) then
		auraCacheUnit, auraCacheFilter, auraCacheTime = unit, filter, now
		-- pcall: the secrecy flag can flip between the check above and the query
		local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, filter or "HELPFUL", 40)
		auraCacheList = ok and list or nil
	end

	local aura = auraCacheList and auraCacheList[index]
	if (not aura) then
		return nil
	end
	return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime, aura.sourceUnit, aura.isStealable, aura.nameplateShowPersonal, aura.spellId, aura.auraInstanceID, aura.isFromPlayerOrPlayerPet
end

-- XPerl_UnitAuraByInstanceMap(unit, filter)
-- auraInstanceID -> true for every aura matching filter. IDs are never secret,
-- so this is the safe way to ask "is this one of my auras" on restricted clients.
function XPerl_UnitAuraByInstanceMap(unit, filter, map)
	map = map or {}
	if (XPerl_HasAuraAPI and not XPerl_AurasSecret()) then
		local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, filter, 40)
		if (ok and list) then
			for i = 1, #list do
				local id = list[i].auraInstanceID
				-- Since 12.0.1 the IDs are secret for indirect units too
				if (id and XPerl_CanAccess(id)) then
					map[id] = true
				end
			end
		end
	end
	return map
end

-- XPerl_DispelColourCurve()
-- Step curve used with C_UnitAuras.GetAuraDispelTypeColor on restricted clients
local dispelColourCurve
function XPerl_DispelColourCurve()
	if (dispelColourCurve or not XPerl_HasColorCurves) then
		return dispelColourCurve
	end
	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)
	local dtc = DebuffTypeColor or {}
	local none = dtc.none or {r = 0.8, g = 0, b = 0}
	local function AddType(id, key)
		local c = dtc[key] or none
		curve:AddPoint(id, CreateColor(c.r, c.g, c.b, 1))
	end
	AddType(0, "none")
	AddType(1, "Magic")
	AddType(2, "Curse")
	AddType(3, "Disease")
	AddType(4, "Poison")
	AddType(9, "none")
	AddType(11, "none")
	dispelColourCurve = curve
	return curve
end

-- XPerl_CooldownFrame_SetAura(cooldown, unit, auraInstanceID)
-- Drives an aura cooldown swipe from a Blizzard duration object when the aura
-- times are secret. Blizzard draws the countdown numbers in that case.
function XPerl_CooldownFrame_SetAura(self, unit, auraInstanceID)
	if (not (C_UnitAuras and C_UnitAuras.GetAuraDuration and self.SetCooldownFromDurationObject) or auraInstanceID == nil) then
		self:Hide()
		return false
	end
	local durationObject = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
	if (not durationObject) then
		self:Hide()
		return false
	end
	self:SetScript("OnUpdate", nil)
	if (self.countdown) then
		self.countdown:Hide()
	end
	self.endTime = nil
	self:SetHideCountdownNumbers(false)
	self:SetCooldownFromDurationObject(durationObject, true)
	self:Show()
	return true
end

-- XPerl_SafeSetWidthFromText(frame, textObject, padding, fallbackWidth)
-- GetStringWidth() can come back a secret number even for a FontString
-- holding plain, non-secret text: taint follows the execution path of the
-- surrounding update, not just the value being measured (section 3) -- a
-- readable source string (e.g. checked via XPerl_CanAccess) is not enough on
-- its own: XPerl_Target_UpdateType crashed with its typeReadable check
-- already passed. Guard the width itself.
function XPerl_SafeSetWidthFromText(frame, textObject, padding, fallbackWidth)
	local width = textObject:GetStringWidth()
	if (XPerl_IsSecret(width)) then
		frame:SetWidth(fallbackWidth)
	else
		frame:SetWidth(width + (padding or 0))
	end
end

-- XPerl_HasAuraContainerNow()
-- Blizzard_AuraContainer is load-on-demand, so the one-shot probe at the top of
-- this file can run before it exists and freeze the flag false for the session.
-- Re-check on demand and load it ourselves.
function XPerl_HasAuraContainerNow()
	if (not C_XMLUtil or type(C_XMLUtil.GetTemplateInfo) ~= "function") then
		return false
	end
	if (C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") ~= nil) then
		XPerl_ForeverAPI.auraContainer = true
		return true
	end
	-- LoadAddOn is not safe to call in combat lockdown; try again once out.
	if (InCombatLockdown()) then
		return false
	end
	local loader = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	if (type(loader) == "function") then
		pcall(loader, "Blizzard_AuraContainer")
	end
	local present = C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") ~= nil
	XPerl_ForeverAPI.auraContainer = present
	return present
end

-- XPerl_AuraContainer_AddGroup(self, container, groupKey, filter, size, showSwipe, maxCount, layoutIndex)
-- Adds one aura group with X-Perl's button setup. A container can hold several
-- groups, laid out in layoutIndex order. maxCount defaults to 40.
function XPerl_AuraContainer_AddGroup(self, container, groupKey, filter, size, showSwipe, maxCount, layoutIndex)
	container:AddAuraGroup(groupKey, filter, {
		maxFrameCount = maxCount or 40,
		layout = {
			elementWidth = size,
			elementHeight = size,
			elementSpacing = 1,
			lineSpacing = 1,
			layoutIndex = layoutIndex or 1,
		},
		initializeFrame = function(button)
			XPerl_AuraContainer_InitButtonCommon(button, size, showSwipe)
		end,
	})
	-- Z-Perl Forever: optional hook XPerl_BuffContainerFilter(frame, container, groupKey, filter),
	-- called once for each new aura group before it is live (so it may be configured while secret).
	if (XPerl_BuffContainerFilter) then
		XPerl_BuffContainerFilter(self, container, groupKey, filter)
	end
end

-- XPerl_AuraContainer_Create(self, holderKey, name, groupKey, filter, size, lineSize, showSwipe, maxCount)
-- Builds a holder + AuraContainer pair; caller positions the holder. Every frame
-- goes through here so the five requirements that each silently break rendering
-- live in one place -- see CLAUDE.md pattern 15 before changing anything here.
function XPerl_AuraContainer_Create(self, holderKey, name, groupKey, filter, size, lineSize, showSwipe, maxCount)
	local level = self:GetFrameLevel() + 10
	local holder = self[holderKey]
	if (not holder) then
		holder = CreateFrame("Frame", nil, self, "DisableUntrustedLayoutScriptsTemplate")
		self[holderKey] = holder
	end
	holder:SetFrameLevel(level)
	holder:Show()

	local container = CreateFrame("AuraContainer", name, holder, "CustomAuraContainerTemplate,DisableUntrustedLayoutScriptsTemplate")
	container:ClearAllPoints()
	container:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	container:SetFrameLevel(level)
	container:SetSize(1, 1)
	container:SetUnit(self.partyid)
	XPerl_AuraContainer_AddGroup(self, container, groupKey, filter, size, showSwipe, maxCount, 1)
	if (container.SetFlowLayoutMaximumLineSize) then
		container:SetFlowLayoutMaximumLineSize(lineSize)
	end
	return container, holder
end

-- XPerl_AuraContainer_ShowPair(self, buffsEnabled, debuffsEnabled)
-- UpdateAllAuras() on every show: the container's own auto-refresh event list
-- does not include UNIT_AURA.
function XPerl_AuraContainer_ShowPair(self, buffsEnabled, debuffsEnabled)
	if (buffsEnabled) then
		self.buffContainer:Show()
		if (self.buffContainer.UpdateAllAuras) then
			self.buffContainer:UpdateAllAuras()
		end
	else
		self.buffContainer:Hide()
	end
	if (debuffsEnabled) then
		self.debuffContainer:Show()
		if (self.debuffContainer.UpdateAllAuras) then
			self.debuffContainer:UpdateAllAuras()
		end
	else
		self.debuffContainer:Hide()
	end
end

-- XPerl_AuraContainer_SafeToReconfigure()
-- An already-adopted group/button can reject reconfiguration while secret.
-- Creating one fresh is fine; touching a live one must defer.
function XPerl_AuraContainer_SafeToReconfigure()
	return not XPerl_AurasSecret()
end

-- XPerl_AuraContainer_SetCountdown(button, size)
-- X-Perl's own countdown can't run while aura times are secret, so the game draws
-- it instead through a duration text binding: whole seconds in X-Perl's yellow,
-- made fully transparent above the "Countdown Start" time by a step colour curve.
-- Returns false if the client lacks the API, so the caller can fall back.
-- (In a do block to keep the file's main chunk under Lua's 200-local limit.)
do
local countdownFormatter, countdownCurve, countdownCurveStart
function XPerl_AuraContainer_SetCountdown(button, size)
	if (not (button.SetDurationText and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum.DurationTextBindingProperty)) then
		return false
	end
	local start = XPerlDB.buffs.countdownStart or 20
	if (not countdownFormatter) then
		countdownFormatter = C_StringUtil.CreateNumericRuleFormatter()
		countdownFormatter:AddBreakpoint({threshold = 0, step = 1, rounding = Enum.NumericRuleFormatRounding.Down, format = "%d"})
	end
	if (countdownCurveStart ~= start) then
		countdownCurve = C_CurveUtil.CreateColorCurve()
		countdownCurve:SetType(Enum.LuaCurveType.Step)
		countdownCurve:AddPoint(0, CreateColor(1, 1, 0, 1))
		countdownCurve:AddPoint(start, CreateColor(1, 1, 0, 0))
		countdownCurveStart = start
	end
	local text = button.xperlCountdown
	if (not text) then
		text = button.cooldown:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		text:SetPoint("TOPLEFT", button)
		text:SetPoint("BOTTOMRIGHT", button, -1, 2)
		button.xperlCountdown = text
	end
	local file, _, flags = GameFontNormalHuge:GetFont()
	text:SetFont(file, floor(size * 0.62 + 0.5), flags)
	local property = Enum.DurationTextBindingProperty.RemainingDuration
	return (pcall(button.SetDurationText, button, text, {
		textFormat = {formatString = "{}", components = {{property = property, formatter = countdownFormatter}}},
		textColor = {curve = countdownCurve, property = property},
	}))
end
end

-- XPerl_AuraContainer_InitButtonCommon(button, size, showSwipe)
-- An aura button arrives blank: no icon texture, no cooldown. Skip creating them
-- and it still sizes, lays out and tooltips correctly while drawing nothing at
-- all. Per-aura detail stays Blizzard's to draw. CLAUDE.md pattern 15.
function XPerl_AuraContainer_InitButtonCommon(button, size, showSwipe)
	if (not button) then
		return
	end
	if (size) then
		button:SetSize(size, size)
	end
	if (not button.icon and button.SetIcon) then
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetAllPoints(button)
		button:SetIcon(button.icon)
	end
	-- X-Perl's debuff border (XPerl_DeBuffTemplate), coloured by dispel type. The
	-- game colours it by type name from Blizzard's debuff colours (the table
	-- X-Perl's own colours come from), so it works while secret; buffs get no
	-- border, as in the normal layout.
	if (not button.xperlBorder and button.AddDispelTypeTexture and Enum.CustomAuraButtonDispelTypeTextureStyle) then
		local border = button:CreateTexture(nil, "OVERLAY")
		border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
		border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
		border:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
		border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT")
		local ok = pcall(button.AddDispelTypeTexture, button, border, {
			style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
			showWhenHarmful = true,
			showWhenHelpful = false,
			showWithoutDispelType = true,
		})
		if (ok) then
			button.xperlBorder = border
		else
			border:Hide()
		end
	end
	if (not button.cooldown and button.SetDurationCooldown) then
		button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		button.cooldown:SetAllPoints(button)
		button.cooldown:SetFrameLevel(button:GetFrameLevel() + 1)
		button:SetDurationCooldown(button.cooldown)
	end
	if (button.cooldown) then
		if (button.cooldown.SetDrawEdge) then
			button.cooldown:SetDrawEdge(false)
		end
		if (button.cooldown.SetDrawSwipe) then
			button.cooldown:SetDrawSwipe(showSwipe and true or false)
		end
		-- Same countdown-text handling the classic buttons get in
		-- XPerl_GetBuffButton: without it every icon force-shows Blizzard's
		-- numbers whatever the option says, and OmniCC-style addons attach too.
		local bconf = XPerlDB and XPerlDB.buffs
		-- X-Perl's "Buff Countdown" option: its own-style countdown drawn by the game,
		-- or, if that isn't available, Blizzard's numbers styled like X-Perl's.
		local xperlCountdown = bconf and bconf.countdown and not bconf.blizzard and size
		local ownCountdown = xperlCountdown and XPerl_AuraContainer_SetCountdown(button, size)
		if (button.cooldown.SetHideCountdownNumbers) then
			button.cooldown:SetHideCountdownNumbers(ownCountdown or not (bconf and (bconf.blizzard or bconf.countdown)))
		end
		local text = xperlCountdown and not ownCountdown and button.cooldown.GetCountdownFontString and button.cooldown:GetCountdownFontString()
		if (text) then
			local file, _, flags = GameFontNormalHuge:GetFont()
			text:SetFont(file, floor(size * 0.62 + 0.5), flags)
			text:SetTextColor(1, 1, 0)
		end
		button.cooldown.noCooldownCount = not (bconf and bconf.omnicc) or nil
	end
end

-- XPerl_UnitFullName(unit)
-- Forever gives units a mandatory surname in UnitName's second return, joined
-- with a space as Blizzard displays it ("Ana Forever"). Always a space: the
-- player's own name arrives pre-combined, so it can't be used to detect which
-- convention is live. See CLAUDE.md pattern 14.
function XPerl_UnitFullName(unit)
	local n, s = UnitName(unit)
	-- On retail the second return is the server name: "Hide Server Names" drops it
	if (XPerlDB and XPerlDB.hideRealm) then
		return n
	end
	if (s and XPerl_CanAccess(s) and XPerl_CanAccess(n) and s ~= "") then
		return n.." "..s
	end
	return n
end
end -- Z-Perl Forever support block

-- The few helpers used throughout this file
local XPerl_CanAccess, XPerl_IsSecret = XPerl_CanAccess, XPerl_IsSecret
local ForeverAPI = XPerl_ForeverAPI
local colourCurves = { }	-- cached Blizzard colour curves and small colour tables
------------------------------------------------------------------------------

local UnitAuraWithBuffs
local LCD = IsVanillaClassic and ForeverAPI.combatLog and LibStub and LibStub("LibClassicDurations", true)
if LCD then
	LCD:Register("ZPerl")
	UnitAuraWithBuffs = LCD.UnitAuraWithBuffs
end
local HealComm = IsVanillaClassic and ForeverAPI.combatLog and LibStub and LibStub("LibHealComm-4.0", true)

-- Upvalues
local _G = _G
local abs = abs
local atan2 = math.atan2
local collectgarbage = collectgarbage
local cos = cos
local deg = math.deg
local error = error
local floor = floor
local format = format
local hooksecurefunc = hooksecurefunc
local ipairs = ipairs
local max = max
local min = min
local next = next
local pairs = pairs
local pcall = pcall
local print = print
local select = select
local setmetatable = setmetatable
local sin = sin
local string = string
local strmatch = strmatch
local strsub = strsub
local strupper = strupper
local tinsert = tinsert
local tonumber = tonumber
local tremove = tremove
local type = type
local unpack = unpack

local CheckInteractDistance = CheckInteractDistance
local CreateFrame = CreateFrame
local DebuffTypeColor = DebuffTypeColor or {
	none    = { r = 0.80, g = 0.00, b = 0.00 },
	Magic   = { r = 0.20, g = 0.60, b = 1.00 },
	Curse   = { r = 0.60, g = 0.00, b = 1.00 },
	Disease = { r = 0.60, g = 0.40, b = 0.00 },
	Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}
local GetAddOnCPUUsage = GetAddOnCPUUsage
local GetAddOnMemoryUsage = GetAddOnMemoryUsage
local GetCursorPosition = GetCursorPosition
local GetDifficultyColor = GetDifficultyColor or GetQuestDifficultyColor
local GetItemCount = GetItemCount
local GetItemInfo = GetItemInfo
local GetLocale = GetLocale
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local GetRaidTargetIndex = GetRaidTargetIndex
local GetReadyCheckStatus = GetReadyCheckStatus
local GetRealmName = GetRealmName
local GetRealZoneText = GetRealZoneText
local GetSpecialization = GetSpecialization
local GetSpellInfo = GetSpellInfo
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsAddOnLoaded = IsAddOnLoaded
local IsAltKeyDown = IsAltKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsInRaid = IsInRaid
local IsItemInRange = IsItemInRange
local IsShiftKeyDown = IsShiftKeyDown
local IsSpellInRange = IsSpellInRange
local SecureButton_GetUnit = SecureButton_GetUnit
local SetCursor = SetCursor
local SetPortraitTexture = SetPortraitTexture
local SetPortraitToTexture = SetPortraitToTexture
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local SpellCanTargetUnit = SpellCanTargetUnit
local SpellIsTargeting = SpellIsTargeting
local UnitAffectingCombat = UnitAffectingCombat
local UnitAlternatePowerInfo = UnitAlternatePowerInfo
local UnitAura = UnitAura
local UnitCanAssist = UnitCanAssist
local UnitCanAttack = UnitCanAttack
local UnitClass = UnitClass
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local UnitExists = UnitExists
local UnitFactionGroup = UnitFactionGroup
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGUID = UnitGUID
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid
local UnitInRange = UnitInRange
local UnitInVehicle = UnitInVehicle
local UnitIsAFK = UnitIsAFK
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsEnemy = UnitIsEnemy
local UnitIsFriend = UnitIsFriend
local UnitIsGhost = UnitIsGhost
local UnitIsPlayer = UnitIsPlayer
local UnitIsPVP = UnitIsPVP
local UnitIsTapDenied = UnitIsTapDenied
local UnitIsUnit = UnitIsUnit
local UnitIsVisible = UnitIsVisible
local UnitLevel = UnitLevel
local UnitName = UnitName
local UnitPlayerControlled = UnitPlayerControlled
local UnitPopup_ShowMenu = UnitPopup_ShowMenu
local UnitPopupMenus = UnitPopupMenus
local UnitPopupShown = UnitPopupShown
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitReaction = UnitReaction
local UnregisterUnitWatch = UnregisterUnitWatch
local UpdateAddOnCPUUsage = UpdateAddOnCPUUsage
local UpdateAddOnMemoryUsage = UpdateAddOnMemoryUsage

local BuffFrame = BuffFrame
local GameTooltip = GameTooltip
local Minimap = Minimap
local UIParent = UIParent

local ArcaneExclusions = XPerl_ArcaneExclusions

local largeNumTag = XPERL_LOC_LARGENUMTAG
local hugeNumTag = XPERL_LOC_HUGENUMTAG
local veryhugeNumTag = XPERL_LOC_VERYHUGENUMTAG

--[==[@debug@
local function d(...)
	ChatFrame1:AddMessage(format(...))
end
--@end-debug@]==]

-- Compact Raid frame manager
local c = _G.CompactRaidFrameManager
if c then
	c:SetFrameStrata("Medium")
end

------------------------------------------------------------------------------
-- Re-usable tables
local FreeTables = setmetatable({}, {__mode = "k"})
local requested, freed = 0, 0

function XPerl_GetReusableTable(...)
	requested = requested + 1
	for t in pairs(FreeTables) do
		FreeTables[t] = nil
		for i = 1, select("#", ...) do
			t[i] = select(i, ...)
		end
		return t
	end
	return {...}
end

function XPerl_FreeTable(t, deep)
	if (t) then
		if (type(t) ~= "table") then
			error("Usage: XPerl_FreeTable([table])")
		end
		if (FreeTables[t]) then
			error("XPerl_FreeTable - Table already freed")
		end

		freed = freed + 1

		FreeTables[t] = true
		for k, v in pairs(t) do
			if (deep and type(v) == "table") then
				XPerl_FreeTable(v, true)
			end
			t[k] = nil
		end
		--t[''] = 0
		--t[''] = nil
	end
end

function XPerl_TableStats()
	print(requested, freed)
	return requested, freed
end

--local new, del = XPerl_GetReusableTable, XPerl_FreeTable

local function rotate(angle)
	local A = cos(angle)
	local B = sin(angle)
	local ULx, ULy = -0.5 * A - -0.5 * B, -0.5 * B + -0.5 * A
	local LLx, LLy = -0.5 * A - 0.5 * B, -0.5 * B + 0.5 * A
	local URx, URy = 0.5 * A - -0.5 * B, 0.5 * B + -0.5 * A
	local LRx, LRy = 0.5 * A - 0.5 * B, 0.5 * B + 0.5 * A
	return ULx + 0.5, ULy + 0.5, LLx + 0.5, LLy + 0.5, URx + 0.5, URy + 0.5, LRx + 0.5, LRy + 0.5
end

-- meta table for string based colours. Allows for other mods changing class colours and things all working
XPerlColourTable = setmetatable({ }, {
	__index = function(self, class)
		if not class then
			return
		end
		local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[strupper(class or "")]
		if (c) then
			c = format("|c00%02X%02X%02X", 255 * c.r, 255 * c.g, 255 * c.b)
		else
			c = "|c00808080"
		end
		self[class] = c
		return c
	end
})

--XPerl_Percent = setmetatable({},
--	{__mode = "kv",
--	__index = function(self, i)
--		if (type(i) == "number" and i >= 0) then
--			self[i] = format(percD, i)
--			return self[i]
--		end
--		return ""
--	end
--	})
--local xpPercent = XPerl_Percent

XPerl_AnchorList = {"TOP", "LEFT", "BOTTOM", "RIGHT"}

local playerClass

-- We have a dummy do-nothing function here for classes that don't have range checking
-- The do-something function is setup after variables_loaded and we work out spell to use just once
function XPerl_UpdateSpellRange()
	return
end

--local SpiritRealm = (C_Spell and C_Spell.GetSpellInfo(235621)) and C_Spell.GetSpellInfo(235621).name or GetSpellInfo(235621)

-- DoRangeCheck
local function DoRangeCheck(unit, opt)
	local range
	if opt.PlusHealth then
		local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
		-- Z-Perl Forever: the health check needs maths, so it is skipped while the
		-- values are secret and the plain range check decides instead.
		if (XPerl_CanAccess(hp) and XPerl_CanAccess(hpMax)) then
			if (not ForeverAPI.healthPercent) then
				hp = UnitIsGhost(unit) and 1 or (UnitIsDead(unit) and 0 or hp)
			end
			-- Begin 4.3 divide by 0 work around.
			local percent
			if UnitIsDeadOrGhost(unit) or (hp == 0 and hpMax == 0) then -- Probably dead target
				percent = 0 -- So just automatically set percent to 0 and avoid division of 0/0 all together in this situation.
			elseif hp > 0 and hpMax == 0 then -- We have current HP but max hp failed.
				hpMax = hp -- Make max hp at least equal to current health
				percent = 1 -- 100% if they are alive with > 0 cur hp, since curhp = maxhp in this hack.
			else
				percent = hp / hpMax -- Everything is dandy, so just do it right way.
			end
			-- End divide by 0 work around
			if (percent > opt.HealthLowPoint) then
				range = 0
			end
		end
	end

	if opt.PlusDebuff and ((opt.PlusHealth and range == 0) or not opt.PlusHealth) then
		local name = XPerl_UnitAuraByIndex(unit, 1, "HARMFUL|RAID")
		if not name then
			range = 0
		elseif not XPerl_CanAccess(name) then
			-- A secret name still proves a curable debuff is there
			range = nil
		else
			if ArcaneExclusions[name] then
				-- It's one of the filtered debuffs, so we have to iterate thru all debuffs to see if anything is curable
				for i = 1, 40 do
					local name = XPerl_UnitAuraByIndex(unit, i, "HARMFUL|RAID")
					if not name then
						range = 0
						break
					elseif not XPerl_CanAccess(name) or not ArcaneExclusions[name] then
						range = nil
						break
					end
				end
			else
				range = nil -- Override's the health check, because there's a debuff on unit
			end
		end
	end

	if not range then
		if opt.interact then
			if opt.interact == 6 then -- 45y
				local checkedRange
				range, checkedRange = UnitInRange(unit)
				if not checkedRange then
					range = 1
				end
			elseif opt.interact == 5 then -- 40y
				local checkedRange
				range, checkedRange = UnitInRange(unit)
				if not checkedRange then
					range = 1
				end
			elseif opt.interact == 3 then -- 10y
				local checkedRange
				range, checkedRange = UnitInRange(unit)
				if not checkedRange then
					range = 1
				end
			elseif opt.interact == 2 then -- 20y
				local checkedRange
				range, checkedRange = UnitInRange(unit)
				if not checkedRange then
					range = 1
				end
			elseif opt.interact == 1 then -- 30y
				local checkedRange
				range, checkedRange = UnitInRange(unit)
				if not checkedRange then
					range = 1
				end
			end
			-- CheckInteractDistance
			-- 1 = Inspect = 28 yards (BCC = 28 yards) (Vanilla = 10 yards)
			-- 2 = Trade = 8 yards (BCC = 8 yards) (Vanilla = 11 yards)
			-- 3 = Duel = 7 yards (BCC = 7 yards) (Vanilla = 10 yards)
			-- 4 = Follow = 28 yards (BCC = 28 yards) (Vanilla = 28 yards)
			-- 5 = Pet-battle Duel = 7 yards (BCC = 7 yards) (Vanilla = 10 yards)
		elseif opt.spell or opt.spell2 then
			if UnitCanAssist("player", unit) and opt.spell then
				range = (C_Spell and C_Spell.IsSpellInRange) and C_Spell.IsSpellInRange(opt.spell, unit) or (IsSpellInRange and IsSpellInRange(opt.spell, unit))
			elseif UnitCanAttack("player", unit) and opt.spell2 then
				range = (C_Spell and C_Spell.IsSpellInRange) and C_Spell.IsSpellInRange(opt.spell2, unit) or (IsSpellInRange and IsSpellInRange(opt.spell2, unit))
			else
				-- Fallback (28y) (BCC = 28y) (Vanilla = 28 yards)
				range = not InCombatLockdown() and CheckInteractDistance(unit, 4) or 1
			end
		else
			range = 1
		end
	end

	-- Z-Perl Forever: a secret range result is returned as-is; the caller turns
	-- it into an alpha with XPerl_RangeAlpha instead of comparing it here.
	if (XPerl_IsSecret(range)) then
		return range, true
	end

	if range ~= 1 and range ~= true then
		return opt.FadeAmount
	end
end

-- XPerl_RangeAlpha(result, secret, inAlpha, outAlpha)
-- Converts a DoRangeCheck result into an alpha value without Lua comparisons
-- when the result is secret. inAlpha is used when in range, outAlpha when not.
function XPerl_RangeAlpha(result, secret, inAlpha, outAlpha)
	if (secret) then
		if (ForeverAPI.booleanCurves) then
			return C_CurveUtil.EvaluateColorValueFromBoolean(result, inAlpha, outAlpha)
		end
		return inAlpha
	end
	if (result) then
		return outAlpha
	end
	return inAlpha
end

-- XPerl_UpdateSpellRangeSecure(self, unit, isRaidFrame)
-- Restricted-client version of the range fader. Every alpha is produced by
-- XPerl_RangeAlpha and handed straight to SetAlpha, so nothing here branches
-- on a unit value.
function XPerl_UpdateSpellRangeSecure(self, unit, isRaidFrame)
	local rf = conf.rangeFinder
	local base = conf.transparency.frame
	local mainA, nameA, statsA = base, 1, 1

	if (rf.enabled and (isRaidFrame or not rf.raidOnly)) then
		if (rf.Main.enabled) then
			local result, secret = DoRangeCheck(unit, rf.Main)
			mainA = XPerl_RangeAlpha(result, secret, base, base * rf.Main.FadeAmount)
		else
			if (rf.NameFrame.enabled) then
				local result, secret = DoRangeCheck(unit, rf.NameFrame)
				nameA = XPerl_RangeAlpha(result, secret, 1, rf.NameFrame.FadeAmount)
			end
			if (rf.StatsFrame.enabled) then
				local result, secret = DoRangeCheck(unit, rf.StatsFrame)
				statsA = XPerl_RangeAlpha(result, secret, 1, rf.StatsFrame.FadeAmount)
			end
		end
	end

	local connected = UnitIsConnected(unit)
	if (XPerl_CanAccess(connected) and not connected) then
		mainA = base * rf.Main.FadeAmount
		nameA, statsA = 1, 1
	end

	self:SetAlpha(mainA)
	if (self.nameFrame) then
		self.nameFrame:SetAlpha(nameA)
	end
	if (self.statsFrame) then
		self.statsFrame:SetAlpha(statsA)
	end
end

-- XPerl_UpdateSpellRange(self)
function XPerl_UpdateSpellRange2(self, overrideUnit, isRaidFrame)
	local unit
	if (overrideUnit) then
		unit = overrideUnit
	else
		unit = self:GetAttribute("unit")
		if (not unit) then
			unit = SecureButton_GetUnit(self)
		end
	end
	if (unit) then
		if (ForeverAPI.booleanCurves) then
			XPerl_UpdateSpellRangeSecure(self, unit, isRaidFrame)
			return
		end

		local rf = conf.rangeFinder
		local mainA, nameA, statsA -- Receives main, name and stats alpha levels

		if (rf.enabled and (isRaidFrame or not conf.rangeFinder.raidOnly)) then
			if (not UnitIsVisible(unit)) then
				if (rf.Main.enabled) then
					mainA = conf.transparency.frame * rf.Main.FadeAmount
				else
					if (rf.NameFrame.enabled) then
						nameA = rf.NameFrame.FadeAmount
					end
					if (rf.StatsFrame.enabled) then
						statsA = rf.StatsFrame.FadeAmount
					end
				end
			else
				if (rf.Main.enabled) then
					mainA = DoRangeCheck(unit, rf.Main)
					if (mainA) then
						mainA = mainA * conf.transparency.frame
					end
				end

				if (rf.NameFrame.enabled) then
					-- check for same item/spell. Saves doing the check multiple times
					if (rf.Main.enabled and (rf.Main.spell == rf.NameFrame.spell) and (rf.Main.item == rf.NameFrame.item) and (rf.Main.spell2 == rf.NameFrame.spell2) and (rf.Main.item2 == rf.NameFrame.item2) and (rf.Main.PlusHealth == rf.NameFrame.PlusHealth)) then
						if (mainA) then
							nameA = rf.NameFrame.FadeAmount
						end
					else
						nameA = DoRangeCheck(unit, rf.NameFrame)
						if (not nameA and mainA) then
							-- In range, but 'Whole' frame is out of range, so we need to override the fade for name
							nameA = 1
						end
					end
				end
				if (rf.StatsFrame.enabled) then
					-- check for same item/spell. Saves doing the check multiple times
					if (rf.Main.enabled and (rf.Main.spell == rf.StatsFrame.spell) and (rf.Main.item == rf.StatsFrame.item) and (rf.Main.spell2 == rf.StatsFrame.spell2) and (rf.Main.item2 == rf.StatsFrame.item2) and (rf.Main.PlusHealth == rf.StatsFrame.PlusHealth)) then
						if (mainA) then
							statsA = rf.StatsFrame.FadeAmount
						end
					else
						statsA = DoRangeCheck(unit, rf.StatsFrame)
						if (not statsA and mainA) then
							-- In range, but 'Whole' frame is out of range, so we need to override the fade for stats
							statsA = 1
						end
					end
				end
			end
		end

		local forcedMainA
		if (not mainA) then
			if (UnitIsConnected(unit)) then
				mainA = conf.transparency.frame
				forcedMainA = true
			else
				mainA = conf.transparency.frame * rf.Main.FadeAmount
				nameA, statsA = mainA
				forcedMainA = true
			end
		end

		self:SetAlpha(mainA)
		if (self.nameFrame) then
			if (nameA or forcedMainA) then
				self.nameFrame:SetAlpha(nameA or mainA)
			else
				self.nameFrame:SetAlpha(1)
			end
		end
		if (self.statsFrame) then
			if (nameA or forcedMainA) then
				self.statsFrame:SetAlpha(statsA or mainA)
			else
				self.statsFrame:SetAlpha(1)
			end
		end
	end
end

-- XPerl_StartupSpellRange()
function XPerl_StartupSpellRange()
	local _, playerClass = UnitClass("player")

	if (not XPerl_DefaultRangeSpells.ANY) then
		XPerl_DefaultRangeSpells.ANY = {}
	end

	local rf = conf.rangeFinder

	local function Setup1(self)
		if type(self.spell) ~= "string" then
			self.spell = XPerl_DefaultRangeSpells[playerClass] and XPerl_DefaultRangeSpells[playerClass].spell
			if type(self.item) ~= "string" then
				self.item = (XPerl_DefaultRangeSpells.ANY and XPerl_DefaultRangeSpells.ANY.item) or ""
			end
		end
		if type(self.spell2) ~= "string" then
			self.spell2 = XPerl_DefaultRangeSpells[playerClass] and XPerl_DefaultRangeSpells[playerClass].spell2
			if type(self.item2) ~= "string" then
				self.item2 = (XPerl_DefaultRangeSpells.ANY and XPerl_DefaultRangeSpells.ANY.item2) or ""
			end
		end

		if (not self.FadeAmount) then
			self.FadeAmount = 0.3
		end
		if (not self.HealthLowPoint) then
			self.HealthLowPoint = 0.7
		end
	end

	Setup1(rf.Main)
	Setup1(rf.NameFrame)
	Setup1(rf.StatsFrame)

	--if (rangeCheckSpell) then
		-- Put the real work function in place
	XPerl_UpdateSpellRange = XPerl_UpdateSpellRange2
	--else
	--	XPerl_UpdateSpellRange = function() end
	--end
end

XPerl_RegisterOptionChanger(XPerl_StartupSpellRange)

-- XPerl_StatsFrame_SetGrey
local function XPerl_StatsFrame_SetGrey(self, r, g, b)
	if (not r) then
		r, g, b = 0.5, 0.5, 0.5
	end

	self.healthBar:SetStatusBarColor(r, g, b, 1)
	self.healthBar.bg:SetVertexColor(r, g, b, 0.5)
	if (self.manaBar) then
		self.manaBar:SetStatusBarColor(r, g, b, 1)
		self.manaBar.bg:SetVertexColor(r, g, b, 0.5)
	end
	self.greyMana = true
end

-- XPerl_SetChildMembers - Recursive
-- This iterates a frame's child frames and regions and assigns member variables
-- based on the sub-set part of the child's name compared to the parent frame name
function XPerl_SetChildMembers(self)
	local n = self:GetName()
	if (n) then
		local match = "^"..n.."(.+)$"

		local function AddList(list)
			for k, v in pairs(list) do
				local t = v:GetName()
				if (t) then
					local found = strmatch(t, match)
					if (found) then
						--if (self[found] == v) then
						--	break		-- Already done
						--end
						self[found] = v
					end
				end
			end
		end

		AddList({self:GetRegions()})

		local c = {self:GetChildren()}
		AddList(c, true)

		for k, v in pairs(c) do
			if (v:GetName()) then
				XPerl_SetChildMembers(v)
			end
			v:SetScript("OnLoad", nil)
		end

		self:SetScript("OnLoad", nil)
	end
end

do
	local shortlist
	local list
	local media

	-- XPerl_RegisterSMBarTextures
	function XPerl_RegisterSMBarTextures()
		if (LibStub) then
			media = LibStub("LibSharedMedia-3.0", true)
		end

		shortlist = {
			{"Perl v2", "Interface\\AddOns\\XPerlForever\\Images\\XPerl_StatusBar"},
		}
		for i = 1, 9 do
			local name = i == 2 and "BantoBar" or "X-Perl "..i
			tinsert(shortlist, {name, "Interface\\AddOns\\XPerlForever\\Images\\XPerl_StatusBar"..(i + 1)})
		end

		if (media) then
			for k, v in pairs(shortlist) do
				media:Register("statusbar", v[1], v[2])
			end

			media:Register("border", "X-Perl Thin", "Interface\\AddOns\\XPerlForever\\Images\\XPerl_ThinEdge")
		end
	end

	-- XPerl_AllBarTextures
	function XPerl_AllBarTextures(short)
		if (not list) then
			if (short) then
				return shortlist
			end

			if (media) then
				list = { }
				local smlBars = media:List("statusbar")
				for k, v in pairs(smlBars) do
					tinsert(list, {v, media:Fetch("statusbar", v)})
				end
			else
				list = shortlist
			end
		end

		return list
	end
end

-- XPerl_GetBarTexture
function XPerl_GetBarTexture()
	local texture = conf and conf.bar and conf.bar.texture and conf.bar.texture[2]
	if texture then
		-- Preserve existing profiles created under the upstream folder name.
		texture = texture:gsub("Interface\\Add[oO]ns\\ZPerl", "Interface\\AddOns\\XPerlForever")
		conf.bar.texture[2] = texture
		return texture
	end
	return "Interface\\AddOns\\XPerlForever\\Images\\XPerl_StatusBar"
end

-- XPerl_StatsFrame_Setup
function XPerl_StatsFrame_Setup(self)
	self:OnBackdropLoaded()
	XPerl_SetChildMembers(self)
	self.SetGrey = XPerl_StatsFrame_SetGrey
end

-- XPerl_GetClassColour
local defaultColour = {r = 0.5, g = 0.5, b = 1}
function XPerl_GetClassColour(class)
	return (class and XPerl_CanAccess(class) and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]) or defaultColour
end

local hookedFrames = {}
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

---------------------------------
--Loading Function             --
---------------------------------

-- XPerl_BlizzFrameDisable
function XPerl_BlizzFrameDisable(self)
	if not self then
		return
	end

	UnregisterUnitWatch(self)

	self:UnregisterAllEvents()

	if self == PlayerFrame then
		if AlternatePowerBar then
			AlternatePowerBar:UnregisterAllEvents()
		end
	end

	self:SetMovable(true)
	self:SetUserPlaced(true)
	self:SetDontSavePosition(true)
	self:SetMovable(false)

	if not InCombatLockdown() then
		self:Hide()
		self:SetParent(hiddenParent)
	end

	if not hookedFrames[self] then
		local ignoreParent
		hooksecurefunc(self, "SetParent", function()
			if ignoreParent then
				return
			end
			ignoreParent = true
			self:SetParent(hiddenParent)
			ignoreParent = nil
		end)

		hookedFrames[self] = true
	end

	local health = self.healthBar or self.healthbar or self.HealthBar
	if health then
		health:UnregisterAllEvents()
	end

	local power = self.manabar or self.ManaBar
	if power then
		power:UnregisterAllEvents()
	end

	local spell = self.castBar or self.spellbar or self.CastingBarFrame
	if spell then
		spell:UnregisterAllEvents()
	end

	local powerBarAlt = self.powerBarAlt or self.PowerBarAlt
	if powerBarAlt then
		powerBarAlt:UnregisterAllEvents()
	end

	local buffFrame = self.BuffFrame
	if buffFrame then
		buffFrame:UnregisterAllEvents()
	end

	local debuffFrame = self.DebuffFrame
	if debuffFrame then
		debuffFrame:UnregisterAllEvents()
	end

	-- The player frame's class power bar also drives the Personal Resource Display's class
	-- resource (e.g. combo points, which other addons can show on the target nameplate).
	local classPowerBar = self.classPowerBar
	if classPowerBar and self ~= PlayerFrame then
		classPowerBar:UnregisterAllEvents()
	end

	local ccRemoverFrame = self.CcRemoverFrame
	if ccRemoverFrame then
		ccRemoverFrame:UnregisterAllEvents()
	end

	local petFrame = self.petFrame or self.PetFrame
	if petFrame then
		petFrame:UnregisterAllEvents()
	end
end

-- smoothColor
local function smoothColor(percentage)
	local r, g, b
	if (percentage < 0.5) then
		r = 1
		g = min(1, max(0, 2 * percentage))
		b = 0
	else
		g = 1
		r = min(1, max(0, 2 * (1 - percentage)))
		b = 0
	end

	return r, g, b
end

-- XPerl_HealthColourCurve
-- Z-Perl Forever: the same gradient as XPerl_SetSmoothBarColor, built as a
-- Blizzard ColorCurve so UnitHealthPercent can evaluate it on a secret percent.
function XPerl_HealthColourCurve()
	if (colourCurves.health or not ForeverAPI.colorCurves) then
		return colourCurves.health
	end
	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Linear)
	if (conf.colour.classic) then
		curve:AddPoint(0, CreateColor(1, 0, 0, 1))
		curve:AddPoint(0.5, CreateColor(1, 1, 0, 1))
		curve:AddPoint(1, CreateColor(0, 1, 0, 1))
	else
		local c = conf.colour.bar
		curve:AddPoint(0, CreateColor(c.healthEmpty.r, c.healthEmpty.g, c.healthEmpty.b, 1))
		curve:AddPoint(1, CreateColor(c.healthFull.r, c.healthFull.g, c.healthFull.b, 1))
	end
	colourCurves.health = curve
	return curve
end

-- XPerl_HealthColour(unit)
-- Colour object for the unit's current health, safe to pass to SetStatusBarColor
function XPerl_HealthColour(unit)
	local curve = XPerl_HealthColourCurve()
	if (curve and unit and ForeverAPI.healthPercent) then
		return UnitHealthPercent(unit, true, curve)
	end
end

---------------------------------
--Smooth Health Bar Color      --
---------------------------------
function XPerl_SetSmoothBarColor(self, percentage, partyid)
	if (self) then
		local r, g, b
		if (XPerl_IsSecret(percentage)) then
			-- Z-Perl Forever: Blizzard evaluates the gradient for us
			local color = XPerl_HealthColour(partyid or self.partyid)
			if (not color) then
				return
			end
			r, g, b = color.r, color.g, color.b
		elseif (conf.colour.classic) then
			r, g, b = smoothColor(percentage)
		else
			local c = conf.colour.bar
			r = min(1, max(0, c.healthEmpty.r + ((c.healthFull.r - c.healthEmpty.r) * percentage)))
			g = min(1, max(0, c.healthEmpty.g + ((c.healthFull.g - c.healthEmpty.g) * percentage)))
			b = min(1, max(0, c.healthEmpty.b + ((c.healthFull.b - c.healthEmpty.b) * percentage)))
		end

		self:SetStatusBarColor(r, g, b)

		if (self.bg) then
			self.bg:SetVertexColor(r, g, b, 0.25)
		end
	end
end

local barColours
function XPerl_ResetBarColourCache()
	colourCurves.health = nil
	colourCurves.class = nil
	barColours = setmetatable({ }, {
		__index = function(self, k)
			local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[k]
			if (c) then
				if (not conf.colour.classbarBright) then
					conf.colour.classbarBright = 1
				end
				self[k] = {
					r = max(0, min(1, c.r * conf.colour.classbarBright)),
					g = max(0, min(1, c.g * conf.colour.classbarBright)),
					b = max(0, min(1, c.b * conf.colour.classbarBright))
				}
				return self[k]
			end
		end
	})
end
XPerl_ResetBarColourCache()

-- XPerl_ClassColourCurve
-- Z-Perl Forever: step curve keyed by classID for when UnitClass() is secret
colourCurves.classIDs = {WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, MONK = 10, DRUID = 11, DEMONHUNTER = 12, EVOKER = 13}
function XPerl_ClassColourCurve()
	if (colourCurves.class or not ForeverAPI.colorCurves) then
		return colourCurves.class
	end
	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)
	for class, id in pairs(colourCurves.classIDs) do
		local c = barColours[class]
		if (c) then
			curve:AddPoint(id, CreateColor(c.r, c.g, c.b, 1))
		end
	end
	colourCurves.class = curve
	return curve
end

-- XPerl_ColourHealthBar
function XPerl_ColourHealthBar(self, healthPct, partyid)
	if (not partyid) then
		partyid = self.partyid
	end
	local bar = self.statsFrame.healthBar
	if (conf.colour.classbar) then
		local _, class, classID = UnitClass(partyid)
		if (class and XPerl_CanAccess(class)) then
			if (UnitIsPlayer(partyid)) then
				local c = barColours[class]
				if (c) then
					bar:SetStatusBarColor(c.r, c.g, c.b)
					if (bar.bg) then
						bar.bg:SetVertexColor(c.r, c.g, c.b, 0.25)
					end
					return
				end
			end
		elseif (XPerl_IsSecret(classID)) then
			-- Z-Perl Forever: the class is secret, let the curve pick the colour
			local curve = XPerl_ClassColourCurve()
			local c = curve and curve:Evaluate(classID)
			if (c) then
				bar:SetStatusBarColor(c.r, c.g, c.b)
				if (bar.bg) then
					bar.bg:SetVertexColor(c.r, c.g, c.b, 0.25)
				end
				return
			end
		end
	end

	XPerl_SetSmoothBarColor(bar, healthPct, partyid)
end
--local XPerl_ColourHealthBar = XPerl_ColourHealthBar

-- XPerl_SetValuedText
function XPerl_SetValuedText(self, unitHealth, unitHealthMax, suffix)
	if (XPerl_IsSecret(unitHealth) or XPerl_IsSecret(unitHealthMax)) then
		-- Z-Perl Forever: secret numbers go straight into the text sink.
		-- AbbreviateNumbers is Blizzard's own secret-aware short formatter.
		if (AbbreviateNumbers) then
			self:SetFormattedText("%s/%s%s", AbbreviateNumbers(unitHealth), AbbreviateNumbers(unitHealthMax), suffix or "")
		else
			self:SetFormattedText("%d/%d%s", unitHealth, unitHealthMax, suffix or "")
		end
		return
	end

	local locale = GetLocale()
	if locale == "zhCN" or locale == "zhTW" then
		if unitHealthMax >= 1000000000000 then
			if abs(unitHealth) >= 1000000000000 then
				self:SetFormattedText("%.2f%s/%.2f%s%s", unitHealth / 1000000000000, veryhugeNumTag, unitHealthMax / 1000000000000, veryhugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 1000000000 then
				self:SetFormattedText("%.1f%s/%.2f%s%s", unitHealth / 100000000, hugeNumTag, unitHealthMax / 1000000000000, veryhugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 100000000 then
				self:SetFormattedText("%.2f%s/%.2f%s%s", unitHealth / 100000000, hugeNumTag, unitHealthMax / 1000000000000, veryhugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 1000000 then
				self:SetFormattedText("%.1f%s/%.2f%s%s", unitHealth / 10000, hugeNumTag, unitHealthMax / 1000000000000, veryhugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 100000 then
				self:SetFormattedText("%.2f%s/%.2f%s%s", unitHealth / 10000, largeNumTag, unitHealthMax / 1000000000000, veryhugeNumTag, suffix or "")
			else
				self:SetFormattedText("%d/%.2f%s%s", unitHealth, unitHealthMax / 1000000000000, veryhugeNumTag, suffix or "")
			end
		elseif unitHealthMax >= 1000000000 then
			if abs(unitHealth) >= 1000000000 then
				self:SetFormattedText("%.1f%s/%.1f%s%s", unitHealth / 100000000, hugeNumTag, unitHealthMax / 100000000, hugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 100000000 then
				self:SetFormattedText("%.2f%s/%.1f%s%s", unitHealth / 100000000, hugeNumTag, unitHealthMax / 100000000, hugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 1000000 then
				self:SetFormattedText("%.1f%s/%.1f%s%s", unitHealth / 10000, largeNumTag, unitHealthMax / 100000000, hugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 100000 then
				self:SetFormattedText("%.2f%s/%.1f%s%s", unitHealth / 10000, largeNumTag, unitHealthMax / 100000000, hugeNumTag, suffix or "")
			else
				self:SetFormattedText("%d/%.2f%s%s", unitHealth, unitHealthMax / 100000000, hugeNumTag, suffix or "")
			end
		elseif unitHealthMax >= 100000000 then
			if abs(unitHealth) >= 100000000 then
				self:SetFormattedText("%.2f%s/%.2f%s%s", unitHealth / 100000000, hugeNumTag, unitHealthMax / 100000000, hugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 1000000 then
				self:SetFormattedText("%.1f%s/%.2f%s%s", unitHealth / 10000, largeNumTag, unitHealthMax / 100000000, hugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 100000 then
				self:SetFormattedText("%.2f%s/%.2f%s%s", unitHealth / 10000, largeNumTag, unitHealthMax / 100000000, hugeNumTag, suffix or "")
			else
				self:SetFormattedText("%d/%.2f%s%s", unitHealth, unitHealthMax / 100000000, hugeNumTag, suffix or "")
			end
		elseif unitHealthMax >= 1000000 then
			if abs(unitHealth) >= 1000000 then
				self:SetFormattedText("%.1f%s/%.1f%s%s", unitHealth / 10000, largeNumTag, unitHealthMax / 10000, largeNumTag, suffix or "")
			elseif abs(unitHealth) >= 100000 then
				self:SetFormattedText("%.2f%s/%.2f%s%s", unitHealth / 10000, largeNumTag, unitHealthMax / 10000, largeNumTag, suffix or "")
			else
				self:SetFormattedText("%d/%.1f%s%s", unitHealth, unitHealthMax / 10000, largeNumTag, suffix or "")
			end
		elseif unitHealthMax >= 100000 then
			if abs(unitHealth) >= 100000 then
				self:SetFormattedText("%.2f%s/%.2f%s%s", unitHealth / 10000, largeNumTag, unitHealthMax / 10000, largeNumTag, suffix or "")
			else
				self:SetFormattedText("%d/%.2f%s%s", unitHealth, unitHealthMax / 10000, largeNumTag, suffix or "")
			end
		else
			self:SetFormattedText("%d/%d%s", unitHealth, unitHealthMax, suffix or "")
		end
	else
		if unitHealthMax >= 1000000000 then
			if abs(unitHealth) >= 1000000000 then
				-- 1.23G/1.23G
				self:SetFormattedText("%.2f%s/%.2f%s%s", unitHealth / 1000000000, veryhugeNumTag, unitHealthMax / 1000000000, veryhugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 10000000 then
				-- 12.3M/1.23G
				self:SetFormattedText("%.1f%s/%.2f%s%s", unitHealth / 1000000, hugeNumTag, unitHealthMax / 1000000000, veryhugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 1000000 then
				-- 1.23M/1.23G
				self:SetFormattedText("%.2f%s/%.2f%s%s", unitHealth / 1000000, hugeNumTag, unitHealthMax / 1000000000, veryhugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 100000 then
				-- 123.4K/1.23G
				self:SetFormattedText("%.1f%s/%.1f%s%s", unitHealth / 1000, largeNumTag, unitHealthMax / 1000000000, veryhugeNumTag, suffix or "")
			else
				-- 12345/1.23G
				self:SetFormattedText("%d/%.2f%s%s", unitHealth, unitHealthMax / 1000000000, veryhugeNumTag, suffix or "")
			end
		elseif unitHealthMax >= 10000000 then
			if abs(unitHealth) >= 10000000 then
				-- 12.3M/12.3M
				self:SetFormattedText("%.1f%s/%.1f%s%s", unitHealth / 1000000, hugeNumTag, unitHealthMax / 1000000, hugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 1000000 then
				-- 1.23M/12.3M
				self:SetFormattedText("%.2f%s/%.1f%s%s", unitHealth / 1000000, hugeNumTag, unitHealthMax / 1000000, hugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 100000 then
				-- 123.4K/12.3M
				self:SetFormattedText("%.1f%s/%.1f%s%s", unitHealth / 1000, largeNumTag, unitHealthMax / 1000000, hugeNumTag, suffix or "")
			else
				-- 12345/12.3M
				self:SetFormattedText("%d/%.1f%s%s", unitHealth, unitHealthMax / 1000000, hugeNumTag, suffix or "")
			end
		elseif unitHealthMax >= 1000000 then
			if abs(unitHealth) >= 1000000 then
				-- 1.23M/1.23M
				self:SetFormattedText("%.2f%s/%.2f%s%s", unitHealth / 1000000, hugeNumTag, unitHealthMax / 1000000, hugeNumTag, suffix or "")
			elseif abs(unitHealth) >= 100000 then
				-- 123.4K/1.23M
				self:SetFormattedText("%.1f%s/%.2f%s%s", unitHealth / 1000, largeNumTag, unitHealthMax / 1000000, hugeNumTag, suffix or "")
			else
				-- 12345/1.23M
				self:SetFormattedText("%d/%.2f%s%s", unitHealth, unitHealthMax / 1000000, hugeNumTag, suffix or "")
			end
		elseif unitHealthMax >= 100000 then
			if abs(unitHealth) >= 100000 then
				-- 123.4K/123.4K
				self:SetFormattedText("%.1f%s/%.1f%s%s", unitHealth / 1000, largeNumTag, unitHealthMax / 1000, largeNumTag, suffix or "")
			else
				-- 12345/123.4K
				self:SetFormattedText("%d/%.1f%s%s", unitHealth, unitHealthMax / 1000, largeNumTag, suffix or "")
			end
		else
			-- 12345/12345
			self:SetFormattedText("%d/%d%s", unitHealth, unitHealthMax, suffix or "")
		end
	end
end
local SetValuedText = XPerl_SetValuedText

-- XPerl_SetHealthBarSecure
-- Z-Perl Forever: health values are secret, so Blizzard supplies the percent
-- (0..100) for the bar and the text, and the colour comes from the curve.
function XPerl_SetHealthBarSecure(self, bar, partyid, hp, Max)
	local hpPct = UnitHealthPercent(partyid, true, CurveConstants.ScaleTo100)

	bar:SetMinMaxValues(0, 100)
	if (conf.bar.inverse) then
		bar:SetValue(UnitHealthPercent(partyid, true, CurveConstants.ReverseTo100))
	else
		bar:SetValue(hpPct)
	end
	-- bar.tex is the StatusBar's own fill texture, so SetValue has already cropped
	-- it. The classic path clips it by hand from the percent, which cannot be done
	-- from a secret one; forcing it back to full here on every poll fought the
	-- widget's crop and jittered patterned bar textures, so it is left alone.

	XPerl_ColourHealthBar(self, UnitHealthPercent(partyid), partyid)

	if (bar.percent) then
		if (self.conf.healerMode and self.conf.healerMode.enable and self.conf.healerMode.type == 2 and UnitHealthMissing) then
			bar.percent:SetFormattedText("-%d", UnitHealthMissing(partyid, true))
		else
			bar.percent:SetFormattedText(percD or "%d%%", hpPct)
		end
	end

	if (bar.text) then
		if (self.conf.healerMode.enable and self.conf.healerMode.type ~= 2 and UnitHealthMissing) then
			bar.text:SetFormattedText("-%d", UnitHealthMissing(partyid, true))
		else
			SetValuedText(bar.text, hp, Max)
		end
	end
end

-- XPerl_SetHealthBar
function XPerl_SetHealthBar(self, hp, Max)
	local bar = self.statsFrame.healthBar

	if (ForeverAPI.healthPercent and self.partyid and (XPerl_IsSecret(hp) or XPerl_IsSecret(Max))) then
		XPerl_SetHealthBarSecure(self, bar, self.partyid, hp, Max)
		return
	end

	bar:SetMinMaxValues(0, Max)
	local percent
	if hp >= 1 and Max == 0 then -- For some dumb reason max HP is 0, normal HP is not, so lets use normal HP as max
		Max = hp
		percent = 1
	elseif hp == 0 and Max == 0 then -- Both are 0, so it's probably dead since usually current HP returns correctly when Max HP fails.
		percent = 0
	else
		percent = hp / Max
	end
	if percent > 1 then percent = 1 end -- percent only goes to 100
	if (conf.bar.inverse) then
		bar:SetValue(Max - hp)
		bar.tex:SetTexCoord(0, max(0,(1 - percent)), 0, 1)
	else
		bar:SetValue(hp)
		bar.tex:SetTexCoord(0, max(0, percent), 0, 1)
	end

	XPerl_ColourHealthBar(self, percent)
	if (bar.percent) then
		if (self.conf.healerMode and self.conf.healerMode.enable and self.conf.healerMode.type == 2) then
			--bar.percent:SetText(hp - Max)
			local health = hp - Max
			local locale = GetLocale()
			if locale == "zhCN" or locale == "zhTW" then
				if (abs(health) >= 1000000000000) then
					bar.percent:SetFormattedText("%.0f%s", health / 1000000000000, veryhugeNumTag)
				elseif (abs(health) >= 100000000) then
					bar.percent:SetFormattedText("%.0f%s", health / 100000000, hugeNumTag)
				elseif (abs(health) >= 1000000) then
					bar.percent:SetFormattedText("%.0f%s", health / 10000, largeNumTag)
				elseif (abs(health) >= 1000) then
					bar.percent:SetFormattedText("%.1f%s", health / 10000, largeNumTag)
				else
					bar.percent:SetFormattedText("%d", health)
				end
			else
				if (abs(health) >= 10000000000) then
					bar.percent:SetFormattedText("%.0f%s", health / 1000000000, veryhugeNumTag)
				elseif (abs(health) >= 1000000000) then
					bar.percent:SetFormattedText("%.1f%s", health / 1000000000, veryhugeNumTag)
				elseif (abs(health) >= 10000000) then
					bar.percent:SetFormattedText("%.0f%s", health / 1000000, hugeNumTag)
				elseif (abs(health) >= 1000000) then
					bar.percent:SetFormattedText("%.1f%s", health / 1000000, hugeNumTag)
				elseif (abs(health) >= 10000) then
					bar.percent:SetFormattedText("%.0f%s", health / 1000, largeNumTag)
				elseif (abs(health) >= 1000) then
					bar.percent:SetFormattedText("%.1f%s", health / 1000, largeNumTag)
				else
					bar.percent:SetFormattedText("%d", health)
				end
			end
		else
			local show = percent * 100
			if (show < 10) then
				bar.percent:SetFormattedText(perc1F or "%.1f%%", percent == 1 and 100 or show + 0.05)
			else
				bar.percent:SetFormattedText(percD or "%d%%", percent == 1 and 100 or show + 0.5)
			end
		end
	end

	if (bar.text) then
		local hbt = bar.text
		if (self.conf.healerMode.enable and self.conf.healerMode.type ~= 2) then
			local health = hp - Max
			if (self.conf.healerMode.type == 1) then
				SetValuedText(hbt, health, Max)
			else
				local locale = GetLocale()
				if locale == "zhCN" or locale == "zhTW" then
					if (abs(health) >= 1000000000000) then
						hbt:SetFormattedText("%.2f%s", health / 1000000000000, veryhugeNumTag)
					elseif (abs(health) >= 1000000000) then
						hbt:SetFormattedText("%.0f%s", health / 100000000, hugeNumTag)
					elseif (abs(health) >= 100000000) then
						hbt:SetFormattedText("%.1f%s", health / 100000000, hugeNumTag)
					elseif (abs(health) >= 1000000) then
						hbt:SetFormattedText("%.0f%s", health / 10000, largeNumTag)
					elseif (abs(health) >= 100000) then
						hbt:SetFormattedText("%.1f%s", health / 10000, largeNumTag)
					else
						hbt:SetFormattedText("%d", health)
					end
				else
					if (abs(health) >= 1000000000) then
						hbt:SetFormattedText("%.2f%s", health / 1000000000, veryhugeNumTag)
					elseif (abs(health) >= 10000000) then
						hbt:SetFormattedText("%.1f%s", health / 1000000, hugeNumTag)
					elseif (abs(health) >= 1000000) then
						hbt:SetFormattedText("%.2f%s", health / 1000000, hugeNumTag)
					elseif (abs(health) >= 100000) then
						hbt:SetFormattedText("%.1f%s", health / 1000, largeNumTag)
					else
						hbt:SetFormattedText("%d", health)
					end
				end
			end
		else
			SetValuedText(hbt, hp, Max)
		end
	end
	--XPerl_SetExpectedHealth(self)
end

---------------------------------
--Class Icon Location Functions--
---------------------------------
--local ClassPos = {
--	WARRIOR	= {0,    0.25,    0,	0.25},
--	MAGE	= {0.25, 0.5,     0,	0.25},
--	ROGUE	= {0.5,  0.75,    0,	0.25},
--	DRUID	= {0.75, 1,       0,	0.25},
--	HUNTER	= {0,    0.25,    0.25,	0.5},
--	SHAMAN	= {0.25, 0.5,     0.25,	0.5},
--	PRIEST	= {0.5,  0.75,    0.25,	0.5},
--	WARLOCK	= {0.75, 1,       0.25,	0.5},
--	PALADIN	= {0,    0.25,    0.5,	0.75},
--	none	= {0.25, 0.5, 0.5, 0.75},
--}
--function XPerl_ClassPos(class)
--	return unpack(ClassPos[class] or ClassPos.none)
--end

local CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS
function XPerl_ClassPos(unitClass)
	if (not XPerl_CanAccess(unitClass)) then
		return 0.25, 0.5, 0.5, 0.75
	end
	local b = CLASS_ICON_TCOORDS[unitClass]		-- Now using the Blizzard supplied from FrameXML/WorldStateFrame.lua
	if (b) then
		return unpack(b)
	end
	return 0.25, 0.5, 0.5, 0.75
end

-- XPerl_UnitClassFile(unit)
-- The unit's class file name ("DRUID"), also when UnitClassBase is secret
-- (enemies in arena): the arena opponent's spec is not secret, so it is used
-- when the unit is one of them. Returns nil if the class can't be known.
function XPerl_UnitClassFile(unit)
	local class = UnitClassBase(unit)
	if (XPerl_CanAccess(class)) then
		return class
	end
	for i = 1, 5 do
		local isOpponent = UnitIsUnit(unit, "arena"..i)
		if (XPerl_CanAccess(isOpponent) and isOpponent) then
			local specID = GetArenaOpponentSpec and GetArenaOpponentSpec(i)
			if (XPerl_CanAccess(specID) and specID and specID > 0) then
				return (select(6, GetSpecializationInfoByID(specID)))
			end
			return
		end
	end
end

-- XPerl_SetClassPortrait(texture, class)
-- Round class icon in a portrait texture (SetPortraitToTexture no longer exists).
-- Returns false for an unknown class.
function XPerl_SetClassPortrait(texture, class)
	local coords = class and CLASS_ICON_TCOORDS[class]
	if (not coords) then
		return false
	end
	texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
	texture:SetTexCoord(unpack(coords))
	return true
end

-- XPerl_Toggle
function XPerl_Toggle()
	if (XPerlLocked == 1) then
		XPerl_UnlockFrames()
	else
		XPerl_LockFrames()
	end
end

-- XPerl_UnlockFrames
function XPerl_UnlockFrames()
	XPerl_LoadOptions()

	XPerlLocked = 0

	if (XPerl_Party_Virtual) then
		XPerl_Party_Virtual(true)
	end

	if (XPerl_Player_Pet_Virtual) then
		XPerl_Player_Pet_Virtual(true)
	end

	if (XPerl_AggroAnchor) then
		XPerl_AggroAnchor:Enable()
	end

	if (XPerl_Options) then
		XPerl_Options:Show()
		XPerl_Options:SetAlpha(0)
		XPerl_Options.Fading = "in"
	end

	if (XPerl_RaidTitles) then
		XPerl_RaidTitles()
		if (XPerl_RaidPets_Titles) then
			XPerl_RaidPets_Titles()
		end
	end
end

-- XPerl_LockFrames
function XPerl_LockFrames()
	XPerlLocked = 1
	if (XPerl_Options) then
		XPerl_Options.Fading = "out"
	end

	if (XPerl_Party_Virtual) then
		XPerl_Party_Virtual()
	end

	if (XPerl_Player_Pet_Virtual) then
		XPerl_Player_Pet_Virtual()
	end

	if (XPerl_AggroAnchor) then
		XPerl_AggroAnchor:Disable()
	end

	if (XPerl_RaidTitles) then
		XPerl_RaidTitles()
		if (XPerl_RaidPets_Titles) then
			XPerl_RaidPets_Titles()
		end
	end

	XPerl_OptionActions()
end

-- Minimap Icon
function XPerl_MinimapButton_OnClick(self, button)
	GameTooltip:Hide()
	if (button == "LeftButton") then
		XPerl_Toggle()
	elseif (button == "RightButton") then
		XPerl_MinimapMenu(self)
	end
end

-- XPerl_MinimapMenu_OnLoad
function XPerl_MinimapMenu_OnLoad(self)
	local dropdown = MSA_DropDownMenu_Create(self:GetName().."_DropDown", self)
	dropdown.displayMode = "MENU"
	dropdown:SetAllPoints(self)
	MSA_DropDownMenu_Initialize(dropdown, XPerl_MinimapMenu_Initialize)
end

-- XPerl_MinimapMenu_Initialize
function XPerl_MinimapMenu_Initialize(self, level)
	local info

	if (level == 2) then
		return
	end

	info = MSA_DropDownMenu_CreateInfo()
	info.isTitle = 1
	info.text = XPerl_ProductName
	MSA_DropDownMenu_AddButton(info)

	info = MSA_DropDownMenu_CreateInfo()
	info.notCheckable = 1
	info.func = XPerl_Toggle
	info.text = XPERL_MINIMENU_OPTIONS
	MSA_DropDownMenu_AddButton(info)

	if (C_AddOns.IsAddOnLoaded("XPerlForever_RaidHelper")) then
		if (XPerl_Assists_Frame and not XPerl_Assists_Frame:IsShown()) then
			info = MSA_DropDownMenu_CreateInfo()
			info.notCheckable = 1
			info.text = XPERL_MINIMENU_ASSIST
			info.func = function()
					ZPerlConfigHelper.AssistsFrame = 1
					ZPerlConfigHelper.TargettingFrame = 1
					XPerl_SetFrameSides()
				end
			MSA_DropDownMenu_AddButton(info)
		end
	end

	if (C_AddOns.IsAddOnLoaded("XPerlForever_RaidMonitor")) then
		if (XPerl_RaidMonitor_Frame and not XPerl_RaidMonitor_Frame:IsShown()) then
			info = MSA_DropDownMenu_CreateInfo()
			info.notCheckable = 1
			info.text = XPERL_MINIMENU_CASTMON
			info.func = function()
				ZPerlRaidMonConfig.enabled = 1
				XPerl_RaidMonitor_Frame:SetFrameSizes()
			end
			MSA_DropDownMenu_AddButton(info)
		end
	end

	if (C_AddOns.IsAddOnLoaded("XPerlForever_RaidAdmin")) then
		if (XPerl_AdminFrame and not XPerl_AdminFrame:IsShown()) then
			info = MSA_DropDownMenu_CreateInfo()
			info.notCheckable = 1
			info.text = XPERL_MINIMENU_RAIDAD
			info.func = function() XPerl_AdminFrame:Show() end
			MSA_DropDownMenu_AddButton(info)
		end

		if (XPerl_Check and not XPerl_Check:IsShown()) then
			info = MSA_DropDownMenu_CreateInfo()
			info.notCheckable = 1
			info.text = XPERL_MINIMENU_ITEMCHK
			info.func = function() XPerl_Check:Show() end
			MSA_DropDownMenu_AddButton(info)
		end

		if (XPerl_RosterText and not XPerl_RosterText:IsShown()) then
			info = MSA_DropDownMenu_CreateInfo()
			info.notCheckable = 1
			info.text = XPERL_MINIMENU_ROSTERTEXT
			info.func = function() XPerl_RosterText:Show() end
			MSA_DropDownMenu_AddButton(info)
		end
	end
end

-- XPerl_MinimapMenu
function XPerl_MinimapMenu(self)
	if (not ZPerl_Minimap) then
		CreateFrame("Frame", "ZPerl_Minimap", nil, BackdropTemplateMixin and "BackdropTemplate")
		XPerl_MinimapMenu_OnLoad(ZPerl_Minimap)
	end

	MSA_ToggleDropDownMenu(1, nil, ZPerl_Minimap_DropDown, "cursor", 0, 0)
end

local xpModList = {"XPerlForever", "XPerlForever_Player", "XPerlForever_PlayerBuffs", "XPerlForever_PlayerPet", "XPerlForever_Target", "XPerlForever_TargetTarget", "XPerlForever_Party", "XPerlForever_PartyPet", "XPerlForever_ArcaneBar", "XPerlForever_RaidFrames", "XPerlForever_RaidHelper", "XPerlForever_RaidAdmin", "XPerlForever_RaidMonitor", "XPerlForever_RaidPets"}
local xpStartupMemory = {}

-- ZPerl_MinimapButton_Init
function ZPerl_MinimapButton_Init(self)
	--self.time = 0
	collectgarbage()
	UpdateAddOnMemoryUsage()
	local totalKB = 0
	for k, v in pairs(xpModList) do
		local usedKB = GetAddOnMemoryUsage(v)
		if ((usedKB or 0) > 0) then
			xpStartupMemory[v] = usedKB
		end
	end

	XPerl_MinimapButton_UpdatePosition(self)

	if (conf.minimap.enable) then
		self:Show()
	else
		self:Hide()
	end

	--self.UpdateTooltip = XPerl_MinimapButton_OnEnter

	ZPerl_MinimapButton_Init = nil
end

-- XPerl_MinimapButton_UpdatePosition
-- Free dragging (XPerlForever.xml OnDragStart/OnDragStop) replaced the old radius/angle
-- circle, which was sized for Era's minimap and misaligned on Forever.
function XPerl_MinimapButton_UpdatePosition(self)
	XPerl_RestorePosition(self)
end

-- DiffColour(diff, val)
local function DiffColour(val)
	local r, g, b, offset
	offset = max(0, min(0.5, 0.5 * min(1, val)))
	if (val < 0) then
		r = 0.5 + offset
		g = 0.5 - offset
		b = r
	else
		r = 0.5 + offset
		g = 0.5 - offset
		b = g
	end
	return format("|c00%02X%02X%02X", 255 * r, 255 * g, 255 * b)
end

-- XPerl_MinimapButton_OnEnter
function XPerl_MinimapButton_OnEnter(self)
	if (self.dragging) then
		return
	end

	GameTooltip:SetOwner(self or UIParent, "ANCHOR_LEFT")
	XPerl_MinimapButton_Details(GameTooltip)
end

-- XPerl_MinimapButton_Details
function XPerl_MinimapButton_Details(tt, ldb)
	-- Show a custom header for the minimap tooltip per user request
	tt:SetText("X-Perl Forever maintained by Ziliya", 1, 1, 1)
	tt:AddLine(XPERL_MINIMAP_HELP1)
	if (not ldb) then
		tt:AddLine(XPERL_MINIMAP_HELP2)
	end
	if UpdateAddOnMemoryUsage then
		if (IsAltKeyDown()) then
			tt:AddLine(XPERL_MINIMAP_HELP6)
		elseif (not IsShiftKeyDown()) then
			tt:AddLine(XPERL_MINIMAP_HELP5)
		end
	end
	if UpdateAddOnMemoryUsage and IsAltKeyDown() then
		local showDiff = IsShiftKeyDown()

		local allAddonsCPU = 0
		for i = 1, C_AddOns.GetNumAddOns() do
			allAddonsCPU = allAddonsCPU + GetAddOnCPUUsage(i)
		end

		-- Show X-Perl memory usage
		UpdateAddOnMemoryUsage()
		UpdateAddOnCPUUsage()
		local totalKB, totalCPU, diffKB, diff = 0, 0, 0
		local cpuText = ""
		for k, v in pairs(xpModList) do
			local usedKB = GetAddOnMemoryUsage(v)
			local usedCPU = GetAddOnCPUUsage(v)
			if ((usedKB or 0) > 0) then
				totalKB = totalKB + usedKB
				totalCPU = totalCPU + usedCPU

				if (allAddonsCPU > 0) then
					cpuText = format(" |c008080FF%.2f%%|r", 100 * (usedCPU / allAddonsCPU))
				end

				if (showDiff) then
					diff = usedKB - xpStartupMemory[v]
					diffKB = diffKB + diff
					tt:AddDoubleLine(format(" %s", v), format("%.1fkB (%s%.1fkB|r)%s", usedKB, DiffColour(diff / 1000), diff, cpuText), 1, 1, 0.5, 1, 1, 1)
				else
					tt:AddDoubleLine(format(" %s", v), format("%.1fkB%s", usedKB, cpuText), 1, 1, 0.5, 1, 1, 1)
				end
			end
		end

		if (showDiff) then
			local color = DiffColour(diffKB / 3000)

			tt:AddDoubleLine("Total", format("%.1fkB (%s%.1fkB|r)", totalKB, color, diffKB), 1, 1, 1, 1, 1, 1)
		else
			tt:AddDoubleLine("Total", format("%.1fkB", totalKB), 1, 1, 1, 1, 1, 1)
		end

		local usedKB = GetAddOnMemoryUsage("XPerlForever_Options")
		if ((usedKB or 0) > 0) then
			tt:AddDoubleLine(" ZPerl_Options", format("%.1fkB", usedKB), 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
		end

		if (totalCPU > 0) then
			tt:AddDoubleLine(" ZPerl CPU Usage Comparison", format("%.2f%%", 100 * (totalCPU / allAddonsCPU)), 0.5, 0.5, 1, 0.5, 0.5, 1)
		end
	end

	tt:Show()
	--tt.updateTooltip = 1
end

function XPerl_GetDisplayedPowerType(unitID)
	return UnitPowerType(unitID) or 0
end

local ManaColours = {
	[Enum.PowerType.Mana] = "mana",
	[Enum.PowerType.Rage] = "rage",
	[Enum.PowerType.Focus] = "focus",
	[Enum.PowerType.Energy] = "energy",
	[Enum.PowerType.Alternate] = "energy", -- used by some bosses, show it as energy bar
}

-- Forever may expose a usable power token while its numeric power type is
-- restricted or differs from the retail Enum table. Keep the classic X-Perl
-- colours available independently of saved-profile migration.
local PowerTokenColours = {
	MANA = "mana",
	RAGE = "rage",
	FOCUS = "focus",
	ENERGY = "energy",
}
local DefaultPowerColours = {
	mana = {r = 0, g = 0, b = 1},
	rage = {r = 1, g = 0, b = 0},
	focus = {r = 1, g = 0.5, b = 0.25},
	energy = {r = 1, g = 1, b = 0},
}

-- XPerl_SetManaBarType
function XPerl_SetManaBarType(self)
	local m = self.statsFrame.manaBar
	if (m and not self.statsFrame.greyMana) then
		local unit = self.partyid -- SecureButton_GetUnit(self)
		if not unit then
			self.targetmanatype = 0
			return
		end
		if (unit) then
			local p, powerToken = UnitPowerType(unit)
			self.targetmanatype = p
			local colourKey
			if XPerl_CanAccess(p) then
				colourKey = ManaColours[p]
			end
			if not colourKey and XPerl_CanAccess(powerToken) then
				colourKey = PowerTokenColours[powerToken]
			end
			local c = colourKey and ((conf.colour.bar and conf.colour.bar[colourKey]) or DefaultPowerColours[colourKey])
			-- Power types X-Perl has no colour for (Astral Power, Runic Power, ...) use Blizzard's colour
			if not c and PowerBarColor then
				if XPerl_CanAccess(powerToken) then
					c = PowerBarColor[powerToken]
				end
				if not c and XPerl_CanAccess(p) then
					c = PowerBarColor[p]
				end
			end
			if (c) then
				m:SetStatusBarColor(c.r, c.g, c.b, 1)
				m.bg:SetVertexColor(c.r, c.g, c.b, 0.25)
			end
		end
	end
end

-- XPerl_TooltipModiferPressed
function XPerl_TooltipModiferPressed(buffs)
	local mod, ic
	if (buffs) then
		if (not conf.tooltip.enableBuffs) then
			return
		end
		mod = conf.tooltip.buffModifier
		ic = conf.tooltip.buffHideInCombat
	else
		if (not conf.tooltip.enable) then
			return
		end
		mod = conf.tooltip.modifier
		ic = conf.tooltip.hideInCombat
	end

	if (mod == "alt") then
		mod = IsAltKeyDown()
	elseif (mod == "shift") then
		mod = IsShiftKeyDown()
	elseif (mod == "control") then
		mod = IsControlKeyDown()
	else
		mod = true
	end

	mod = mod and (not ic or not InCombatLockdown())

	return mod
end

-- XPerl_PlayerTip
function XPerl_PlayerTip(self, unitid)
	if (not unitid) then
		unitid = SecureButton_GetUnit(self)
	end

	if (not unitid or XPerlLocked == 0) then
		return
	end

	if (not XPerl_TooltipModiferPressed()) then
		return
	end

	if (SpellIsTargeting()) then
		if (SpellCanTargetUnit(unitid)) then
			SetCursor("CAST_CURSOR")
		else
			SetCursor("CAST_ERROR_CURSOR")
		end
	end

	GameTooltip_SetDefaultAnchor(GameTooltip, self)
	GameTooltip:SetUnit(unitid)
	-- Called from addon code, GameTooltip_UnitColor errors on secret unit values
	-- (enemies in combat); SetUnit has already coloured the name, so keep that
	local ok, r, g, b = pcall(GameTooltip_UnitColor, unitid)
	if (ok and r) then
		GameTooltipTextLeft1:SetTextColor(r, g, b)
	end
	GameTooltip:Show()

	if (XPerl_RaidTipExtra) then
		XPerl_RaidTipExtra(unitid)
	end

	XPerl_Highlight:TooltipInfo(UnitGUID(unitid))
end

-- XPerl_PlayerTipHide
function XPerl_PlayerTipHide()
	if (conf.tooltip.fading) then
		GameTooltip:FadeOut()
	else
		GameTooltip:Hide()
	end
end

-- XPerl_ColourFriendlyUnit
function XPerl_ColourFriendlyUnit(self, partyid)
	local color
	-- Z-Perl Forever: XPerl_SafeBool turns a secret boolean into the given default
	if (XPerl_SafeBool(UnitCanAttack("player", partyid), false) and XPerl_SafeBool(UnitIsEnemy("player", partyid), false)) then	-- For dueling
		color = conf.colour.reaction.enemy
	else
		if (conf.colour.class) then
			local _, class = UnitClass(partyid)
			color = XPerl_GetClassColour(class)
		else
			if (XPerl_SafeBool(UnitIsPVP(partyid), false)) then
				color = conf.colour.reaction.friend
			else
				color = conf.colour.reaction.none
			end
		end
	end

	self:SetTextColor(color.r, color.g, color.b, conf.transparency.text)
end

-- XPerl_SameFaction
-- Z-Perl Forever: faction names can be secret for creatures inside instances
function XPerl_SameFaction(argUnit)
	local mine, theirs = UnitFactionGroup("player"), UnitFactionGroup(argUnit)
	if (not XPerl_CanAccess(theirs)) then
		return false
	end
	return mine == theirs
end

-- XPerl_ReactionColour
function XPerl_ReactionColour(argUnit)
	-- Z-Perl Forever: every boolean here can be secret for indirect units and
	-- creatures inside instances; XPerl_SafeBool supplies a neutral default
	if (XPerl_SafeBool(UnitPlayerControlled(argUnit), false) or not XPerl_SafeBool(UnitIsVisible(argUnit), true)) then
		if (XPerl_SameFaction(argUnit)) then
			if (XPerl_SafeBool(UnitIsEnemy("player", argUnit), false)) then
				-- Dueling
				return conf.colour.reaction.enemy
			elseif (XPerl_SafeBool(UnitIsPVP(argUnit), false)) then
				return conf.colour.reaction.friend
			end
		else
			if (XPerl_SafeBool(UnitIsPVP(argUnit), false)) then
				if (UnitIsPVP("player")) then
					return conf.colour.reaction.enemy
				else
					return conf.colour.reaction.neutral
				end
			end
		end
	else
		if XPerl_SafeBool(UnitIsTapDenied(argUnit), false) and not XPerl_SafeBool(UnitIsFriend("player", argUnit), true) then
			return conf.colour.reaction.tapped
		else
			local reaction = UnitReaction(argUnit, "player")
			if (reaction and XPerl_CanAccess(reaction)) then
				if (reaction >= 5) then
					return conf.colour.reaction.friend
				elseif (reaction <= 2) then
					return conf.colour.reaction.enemy
				elseif (reaction == 3) then
					return conf.colour.reaction.unfriendly
				else
					return conf.colour.reaction.neutral
				end
			else
				if (XPerl_SameFaction(argUnit)) then
					return conf.colour.reaction.friend
				elseif (XPerl_SafeBool(UnitIsEnemy("player", argUnit), false)) then
					return conf.colour.reaction.enemy
				else
					return conf.colour.reaction.neutral
				end
			end
		end
	end

	return conf.colour.reaction.none
end

-- XPerl_SetUnitNameColor
function XPerl_SetUnitNameColor(self, unit)
	local color
	if (XPerl_SafeBool(UnitIsPlayer(unit), false) or not XPerl_SafeBool(UnitIsVisible(unit), true)) then -- Changed UnitPlayerControlled to UnitIsPlayer for 2.3.5
		-- 1.8.3 - Changed to override pvp name colours
		if (conf.colour.class) then
			local _, class = UnitClass(unit)
			color = XPerl_GetClassColour(class)
		else
			color = XPerl_ReactionColour(unit)
		end
	else
		if XPerl_SafeBool(UnitIsTapDenied(unit), false) and not XPerl_SafeBool(UnitIsFriend("player", unit), true) then
			color = conf.colour.reaction.tapped
		else
			color = XPerl_ReactionColour(unit)
		end
	end

	self:SetTextColor(color.r, color.g, color.b, conf.transparency.text)
end

-- XPerl_CombatFlashSet
function XPerl_CombatFlashSet(self, elapsed, argNew, argGreen)
	if (not conf.combatFlash) then
		self.PlayerFlash = nil
		return
	end

	if (self) then
		if (argNew) then
			self.PlayerFlash = 1.2 -- Old value: 1.5
			self.PlayerFlashGreen = argGreen
		else
			if (elapsed and self.PlayerFlash) then
				self.PlayerFlash = self.PlayerFlash - elapsed

				if (self.PlayerFlash <= 0) then
					self.PlayerFlash = 0
					self.PlayerFlashGreen = nil
				end
			else
				return
			end
		end

		return true
	end
end

-- XPerl_CombatFlashSetFrames
function XPerl_CombatFlashSetFrames(self)
	if (self.PlayerFlash) then
		local baseColour = self.forcedColour or conf.colour.border

		local r, g, b, a
		if (self.PlayerFlash > 0) then
			local flashOffsetColour = min(self.PlayerFlash, 1) / 2
			if (self.PlayerFlashGreen) then
				r = min(1, max(0, baseColour.r - flashOffsetColour))
				g = min(1, max(0, baseColour.g + flashOffsetColour))
			else
				r = min(1, max(0, baseColour.r + flashOffsetColour))
				g = min(1, max(0, baseColour.g - flashOffsetColour))
			end
			b = min(1, max(0, baseColour.b - flashOffsetColour))
			a = min(1, max(0, baseColour.a + flashOffsetColour))
		else
			r, g, b, a = baseColour.r, baseColour.g, baseColour.b, baseColour.a
			self.PlayerFlash = false
		end

		for i = 1, #self.FlashFrames do
			self.FlashFrames[i]:SetBackdropBorderColor(r, g, b, a)
		end
	end
end

local MagicCureTalentsClassic = {
	["PALADIN"] = 4987, -- Clense
}

local MagicCureTalents = {
	["DRUID"] = 4, -- Resto
	["PALADIN"] = 1, -- Holy
	["SHAMAN"] = 3, -- Resto
}

local function CanClassCureMagic(class)
	if (MagicCureTalents[class]) then
		return MagicCureTalentsClassic[class] and IsSpellKnown(MagicCureTalentsClassic[class])
	end
end

local getShow
function ZPerl_DebufHighlightInit()
	-- We also re-set the colours here so that we highlight best colour per class
	if (playerClass == "MAGE") then
		getShow = function(Curses)
			local show
			if (not conf.highlightDebuffs.class) then
				show = Curses.Magic or Curses.Curse or Curses.Poison or Curses.Disease
			end
			return Curses.Curse or show
		end
	elseif (playerClass == "DRUID") then
		getShow = function(Curses)
			local show
			if (not conf.highlightDebuffs.class) then
				show = Curses.Magic or Curses.Curse or Curses.Poison or Curses.Disease
			end
			local magic
			if (CanClassCureMagic(playerClass)) then
				magic = Curses.Magic
			end
			return Curses.Curse or Curses.Poison or magic or show
		end
	elseif (playerClass == "PRIEST") then
		getShow = function(Curses)
			local show
			if (not conf.highlightDebuffs.class) then
				show = Curses.Magic or Curses.Curse or Curses.Poison or Curses.Disease
			end
			return Curses.Magic or Curses.Disease or show
		end
	elseif (playerClass == "WARLOCK") then
		getShow = function(Curses)
			local show
			if (not conf.highlightDebuffs.class) then
				show = Curses.Magic or Curses.Curse or Curses.Poison or Curses.Disease
			end
			return Curses.Magic or show
		end
	elseif (playerClass == "PALADIN") then
		getShow = function(Curses)
			local show
			if (not conf.highlightDebuffs.class) then
				show = Curses.Magic or Curses.Curse or Curses.Poison or Curses.Disease
			end
			local magic
			if (CanClassCureMagic(playerClass)) then
				magic = Curses.Magic
			end
			return Curses.Poison or Curses.Disease or magic or show
		end
	elseif (playerClass == "SHAMAN") then
		getShow = function(Curses)
			local show
			if (not conf.highlightDebuffs.class) then
				show = Curses.Magic or Curses.Curse or Curses.Poison or Curses.Disease
			end
			local magic
			if (CanClassCureMagic(playerClass)) then
				magic = Curses.Magic
			end
			return Curses.Poison or Curses.Disease or magic or show
		end
	elseif (playerClass == "ROGUE") then
		getShow = function(Curses)
			local show
			if (not conf.highlightDebuffs.class) then
				show = Curses.Magic or Curses.Curse or Curses.Poison or Curses.Disease
			end
			return Curses.Poison or show
		end
	else
		getShow = function(Curses)
			return Curses.Magic or Curses.Curse or Curses.Poison or Curses.Disease
		end
	end

	ZPerl_DebufHighlightInit = nil
end

local bgDef = {
	bgFile = "Interface\\AddOns\\XPerlForever\\Images\\XPerl_FrameBack",
	edgeFile = "",
	tile = true,
	tileSize = 32,
	edgeSize = 16,
	insets = {left = 2, right = 2, top = 2, bottom = 2}
}
local normalEdge = "Interface\\Tooltips\\UI-Tooltip-Border"
local curseEdge = "Interface\\AddOns\\XPerlForever\\Images\\XPerl_Curse"

-- XPerl_CheckDebuffs
--local Curses = setmetatable({ }, {__mode = "k"})	-- 2.2.6 - Now re-using static table to save garbage memory creation
local Curses = { }
function XPerl_CheckDebuffs(self, unit, resetBorders)
	if not self.FlashFrames then
		return
	end

	local high = conf.highlightDebuffs.enable or (self == XPerl_Target and conf.target.highlightDebuffs.enable) or (self == XPerl_Focus and conf.focus.highlightDebuffs.enable)

	if resetBorders or not high or not getShow then
		-- Reset the frame edges back to normal in case they changed options while debuffed.
		self.forcedColour = nil
		bgDef.edgeFile = self.edgeFile or normalEdge
		bgDef.edgeSize = self.edgeSize or 16
		bgDef.insets.left = self.edgeInsets or 3
		bgDef.insets.top = self.edgeInsets or 3
		bgDef.insets.right = self.edgeInsets or 3
		bgDef.insets.bottom = self.edgeInsets or 3
		--for i, f in pairs(self.FlashFrames) do
		for i = 1, #self.FlashFrames do
			local f = self.FlashFrames[i]
			f:SetBackdrop(bgDef)
			f:SetBackdropColor(conf.colour.frame.r, conf.colour.frame.g, conf.colour.frame.b, conf.colour.frame.a)
			f:SetBackdropBorderColor(conf.colour.border.r, conf.colour.border.g, conf.colour.border.b, conf.colour.border.a)
		end
		return
	end

	if not unit then
		unit = self:GetAttribute("unit")
		if not unit then
			return
		end
	end

	Curses.Magic, Curses.Curse, Curses.Poison, Curses.Disease = nil, nil, nil, nil

	local show
	local debuffCount = 0
	local _, unitClass = UnitClass(unit)

	for i = 1, 40 do
		local name, dispelName
		local _
		name, _, _, dispelName = XPerl_UnitAuraByIndex(unit, i, "HARMFUL")
		if not name then
			break
		end

		-- Z-Perl Forever: secret aura names/types cannot be looked up, skip them
		if dispelName and XPerl_CanAccess(dispelName) and XPerl_CanAccess(name) then
			local exclude = ArcaneExclusions[name]
			if not exclude or (type(exclude) == "table" and not exclude[unitClass]) then
				Curses[dispelName] = dispelName
				debuffCount = debuffCount + 1
			end
		end
	end

	if debuffCount > 0 then
		-- 2.2.6 - Very (very very) slight speed optimazation by having a function per class which is set at startup
		show = getShow(Curses)
	end

	local colour, borderColour
	if show then
		colour = DebuffTypeColor[show]
		colour.a = 1

		if conf.highlightDebuffs.border then
			borderColour = colour
		else
			borderColour = conf.colour.border
		end
	else
		colour = conf.colour.frame
		borderColour = conf.colour.border
	end

	if show and conf.highlightDebuffs.frame then
		self.forcedColour = borderColour
		bgDef.edgeFile = curseEdge
	else
		self.forcedColour = nil
		--bgDef.edgeFile = normalEdge

		bgDef.edgeFile = self.edgeFile or normalEdge
		bgDef.edgeSize = self.edgeSize or 16
		bgDef.insets.left = self.edgeInsets or 3
		bgDef.insets.top = self.edgeInsets or 3
		bgDef.insets.right = self.edgeInsets or 3
		bgDef.insets.bottom = self.edgeInsets or 3
	end

	--for i, f in pairs(self.FlashFrames) do
	for i = 1, #self.FlashFrames do
		local f = self.FlashFrames[i]
		if not conf.highlightDebuffs.frame then
			colour = conf.colour.frame
		end
		f:SetBackdrop(bgDef)
		f:SetBackdropColor(colour.r, colour.g, colour.b, colour.a)
		f:SetBackdropBorderColor(borderColour.r, borderColour.g, borderColour.b, borderColour.a)
	end
end

-- XPerl_GetSavePositionTable
function XPerl_GetSavePositionTable(create)
	if (not ZPerlConfigNew) then
		return
	end

	local name = UnitName("player")
	local realm = GetRealmName()

	if (not ZPerlConfigNew.savedPositions) then
		if (not create) then
			return
		end
		ZPerlConfigNew.savedPositions = {}
	end
	local c = ZPerlConfigNew.savedPositions
	if (not c[realm]) then
		if (not create) then
			return
		end
		c[realm] = {}
	end
	if (not c[realm][name]) then
		if (not create) then
			return
		end
		c[realm][name] = {}
	end
	local table = c[realm][name]

	return table
end


-- XPerl_SavePosition
function XPerl_SavePosition(self, onlyIfEmpty)
	local name = self:GetName()
	if (name) then
		local s = self:GetScale()
		local t = self:GetTop()
		local l = self:GetLeft()
		local h = self:IsResizable() and self:GetHeight()
		local w = self:IsResizable() and self:GetWidth()

		local table = XPerl_GetSavePositionTable(true)
		if (table) then
			if (not onlyIfEmpty or (onlyIfEmpty and not table[name])) then
				if (t and l) then
					if (not table[name]) then
						table[name] = {}
					end
					table[name].top = t * s
					table[name].left = l * s
					table[name].height = h
					table[name].width = w
				else
					table[name] = nil
				end
			else
				if (table[name] and not self:IsUserPlaced()) then
					XPerl_RestorePosition(self)
				end
			end
		end
	end
end

-- XPerl_RestorePosition
function XPerl_RestorePosition(self)
	-- These are protected calls when reached from a secure script context (the
	-- options panel's OnClick handlers): ADDON_ACTION_BLOCKED in combat.
	if (InCombatLockdown()) then
		return
	end
	if (ZPerlConfigNew.savedPositions) then
		local name = self:GetName()
		if (name) then
			local table = XPerl_GetSavePositionTable()
			if (table) then
				local pos = table[name]
				if (pos and pos.left and pos.top) then
					self:ClearAllPoints()
					self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.left / self:GetScale(), pos.top / self:GetScale())

					if (pos.height and pos.width) then
						if (self:IsResizable()) then
							self:SetHeight(pos.height)
							self:SetWidth(pos.width)
						else
							pos.height, pos.width = nil, nil
						end
					end

					self:SetUserPlaced(true)
				end
			end
		end
	end
end

-- XPerl_RestoreAllPositions
function XPerl_RestoreAllPositions()
	local table = XPerl_GetSavePositionTable()
	if table then
		for k, v in pairs(table) do
			if k == "XPerl_Runes" or k == "XPerl_RaidHelper_Frame" or k == "XPerl_RaidMonitor_Frame" or k == "XPerl_Check" or k == "XPerl_AdminFrame" or k == "XPerl_Assists_Frame" then
				-- Fix for a wrong name with versions 2.3.2 and 2.3.2a
				-- It was using XPerl_Frame instead of XPerl_MTList_Anchor
				-- and XPerl_RaidMonitor_Frame instead of XPerl_RaidMonitor_Anchor
				-- And now a change to XPerl_Check to XPerl_CheckAnchor and XPerl_AdminFrame to XPerl_AdminFrameAnchor
				table[k] = nil
			elseif k == "XPerl_Options" or k == "XPerl_OptionsAnchor" then
				-- Noop
			else
				local frame = _G[k]
				if frame then
					if v.left and v.top then
						frame:SetUserPlaced(false)
						frame:ClearAllPoints()
						frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", v.left / frame:GetScale(), v.top / frame:GetScale())
						if k == "XPerl_Assists_FrameAnchor" then
							if ZPerlConfigHelper then
								if ZPerlConfigHelper.sizeAssistsX and ZPerlConfigHelper.sizeAssistsY then
									XPerl_Assists_Frame:SetWidth(ZPerlConfigHelper.sizeAssistsX)
									XPerl_Assists_Frame:SetHeight(ZPerlConfigHelper.sizeAssistsY)
								end
								if ZPerlConfigHelper.sizeAssistsS then
									XPerl_Assists_Frame:SetScale(ZPerlConfigHelper.sizeAssistsS)
								end
							end
						else
							if v.height and v.width then
								if frame:IsResizable() then
									frame:SetHeight(v.height)
									frame:SetWidth(v.width)
								else
									v.height, v.width = nil, nil
								end
							end
						end
					end
				end
			end
		end
	end
end

local BuffExceptions
local DebuffExceptions
local SeasonalDebuffs
local RaidFrameIgnores
BuffExceptions = {
	PRIEST = {
		[XPerl_SpellName(774)] = true,					-- Rejuvenation
		[XPerl_SpellName(8936)] = true,				-- Regrowth
		--[XPerl_SpellName(33076)] = true,				-- Prayer of Mending
		--[XPerl_SpellName(81749)] = true,				-- Atonement
	},
	DRUID = {
		[XPerl_SpellName(139)] = true,					-- Renew
	},
	WARLOCK = {
		[XPerl_SpellName(20707)] = true,				-- Soulstone Resurrection
	},
	HUNTER = {
		[XPerl_SpellName(13165)] = true,				-- Aspect of the Hawk
		[XPerl_SpellName(5118)] = true,				-- Aspect of the Cheetah
		[XPerl_SpellName(13159)] = true,				-- Aspect of the Pack
		--[XPerl_SpellName(61648)] = true,				-- Aspect of the Beast
		--[XPerl_SpellName(13163)] = true,				-- Aspect of the Monkey
		[XPerl_SpellName(19506)] = true,				-- Trueshot Aura
		[XPerl_SpellName(5384)] = true,				-- Feign Death
	},
	ROGUE = {
		[XPerl_SpellName(1784)] = true,				-- Stealth
		[XPerl_SpellName(1856)] = true,				-- Vanish
		[XPerl_SpellName(2983)] = true,				-- Sprint
		[XPerl_SpellName(13750)] = true,				-- Adrenaline Rush
		[XPerl_SpellName(13877)] = true,				-- Blade Flurry
	},
	PALADIN = {
		[XPerl_SpellName(20154)] = true,				-- Seal of Righteousness
		[XPerl_SpellName(20165)] = true,				-- Seal of Insight
		[XPerl_SpellName(20164)] = true,				-- Seal of Justice
		--[XPerl_SpellName(31801)] = true,				-- Seal of Truth
		--[XPerl_SpellName(20375)] = true,				-- Seal of Command
		--[XPerl_SpellName(20166)] = true,				-- Seal of Wisdom
		[XPerl_SpellName(20165)] = true,				-- Seal of Light
		--[XPerl_SpellName(53736)] = true,				-- Seal of Corruption
		--[XPerl_SpellName(31892)] = true,				-- Seal of Blood
		--[XPerl_SpellName(31801)] = true,				-- Seal of Vengeance
		[XPerl_SpellName(25780)] = true,				-- Righteous Fury
		[XPerl_SpellName(20925)] = true,				-- Holy Shield
		--[XPerl_SpellName(54428)] = true,				-- Divine Plea
	},
}
DebuffExceptions = {
	ALL = {
		[XPerl_SpellName(11196)] = true,				-- Recently Bandaged
	},
	PRIEST = {
		[XPerl_SpellName(6788)] = true,				-- Weakened Soul
	},
	PALADIN = {
		[XPerl_SpellName(25771)] = true				-- Forbearance
	}
}

SeasonalDebuffs = {
	[XPerl_SpellName(26004)] = true,					-- Mistletoe
	[XPerl_SpellName(26680)] = true,					-- Adored
	[XPerl_SpellName(26898)] = true,					-- Heartbroken
	--[XPerl_SpellName(64805)] = true,					-- Bested Darnassus
	--[XPerl_SpellName(64808)] = true,					-- Bested the Exodar
	--[XPerl_SpellName(64809)] = true,					-- Bested Gnomeregan
	--[XPerl_SpellName(64810)] = true,					-- Bested Ironforge
	--[XPerl_SpellName(64811)] = true,					-- Bested Orgrimmar
	--[XPerl_SpellName(64812)] = true,					-- Bested Sen'jin
	--[XPerl_SpellName(64813)] = true,					-- Bested Silvermoon City
	--[XPerl_SpellName(64814)] = true,					-- Bested Stormwind
	--[XPerl_SpellName(64815)] = true,					-- Bested Thunder Bluff
	--[XPerl_SpellName(64816)] = true,					-- Bested the Undercity
	--[XPerl_SpellName(36900)] = true,					-- Soul Split: Evil!
	--[XPerl_SpellName(36901)] = true,					-- Soul Split: Good
	--[XPerl_SpellName(36899)] = true,					-- Transporter Malfunction
	[XPerl_SpellName(24755)] = true,					-- Tricked or Treated
	--[XPerl_SpellName(69127)] = true,					-- Chill of the Throne
	--[XPerl_SpellName(69438)] = true,					-- Sample Satisfaction
}

RaidFrameIgnores = {
	[XPerl_SpellName(26013)] = true,					-- Deserter
	--[XPerl_SpellName(71041)] = true,					-- Dungeon Deserter
	--[XPerl_SpellName(71328)] = true,					-- Dungeon Cooldown
}

-- BuffException
-- Returns the UnitAura values, then the unfiltered index, then (Forever)
-- auraInstanceID and isFromPlayerOrPlayerPet.
local showInfo
local function BuffException(unit, index, filter, func, exceptions, raidFrames)
	local name, icon, applications, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId, auraInstanceID, isMine
	if filter ~= "HELPFUL|RAID" and filter ~= "HARMFUL|RAID" then
		-- Not filtered, just return it
		name, icon, applications, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId, auraInstanceID, isMine = func(unit, index, filter)
		return name, icon, applications, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId, index, auraInstanceID, isMine
	end

	name, icon, applications, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId, auraInstanceID, isMine = func(unit, index, filter)
	if icon then
		-- We need the index of the buff unfiltered later for tooltips
		-- Z-Perl Forever: only when the fields can be compared
		if (XPerl_CanAccess(name)) then
			for i = 1, 40 do
				local name, icon, applications, sourceUnit
				local _
				name, icon, applications, _, _, _, sourceUnit = func(unit, i, filter)
				if not name then
					break
				end
				if name == name and icon == icon and applications == applications and sourceUnit == sourceUnit then
					index = i
					break
				end
			end
		end

		return name, icon, applications, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId, index, auraInstanceID, isMine
	end

	-- See how many filtered buffs WoW has returned by default
	local normalBuffFilterCount = 0
	for i = 1, 40 do
		name = func(unit, i, filter == "HELPFUL" and "HELPFUL|RAID" or (filter == "HARMFUL" and "HARMFUL|RAID" or filter))
		if not name then
			normalBuffFilterCount = i - 1
			break
		end
	end

	-- Nothing found by default, so look for exceptions that we want to tack onto the end
	local unitClass
	local foundValid = 0
	local classExceptions = exceptions[playerClass]
	local allExceptions = exceptions.ALL
	for i = 1, 40 do
		name, icon, applications, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId, auraInstanceID, isMine = func(unit, i, filter)
		if not name then
			break
		end

		local good
		if (XPerl_CanAccess(name)) then
			if classExceptions then
				good = classExceptions[name]
			end
			if not good and allExceptions then
				good = allExceptions[name]
			end
		end

		if type(good) == "string" then
			if not unitClass then
				local _, class = UnitClass(unit)
				unitClass = class
			end
			if good ~= unitClass then
				good = nil
			end
		end

		if good then
			foundValid = foundValid + 1
			if foundValid + normalBuffFilterCount == index then
				return name, icon, applications, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId, i, auraInstanceID, isMine
			end
		end
	end
end

-- DebuffException
local function DebuffException(unit, start, filter, func, raidFrames)
	local name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellID, index, auraInstanceID, isMine
	local valid = 0
	for i = 1, 40 do
		name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellID, index, auraInstanceID, isMine = BuffException(unit, i, filter, func, DebuffExceptions, raidFrames)
		if not name then
			break
		end
		local readable = XPerl_CanAccess(name)
		if not readable or (not SeasonalDebuffs[name] and not (raidFrames and RaidFrameIgnores[name])) then
			valid = valid + 1
			if valid == start then
				return name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellID, index, auraInstanceID, isMine
			end
		end
	end
end

-- XPerl_AuraFunc
-- Z-Perl Forever: the aura reader for a unit. LibClassicDurations adds target
-- durations on Classic Era; the client API is used whenever it exists.
function XPerl_AuraFunc(unit)
	if (ForeverAPI.auras) then
		return XPerl_UnitAuraByIndex
	end
	if (unit == "target" and UnitAuraWithBuffs) then
		return UnitAuraWithBuffs
	end
	return XPerl_UnitAuraByIndex
end

-- XPerl_UnitBuff
function XPerl_UnitBuff(unit, index, filter, raidFrames)
	return BuffException(unit, index, filter, XPerl_AuraFunc(unit), BuffExceptions, raidFrames)
end

-- XPerl_UnitDebuff
function XPerl_UnitDebuff(unit, index, filter, raidFrames)
	if conf.buffs.ignoreSeasonal or raidFrames then
		return DebuffException(unit, index, filter, XPerl_UnitAuraByIndex, raidFrames)
	end
	return BuffException(unit, index, filter, XPerl_UnitAuraByIndex, DebuffExceptions, raidFrames)
end

-- XPerl_TooltipSetUnitBuff
-- Retreives the index of the actual unfiltered buff, and uses this on unfiltered tooltip call
function XPerl_TooltipSetUnitBuff(self, unit, ind, filter, raidFrames)
	local name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellID, index = BuffException(unit, ind, filter, XPerl_AuraFunc(unit), BuffExceptions, raidFrames)
	if name and index then
		if Utopia_SetUnitBuff then
			Utopia_SetUnitBuff(self, unit, index)
		else
			self:SetUnitBuff(unit, index)
		end
	end
end

-- XPerl_TooltipSetUnitDebuff
-- Retreives the index of the actual unfiltered debuff, and uses this on unfiltered tooltip call
function XPerl_TooltipSetUnitDebuff(self, unit, ind, filter, raidFrames)
	local name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellID, index = XPerl_UnitDebuff(unit, ind, filter, raidFrames)
	if name and index then
		if Utopia_SetUnitDebuff then
			Utopia_SetUnitDebuff(self, unit, index)
		else
			self:SetUnitDebuff(unit, index)
		end
	end
end

----------------------
-- Fading Bar Stuff --
----------------------
local fadeBars = {}
local freeFadeBars = {}
local tempDisableFadeBars

function XPerl_NoFadeBars(tempDisable)
	tempDisableFadeBars = tempDisable
end

-- CheckOnUpdate
local function CheckOnUpdate()
	if next(fadeBars) then
		XPerl_Globals:SetScript("OnUpdate", XPerl_BarUpdate)
	else
		XPerl_Globals:SetScript("OnUpdate", nil)
	end
end

-- XPerl_BarUpdate
--local speakerTimer = 0
--local speakerCycle = 0
function XPerl_BarUpdate(self, arg1)
	local did
	for k, v in pairs(fadeBars) do
		if k:IsShown() then
			v:SetAlpha(k.fadeAlpha)
			k.fadeAlpha = k.fadeAlpha - (arg1 / conf.bar.fadeTime)

			local r, g, b = v.tex:GetVertexColor()
			v:SetStatusBarColor(r, g, b)
		else
			-- Not shown, so end it
			k.fadeAlpha = 0
		end

		if k.fadeAlpha <= 0 then
			tinsert(freeFadeBars, v)
			fadeBars[k] = nil
			k.fadeAlpha = nil
			k.fadeBar = nil
			v:SetValue(0)
			v:Hide()
			v.tex = nil
			did = true
		end
	end

	if did then
		CheckOnUpdate()
	end
end

-- GetFreeFader
local function GetFreeFader(parent)
	local bar = freeFadeBars[1]
	if bar then
		tremove(freeFadeBars, 1)
		bar:SetParent(parent)
	else
		bar = CreateFrame("StatusBar", nil, parent)
	end

	if bar then
		fadeBars[parent] = bar
		CheckOnUpdate()

		bar.tex = parent.tex

		local tex = parent:GetStatusBarTexture()
		if tex:GetTexture() then
			bar:SetStatusBarTexture(tex:GetTexture())
			bar:GetStatusBarTexture():SetHorizTile(false)
			bar:GetStatusBarTexture():SetVertTile(false)
		end

		local r, g, b = bar.tex:GetVertexColor()
		bar:SetStatusBarColor(r, g, b)

		bar:SetFrameLevel(parent:GetFrameLevel())

		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", 0, 0)
		bar:SetPoint("BOTTOMRIGHT", 0, 0)
		bar:SetAlpha(1)

		return bar
	end
end

-- XPerl_StatusBarSetValue
function XPerl_StatusBarSetValue(self, val)
	if not tempDisableFadeBars and conf.bar.fading and self:GetName() then
		local min, max = self:GetMinMaxValues()
		local current = self:GetValue()

		-- Z-Perl Forever: no fade bar while the values are secret
		if XPerl_CanAccess(val) and XPerl_CanAccess(current) and XPerl_CanAccess(max) and val < current and val <= max and val >= min then
			local bar = fadeBars[self]

			if not bar then
				bar = GetFreeFader(self)
			end

			if bar then
				if not self.fadeAlpha then
					self.fadeAlpha = self:GetParent():GetAlpha()
					bar:SetValue(current)
				end

				bar:SetMinMaxValues(min, max)
				bar:SetAlpha(self.fadeAlpha)
				bar:Show()
			end
		end
	end

	XPerl_OldStatusBarSetValue(self, val)
end

-- XPerl_RegisterClickCastFrame
function XPerl_RegisterClickCastFrame(self)
	if not ClickCastFrames then
		ClickCastFrames = { }
	end
	ClickCastFrames[self] = true
end

function XPerl_UnregisterClickCastFrame(self)
	if ClickCastFrames then
		ClickCastFrames[self] = nil
	end
end

-- XPerl_SecureUnitButton_OnLoad
function XPerl_SecureUnitButton_OnLoad(self, unit, menufunc, m1, m2, toggledisabled)
	self:SetAttribute("*type1", "target")
	if toggledisabled then
		self:SetAttribute("type2", "menu")
	else
		self:SetAttribute("type2", "togglemenu")
	end

	if unit then
		self:SetAttribute("unit", unit)
	end

	XPerl_RegisterClickCastFrame(self)
end

-- XPerl_GetBuffButton
local buffIconCount = 0
function XPerl_GetBuffButton(self, buffnum, debuff, createIfAbsent, newID)
	debuff = debuff or 0
	local buffType, buffList		--, buffFrame

	if debuff == 1 then
		--buffFrame = self.debuffFrame
		buffType = "DeBuff"
		buffList = self.buffFrame.debuff
		if not buffList then
			self.buffFrame.debuff = { }
			buffList = self.buffFrame.debuff
		end
	else
		--buffFrame = self.buffFrame
		buffType = "Buff"
		buffList = self.buffFrame.buff
		if not buffList then
			self.buffFrame.buff = { }
			buffList = self.buffFrame.buff
		end
	end

	local button = buffList and buffList[buffnum]

	if not button and createIfAbsent then
		local setup = self.buffSetup
		local parent = self.buffFrame

		if debuff == 1 and setup.debuffParent then
			parent = self.debuffFrame
		end

		buffIconCount = buffIconCount + 1
		button = CreateFrame("Button", "XPerlBuff"..buffIconCount, parent, BackdropTemplateMixin and format("BackdropTemplate,XPerl_Cooldown_%sTemplate", buffType) or format("XPerl_Cooldown_%sTemplate", buffType))
		button:Hide()

		if setup.rightClickable then
			button:RegisterForClicks("RightButtonUp")
			--button:SetAttribute("type", "cancelaura")
			--button:SetAttribute("index", "number")
		end

		local size = self.conf.buffs.size
		if debuff == 1 then
			size = self.conf.debuffs.size or (size * (1 + (setup.debuffSizeMod * debuff)))
		end
		button:SetScale(size / 32)

		if setup.onCreate then
			setup.onCreate(button)
		end

		if debuff == 1 then
			--buffFrame.UpdateTooltip = setup.updateTooltipDebuff
			button.UpdateTooltip = setup.updateTooltipDebuff
			for k, v in pairs (setup.debuffScripts) do
				button:SetScript(k, v)
			end
		else
			--buffFrame.UpdateTooltip = setup.updateTooltipBuff
			button.UpdateTooltip = setup.updateTooltipBuff
			for k, v in pairs (setup.buffScripts) do
				button:SetScript(k, v)
			end
		end
		buffList[buffnum] = button

		button:ClearAllPoints()
		if buffnum == 1 then
			if debuff == 1 then
				if setup.debuffAnchor1 then
					setup.debuffAnchor1(self, button)
				end
			else
				if setup.buffAnchor1 then
					setup.buffAnchor1(self, button)
				end
			end
		else
			button:SetPoint("TOPLEFT", buffList[buffnum - 1], "TOPRIGHT", 1 + debuff, 0)
		end
	end
	-- TODO: Variable this
	button.cooldown:SetDrawEdge(false)
	-- Blizzard Cooldown Text Support
	if not conf.buffs.blizzard then
		button.cooldown:SetHideCountdownNumbers(true)
	else
		button.cooldown:SetHideCountdownNumbers(false)
	end
	-- OmniCC Support
	if not conf.buffs.omnicc then
		button.cooldown.noCooldownCount = true
	else
		button.cooldown.noCooldownCount = nil
	end
	button:SetID(newID or buffnum)

	return button
end

-- BuffCooldownDisplay
local function BuffCooldownDisplay(self)
	if self.countdown then
		local t = GetTime()
		if t > self.endTime - 1 then
			self.countdown:SetText(strsub(format("%.1f", max(0, self.endTime - t)), 2, 10))
			self.countdown:Show()
		elseif t > self.endTime - conf.buffs.countdownStart then
			self.countdown:SetText(max(0, floor(self.endTime - t)))
			self.countdown:Show()
		else
			self.countdown:Hide()
		end
	end
end

-- XPerl_CooldownFrame_SetTimer(self, start, duration, enable)
function XPerl_CooldownFrame_SetTimer(self, start, duration, enable, mine)
	if (XPerl_IsSecret(start) or XPerl_IsSecret(duration)) then
		-- Z-Perl Forever: callers use XPerl_CooldownFrame_SetAura for secret times
		self:Hide()
		return
	end
	if start > 0 and duration > 0 and enable > 0 then
		self:SetCooldown(start, duration)
		self.endTime = start + duration

		if conf.buffs.countdown and (mine or conf.buffs.countdownAny) then
			self:SetScript("OnUpdate", BuffCooldownDisplay)
		else
			self:SetScript("OnUpdate", nil)
			self.countdown:Hide()
		end

		self:Show()
	else
		self:Hide()
	end
end

-- AuraButtonOnShow
local function AuraButtonOnShow(self)
	if (not conf.buffs.blizzardCooldowns) then
		if (self.cooldown) then
			self.cooldown:Hide()
		end
		return
	end

	local cd = self.cooldown
	if (not cd) then
		cd = CreateFrame("Cooldown", nil, self, BackdropTemplateMixin and "BackdropTemplate,CooldownFrameTemplate" or "CooldownFrameTemplate")
		self.cooldown = cd
		if self.Icon then
			cd:SetAllPoints(self.Icon)
		else
			cd:SetAllPoints(self:GetName().."Icon")
		end
	end
	cd:SetReverse(true)
	--cd:SetDrawEdge(true) Blizzard removed this call from 5.0.4, commented it out to avoid lua error

	if (not cd.countdown) then
		cd.countdown = self.cooldown:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		if self.Icon then
			cd.countdown:SetPoint("TOPLEFT", self.Icon)
			cd.countdown:SetPoint("BOTTOMRIGHT", self.Icon, -1, 2)
		else
			cd.countdown:SetPoint("TOPLEFT", self:GetName().."Icon")
			cd.countdown:SetPoint("BOTTOMRIGHT", self:GetName().."Icon", -1, 2)
		end
		cd.countdown:SetTextColor(1, 1, 0)
	end

	local duration, expirationTime, sourceUnit, auraInstanceID
	local _
	_, _, _, _, duration, expirationTime, sourceUnit, _, _, _, auraInstanceID = XPerl_UnitAuraByIndex("player", self.xindex, self.xfilter)

	if duration and expirationTime then
		if (XPerl_IsSecret(duration) or XPerl_IsSecret(expirationTime)) then
			-- Z-Perl Forever: secret aura times, let Blizzard drive the swipe
			XPerl_CooldownFrame_SetAura(self.cooldown, "player", auraInstanceID)
		else
			local start = expirationTime - duration
			XPerl_CooldownFrame_SetTimer(self.cooldown, start, duration, 1, XPerl_CanAccess(sourceUnit) and sourceUnit == "player")
		end
	end
end

-- XPerl_AuraButton_UpdateInFo
-- Hook for Blizzard aura button setup to add cooldowns if we have them enabled
local function XPerl_AuraButton_UpdateInfo(button, buttonInfo, expanded)
	if not button then
		return
	end
	if (conf.buffs.blizzardCooldowns and BuffFrame:IsShown()) then
		button.xindex = buttonInfo.index
		button.xfilter = buttonInfo.filter
		button:SetScript("OnShow", AuraButtonOnShow)
		if (button:IsShown()) then
			AuraButtonOnShow(button)
		end
	end
end

-- XPerl_AuraButton_Update
-- Hook for Blizzard aura button setup to add cooldowns if we have them enabled
local function XPerl_AuraButton_Update(buttonName, index, filter)
	if (conf.buffs.blizzardCooldowns and BuffFrame:IsShown()) then
		local buffName = buttonName..index
		local button = _G[buffName]
		if (button) then
			button.xindex = index
			button.xfilter = filter
			button:SetScript("OnShow", AuraButtonOnShow)
			if (button:IsShown()) then
				AuraButtonOnShow(button)
			end
		end
	end
end

if AuraFrameMixin then
	-- TODO: Figure out what's changed here
	--hooksecurefunc(AuraFrameMixin, "Update", XPerl_AuraButton_UpdateInfo)
elseif AuraButton_Update then
	hooksecurefunc("AuraButton_Update", XPerl_AuraButton_Update)
end

-- XPerl_Unit_BuffSpacing
local function XPerl_Unit_BuffSpacing(self)
	local w = self.statsFrame:GetWidth()
	if (self.portraitFrame and self.portraitFrame:IsShown()) then
		w = w - 2 + self.portraitFrame:GetWidth()
	end
	if (self.levelFrame and self.levelFrame:IsShown()) then
		w = w - 2 + self.levelFrame:GetWidth()
	end
	if (not self.buffSpacing) then
		--self.buffSpacing = XPerl_GetReusableTable()
		self.buffSpacing = { }
	end
	self.buffSpacing.rowWidth = w

	local srs = 0
	if (not self.conf.buffs.above) then
		if (not self.statsFrame.manaBar or not self.statsFrame.manaBar:IsShown()) then
			srs = 10
		end

		if (self.creatureTypeFrame and self.creatureTypeFrame:IsShown()) then
			srs = srs + self.creatureTypeFrame:GetHeight() - 2
		end
	end

	if (srs > 0) then
		self.buffSpacing.smallRowHeight = srs
		self.buffSpacing.smallRowWidth = self.statsFrame:GetWidth()
	else
		self.buffSpacing.smallRowHeight = 0
		self.buffSpacing.smallRowWidth = w
	end
end

-- WieghAnchor(self, at)
local function WieghAnchor(self)
	if (not self.TOPLEFT or self.conf.flip ~= self.lastFlip or self.conf.buffs.above ~= self.lastAbove) then
		self.lastFlip = self.conf.flip
		self.lastAbove = self.conf.buffs.above

		local left, right, top, bottom
		if (self.conf.flip) then
			left, right = "RIGHT", "LEFT"
			self.SPACING = -1
		else
			left, right = "LEFT", "RIGHT"
			self.SPACING = 1
		end
		if (self.conf.buffs.above) then
			top, bottom = "BOTTOM", "TOP"
			self.VSPACING = 1
		else
			top, bottom = "TOP", "BOTTOM"
			self.VSPACING = -1
		end

		self.TOPLEFT = top..left
		self.TOPRIGHT = top..right
		self.BOTTOMLEFT = bottom..left
		self.BOTTOMRIGHT = bottom..right
	end
end

-- XPerl_Unit_BuffPositionsType
local function XPerl_Unit_BuffPositionsType(self, list, useSmallStart, buffSizeBase)
	local prevBuff, reusedSpace, hideFrom
	local firstOfRow = nil
	local prevRow, prevRowI = list[1], 1
	if (not prevRow) then
		return
	end
	local above = self.conf.buffs.above
	local colPoint, curRow, rowsHeight = 0, 1, 0
	local rowSize = (useSmallStart and self.buffSpacing.smallRowWidth) or self.buffSpacing.rowWidth
	local maxRows = self.conf.buffs.rows or 99
	local decrementMaxRowsIfLastIsBig -- Descriptive variable names ftw... If only upvalues took no actual memory space for the name... :(

	for i = 1, #list do
		if (curRow > maxRows) then
			hideFrom = i
			break
		end

		if (rowsHeight >= self.buffSpacing.smallRowHeight) then
			rowSize = self.buffSpacing.rowWidth
		end

		local buff = list[i]
		if (i > 1 and not buff:IsShown()) then
			break
		end

		local buffSize = (buff.big and (buffSizeBase * 2)) or buffSizeBase

		buff:ClearAllPoints()
		if (i == 1) then
			prevRow, prevRowI = buff, 1

			if (buff.big) then
				if (curRow == maxRows) then
					maxRows = maxRows + 1
					decrementMaxRowsIfLastIsBig = true
				end
			end

			if (self.prevBuff) then
				buff:SetPoint(self.TOPLEFT, self.prevBuff, self.BOTTOMLEFT, 0, self.VSPACING)
			else
				buff:SetPoint(self.TOPLEFT, 0, 0)
			end
		elseif (firstOfRow) then
			firstOfRow = nil
			if (not buff.big and prevRow.big and not reusedSpace) then
				-- Previous row starts with a big buff at start, so we try to use the odd space between rows
				-- for normal size buffs instead of starting a new row and having a buff width of wasted space.
				-- So we get:
				--	1123456
				--	11789AB
				--	CDEF
				-- Instead of:
				--	1123456
				--	11
				--	789ABCD
				--	EF

				local tempColPoint = (buffSizeBase * 2) + 1
				local j = prevRowI
				while (j < #list) do
					local temp = list[j + 1]
					if (temp and temp.big) then
						tempColPoint = tempColPoint + (buffSizeBase * 2) + 1
						j = j + 1
					else
						break
					end
				end

				if (tempColPoint < rowSize - buffSizeBase) then		--  and rowsHeight - buffSizeBase - 1 >= self.buffSpacing.smallRowHeight
					local prevRowBig, prevRowBigI = list[j], j
					colPoint = tempColPoint
					buff:SetPoint(self.BOTTOMLEFT, prevRowBig, self.BOTTOMRIGHT, self.SPACING, 0)
				else
					buff:SetPoint(self.TOPLEFT, prevRow, self.BOTTOMLEFT, 0, self.VSPACING)
					prevRow, prevRowI = buff, i
				end
				reusedSpace = true
			else
				buff:SetPoint(self.TOPLEFT, prevRow, self.BOTTOMLEFT, 0, self.VSPACING)
				prevRow, prevRowI = buff, i
				reusedSpace = nil

				if (buff.big) then
					if (curRow == maxRows) then
						maxRows = maxRows + 1
						decrementMaxRowsIfLastIsBig = true
					end
				end
			end
		else
			buff:SetPoint(self.TOPLEFT, prevBuff, self.TOPRIGHT, self.SPACING, 0)
		end

		colPoint = colPoint + buffSize + 1

		local nextBuff = list[i + 1]
		local nextBuffSize = buffSize
		if (nextBuff) then
			nextBuffSize = (nextBuff.big and (buffSizeBase * 2)) or buffSizeBase
		end

		if (self.conf.buffs.wrap and colPoint + nextBuffSize + 1 > rowSize) then
			if (buff.big and decrementMaxRowsIfLastIsBig) then
				decrementMaxRowsIfLastIsBig = nil
				maxRows = maxRows - 1
			end

			colPoint = 0
			curRow = curRow + 1
			if (prevRow.big) then
				rowsHeight = rowsHeight + (buffSize * 2) + 1
			else
				rowsHeight = rowsHeight + buffSize + 1
			end
			firstOfRow = true
		end

		prevBuff = buff
	end

	if (hideFrom) then
		for i = hideFrom,#list do
			list[i]:Hide()
		end
	end
	if (useSmallStart) then
		self.hideFrom1 = hideFrom
	else
		self.hideFrom2 = hideFrom
	end

	self.prevBuff = prevRow
end

-- XPerl_Unit_BuffPositions
function XPerl_Unit_BuffPositions(self, buffList1, buffList2, size1, size2)
	-- Z-Perl Forever: the layout key must be built from readable values only
	local canAttack = UnitCanAttack("player", self.partyid)
	local powerMax = UnitPowerMax(self.partyid)
	local optMix = format("%d%d%d%d%d%d%d", self.perlBuffs or 0, self.perlDebuffs or 0, self.perlBuffsMine or 0, self.perlDebuffsMine or 0, (XPerl_CanAccess(canAttack) and canAttack) and 1 or 0, (XPerl_CanAccess(powerMax) and powerMax > 0) and 1 or 0, (self.creatureTypeFrame and self.creatureTypeFrame:IsVisible()) and 1 or 0)
	if (optMix ~= self.buffOptMix) then
		WieghAnchor(self)

		local buffsFirst = self.buffFrame.buff == buffList1

		self.buffOptMix = optMix
		self.prevBuff = nil

		if (self.GetBuffSpacing) then
			self:GetBuffSpacing(self)
		else
			XPerl_Unit_BuffSpacing(self)
		end

		-- De-anchor first 2 because faction changes can mess up the order of things.
		if (buffList1 and buffList1[1]) then
			buffList1[1]:ClearAllPoints()
		end
		if (buffList2 and buffList2[1]) then
			buffList2[1]:ClearAllPoints()
		end

		if (buffList1) then
			XPerl_Unit_BuffPositionsType(self, buffList1, true, size1)
		end
		-- An empty first row takes no space: the second row starts at the top
		if (not (buffList1 and buffList1[1] and buffList1[1]:IsShown())) then
			self.prevBuff = nil
		end
		if (buffList2) then
			XPerl_Unit_BuffPositionsType(self, buffList2, false, size2)
		end

		if (buffList2) then
			-- If top row is disabled, then nudge the bottom row into it's place
			if (buffsFirst) then
				if (not self.conf.buffs.enable) then
					buffList2[1]:SetPoint(self.TOPLEFT, self.buffFrame, self.TOPLEFT, 0, self.VSPACING)
				end
			else
				if (not self.conf.debuffs.enable) then
					buffList2[1]:SetPoint(self.TOPLEFT, self.buffFrame, self.TOPLEFT, 0, self.VSPACING)
				end
			end
		end
	else
		if (self.hideFrom1 and buffList1) then
			for i = self.hideFrom1,#buffList1 do
				buffList1[i]:Hide()
			end
		end
		if (self.hideFrom2 and buffList2) then
			for i = self.hideFrom2,#buffList2 do
				buffList2[i]:Hide()
			end
		end
	end
end

-- XPerl_Unit_UpdateBuffs(self)
function XPerl_Unit_UpdateBuffs(self, maxBuffs, maxDebuffs, castableOnly, curableOnly)
	-- Z-Perl Forever: force a fresh XPerl_UnitAuraByIndex fetch for this pass --
	-- see XPerl_UnitAuraCache_Invalidate's own comment (support block, XPerlForever.lua)
	-- for why this can't just be "auraCacheList = nil" here.
	XPerl_UnitAuraCache_Invalidate()
	local buffs, debuffs, buffsMine, debuffsMine = 0, 0, 0, 0
	local partyid = self.partyid

	if (self.conf and UnitExists(partyid)) then
		if (not maxBuffs) then
			maxBuffs = 40
		end
		if (not maxDebuffs) then
			maxDebuffs = 40
		end
		local lastIcon = 0

		XPerl_GetBuffButton(self, 1, 0, true)
		XPerl_GetBuffButton(self, 1, 1, true)

		local canAttack = UnitCanAttack("player", partyid)
		canAttack = XPerl_CanAccess(canAttack) and canAttack
		local isFriendly = not canAttack
		-- "Key Enemy Buffs" (target/focus): on enemies keep only important or dispellable buffs
		local isFilteredOut = canAttack and self.conf.buffs.keyOnly and C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID

		if (self.conf.buffs.enable and maxBuffs and maxBuffs > 0) then
			local buffIconIndex = 1
			self.buffFrame:Show()
			-- Z-Perl Forever: sourceUnit can be secret, so "mine" is decided from
			-- a PLAYER filtered pass keyed by auraInstanceID (never secret)
			local mineMap
			for mine = 1, 2 do
				if (self.conf.buffs.onlyMine and mine == 2) then
					if (not canAttack) then
						break
					end
					-- else we'll ignore this option for enemy targets, because
					-- it's unlikey that we'll be buffing them
				end
				-- Two passes here now since 3.0.1, cos they did away with the GetPlayerBuff function
				-- in favor of all in UnitAura instead. We still want our big buffs first in the list,
				-- so we have to scan thru twice. I know what you're thinking: "Why do 2 passes when
				-- player's buffs are first anyway". Well, usually they are, but in the case of hunters
				-- and warlocks, the pet triggered buffs can be anywhere, but we still want those alongside
				-- our own buffs.
				for buffnum = 1, maxBuffs do
					local filter = castableOnly == 1 and "HELPFUL|RAID" or "HELPFUL"
					local name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellID, _, auraInstanceID, isMine = XPerl_UnitBuff(partyid, buffnum, filter)
					if (not name) then
						if (mine == 1) then
							maxBuffs = buffnum - 1
						end
						break
					end

					local isPlayer
					if (XPerl_CanAccess(unitCaster)) then
						if (self.conf.buffs.bigpet) then
							isPlayer = unitCaster == "player" or unitCaster == "pet" or unitCaster == "vehicle"
						else
							isPlayer = unitCaster == "player" or unitCaster == "vehicle"
						end
					elseif (auraInstanceID ~= nil and XPerl_CanAccess(auraInstanceID)) then
						if (not mineMap) then
							mineMap = XPerl_UnitAuraByInstanceMap(partyid, filter.."|PLAYER")
						end
						isPlayer = mineMap[auraInstanceID] or (self.conf.buffs.bigpet and XPerl_CanAccess(isMine) and isMine) or false
					else
						-- Everything about this aura is secret: it is shown, but not as "mine"
						isPlayer = false
					end
					local stealable = XPerl_CanAccess(canStealOrPurge) and canStealOrPurge

					-- Z-Perl Forever: optional hook XPerl_BuffFilter(frame, unit, spellID, auraInstanceID, isPlayer),
					-- called for buffs that would be shown; return true to hide the buff (no gap, not counted).
					local notKey
					if (isFilteredOut and auraInstanceID and XPerl_CanAccess(auraInstanceID)) then
						local notImportant = isFilteredOut(partyid, auraInstanceID, "HELPFUL|IMPORTANT")
						local notDispellable = isFilteredOut(partyid, auraInstanceID, "HELPFUL|DISPELLABLE")
						notKey = XPerl_CanAccess(notImportant) and XPerl_CanAccess(notDispellable) and notImportant and notDispellable
					end

					if (icon and not notKey and (((mine == 1) and (isPlayer or stealable)) or ((mine == 2) and not (isPlayer or stealable))) and not (XPerl_BuffFilter and XPerl_BuffFilter(self, partyid, spellID, auraInstanceID, isPlayer))) then
						local button = XPerl_GetBuffButton(self, buffIconIndex, 0, true, buffnum)
						button.filter = filter
						button:SetAlpha(1)

						buffs = buffs + 1

						button.icon:SetTexture(icon)
						if (XPerl_IsSecret(count)) then
							-- Z-Perl Forever: Blizzard formats the stack count
							button.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(partyid, auraInstanceID, 2))
							button.count:Show()
						elseif (count > 1) then
							button.count:SetText(count)
							button.count:Show()
						else
							button.count:Hide()
						end

						-- Handle cooldowns
						if (button.cooldown) then
							if (XPerl_IsSecret(duration) or XPerl_IsSecret(expirationTime)) then
								if (conf.buffs.cooldown and (isPlayer or conf.buffs.cooldownAny)) then
									XPerl_CooldownFrame_SetAura(button.cooldown, partyid, auraInstanceID)
								else
									button.cooldown:Hide()
								end
							elseif (duration and duration > 0 and expirationTime and expirationTime > 0 and conf.buffs.cooldown and (isPlayer or conf.buffs.cooldownAny)) then
								local start = expirationTime - duration
								XPerl_CooldownFrame_SetTimer(button.cooldown, start, duration, 1, isPlayer)
							else
								button.cooldown:Hide()
							end
						end

						button:Show()

						if (stealable) then --  and UnitCanAttack("player", partyid)
							if (not button.steal) then
								button.steal = CreateFrame("Frame", nil, button, BackdropTemplateMixin and "BackdropTemplate")
								button.steal:SetPoint("TOPLEFT", -2, 2)
								button.steal:SetPoint("BOTTOMRIGHT", 2, -2)

								button.steal.tex = button.steal:CreateTexture(nil, "OVERLAY")
								button.steal.tex:SetAllPoints()
								button.steal.tex:SetTexture("Interface\\AddOns\\XPerlForever\\Images\\StealMe")

								local g = button.steal.tex:CreateAnimationGroup()
								button.steal.anim = g
								local r = g:CreateAnimation("Rotation")
								g.rot = r

								r:SetDuration(4)
								r:SetDegrees(-360)
								r:SetOrigin("CENTER", 0, 0)

								g:SetLooping("REPEAT")
								g:Play()
							end

							button.steal:Show()
							button.steal.anim:Play()
							--button.steal:SetScript("OnUpdate", fixMeBlizzard) -- Workaround for Play not always working...
						else
							if (button.steal) then
								button.steal:Hide()
							end
						end

						lastIcon = buffIconIndex

						if ((self.conf.buffs.big and isPlayer) or (self.conf.buffs.bigStealable and stealable)) then
							buffsMine = buffsMine + 1
							button.big = true
							button:SetScale((self.conf.buffs.size * 2) / 32)
						else
							button.big = nil
							button:SetScale(self.conf.buffs.size / 32)
						end
						buffIconIndex = buffIconIndex + 1
					end
				end
			end
			for buffnum = lastIcon + 1, 40 do
				local button = self.buffFrame.buff and self.buffFrame.buff[buffnum]
				if (button) then
					button.expireTime = nil
					button:Hide()
				else
					break
				end
			end
		else
			self.buffFrame:Hide()
		end

		if (self.conf.debuffs.enable and maxDebuffs and maxDebuffs > 0) then
			local buffIconIndex = 1
			self.debuffFrame:Show()
			lastIcon = 0
			local mineMap
			-- "CC Debuffs Only" (focus): crowd control from anyone, so "only mine" doesn't apply
			local ccOnly = self.conf.debuffs.ccOnly
			for mine = 1, 2 do
				if (self.conf.debuffs.onlyMine and mine == 2 and not ccOnly) then
					if (canAttack) then
						break
					end
					-- Else we'll ignore this option for friendly targets, because it's unlikey
					-- (except for PW:Shield and HoProtection) that we'll be debuffing friendlies
				end

				for buffnum = 1, maxDebuffs do
					local filter = ccOnly and "HARMFUL|CROWD_CONTROL" or ((isFriendly and curableOnly == 1) and "HARMFUL|RAID" or "HARMFUL")
					local name, icon, count, debuffType, duration, expirationTime, unitCaster, canStealOrPurge, nameplateShowPersonal, spellID, _, auraInstanceID, isMine = XPerl_UnitDebuff(partyid, buffnum, filter)

					if (not name) then
						if (mine == 1) then
							maxDebuffs = buffnum - 1
						end
						break
					end

					local isPlayer
					if (XPerl_CanAccess(unitCaster)) then
						if (self.conf.buffs.bigpet) then
							isPlayer = unitCaster == "player" or unitCaster == "pet" or unitCaster == "vehicle"
						else
							isPlayer = unitCaster == "player"
						end
					elseif (auraInstanceID ~= nil and XPerl_CanAccess(auraInstanceID)) then
						if (not mineMap) then
							mineMap = XPerl_UnitAuraByInstanceMap(partyid, filter.."|PLAYER")
						end
						isPlayer = mineMap[auraInstanceID] or (self.conf.buffs.bigpet and XPerl_CanAccess(isMine) and isMine) or false
					else
						isPlayer = false
					end

					if (icon and (((mine == 1) and isPlayer) or ((mine == 2) and not isPlayer))) then
						local button = XPerl_GetBuffButton(self, buffIconIndex, 1, true, buffnum)
						button.filter = filter
						button:SetAlpha(1)

						debuffs = debuffs + 1

						button.icon:SetTexture(icon)
						if (XPerl_IsSecret(count)) then
							button.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(partyid, auraInstanceID, 2))
							button.count:Show()
						elseif ((count or 0) > 1) then
							button.count:SetText(count)
							button.count:Show()
						else
							button.count:Hide()
						end

						if (XPerl_IsSecret(debuffType) and C_UnitAuras.GetAuraDispelTypeColor and XPerl_DispelColourCurve()) then
							-- Z-Perl Forever: Blizzard resolves the dispel colour from the curve
							local c = C_UnitAuras.GetAuraDispelTypeColor(partyid, auraInstanceID, XPerl_DispelColourCurve())
							if (c) then
								button.border:SetVertexColor(c.r, c.g, c.b)
							end
						else
							local borderColor = DebuffTypeColor[(XPerl_CanAccess(debuffType) and debuffType) or "none"] or DebuffTypeColor.none
							button.border:SetVertexColor(borderColor.r, borderColor.g, borderColor.b)
						end

						-- Handle cooldowns
						if (button.cooldown) then
							if (XPerl_IsSecret(duration) or XPerl_IsSecret(expirationTime)) then
								if (conf.buffs.cooldown and (isPlayer or conf.buffs.cooldownAny)) then
									XPerl_CooldownFrame_SetAura(button.cooldown, partyid, auraInstanceID)
								else
									button.cooldown:Hide()
								end
							elseif (duration and duration > 0 and expirationTime and expirationTime > 0 and conf.buffs.cooldown and (isPlayer or conf.buffs.cooldownAny)) then
								local start = expirationTime - duration
								XPerl_CooldownFrame_SetTimer(button.cooldown, start, duration, 1, isPlayer)
							else
								button.cooldown:Hide()
							end
						end

						lastIcon = buffIconIndex
						button:Show()

						if (self.conf.debuffs.big and isPlayer) then
							debuffsMine = debuffsMine + 1
							button.big = true
							button:SetScale((self.conf.debuffs.size * 2) / 32)
						else
							button.big = nil
							button:SetScale(self.conf.debuffs.size / 32)
						end
						buffIconIndex = buffIconIndex + 1
					end
				end
			end
			for buffnum = lastIcon + 1, 40 do
				local button = self.buffFrame.debuff and self.buffFrame.debuff[buffnum]
				if (button) then
					button.expireTime = nil
					button:Hide()
				else
					break
				end
			end
		else
			self.debuffFrame:Hide()
		end
	end

	self.perlBuffs = buffs
	self.perlDebuffs = debuffs

	if (self.conf and self.conf.buffs.big) then
		self.perlBuffsMine = buffsMine
		self.perlDebuffsMine = debuffsMine
	else
		self.perlBuffsMine, self.perlDebuffsMine = nil, nil
	end
end

-- XPerl_SetBuffSize
function XPerl_SetBuffSize(self)
	local sizeBuff = self.conf.buffs.size
	local sizeDebuff = (self.conf.debuffs and self.conf.debuffs.size) or (sizeBuff * (1 + self.buffSetup.debuffSizeMod))

	local buff
	for i = 1, 40 do
		buff = self.buffFrame.buff and self.buffFrame.buff[i]
		if (buff) then
			buff:SetScale(sizeBuff / 32)
		end

		buff = self.buffFrame.debuff and self.buffFrame.debuff[i]
		if (buff) then
			buff:SetScale(sizeDebuff / 32)
		end

		buff = self.buffFrame.tempEnchant and self.buffFrame.tempEnchant[i]
		if (buff) then
			buff:SetScale(sizeBuff / 32)
		end
	end
end

-- XPerl_Update_RaidIcon
function XPerl_Update_RaidIcon(self, unit)
	local index = GetRaidTargetIndex(unit)
	if index then
		local mark
		if unit == "player" or unit == "vehicle" or unit == "target" or unit == "focus" then
			if self.texture then
				mark = self.texture
			else
				mark = self
			end
		else
			mark = self
		end
		SetRaidTargetIconTexture(mark, index)
		self:Show()
	else
		self:Hide()
	end
end

------------------------------------------------------------------------------
-- Flashing frames handler. Is hidden when there's nothing to do.
local FlashFrame = CreateFrame("Frame", "XPerl_FlashFrame", nil, BackdropTemplateMixin and "BackdropTemplate")
FlashFrame.list = { }

-- XPerl_FrameFlash_OnUpdate(self, elapsed)
local function XPerl_FrameFlash_OnUpdate(self, elapsed)
	for k, v in pairs(self.list) do
		if (k.frameFlash.out) then
			k.frameFlash.alpha = k.frameFlash.alpha - elapsed
			if (k.frameFlash.alpha < 0.2) then
				k.frameFlash.alpha = 0.2
				k.frameFlash.out = nil

				if (k.frameFlash.method == "out") then
					XPerl_FrameFlashStop(k)
				end
			end
		else
			k.frameFlash.alpha = k.frameFlash.alpha + elapsed
			if (k.frameFlash.alpha > 1) then
				k.frameFlash.alpha = 1
				k.frameFlash.out = true

				if (k.frameFlash.method == "in") then
					XPerl_FrameFlashStop(k)
				end
			end
		end

		if (k.frameFlash) then
			k:SetAlpha(k.frameFlash.alpha)
		end
	end
end

FlashFrame:SetScript("OnUpdate", XPerl_FrameFlash_OnUpdate)

-- XPerl_FrameFlash
function XPerl_FrameFlash(self)
	if (not FlashFrame.list[self]) then
		if (self.frameFlash) then
			error("X-Perl ["..self:GetName()..".frameFlash is set with no entry in FlashFrame.list]")
		end

		self.frameFlash = {out = true, alpha = 1, shown = self:IsShown()}

		FlashFrame.list[self] = true
		FlashFrame:Show()
		self:Show()
	end
end

-- XPerl_FrameIsFlashing(self)
function XPerl_FrameIsFlashing(self)
	return self.frameFlash		--FlashFrame.list[self]
end

-- XPerl_FrameFlashStop
function XPerl_FrameFlashStop(self, method)
	if (not self.frameFlash) then
		return
	end

	if (method) then
		self.frameFlash.method = method
		return
	end

	if (not self.frameFlash.shown) then
		self:Hide()
	end

	--XPerl_FreeTable(self.frameFlash)
	self.frameFlash = nil

	self:SetAlpha(1)

	FlashFrame.list[self] = nil

	if (not next(FlashFrame.list)) then
		FlashFrame:Hide()
	end
end

-- XPerl_ProtectedCall
function XPerl_ProtectedCall(func, self)
	if (func) then
		if (InCombatLockdown()) then
			XPerl_OutOfCombatQueue[func] = self == nil and false or self
		else
			func(self)
		end
	end
end

-- nextMember(last)
function XPerl_NextMember(_, last)
	if (last) then
		local raidCount = GetNumGroupMembers()
		if (raidCount > 0) then
			if (IsInRaid()) then
				local i = tonumber(strmatch(last, "^raid(%d+)"))
				if (i and i < raidCount) then
					i = i + 1
					local unitName, _, group, _, _, unitClass, zone, online, dead = GetRaidRosterInfo(i)
					return "raid"..i, unitName, unitClass, group, zone, online, dead
				end
			else
				local partyCount = GetNumSubgroupMembers()
				if (partyCount > 0) then
					local id
					if (last == "player") then
						id = "party1"
					else
						local i = tonumber(strmatch(last, "^party(%d+)"))
						if (i and i < partyCount) then
							i = i + 1
							id = "party"..i
						end
					end

					if (id) then
						local _, class = UnitClass(id)
						return id, UnitName(id), class, 1, "", UnitIsConnected(id), UnitIsDeadOrGhost(id)
					end
				end
			end
		end
	else
		if (IsInRaid()) then
			local unitName, _, group, _, _, unitClass, zone, online, dead = GetRaidRosterInfo(1)
			return "raid1", unitName, unitClass, group, zone, online, dead
		else
			local _, class = UnitClass("player")
			return "player", UnitName("player"), class, 1, GetRealZoneText(), 1, UnitIsDeadOrGhost("player")
		end
	end
end

-- XPerl_Unit_UpdatePortrait
function XPerl_Unit_UpdatePortrait(self, force)
	if (self.conf and self.conf.portrait) then
		-- Arena enemies: their 3D model doesn't load for addons, so use the 2D
		-- portrait, or their class icon if the game doesn't provide that either
		local _, instanceType = IsInInstance()
		if (instanceType == "arena" and XPerl_SafeBool(UnitCanAttack("player", self.partyid), false)) then
			local portrait = self.portraitFrame.portrait
			self.portraitFrame.portrait3D:Hide()
			self.portraitFrame.portrait3D.guid = nil
			portrait:SetTexture(nil)
			portrait:SetTexCoord(0, 1, 0, 1)
			SetPortraitTexture(portrait, self.partyid)
			-- Only when the game clearly gave no portrait (an unreadable answer
			-- usually still means it drew one)
			local texture = portrait:GetTexture()
			if (XPerl_CanAccess(texture) and not texture) then
				XPerl_SetClassPortrait(portrait, XPerl_UnitClassFile(self.partyid))
			end
			portrait:Show()
			return
		end
		local portrait = self.portraitFrame.portrait
		if not (self.conf.classPortrait and XPerl_SafeBool(UnitIsPlayer(self.partyid), false) and XPerl_SetClassPortrait(portrait, XPerl_UnitClassFile(self.partyid))) then
			portrait:SetTexCoord(0, 1, 0, 1)
			SetPortraitTexture(portrait, self.partyid)
		end
		-- If a player moves out of range for a 3D portrait, it will show their proper 2D one.
		-- NPC 3D portraits also frequently fail to render at all inside instances
		-- (dungeons/raids) on this client, leaving a blank spot instead of a model --
		-- use the already-populated 2D portrait for NPCs there instead of attempting
		-- 3D. Real players keep their animated portrait everywhere, since that case
		-- has been reliable.
		if (self.conf.portrait3D and UnitIsVisible(self.partyid) and (not IsInInstance() or UnitIsPlayer(self.partyid))) then
			self.portraitFrame.portrait:Hide()
			local guid = UnitGUID(self.partyid)
			-- A secret GUID cannot be compared, and that includes the *stored*
			-- one from a previous secret-identity target -- this crashed on a
			-- perfectly readable new guid because the stored one was secret.
			-- Guard both sides; always refresh if either is unreadable.
			if force or not XPerl_CanAccess(guid) or not XPerl_CanAccess(self.portraitFrame.portrait3D.guid) or guid ~= self.portraitFrame.portrait3D.guid or not self.portraitFrame.portrait3D:IsShown() then
				self.portraitFrame.portrait3D:Show()
				self.portraitFrame.portrait3D:ClearModel()
				self.portraitFrame.portrait3D:SetUnit(self.partyid)
				self.portraitFrame.portrait3D:SetPortraitZoom(1)
				self.portraitFrame.portrait3D.guid = guid
			end
		else
			self.portraitFrame.portrait:Show()
			self.portraitFrame.portrait3D:Hide()
		end
	end
end

-- XPerl_Unit_UpdateLevel
colourCurves.levelSecret = {r = 1, g = 1, b = 1}
function XPerl_Unit_UpdateLevel(self)
	local level = UnitLevel(self.partyid)
	-- Z-Perl Forever: creature levels can be secret inside instances
	local readable = XPerl_CanAccess(level)
	local color = readable and GetDifficultyColor(level) or colourCurves.levelSecret
	if (self.levelFrame) then
		self.levelFrame.text:SetTextColor(color.r,color.g,color.b)
		self.levelFrame.text:SetText(level)
	elseif (self.nameFrame.level) then
		if (readable and level == 0) then
			level = ""
		end
		self.nameFrame.level:SetTextColor(color.r,color.g,color.b)
		self.nameFrame.level:SetText(level)
	end
end

-- XPerl_Unit_GetHealth
--This function sucks, it needs reworking so it self corrects /0 problems here. But i haven't quite figured out how to approach it here yet. So i just fix stuff at sethealth functions.
function XPerl_Unit_GetHealth(self)
	local partyid = self.partyid
	local hp, hpMax = UnitHealth(partyid), UnitHealthMax(partyid)

	-- Z-Perl Forever: secret values are returned untouched for the widgets
	if (not XPerl_CanAccess(hp) or not XPerl_CanAccess(hpMax)) then
		return hp, hpMax, false
	end

	if (not ForeverAPI.healthPercent) then
		hp = UnitIsGhost(partyid) and 1 or (UnitIsDead(partyid) and 0 or hp)
	end

	if (hp > hpMax) then
		if (UnitIsGhost(partyid)) then
			hp = 1
		elseif UnitIsDead(partyid) then
			hp = 0
		else
			hp = hpMax
		end
	end

	return hp or 0, hpMax or 1, (hpMax == 100)
end

-- ZPerl_Unit_OnEnter
function ZPerl_Unit_OnEnter(self)
	XPerl_PlayerTip(self)
	if (self.highlight) then
		self.highlight:Select()
	end

	if (self.statsFrame and self.statsFrame.healthBar and self.statsFrame.healthBar.text and not self.statsFrame.healthBar.text:IsShown()) then
		self.hideValues = true
		self.statsFrame.healthBar.text:Show()
		if (self.statsFrame.manaBar) then
			self.statsFrame.manaBar.text:Show()
		end
		if (self.statsFrame.xpBar and self.statsFrame.xpBar:IsShown()) then
			self.statsFrame.xpBar.text:Show()
		end
		if (self.statsFrame.repBar and self.statsFrame.repBar:IsShown()) then
			self.statsFrame.repBar.text:Show()
		end
	end
end

-- ZPerl_Unit_OnLeave
function ZPerl_Unit_OnLeave(self)
	XPerl_PlayerTipHide()
	if (self.highlight) then
		self.highlight:Deselect()
	end

	if (self.hideValues) then
		self.hideValues = nil

		self.statsFrame.healthBar.text:Hide()
		if (self.statsFrame.manaBar) then
			self.statsFrame.manaBar.text:Hide()
		end
		if (self.statsFrame.xpBar and self.statsFrame.xpBar:IsShown()) then
			self.statsFrame.xpBar.text:Hide()
		end
		if (self.statsFrame.repBar and self.statsFrame.repBar:IsShown()) then
			self.statsFrame.repBar.text:Hide()
		end
	end
end

-- XPerl_Unit_SetBuffTooltip
function XPerl_Unit_SetBuffTooltip(self)
	if (conf and conf.tooltip.enableBuffs and XPerl_TooltipModiferPressed(true)) then
		if (not conf.tooltip.buffHideInCombat or not InCombatLockdown()) then
			local frame = self:GetParent():GetParent()
			local partyid = frame.partyid
			if (partyid) then
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 0, 0)
				XPerl_TooltipSetUnitBuff(GameTooltip, partyid, self:GetID(), self.filter)
			end
		end
	end
end

-- XPerl_Unit_SetDeBuffTooltip
function XPerl_Unit_SetDeBuffTooltip(self)
	if (conf and conf.tooltip.enableBuffs and XPerl_TooltipModiferPressed(true)) then
		if (not conf.tooltip.hideInCombat or not InCombatLockdown()) then
			local frame = self:GetParent():GetParent()
			local partyid = frame.partyid
			if (partyid) then
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 0, 0)
				XPerl_TooltipSetUnitDebuff(GameTooltip, partyid, self:GetID(), self.filter)
			end
		end
	end
end

-- XPerl_Unit_UpdateReadyState
function XPerl_Unit_UpdateReadyState(self)
	local status = conf.showReadyCheck and self.partyid and GetReadyCheckStatus(self.partyid)
	if status then
		self.statsFrame.ready:Show()
		if status == "ready" then
			self.statsFrame.ready.check:SetTexture(READY_CHECK_READY_TEXTURE)
		elseif status == "waiting" then
			self.statsFrame.ready.check:SetTexture(READY_CHECK_WAITING_TEXTURE)
		elseif status == "notready" then
			self.statsFrame.ready.check:SetTexture(READY_CHECK_NOT_READY_TEXTURE)
		else
			self.statsFrame.ready:Hide()
		end
	else
		self.statsFrame.ready:Hide()
	end
end

-- XPerl_SwitchAnchor(self, new)
-- Changes anchored corner without actually moving the frame

-- XPerl_SwitchAnchor
function XPerl_SwitchAnchor(self, New)
	if (not self:GetPoint(2)) then
		local a1, f, a2, x, y = self:GetPoint(1)

		if (a1 == a2 and New ~= a1) then
			local parent = self:GetParent()
			local newV = strmatch(New, "TOP") or strmatch(New, "BOTTOM")
			local newH = strmatch(New, "LEFT") or strmatch(New, "RIGHT")

			if (newV == "TOP") then
				y = -(768 - (self:GetTop() * self:GetEffectiveScale())) / self:GetEffectiveScale()
			elseif (newV == "BOTTOM") then
				y = self:GetBottom()
			else
				y = self:GetBottom() + self:GetHeight() / 2
			end

			if (newH == "LEFT") then
				x = self:GetLeft()
			elseif (newV == "RIGHT") then
				x = self:GetRight()
			else
				x = self:GetLeft() + self:GetWidth() / 2
			end

			self:ClearAllPoints()
			self:SetPoint(New, f, New, x, y)
		end
	end
end

---------------------------------
-- Scaling frame corner thingy --
---------------------------------
-- Seems a convoluted way of doing things, rather than just anchoring bottomleft, topright.. but
-- doing that introduces a really ugly latency between the anchor moving and the frame scaling because
-- the OnSizeChanged event is fired on the frame after the actual resize took place.

local scaleIndication

local function scaleMouseDown(self)

	GameTooltip:Hide()

	if (self.resizable and IsShiftKeyDown()) then
		self.sizing = true
	elseif (self.scalable) then
		self.scaling = true
	end

	if (not scaleIndication) then
		scaleIndication = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate")
		scaleIndication:SetWidth(100)
		scaleIndication:SetHeight(18)
		scaleIndication.text = scaleIndication:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		scaleIndication.text:SetAllPoints()
		scaleIndication.text:SetJustifyH("LEFT")
	end

	scaleIndication:Show()
	scaleIndication:ClearAllPoints()
	scaleIndication:SetPoint("LEFT", self, "RIGHT", 4, 0)

	if (self.scaling) then
		scaleIndication.text:SetFormattedText("%.1f%%", self.frame:GetScale() * 100)
	else
		scaleIndication.text:SetFormattedText("%dx%d", self.frame:GetWidth(), self.frame:GetHeight())
	end

	self.anchor:StartSizing(self.resizeTop and "TOPRIGHT")

	self.oldBdBorder = {self.frame:GetBackdropBorderColor()}
	self.frame:SetBackdropBorderColor(1, 1, 0.5, 1)
end

local function scaleMouseUp(self)
	self.anchor:StopMovingOrSizing()

	scaleIndication:Hide()

	XPerl_SavePosition(self.anchor)

	if self.resizeTop then
		XPerl_SwitchAnchor(self.anchor, "BOTTOMLEFT")
	end

	if self.scaling then
		if self.onScaleChanged then
			self:onScaleChanged(self.frame:GetScale())
		end
	end

	if self.sizing then
		if self.onSizeChanged then
			self:onSizeChanged(self.frame:GetWidth(), self.frame:GetHeight())
		end
	end

	if self.oldBdBorder then
		self.frame:SetBackdropBorderColor(unpack(self.oldBdBorder))
		self.oldBdBorder = nil
	end

	self.scaling = nil
	self.sizing = nil
end

local function scaleMouseChange(self)
	if (self.corner.sizing) then
		self.corner.frame:SetWidth(self:GetWidth() / self.corner.frame:GetScale())
		self.corner.frame:SetHeight(self:GetHeight() / self.corner.frame:GetScale())

		self.corner.startSize.w = self.corner.frame:GetWidth()
		self.corner.startSize.h = self.corner.frame:GetHeight()

		if (scaleIndication and scaleIndication:IsShown()) then
			scaleIndication.text:SetFormattedText("|c00FFFF80%d|c00808080x|c00FFFF80%d", self.corner.frame:GetWidth(), self.corner.frame:GetHeight())
		end

	elseif (self.corner.scaling) then
		local w = self:GetWidth()
		if (w) then
			self.corner.scaling = nil
			local ratio = self.corner.frame:GetWidth() / self.corner.frame:GetHeight()
			local s = min(self.corner.maxScale, max(self.corner.minScale, w / self.corner.startSize.w))	-- New Scale

			w = self.corner.startSize.w * s		-- Set height and width of anchor window to match ratio of actual
			if (self.corner.resizeTop) then
				XPerl_SwitchAnchor(self, "BOTTOMLEFT")
				local bottom, left = self:GetBottom(), self:GetLeft()
				self:SetWidth(w)
				self:SetHeight(w / ratio)
			else
				self:SetWidth(w)
				self:SetHeight(w / ratio)
			end

			if (scaleIndication and scaleIndication:IsShown()) then
				scaleIndication.text:SetFormattedText("%.1f%%", s * 100)
			end

			self.corner.frame:SetScale(s)
			self.corner.scaling = true
		end
	end
end

-- scaleMouseEnter
local function scaleMouseEnter(self)
	self.tex:SetVertexColor(1, 1, 1, 1)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if (self.scalable) then
		GameTooltip:SetText(XPERL_DRAGHINT1, nil, nil, nil, nil, true)
	end
	if (self.resizable) then
		GameTooltip:AddLine(XPERL_DRAGHINT2, nil, nil, nil, true)
	end
	GameTooltip:Show()
end

-- scaleMouseLeave
local function scaleMouseLeave(self)
	self.tex:SetVertexColor(1, 1, 1, 0.5)
	GameTooltip:Hide()
end

-- XPerl_RegisterScalableFrame
function XPerl_RegisterScalableFrame(self, anchorFrame, minScale, maxScale, resizeTop, resizable, scalable)
	if (scalable == nil) then
		scalable = true
	end

	if (not self.corner) then
		self.corner = CreateFrame("Frame", nil, self)
		self.corner:SetFrameLevel(self:GetFrameLevel() + 3)
		self.corner:EnableMouse(true)
		self.corner:SetScript("OnMouseDown", scaleMouseDown)
		self.corner:SetScript("OnMouseUp", scaleMouseUp)
		self.corner:SetScript("OnEnter", scaleMouseEnter)
		self.corner:SetScript("OnLeave", scaleMouseLeave)
		self.corner:SetHeight(12)
		self.corner:SetWidth(12)

		anchorFrame:SetScript("OnSizeChanged", scaleMouseChange)
		anchorFrame.corner = self.corner

		self.corner.tex = self.corner:CreateTexture(nil, "BORDER")
		self.corner.tex:SetTexture("Interface\\AddOns\\XPerlForever\\Images\\XPerl_Elements")
		self.corner.tex:SetAllPoints()
		self.corner.tex:SetVertexColor(1, 1, 1, 0.5)

		self.corner.anchor = anchorFrame
		self.corner.frame = self
	end

	if self.SetResizeBounds then
		self:SetResizeBounds(10, 10)
	else
		self:SetMinResize(10, 10)
	end

	self.corner.scalable = scalable
	self.corner.resizable = resizable
	self.corner.resizeTop = resizeTop
	self.corner.minScale = minScale or 0.4
	self.corner.maxScale = maxScale or 5
	self.corner.startSize = {w = self:GetWidth(), h = self:GetHeight()}

	local bgDef = self:GetBackdrop()

	self.corner:ClearAllPoints()
	if (resizeTop) then
		self.corner.tex:SetTexCoord(0.78125, 1, 0.5, 0.703125)
		self.corner:SetPoint("TOPRIGHT", -bgDef.insets.right, -bgDef.insets.top)
		self.corner:SetHitRectInsets(0, -6, -6, 0)		-- So the click area extends over the tooltip border
	else
		self.corner.tex:SetTexCoord(0.78125, 1, 0.78125, 1)
		self.corner:SetPoint("BOTTOMRIGHT", -bgDef.insets.right, bgDef.insets.bottom)
		self.corner:SetHitRectInsets(0, -6, 0, -6)		-- So the click area extends over the tooltip border
	end

	self.corner.scaling = true
	scaleMouseChange(anchorFrame)
	self.corner.scaling = nil
end

-- XPerl_SetExpectedAbsorbs
function XPerl_SetExpectedAbsorbs(self)
	local bar
	if self.statsFrame and self.statsFrame.expectedAbsorbs then
		bar = self.statsFrame.expectedAbsorbs
	else
		bar = self.expectedAbsorbs
	end
	if (bar) then
		local unit = self.partyid

		if not unit then
			unit = self:GetParent().targetid
		end

		local amount = type(UnitGetTotalAbsorbs) == "function" and UnitGetTotalAbsorbs(unit)

		if (XPerl_IsSecret(amount)) then
			-- Z-Perl Forever: the amount cannot be positioned by maths. Draw it as
			-- a reverse-filled overlay on the health bar; Blizzard scales it.
			local healthBar
			if self.statsFrame and self.statsFrame.healthBar then
				healthBar = self.statsFrame.healthBar
			else
				healthBar = self.healthBar
			end
			if (not conf.colour.bar.absorb) then
				conf.colour.bar.absorb = {r = 0.14, g = 0.33, b = 0.7, a = 0.7}
			end
			bar:SetStatusBarColor(conf.colour.bar.absorb.r, conf.colour.bar.absorb.g, conf.colour.bar.absorb.b, conf.colour.bar.absorb.a)
			if (healthBar) then
				bar:ClearAllPoints()
				bar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
				bar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
				if (bar.SetFrameLevel and healthBar.GetFrameLevel) then
					bar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
				end
			end
			if (bar.SetReverseFill) then
				bar:SetReverseFill(true)
			end
			bar:SetMinMaxValues(0, UnitHealthMax(unit))
			bar:SetValue(amount)
			bar:Show()
			return
		end

		-- Z-Perl Forever: identity-based secrecy for this unit is independent
		-- of amount's own secrecy above -- guard these too (pattern 12).
		if (amount and amount > 0 and not XPerl_SafeBool(UnitIsDeadOrGhost(unit), false)) then
			local healthMax = UnitHealthMax(unit)
			local health = XPerl_SafeBool(UnitIsGhost(unit), false) and 1 or (XPerl_SafeBool(UnitIsDead(unit), false) and 0 or UnitHealth(unit))

			if XPerl_SafeBool(UnitIsAFK(unit), false) then
				bar:SetStatusBarColor(0.2, 0.2, 0.2, 0.7)
			else
				if not conf.colour.bar.absorb then
					conf.colour.bar.absorb = { }
					conf.colour.bar.absorb.r = 0.14
					conf.colour.bar.absorb.g = 0.33
					conf.colour.bar.absorb.b = 0.7
					conf.colour.bar.absorb.a = 0.7
				end

				bar:SetStatusBarColor(conf.colour.bar.absorb.r, conf.colour.bar.absorb.g, conf.colour.bar.absorb.b, conf.colour.bar.absorb.a)
			end

			if (bar.SetReverseFill) then
				bar:SetReverseFill(false)
			end
			bar:Show()
			bar:SetMinMaxValues(0, healthMax)

			local healthBar
			if self.statsFrame and self.statsFrame.healthBar then
				healthBar = self.statsFrame.healthBar
			else
				healthBar = self.healthBar
			end
			local min, max = healthBar:GetMinMaxValues()
			local value = healthBar:GetValue()
			if (not XPerl_CanAccess(max) or not XPerl_CanAccess(value) or max == 0) then
				bar:Hide()
				return
			end
			local position = ((max - value) / max) * healthBar:GetWidth()

			if healthBar:GetWidth() <= 0 or healthBar:GetWidth() == position then
				return
			end

			bar:SetValue(amount * (healthBar:GetWidth() / (healthBar:GetWidth() - position)))

			bar:SetPoint("TopRight", healthBar, "TopRight", -position, 0)
			bar:SetPoint("BottomRight", healthBar, "BottomRight", -position, 0)
			return
		end
		bar:Hide()
	end
end

-- XPerl_SetExpectedHealth
function XPerl_SetExpectedHealth(self)
	local bar
	if self.statsFrame and self.statsFrame.expectedHealth then
		bar = self.statsFrame.expectedHealth
	else
		bar = self.expectedHealth
	end
	if (bar) then
		local unit = self.partyid

		if not unit then
			unit = self:GetParent().targetid
		end

		-- Z-Perl Forever: LibHealComm needs the combat log and addon messages,
		-- neither of which exist on a restricted client. Use the client's own
		-- incoming heal value when the library is not available.
		local amount
		if (HealComm) then
			local guid = UnitGUID(unit)
			amount = (HealComm:GetHealAmount(guid, HealComm.CASTED_HEALS, GetTime() + 3) or 0) * HealComm:GetHealModifier(guid)
		elseif (type(UnitGetIncomingHeals) == "function") then
			amount = UnitGetIncomingHeals(unit)
		end

		if not conf.colour.bar.healprediction then
			conf.colour.bar.healprediction = { }
			conf.colour.bar.healprediction.r = 0
			conf.colour.bar.healprediction.g = 1
			conf.colour.bar.healprediction.b = 1
			conf.colour.bar.healprediction.a = 1
		end

		if (XPerl_IsSecret(amount)) then
			-- Secret heal amount: UnitHealth(unit, true) is health plus incoming
			-- heals as computed by Blizzard, which is exactly this bar's value.
			bar:SetStatusBarColor(conf.colour.bar.healprediction.r, conf.colour.bar.healprediction.g, conf.colour.bar.healprediction.b, conf.colour.bar.healprediction.a)
			bar:SetMinMaxValues(0, UnitHealthMax(unit))
			bar:SetValue(UnitHealth(unit, true))
			bar:Show()
			return
		end

		if (amount and amount > 0 and not UnitIsDeadOrGhost(unit)) then
			local healthMax = UnitHealthMax(unit)
			local health = UnitIsGhost(unit) and 1 or (UnitIsDead(unit) and 0 or UnitHealth(unit))
			if (not XPerl_CanAccess(health) or not XPerl_CanAccess(healthMax)) then
				bar:Hide()
				return
			end

			bar:SetStatusBarColor(conf.colour.bar.healprediction.r, conf.colour.bar.healprediction.g, conf.colour.bar.healprediction.b, conf.colour.bar.healprediction.a)

			bar:Show()
			bar:SetMinMaxValues(0, healthMax)
			bar:SetValue(min(healthMax, health + amount))

			return
		end
		bar:Hide()
	end
end

-- Threat Display
local function DrawHand(self, percent)
	local angle = 360 - (percent * 2.7 - 135)
	local ULx, ULy, LLx, LLy, URx, URy, LRx, LRy = rotate(angle)
	self.needle:SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
end

local function DrawSlider(self, percent)
	local offset = (self:GetWidth() - 9) / 100 * percent
	self.needle:ClearAllPoints()
	self.needle:SetPoint("CENTER", self, "TOPLEFT", offset + 5, -2)

	local r, g, b
	if (percent <= 70) then
		r, g, b = 0, 1, 0
	else
		r, g, b = smoothColor(abs((percent - 100) / 30))
	end

	self.needle:SetVertexColor(r, g, b)
end

-- XPerl_ThreatDisplayOnLoad
function XPerl_ThreatDisplayOnLoad(self, mode)
	XPerl_SetChildMembers(self)
	self:SetFrameLevel(self:GetParent():GetFrameLevel() + 4)
	self.text:SetWidth(100)
	self.current, self.target = 0, 0
	self.mode = mode

	if (mode == "nameFrame") then
		self.Draw = DrawSlider
	else
		self.Draw = DrawHand
	end
	self:Draw(0)
end

-- threatOnUpdate
local function threatOnUpdate(self, elapsed)
	local diff = (self.target - self.current) * 0.2
	self.current = min(100, max(0, self.current + diff))
	if (abs(self.current - self.target) <= 0.01) then
		self.current = self.target
		self:SetScript("OnUpdate", nil)
	end

	self:Draw(self.current)
end

-- XPerl_Unit_ThreatStatus
function XPerl_Unit_ThreatStatus(self, relative, immediate)
	if (type(UnitDetailedThreatSituation) ~= "function" or not self.partyid or not self.conf) then
		return
	end

	local mode = self.conf.threatMode or (self.conf.portrait and "portraitFrame" or "nameFrame")
	local t = self.threatFrames and self.threatFrames[mode]
	if (not self.conf.threat) then
		if (t) then
			t:Hide()
		end
		return
	end

	if (not t) then
		if (self.threatFrames) then
			for mode,frame in pairs(self.threatFrames) do
				frame:SetScript("OnUpdate", nil)
				frame.current, frame.target = 0, 0
				frame:Hide()
			end
		else
			self.threatFrames = {}
		end
		if (self[mode]) then -- If desired parent frame exists
			t = CreateFrame("Frame", self:GetName().."Threat"..mode, self[mode], BackdropTemplateMixin and "BackdropTemplate,XPerl_ThreatTemplate"..mode or "XPerl_ThreatTemplate"..mode)
			t:SetAllPoints()
			self.threatFrames[mode] = t
		end

		self.threat = self.threatFrames[mode]
	end

	if (t) then
		local isTanking, state, scaledPercent, rawPercent, threatValue
		local one, two
		-- Z-Perl Forever: attack/combat flags for compound units can be secret
		if (XPerl_SafeBool(UnitAffectingCombat(self.partyid), false) or (relative and XPerl_SafeBool(UnitAffectingCombat(relative), false))) then
			if (relative and XPerl_SafeBool(UnitCanAttack(relative, self.partyid), false)) then
				one, two = relative, self.partyid
			else
				if (UnitExists("target") and XPerl_SafeBool(UnitCanAttack(self.partyid, "target"), false)) then
					one, two = self.partyid, "target"
				elseif (XPerl_SafeBool(UnitCanAttack("player", self.partyid), false)) then
					one, two = "player", self.partyid
				elseif (XPerl_SafeBool(UnitCanAttack(self.partyid, self.partyid.."target"), false)) then
					one, two = self.partyid, self.partyid.."target"
				end
			end

			if (one) then
				-- scaledPercent is 0% - 100%, 100 means you pull agro
				-- rawPercent is before normalization so can go up to 110% or 130% before you pull agro
				isTanking, state, scaledPercent, rawPercent, threatValue = UnitDetailedThreatSituation(one, two)
			end
		end

		if (scaledPercent) then
			if (XPerl_CanAccess(scaledPercent)) then
				if (scaledPercent ~= t.target) then
					t.target = scaledPercent
					if (immediate) then
						t.current = scaledPercent
					end
					t.one = one
					t.two = two
					t:SetScript("OnUpdate", threatOnUpdate)
				end

				local r, g, b = smoothColor(scaledPercent)
				t.text:SetTextColor(r, g, b)
			else
				-- Z-Perl Forever: the text sink can show a secret percent, but the
				-- needle animation needs maths, so it stays where it is.
				t:SetScript("OnUpdate", nil)
				t.text:SetTextColor(1, 1, 1)
			end

			t.text:SetFormattedText("%d%%", scaledPercent)

			t:Show()
			return
		end

		t:Hide()
	end
end

function XPerl_Register_Prediction(self, conf, guidToUnit, ...)
	if not self then
		return
	end

	-- Z-Perl Forever: without LibHealComm the client's own event drives the bar
	if not HealComm then
		if conf.healprediction and type(UnitGetIncomingHeals) == "function" then
			XPerl_RegisterEventSafe(self, "UNIT_HEAL_PREDICTION")
		else
			XPerl_UnregisterEventSafe(self, "UNIT_HEAL_PREDICTION")
		end
		return
	end

	if conf.healprediction then
		local UpdateHealth = function(event, ...)
			local unit = guidToUnit(select(select("#", ...), ...))
			if unit then
				local f = self:GetScript("OnEvent")
				f(self, "UNIT_HEAL_PREDICTION", unit)
			end
		end
		HealComm.RegisterCallback(self, "HealComm_HealStarted", UpdateHealth)
		HealComm.RegisterCallback(self, "HealComm_HealStopped", UpdateHealth)
		HealComm.RegisterCallback(self, "HealComm_HealDelayed", UpdateHealth)
		HealComm.RegisterCallback(self, "HealComm_HealUpdated", UpdateHealth)
		HealComm.RegisterCallback(self, "HealComm_ModifierChanged", UpdateHealth)
		HealComm.RegisterCallback(self, "HealComm_GUIDDisappeared", UpdateHealth)
	else
		HealComm.UnregisterCallback(self, "HealComm_HealStarted")
		HealComm.UnregisterCallback(self, "HealComm_HealStopped")
		HealComm.UnregisterCallback(self, "HealComm_HealDelayed")
		HealComm.UnregisterCallback(self, "HealComm_HealUpdated")
		HealComm.UnregisterCallback(self, "HealComm_ModifierChanged")
		HealComm.UnregisterCallback(self, "HealComm_GUIDDisappeared")
	end
end
