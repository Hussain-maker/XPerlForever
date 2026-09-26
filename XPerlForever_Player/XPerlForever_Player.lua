-- X-Perl UnitFrames
-- Author: Resike
-- License: GNU GPL v3, 29 June 2007 (see LICENSE.txt)

local XPerl_Player_Events = { }
local isOutOfControl
local playerClass, playerName
local conf, pconf
XPerl_RequestConfig(function(new)
	conf = new
	pconf = conf.player
	if (XPerl_Player) then
		XPerl_Player.conf = conf.player
	end
end, "$Revision:  $")

local perc1F = "%.1f"..PERCENT_SYMBOL
local percD = "%.0f"..PERCENT_SYMBOL

--[===[@debug@
local function d(...)
	ChatFrame1:AddMessage(format(...))
end
--@end-debug@]===]

local IsClassic = WOW_PROJECT_ID >= WOW_PROJECT_CLASSIC

-- Upvalues
local ceil = ceil
local floor = floor
local format = format
local hooksecurefunc = hooksecurefunc
local max = max
local pairs = pairs
local pcall = pcall
local string = string

local CreateFrame = CreateFrame
local GetDifficultyColor = GetDifficultyColor or GetQuestDifficultyColor
local GetLootMethod = GetLootMethod or C_PartyInfo.GetLootMethod
local GetNumGroupMembers = GetNumGroupMembers
local GetPVPTimer = GetPVPTimer
local GetRaidRosterInfo = GetRaidRosterInfo
local GetShapeshiftForm = GetShapeshiftForm
local GetSpecialization = GetSpecialization
local GetSpellInfo = GetSpellInfo
local GetXPExhaustion = GetXPExhaustion
local InCombatLockdown = InCombatLockdown
local IsInRaid = IsInRaid
local IsPVPTimerRunning = IsPVPTimerRunning
local IsResting = IsResting
local UnitAffectingCombat = UnitAffectingCombat
local UnitClass = UnitClass
local UnitFactionGroup = UnitFactionGroup
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitGUID = UnitGUID
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid
local UnitIsAFK = UnitIsAFK
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsGhost = UnitIsGhost
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsMercenary = UnitIsMercenary
local UnitIsPVP = UnitIsPVP
local UnitIsPVPFreeForAll = UnitIsPVPFreeForAll
local UnitIsUnit = UnitIsUnit
local UnitLevel = UnitLevel
local UnitName = UnitName
local UnitOnTaxi = UnitOnTaxi
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitXP = UnitXP
local UnitXPMax = UnitXPMax

local CombatFeedback_Initialize = CombatFeedback_Initialize
local CombatFeedback_OnCombatEvent = CombatFeedback_OnCombatEvent
local CombatFeedback_OnUpdate = CombatFeedback_OnUpdate

-- Z-Perl Forever: secret value helpers from XPerlForever.lua
local XPerl_CanAccess = XPerl_CanAccess
local XPerl_IsSecret = XPerl_IsSecret
local XPerl_GetPowerPercent = XPerl_GetPowerPercent
local XPerl_SafeBool = XPerl_SafeBool

local XPerl_PlayerStatus_OnUpdate
local XPerl_Player_HighlightCallback

--local feignDeath = (C_Spell and C_Spell.GetSpellInfo(5384)) and C_Spell.GetSpellInfo(5384).name or GetSpellInfo(5384)
--local spiritOfRedemption = (C_Spell and C_Spell.GetSpellInfo(27827)) and C_Spell.GetSpellInfo(27827).name or GetSpellInfo(27827)


----------------------
-- Loading Function --
----------------------
function XPerl_Player_OnLoad(self)
	XPerl_SetChildMembers(self)
	self.partyid = "player"
	self.unit = self.partyid

	XPerl_BlizzFrameDisable(PlayerFrame)

	CombatFeedback_Initialize(self, self.hitIndicator.text, 30)

	self.portraitFrame:SetAttribute("*type1", "target")
	self.portraitFrame:SetAttribute("type2", "togglemenu")
	self.portraitFrame:SetAttribute("unit", self.partyid)
	self.nameFrame:SetAttribute("*type1", "target")
	self.nameFrame:SetAttribute("type2", "togglemenu")
	self.nameFrame:SetAttribute("unit", self.partyid)
	self.statsFrame:SetAttribute("*type1", "target")
	self.statsFrame:SetAttribute("type2", "togglemenu")
	self.statsFrame:SetAttribute("unit", self.partyid)
	self:SetAttribute("*type1", "target")
	self:SetAttribute("type2", "togglemenu")
	self:SetAttribute("unit", self.partyid)

	self.state = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")

	--RegisterAttributeDriver(self.nameFrame, "unit", "[vehicleui] vehicle; player")
	RegisterAttributeDriver(self, "unit", "[vehicleui] vehicle; player")

	XPerl_RegisterClickCastFrame(self.portraitFrame)
	XPerl_RegisterClickCastFrame(self.nameFrame)
	XPerl_RegisterClickCastFrame(self.statsFrame)
	XPerl_RegisterClickCastFrame(self)

	self:RegisterEvent("VARIABLES_LOADED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_ALIVE")

	if (HealBot_Options_EnablePlayerFrame) then
		HealBot_Options_EnablePlayerFrame = function() end
	end

	self:SetScript("OnUpdate", XPerl_Player_OnUpdate)
	self:SetScript("OnEvent", XPerl_Player_OnEvent)
	self:SetScript("OnShow", XPerl_Unit_UpdatePortrait)
	self.time = 0

	self.Power = 0
	self.nameFrame.pvp.time = 0

	self.nameFrame.pvptimer:SetScript("OnUpdate", XPerl_Player_UpdatePVPTimerOnUpdate)

	local _, playerClass = UnitClass("player")
	if (playerClass == "DRUID") or (playerClass == "SHAMAN") or (playerClass == "PRIEST") then
		XPerl_Player_DruidBarUpdate(self)
	end

	XPerl_RegisterHighlight(self.highlight, 3)

	local perlframes = {self.nameFrame, self.statsFrame, self.levelFrame, self.portraitFrame, self.groupFrame}
	self.FlashFrames = {self.portraitFrame, self.nameFrame,self.levelFrame, self.statsFrame}
	XPerl_RegisterPerlFrames(self, perlframes)--, self.runes

	XPerl_RegisterOptionChanger(XPerl_Player_Set_Bits, self)
	XPerl_Highlight:Register(XPerl_Player_HighlightCallback, self)
	--self.IgnoreHighlightStates = {AGGRO = true}

	if (XPerlDB) then
		self.conf = XPerlDB.player
	end

	XPerl_Player_OnLoad = nil
end

-- XPerl_Player_HighlightCallback(updateName)
function XPerl_Player_HighlightCallback(self, updateGUID)
	if (updateGUID == UnitGUID("player")) then
		XPerl_Highlight:SetHighlight(self, updateGUID)
	end
end

-- UpdateAssignedRoles
local function UpdateAssignedRoles(self)
	local unit = self.partyid
	local icon = self.nameFrame.roleIcon
	local isTank, isHealer, isDamage
	if type(UnitGroupRolesAssigned) == "function" then
		local role = UnitGroupRolesAssigned(unit)
		isTank = false
		isHealer = false
		isDamage = false
		if role == "TANK" then
			isTank = true
		elseif role == "HEALER" then
			isHealer = true
		elseif role == "DAMAGER" then
			isDamage = true
		end
	end

	-- role icons option check by playerlin
	if (conf and conf.xperlOldroleicons) then
		if isTank then
			icon:SetTexture("Interface\\GroupFrame\\UI-Group-MainTankIcon")
			icon:Show()
		elseif isHealer then
			icon:SetTexture("Interface\\AddOns\\XPerlForever\\Images\\XPerl_RoleHealer_old")
			icon:Show()
		elseif isDamage then
			icon:SetTexture("Interface\\GroupFrame\\UI-Group-MainAssistIcon")
			icon:Show()
		else
			icon:Hide()
		end
	else
		if isTank then
			icon:SetTexture("Interface\\AddOns\\XPerlForever\\Images\\XPerl_RoleTank")
			icon:Show()
		elseif isHealer then
			icon:SetTexture("Interface\\AddOns\\XPerlForever\\Images\\XPerl_RoleHealer")
			icon:Show()
		elseif isDamage then
			icon:SetTexture("Interface\\AddOns\\XPerlForever\\Images\\XPerl_RoleDamage")
			icon:Show()
		else
			icon:Hide()
		end
	end
end

-------------------------
-- The Update Function --
-------------------------

local function XPerl_Player_CombatFlash(self, elapsed, argNew, argGreen)
	if (XPerl_CombatFlashSet(self, elapsed, argNew, argGreen)) then
		XPerl_CombatFlashSetFrames(self)
	end
end

-- XPerl_Player_UpdateManaType
local function XPerl_Player_UpdateManaType(self)
	XPerl_SetManaBarType(self)
end

-- XPerl_Player_UpdateLeader()
local function XPerl_Player_UpdateLeader(self)
	local nf = self.nameFrame

	-- Loot Master
	local method, pindex, rindex, ml
	if (UnitInParty("party1") or UnitInRaid("player")) then
		method, pindex, rindex = GetLootMethod()

		if (method == "master") then
			if (rindex ~= nil) then
				ml = UnitIsUnit("raid"..rindex, "player")
			elseif (pindex and (pindex == 0)) then
				ml = true
			end
		end
	end

	if (ml) then
		nf.masterIcon:Show()
	else
		nf.masterIcon:Hide()
	end

	-- Leader
	if (UnitIsGroupLeader("player")) then
		nf.leaderIcon:Show()
	else
		nf.leaderIcon:Hide()
	end

	if (UnitIsGroupAssistant("player")) then
		nf.assistIcon:Show()
	else
		nf.assistIcon:Hide()
	end

	UpdateAssignedRoles(self)

	if (pconf and pconf.partyNumber and IsInRaid()) then
		for i = 1, GetNumGroupMembers() do
			local _, _, subgroup = GetRaidRosterInfo(i)
			if (UnitIsUnit("raid"..i, "player")) then
				if (pconf.withName) then
					nf.group:SetFormattedText(XPERL_RAID_GROUPSHORT, subgroup)
					nf.group:Show()
					self.groupFrame:Hide()
					return
				else
					self.groupFrame.text:SetFormattedText(XPERL_RAID_GROUP, subgroup)
					self.groupFrame:Show()
					nf.group:Hide()
					return
				end
			end
		end
	end

	nf.group:Hide()
	self.groupFrame:Hide()
end

local function XPerl_Player_UpdateRaidTarget(self)
	XPerl_Update_RaidIcon(self.nameFrame.raidIcon, self.partyid)
end

-- XPerl_Player_UpdateCombat
local function XPerl_Player_UpdateCombat(self)
	local nf = self.nameFrame
	if (UnitAffectingCombat("player")) then
		nf.text:SetTextColor(1, 0, 0)
		nf.combatIcon:SetTexCoord(0.49, 1, 0, 0.49)
		nf.combatIcon:Show()
	else
		if (self.partyid ~= "player") then
			local c = conf.colour.reaction.none
			nf.text:SetTextColor(c.r, c.g, c.b, conf.transparency.text)
		else
			XPerl_ColourFriendlyUnit(nf.text, self.partyid)
		end

		if (IsResting()) then
			nf.combatIcon:SetTexCoord(0, 0.49, 0, 0.49)
			nf.combatIcon:Show()
		else
			nf.combatIcon:Hide()
		end
	end
end

-- XPerl_Player_UpdateName()
local function XPerl_Player_UpdateName(self)
	-- Z-Perl Forever: full "First Last" (or "First-Realm") display name
	playerName = XPerl_UnitFullName(self.partyid)
	self.nameFrame.text:SetText(playerName)
	XPerl_Player_UpdateCombat(self)
end

-- XPerl_Player_UpdateClass
local function XPerl_Player_UpdateClass(self)
	local _, class = UnitClass(self.partyid)
	playerClass = class
	playerName = XPerl_UnitFullName(self.partyid)
	local l, r, t, b = XPerl_ClassPos(playerClass)
	self.classFrame.tex:SetTexCoord(l, r, t, b)

	if (pconf.classIcon) then
		self.classFrame:Show()
	else
		self.classFrame:Hide()
	end
end

-- There are two different functions to get faction info, used in retail/classic/era.
-- To maintain compatibility, we fake the original function if it's not there.
local GetWatchedFactionInfo
if _G.GetWatchedFactionInfo then
	GetWatchedFactionInfo = _G.GetWatchedFactionInfo
else
	GetWatchedFactionInfo = function()
		local data = C_Reputation.GetWatchedFactionData()
		if data then
			return data.name, data.reaction, data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding, data.factionID
		end
		return nil, nil, nil, nil, nil, nil -- documenting that there should be six returns.
	end
end

-- XPerl_Player_UpdateRep
local function XPerl_Player_UpdateRep(self)
	if (pconf and pconf.repBar) then
		local rb = self.statsFrame.repBar
		if (rb) then
			local name, reaction, min, max, value, factionID = GetWatchedFactionInfo()
			local color
			local perc

			if max == 43000 then
				max = 42000
			end

			if (factionID == 1733 or factionID == 1736 or factionID == 1737 or factionID == 1738 or factionID == 1739 or factionID == 1740 or factionID == 1741) and min == 20000 and max == 21000 and value == 20000 then
				min = 21000
				value = 21000
			end

			if name then
				color = FACTION_BAR_COLORS[reaction]
				if min > 0 and max > 0 and value > 0 and min ~= max and min ~= value then
					value = value - min
					max = max - min
				end
				min = 0
				if value > 0 and max > 0 then
					perc = (value * 100) / max
				else
					perc = 100
				end
			else
				name = XPERL_LOC_NONEWATCHED
				value = 0
				max = 1
				min = 0
				color = FACTION_BAR_COLORS[4]
				perc = 0
			end

			rb:SetMinMaxValues(min, max)
			rb:SetValue(value)

			rb:SetStatusBarColor(color.r, color.g, color.b, 1)
			rb.bg:SetVertexColor(color.r, color.g, color.b, 0.25)

			if perc < 0 then
				perc = 0
			elseif perc > 100 then
				perc = 100
			end

			rb.tex:SetTexCoord(0, perc / 100, 0, 1)

			if max == 1 then
				rb.text:SetText(name)
			else
				rb.text:SetFormattedText("%d/%d", value, max)
			end

			if perc < 100 then
				rb.percent:SetFormattedText(perc1F, perc)
			else
				rb.percent:SetFormattedText(percD, perc)
			end
		end
	end
end

-- XPerl_Player_UpdateXP
local function XPerl_Player_UpdateXP(self)
	if (pconf.xpBar) then
		local xpBar = self.statsFrame.xpBar
		if (xpBar) then
			local restBar = self.statsFrame.xpRestBar
			local playerxp = UnitXP("player")
			local playerxpmax = UnitXPMax("player")
			local playerxprest = GetXPExhaustion() or 0
			xpBar:SetMinMaxValues(0, playerxpmax)
			restBar:SetMinMaxValues(0, playerxpmax)
			xpBar:SetValue(playerxp)

			local color
			local w = xpBar:GetRight() - xpBar:GetLeft()
			for mode = 1, 3 do
				local suffix
				if (playerxprest > 0) then
					if (mode == 1) then
						suffix = format(" +%d", playerxprest)
					elseif (mode == 2) then
						if (playerxprest >= 1000000) then
							suffix = format(" +%.1fM", playerxprest / 1000000)
						else
							suffix = format(" +%.1fk", playerxprest / 1000)
						end
					else
						if (playerxprest >= 1000000) then
							suffix = format(" +%dM", playerxprest / 1000000)
						else
							suffix = format(" +%dk", playerxprest / 1000)
						end
					end

					color = {r = 0.3, g = 0.3, b = 1}
				else
					color = {r = 0.6, g = 0, b = 0.6}
				end

				if (pconf.xpDeficit) then
					XPerl_SetValuedText(xpBar.text, playerxp - playerxpmax, playerxpmax, suffix)
				else
					XPerl_SetValuedText(xpBar.text, playerxp, playerxpmax, suffix)
				end
				if (xpBar.text:GetStringWidth() + 20 <= w) then
					break
				end
			end

			xpBar:SetStatusBarColor(color.r, color.g, color.b, 1)
			xpBar.bg:SetVertexColor(color.r, color.g, color.b, 0.25)
			local x = playerxp / playerxpmax
			if x > 1 then
				x = 1
			end
			xpBar.tex:SetTexCoord(0, x, 0, 1)

			restBar:SetValue(playerxp + playerxprest)
			restBar:SetStatusBarColor(color.r, color.g, color.b, 0.5)
			local y = (playerxp + playerxprest) / playerxpmax
			if y > 1 then
				y = 1
			end
			restBar.tex:SetTexCoord(0, y, 0, 1)
			restBar.bg:SetVertexColor(color.r, color.g, color.b, 0.25)
			xpBar.percent:SetFormattedText(percD, (playerxp * 100) / playerxpmax)
		end
	end
end

-- XPerl_Player_UpdatePVPTimer
function XPerl_Player_UpdatePVPTimerOnUpdate(self, elapsed)
	self.time = (self.time or 0) + elapsed
	if self.time >= 0.5 then
		local timeLeft = GetPVPTimer()

		if timeLeft > 0 then
			timeLeft = floor(timeLeft / 1000)
			self.text:SetFormattedText("%d:%02d", timeLeft / 60, timeLeft % 60)
		end

		self.time = 0
	end
end

-- XPerl_Player_UpdatePVPTimer
local function XPerl_Player_UpdatePVPTimer(self)
	if pconf.pvpIcon and IsPVPTimerRunning() then
		self.nameFrame.pvptimer:Show()
	else
		self.nameFrame.pvptimer:Hide()
		self.nameFrame.pvptimer.text:SetText("")
	end
end

-- XPerl_Player_UpdatePVP
local function XPerl_Player_UpdatePVP(self)
	-- PVP Status settings
	--local nf = self.nameFrame
	if (UnitAffectingCombat(self.partyid)) then
		self.nameFrame.text:SetTextColor(1, 0, 0)
	else
		XPerl_ColourFriendlyUnit(self.nameFrame.text, "player")
	end

	local pvpIcon = self.nameFrame.pvp

	local factionGroup, factionName = UnitFactionGroup("player")

	if pconf.pvpIcon and UnitIsPVPFreeForAll("player") then
		pvpIcon.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-FFA")
		pvpIcon:Show()
	elseif pconf.pvpIcon and factionGroup and factionGroup ~= "Neutral" and UnitIsPVP("player") then
		pvpIcon.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-"..factionGroup)

		if type(UnitIsMercenary) == "function" and UnitIsMercenary("player") then
			if factionGroup == "Horde" then
				pvpIcon.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Alliance")
			elseif factionGroup == "Alliance" then
				pvpIcon.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Horde")
			end
		end

		pvpIcon:Show()
	else
		pvpIcon:Hide()
	end

	XPerl_Player_UpdatePVPTimer(self)
end

-- CreateBar(self, name)
local function CreateBar(self, name)
	local f = CreateFrame("StatusBar", self.statsFrame:GetName()..name, self.statsFrame, "XPerlStatusBar")
	f:SetPoint("TOPLEFT", self.statsFrame.manaBar, "BOTTOMLEFT", 0, 0)
	f:SetHeight(10)
	self.statsFrame[name] = f
	f:SetWidth(112)
	return f
end

-- MakeDruidBar()
local function MakeDruidBar(self)
	local f = CreateBar(self, "druidBar")
	local c = conf.colour.bar.mana
	f:SetStatusBarColor(c.r, c.g, c.b)
	f.bg:SetVertexColor(c.r, c.g, c.b, 0.25)
	MakeDruidBar = nil
end

-- XPerl_Player_DruidBarUpdate
function XPerl_Player_DruidBarUpdate(self)
	local druidBar = self.statsFrame.druidBar
	if (pconf.noDruidBar) then
		if (druidBar) then
			druidBar:Hide()
			XPerl_StatsFrameSetup(self, {self.statsFrame.xpBar, self.statsFrame.repBar})
		end
		return
	elseif (not druidBar) then
		if (MakeDruidBar) then
			MakeDruidBar(self)
			druidBar = self.statsFrame.druidBar
		end
	end

	local maxMana = UnitPowerMax("player", 0)
	if XPerl_CanAccess(maxMana) and maxMana == 0 then
		maxMana = nil
	end
	local currMana = UnitPower("player", 0)

	druidBar:SetMinMaxValues(0, maxMana or 1)
	druidBar:SetValue(currMana or 0)
	if (XPerl_IsSecret(currMana) or XPerl_IsSecret(maxMana)) then
		-- Z-Perl Forever: mana is secret in combat, text sinks only
		druidBar.text:SetFormattedText("%d/%d", currMana, maxMana or 1)
		druidBar.percent:SetFormattedText(percD, XPerl_GetPowerPercent("player", 0, currMana, maxMana))
	else
		druidBar.text:SetFormattedText("%d/%d", ceil(currMana or 0), maxMana or 1)
		druidBar.percent:SetFormattedText(percD, (currMana or 0) * 100 / (maxMana or 1))
	end

	--local druidBarExtra
	if ((playerClass == "DRUID" or playerClass == "PRIEST") and UnitPowerType(self.partyid) > 0) then -- Shaman's UnitPowerType is buggy
		if (pconf.values) then
			druidBar.text:Show()
		else
			druidBar.text:Hide()
		end
		if (pconf.percent) then
			druidBar.percent:Show()
		else
			druidBar.percent:Hide()
		end
		druidBar:Show()
		--druidBar:SetHeight(10)
		--druidBarExtra = 1
	else
		--druidBar.percent:Hide()
		--druidBar.text:Hide()
		druidBar:Hide()
		--druidBar:SetHeight(1)
		--druidBarExtra = 0
	end

	local h = 40 + ((((druidBar and druidBar:IsShown()) and 1 or 0) + (pconf.repBar and 1 or 0) + (pconf.xpBar and 1 or 0)) * 10)
	if not InCombatLockdown() then
		self.statsFrame:SetHeight(h)
	end

	XPerl_StatsFrameSetup(self, {druidBar, self.statsFrame.xpBar, self.statsFrame.repBar})
end

-- XPerl_Player_UpdateMana
local function XPerl_Player_UpdateMana(self)
	local powerType = XPerl_GetDisplayedPowerType(self.partyid)
	local unitPower = UnitPower(self.partyid, powerType)
	local unitPowerMax = UnitPowerMax(self.partyid, powerType)

	self.statsFrame.manaBar:SetMinMaxValues(0, unitPowerMax)
	self.statsFrame.manaBar:SetValue(unitPower)

	-- Z-Perl Forever: the percent is plain maths when readable and a Blizzard
	-- supplied (secret) value otherwise. It only ever goes into text sinks.
	local powerPct = XPerl_GetPowerPercent(self.partyid, powerType, unitPower, unitPowerMax)

	--self.statsFrame.manaBar.text:SetFormattedText("%d/%d", playermana, playermanamax)
	XPerl_SetValuedText(self.statsFrame.manaBar.text, unitPower, unitPowerMax)

	if (powerType >= 1 or (XPerl_CanAccess(unitPowerMax) and unitPowerMax < 1)) then
		self.statsFrame.manaBar.percent:SetText(unitPower)
	else
		self.statsFrame.manaBar.percent:SetFormattedText(percD, powerPct)
	end

	if (XPerl_CanAccess(powerPct)) then
		self.statsFrame.manaBar.tex:SetTexCoord(0, max(0, powerPct / 100), 0, 1)
	else
		self.statsFrame.manaBar.tex:SetTexCoord(0, 1, 0, 1)
	end

	if (not self.statsFrame.greyMana) then
		if (pconf.values) then
			self.statsFrame.manaBar.text:Show()
		end
		if (pconf.percent) then
			self.statsFrame.manaBar.percent:Show()
		end
	end

	if (playerClass == "DRUID") or (playerClass == "SHAMAN") or (playerClass == "PRIEST") then
		XPerl_Player_DruidBarUpdate(self)
	end
end

-- XPerl_Player_UpdateHealPrediction
local function XPerl_Player_UpdateHealPrediction(self)
	if pconf.healprediction then
		XPerl_SetExpectedHealth(self)
	else
		self.statsFrame.expectedHealth:Hide()
	end
end

-- XPerl_Player_UpdateAbsorbPrediction
local function XPerl_Player_UpdateAbsorbPrediction(self)
	if pconf.absorbs then
		XPerl_SetExpectedAbsorbs(self)
	else
		self.statsFrame.expectedAbsorbs:Hide()
	end
end

local function XPerl_Player_UpdateResurrectionStatus(self)
	if UnitHasIncomingResurrection(self.partyid) then
		if pconf.portrait then
			self.portraitFrame.resurrect:Show()
		else
			self.statsFrame.resurrect:Show()
		end
	else
		if pconf.portrait then
			self.portraitFrame.resurrect:Hide()
		else
			self.statsFrame.resurrect:Hide()
		end
	end
end

-- XPerl_Player_UpdateHealth
local function XPerl_Player_UpdateHealth(self)
	local partyid = self.partyid
	local sf = self.statsFrame
	local hb = sf.healthBar
	local playerhealth, playerhealthmax = XPerl_Unit_GetHealth(self)

	-- Z-Perl Forever: Confirmed that even "player" itself can
	-- return secret booleans from UnitIsAFK/UnitIsDead/UnitIsGhost on this
	-- beta; guard all of them (pattern 12), matching the sibling fix already
	-- applied to XPerl_Target_UpdateHealth.
	self.afk = XPerl_SafeBool(UnitIsAFK(partyid), false) and conf.showAFK == 1

	XPerl_SetHealthBar(self, playerhealth, playerhealthmax)
	XPerl_Player_UpdateAbsorbPrediction(self)
	XPerl_Player_UpdateHealPrediction(self)
	XPerl_Player_UpdateResurrectionStatus(self)

	local greyMsg
	if (XPerl_SafeBool(UnitIsDead(partyid), false)) then
		greyMsg = XPERL_LOC_DEAD
	elseif (XPerl_SafeBool(UnitIsGhost(partyid), false)) then
		greyMsg = XPERL_LOC_GHOST
	elseif (XPerl_SafeBool(UnitIsAFK("player"), false) and conf.showAFK) then
		greyMsg = CHAT_MSG_AFK
	end

	if (greyMsg) then
		if (pconf.percent) then
			hb.percent:SetText(greyMsg)
			hb.percent:Show()
		else
			hb.text:SetText(greyMsg)
			hb.text:Show()
		end

		sf:SetGrey()
	else
		if (sf.greyMana) then
			if (not pconf.values) then
				hb.text:Hide()
			end

			sf.greyMana = nil
			XPerl_Player_UpdateManaType(self)
		end
	end

	XPerl_PlayerStatus_OnUpdate(self, playerhealth, playerhealthmax)
end

-- XPerl_Player_UpdateLevel
local function XPerl_Player_UpdateLevel(self)
	local color = GetDifficultyColor(UnitLevel(self.partyid))
	self.levelFrame.text:SetTextColor(color.r, color.g, color.b, conf.transparency.text)

	self.levelFrame.text:SetText(UnitLevel(self.partyid))
end


-- XPerl_PlayerStatus_OnUpdate
function XPerl_PlayerStatus_OnUpdate(self, val, max)
	if (pconf.fullScreen.enable) then
		local testLow = pconf.fullScreen.lowHP / 100
		local testHigh = pconf.fullScreen.highHP / 100

		-- Z-Perl Forever: no low-health flash while the values are secret
		if (val and max and XPerl_CanAccess(val) and XPerl_CanAccess(max) and val > 0 and max > 0) then
			local test = val / max

			if ( test <= testLow and not XPerl_LowHealthFrame.frameFlash and not UnitIsDeadOrGhost("player")) then
				XPerl_FrameFlash(XPerl_LowHealthFrame)
			elseif ( (test >= testHigh and XPerl_LowHealthFrame.frameFlash) or UnitIsDeadOrGhost("player") ) then
				XPerl_FrameFlashStop(XPerl_LowHealthFrame, "out")
			end
			return
		else
			if (not UnitOnTaxi("player")) then
				if (isOutOfControl and not XPerl_OutOfControlFrame.frameFlash and not UnitOnTaxi("player")) then
					XPerl_FrameFlash(XPerl_OutOfControlFrame)
				elseif (not isOutOfControl and XPerl_OutOfControlFrame.frameFlash) then
					XPerl_FrameFlashStop(XPerl_OutOfControlFrame, "out")
				end
				return
			end
		end
	end

	if (XPerl_LowHealthFrame.frameFlash) then
		XPerl_FrameFlashStop(XPerl_LowHealthFrame)
	end
	if (XPerl_OutOfControlFrame.frameFlash) then
		XPerl_FrameFlashStop(XPerl_OutOfControlFrame)
	end
end

-- XPerl_Player_OnUpdate
function XPerl_Player_OnUpdate(self, elapsed)
	if pconf.hitIndicator and pconf.portrait then
		CombatFeedback_OnUpdate(self, elapsed)
	end

	local partyid = self.partyid
	-- Z-Perl Forever: same shape as the sibling fix in XPerlForever_Target.lua --
	-- Confirmed crashing even for "player" itself. Default to
	-- self.afk when secret so the comparison reads "no change".
	local newAFK = XPerl_SafeBool(UnitIsAFK(partyid), self.afk)

	if (conf.showAFK and newAFK ~= self.afk) then
		XPerl_Player_UpdateHealth(self)
	end

	if (self.PlayerFlash) then
		XPerl_Player_CombatFlash(self, elapsed, false)
	end

	--XPerl_Player_UpdateMana(self)
end

-- XPerl_Player_UpdateBuffs
local function XPerl_Player_UpdateBuffs(self)
	-- TODO: create a highlight handler for the player too
	if (conf.highlightDebuffs.enable) then
		XPerl_CheckDebuffs(self, self.partyid)
	end

	-- Z-Perl Forever: own buff buttons when the secure aura header is unavailable
	if (XPerl_Player_Buffs_Update) then
		XPerl_Player_Buffs_Update(self)
	end

	if (playerClass == "DRUID") then
		XPerl_Player_UpdateMana(self)
	end

	if (pconf.fullScreen.enable) then
		if (isOutOfControl and not UnitOnTaxi("player")) then
			XPerl_PlayerStatus_OnUpdate(self)
		end
	end
end

-- XPerl_Player_UpdateDisplay
function XPerl_Player_UpdateDisplay(self)
	XPerl_Player_UpdateXP(self)
	XPerl_Player_UpdateRep(self)
	XPerl_Player_UpdateManaType(self)
	XPerl_Player_UpdateLevel(self)
	XPerl_Player_UpdateName(self)
	XPerl_Player_UpdateClass(self)
	XPerl_Player_UpdatePVP(self)
	XPerl_Player_UpdateCombat(self)
	XPerl_Player_UpdateLeader(self)
	XPerl_Player_UpdateRaidTarget(self)
	XPerl_Player_UpdateMana(self)
	XPerl_Player_UpdateHealth(self)
	XPerl_Player_UpdateBuffs(self)
	XPerl_Unit_UpdatePortrait(self)
end

-- EVENTS AND STUFF

-------------------
-- Event Handler --
-------------------
function XPerl_Player_OnEvent(self, event, unit, ...)
	if string.find(event, "^UNIT_") then
		if (unit == "player" or unit == "vehicle") then
			if event == "UNIT_HEAL_PREDICTION" or event == "UNIT_ABSORB_AMOUNT_CHANGED" or event == "UNIT_COMBAT" then
				XPerl_Player_Events[event](self, unit, ...)
			else
				XPerl_Player_Events[event](self, ...)
			end
		end
	else
		XPerl_Player_Events[event](self, event, unit, ...)
	end
end

function XPerl_Player_Events:PLAYER_ALIVE()
	XPerl_Player_UpdateDisplay(self)
end


-- PLAYER_ENTERING_WORLD
function XPerl_Player_Events:PLAYER_ENTERING_WORLD(event, initialLogin, reloadingUI)
	self.updateAFK = true

	self.partyid = "player"
	self.unit = self.partyid
	if self.runes and self.runes.child and self.runes.child.unit then
		self.runes.child.unit = self.partyid
	end
	self:SetAttribute("unit", "player")
	if (XPerl_ArcaneBar_SetUnit) then
		XPerl_ArcaneBar_SetUnit(self.nameFrame, "player")
	end

	if (initialLogin or reloadingUI) and not InCombatLockdown() and not XPerl_ForeverNoSecureSnippets then
		self.state:SetFrameRef("ZPerlPlayer", self)
		self.state:SetFrameRef("ZPerlPlayerPortrait", self.portraitFrame)
		self.state:SetFrameRef("ZPerlPlayerStats", self.statsFrame)

		local class, classFileName, classID = UnitClass("player")

		self.state:SetAttribute("playerClass", classFileName)
		if not IsClassic and GetSpecialization then
			self.state:SetAttribute("playerSpec", GetSpecialization())
		end
		self.state:SetAttribute("extendedPortrait", pconf.extendPortrait)
		self.state:SetAttribute("druidBarOff", pconf.noDruidBar)
		self.state:SetAttribute("xpBar", pconf.xpBar)
		self.state:SetAttribute("repBar", pconf.repBar)
		self.state:SetAttribute("special", pconf.showRunes)
		self.state:SetAttribute("docked", pconf.dockRunes)

		self.state:Execute([[
			frame = self:GetFrameRef("ZPerlPlayer")
			portrait = self:GetFrameRef("ZPerlPlayerPortrait")
			stats = self:GetFrameRef("ZPerlPlayerStats")
		]])

		self.state:SetAttribute("_onstate-petbattleupdate", [[
			if newstate == "inpetbattle" then
				frame:Hide()
			else
				local buffs = self:GetFrameRef("ZPerlPlayerBuffs")

				local class = self:GetAttribute("playerClass")
				local spec = self:GetAttribute("playerSpec")
				local extend = self:GetAttribute("extendedPortrait")
				local bar = self:GetAttribute("druidBarOff")
				local xp = self:GetAttribute("xpBar")
				local rep = self:GetAttribute("repBar")
				local special = self:GetAttribute("spec")
				local docked = self:GetAttribute("docked")
				local above = self:GetAttribute("buffsAbove")

				local offset = 10 * ((bar and 0 or 1) + (xp and 1 or 0) + (rep and 1 or 0))
				local buffoffset = 13.5 * ((bar and 0 or 1) + (xp and 1 or 0) + (rep and 1 or 0))

				if class == "DRUID" then
					if spec == 1 then
						if newstate == 1 then
							if extend then
								frame:SetHeight(62 + offset)
								portrait:SetHeight(62 + offset)
							else
								frame:SetHeight(62)
								portrait:SetHeight(62)
							end
							stats:SetHeight(40 + offset)
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
								end
							end
						elseif newstate == 2 then
							if extend then
								frame:SetHeight(62 + offset)
								portrait:SetHeight(62 + offset)
							else
								frame:SetHeight(62)
								portrait:SetHeight(62)
							end
							stats:SetHeight(40 + offset)
							if not above and buffs then
								if extend then
									if special and docked then
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0 - 28)
									else
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
									end
								else
									if special and docked then
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset - 28)
									else
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
									end
								end
							end
						elseif newstate == 3 then
							if extend then
								if bar then
									frame:SetHeight(62 + offset)
									portrait:SetHeight(62 + offset)
								else
									frame:SetHeight(62 + offset - 10)
									portrait:SetHeight(62 + offset - 10)
								end
							else
								if bar then
									frame:SetHeight(62)
									portrait:SetHeight(62)
								else
									frame:SetHeight(62)
									portrait:SetHeight(62)
								end
							end
							if bar then
								stats:SetHeight(40 + offset)
							else
								stats:SetHeight(40 + offset - 10)
							end
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									if bar then
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
									else
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset + 13.5)
									end
								end
							end
						elseif newstate == 4 then
							if extend then
								frame:SetHeight(62 + offset)
								portrait:SetHeight(62 + offset)
							else
								frame:SetHeight(62)
								portrait:SetHeight(62)
							end
							stats:SetHeight(40 + offset)
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
								end
							end
						else
							if extend then
								frame:SetHeight(62 + offset)
								portrait:SetHeight(62 + offset)
							else
								frame:SetHeight(62)
								portrait:SetHeight(62)
							end
							stats:SetHeight(40 + offset)
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
								end
							end
						end
					elseif spec == 2 or spec == 3 or spec == 4 then
						if newstate == 1 then
							if extend then
								frame:SetHeight(62 + offset)
								portrait:SetHeight(62 + offset)
							else
								frame:SetHeight(62)
								portrait:SetHeight(62)
							end
							stats:SetHeight(40 + offset)
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
								end
							end
						elseif newstate == 2 then
							if extend then
								frame:SetHeight(62 + offset)
								portrait:SetHeight(62 + offset)
							else
								frame:SetHeight(62)
								portrait:SetHeight(62)
							end
							stats:SetHeight(40 + offset)
							if not above and buffs then
								if extend then
									if special and docked then
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0 - 28)
									else
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
									end
								else
									if special and docked then
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset - 28)
									else
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
									end
								end
							end
						elseif newstate == 3 then
							if extend then
								if bar then
									frame:SetHeight(62 + offset)
									portrait:SetHeight(62 + offset)
								else
									frame:SetHeight(62 + offset - 10)
									portrait:SetHeight(62 + offset - 10)
								end
							else
								if bar then
									frame:SetHeight(62)
									portrait:SetHeight(62)
								else
									frame:SetHeight(62)
									portrait:SetHeight(62)
								end
							end
							if bar then
								stats:SetHeight(40 + offset)
							else
								stats:SetHeight(40 + offset - 10)
							end
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									if bar then
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
									else
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset + 13.5)
									end
								end
							end
						else
							if extend then
								if bar then
									frame:SetHeight(62 + offset)
									portrait:SetHeight(62 + offset)
								else
									frame:SetHeight(62 + offset - 10)
									portrait:SetHeight(62 + offset - 10)
								end
							else
								if bar then
									frame:SetHeight(62)
									portrait:SetHeight(62)
								else
									frame:SetHeight(62)
									portrait:SetHeight(62)
								end
							end
							if bar then
								stats:SetHeight(40 + offset)
							else
								stats:SetHeight(40 + offset - 10)
							end
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									if bar then
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
									else
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset + 13.5)
									end
								end
							end
						end
					else
						if newstate == 1 then
							if extend then
								frame:SetHeight(62 + offset)
								portrait:SetHeight(62 + offset)
							else
								frame:SetHeight(62)
								portrait:SetHeight(62)
							end
							stats:SetHeight(40 + offset)
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
								end
							end
						elseif newstate == 2 then
							if extend then
								if bar then
									frame:SetHeight(62 + offset)
									portrait:SetHeight(62 + offset)
								else
									frame:SetHeight(62 + offset - 10)
									portrait:SetHeight(62 + offset - 10)
								end
							else
								if bar then
									frame:SetHeight(62)
									portrait:SetHeight(62)
								else
									frame:SetHeight(62)
									portrait:SetHeight(62)
								end
							end
							if bar then
								stats:SetHeight(40 + offset)
							else
								stats:SetHeight(40 + offset - 10)
							end
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									if bar then
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
									else
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset + 13.5)
									end
								end
							end
						elseif newstate == 3 then
							if extend then
								frame:SetHeight(62 + offset)
								portrait:SetHeight(62 + offset)
							else
								frame:SetHeight(62)
								portrait:SetHeight(62)
							end
							stats:SetHeight(40 + offset)
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
								end
							end
						elseif newstate == 4 then
							if extend then
								if bar then
									frame:SetHeight(62 + offset)
									portrait:SetHeight(62 + offset)
								else
									frame:SetHeight(62 + offset - 10)
									portrait:SetHeight(62 + offset - 10)
								end
							else
								if bar then
									frame:SetHeight(62)
									portrait:SetHeight(62)
								else
									frame:SetHeight(62)
									portrait:SetHeight(62)
								end
							end
							if bar then
								stats:SetHeight(40 + offset)
							else
								stats:SetHeight(40 + offset - 10)
							end
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									if bar then
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
									else
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset + 13.5)
									end
								end
							end
						else
							if extend then
								if bar then
									frame:SetHeight(62 + offset)
									portrait:SetHeight(62 + offset)
								else
									frame:SetHeight(62 + offset - 10)
									portrait:SetHeight(62 + offset - 10)
								end
							else
								if bar then
									frame:SetHeight(62)
									portrait:SetHeight(62)
								else
									frame:SetHeight(62)
									portrait:SetHeight(62)
								end
							end
							if bar then
								stats:SetHeight(40 + offset)
							else
								stats:SetHeight(40 + offset - 10)
							end
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									if bar then
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
									else
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset + 13.5)
									end
								end
							end
						end
					end
				elseif class == "PRIEST" then
					if spec == 1 or spec == 2 then
						if extend then
							frame:SetHeight(62 + offset)
							portrait:SetHeight(62 + offset)
						else
							frame:SetHeight(62)
							portrait:SetHeight(62)
						end
						if bar then
							stats:SetHeight(40 + offset)
						else
							stats:SetHeight(40 + offset - 10)
						end
						if not above and buffs then
							if extend then
								buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
							else
								if bar then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
								else
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset + 13.5)
								end
							end
						end
					elseif spec == 3 then
						if extend then
							frame:SetHeight(62 + offset)
							portrait:SetHeight(62 + offset)
						else
							frame:SetHeight(62)
							portrait:SetHeight(62)
						end
						stats:SetHeight(40 + offset)
						if not above and buffs then
							if extend then
								buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
							else
								buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
							end
						end
					end
				elseif class == "SHAMAN" then
					if spec == 1 then
						if newstate == 1 then
							if extend then
								if bar then
									frame:SetHeight(62 + offset)
									portrait:SetHeight(62 + offset)
								else
									frame:SetHeight(62 + offset - 10)
									portrait:SetHeight(62 + offset - 10)
								end
							else
								if bar then
									frame:SetHeight(62)
									portrait:SetHeight(62)
								else
									frame:SetHeight(62)
									portrait:SetHeight(62)
								end
							end
							if bar then
								stats:SetHeight(40 + offset)
							else
								stats:SetHeight(40 + offset - 10)
							end
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									if bar then
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
									else
										buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset + 13.5)
									end
								end
							end
						else
							if extend then
								frame:SetHeight(62 + offset)
								portrait:SetHeight(62 + offset)
							else
								frame:SetHeight(62)
								portrait:SetHeight(62)
							end
							stats:SetHeight(40 + offset)
							if not above and buffs then
								if extend then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
								else
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
								end
							end
						end
					elseif spec == 2 or spec == 3 then
						if extend then
							if bar then
								frame:SetHeight(62 + offset)
								portrait:SetHeight(62 + offset)
							else
								frame:SetHeight(62 + offset - 10)
								portrait:SetHeight(62 + offset - 10)
							end
						else
							frame:SetHeight(62)
							portrait:SetHeight(62)
						end
						if bar then
							stats:SetHeight(40 + offset)
						else
							stats:SetHeight(40 + offset - 10)
						end
						if not above and buffs then
							if extend then
								buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, 0)
							else
								if bar then
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset)
								else
									buffs:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 5, -buffoffset + 13.5)
								end
							end
						end
					end
				end

				frame:Show()
			end
		]])

		RegisterStateDriver(self.state, "petbattleupdate", "[petbattle] inpetbattle; [form:0] 0; [form:1] 1; [form:2] 2; [form:3] 3; [form:4] 4; none")
	end

	XPerl_Player_UpdateDisplay(self)

	--C_Timer.After(0.1, function() XPerl_Player_Set_Bits(self) end)
end

-- UNIT_COMBAT
function XPerl_Player_Events:UNIT_COMBAT(unit, action, descriptor, damage, damageType)
	if unit ~= self.partyid then
		return
	end

	if (pconf.hitIndicator and pconf.portrait) then
		CombatFeedback_OnCombatEvent(self, action, descriptor, damage, damageType)
	end

	if (action == "HEAL") then
		XPerl_Player_CombatFlash(self, 0, true, true)
	elseif (damage and damage > 0) then
		XPerl_Player_CombatFlash(self, 0, true)
	end
end

-- UNIT_PORTRAIT_UPDATE
function XPerl_Player_Events:UNIT_PORTRAIT_UPDATE()
	XPerl_Unit_UpdatePortrait(self, true)
end

-- VARIABLES_LOADED
function XPerl_Player_Events:VARIABLES_LOADED()

	self.doubleCheckAFK = 2 -- Check during 2nd UPDATE_FACTION, which are the last guarenteed events to come after logging in
	self:UnregisterEvent("VARIABLES_LOADED")

	local events = {
		"PLAYER_ENTERING_WORLD",
		"PARTY_LEADER_CHANGED",
		"PARTY_LOOT_METHOD_CHANGED",
		"GROUP_ROSTER_UPDATE",
		"PLAYER_UPDATE_RESTING",
		"PLAYER_REGEN_ENABLED",
		"PLAYER_REGEN_DISABLED",
		"PLAYER_ENTER_COMBAT",
		"PLAYER_LEAVE_COMBAT",
		"PLAYER_DEAD",
		"PLAYER_SPECIALIZATION_CHANGED",
		"UPDATE_FACTION",
		"UNIT_AURA",
		"PLAYER_CONTROL_LOST",
		"PLAYER_CONTROL_GAINED",
		"UNIT_COMBAT",
		"UNIT_POWER_FREQUENT",
		"UNIT_MAXPOWER",
		XPerl_ForeverAPI.healthEvent,
		"UNIT_MAXHEALTH",
		"UNIT_LEVEL",
		"UNIT_DISPLAYPOWER",
		"UNIT_NAME_UPDATE",
		"UNIT_FACTION",
		"UNIT_PORTRAIT_UPDATE",
		"UNIT_FLAGS",
		"PLAYER_FLAGS_CHANGED",
		"UNIT_ENTERED_VEHICLE",
		"UNIT_EXITING_VEHICLE",
		--"UNIT_PET",
		"PLAYER_TALENT_UPDATE",
		"RAID_TARGET_UPDATE",
		"UPDATE_SHAPESHIFT_FORM",
		"UPDATE_EXHAUSTION",
		--"PET_BATTLE_OPENING_START",
		--"PET_BATTLE_CLOSE",
		"INCOMING_RESURRECT_CHANGED",
	}

	for i, event in pairs(events) do
		if string.find(event, "^UNIT_") or string.find(event, "^INCOMING") then
			if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITING_VEHICLE" then
				if pcall(self.RegisterUnitEvent, self, event, "player") then
					self:RegisterUnitEvent(event, "player")
				end
			else
				if pcall(self.RegisterUnitEvent, self, event, "player", "vehicle") then
					self:RegisterUnitEvent(event, "player", "vehicle")
				end
			end
		else
			if pcall(self.RegisterEvent, self, event) then
				self:RegisterEvent(event)
			end
		end
	end

	--XPerl_Player_UpdateDisplay(self)

	XPerl_Player_Events.VARIABLES_LOADED = nil
end

function XPerl_Player_Events:UPDATE_EXHAUSTION()
	XPerl_Player_UpdateXP(self)
end

-- PARTY_LOOT_METHOD_CHANGED
function XPerl_Player_Events:PARTY_LOOT_METHOD_CHANGED()
	XPerl_Player_UpdateLeader(self)
end

-- PARTY_LEADER_CHANGED
function XPerl_Player_Events:PARTY_LEADER_CHANGED()
	XPerl_Player_UpdateLeader(self)
end

-- GROUP_ROSTER_UPDATE
function XPerl_Player_Events:GROUP_ROSTER_UPDATE()
	XPerl_Player_UpdateLeader(self)
end

-- UNIT_HEALTH_FREQUENT
function XPerl_Player_Events:UNIT_HEALTH_FREQUENT()
	XPerl_Player_UpdateHealth(self)
end

-- UNIT_HEALTH
function XPerl_Player_Events:UNIT_HEALTH()
	XPerl_Player_UpdateHealth(self)
end

-- UNIT_MAXHEALTH
function XPerl_Player_Events:UNIT_MAXHEALTH()
	XPerl_Player_UpdateHealth(self)
end

-- PLAYER_DEAD
function XPerl_Player_Events:PLAYER_DEAD()
	XPerl_Player_UpdateHealth(self)
end

-- UNIT_POWER_FREQUENT
function XPerl_Player_Events:UNIT_POWER_FREQUENT()
	XPerl_Player_UpdateMana(self)
end

-- UNIT_MAXPOWER
function XPerl_Player_Events:UNIT_MAXPOWER()
	XPerl_Player_UpdateMana(self)
end

-- UNIT_DISPLAYPOWER
function XPerl_Player_Events:UNIT_DISPLAYPOWER()
	XPerl_Player_UpdateManaType(self)
	XPerl_Player_UpdateMana(self)
end

-- UNIT_NAME_UPDATE
function XPerl_Player_Events:UNIT_NAME_UPDATE()
	XPerl_Player_UpdateName(self)
end

-- UNIT_LEVEL
function XPerl_Player_Events:UNIT_LEVEL()
	XPerl_Player_UpdateLevel(self)
	XPerl_Player_UpdateXP(self)
end

-- PLAYER_XP_UPDATE
function XPerl_Player_Events:PLAYER_XP_UPDATE()
	XPerl_Player_UpdateXP(self)
end

-- UPDATE_FACTION
function XPerl_Player_Events:UPDATE_FACTION()
	XPerl_Player_UpdateRep(self)

	if (self.doubleCheckAFK) then
		if (conf and pconf) then
			self.doubleCheckAFK = self.doubleCheckAFK - 1
			if (self.doubleCheckAFK <= 0) then
				XPerl_Player_UpdateHealth(self)
				self.doubleCheckAFK = nil
			end
		end
	end
end

-- UNIT_FACTION
function XPerl_Player_Events:UNIT_FACTION()
	XPerl_Player_UpdateHealth(self)
	XPerl_Player_UpdatePVP(self)
	XPerl_Player_UpdateCombat(self)
end
XPerl_Player_Events.UNIT_FLAGS = XPerl_Player_Events.UNIT_FACTION

function XPerl_Player_Events:PLAYER_FLAGS_CHANGED()
	XPerl_Player_UpdateHealth(self)
	XPerl_Player_UpdatePVPTimer(self)
end

-- RAID_TARGET_UPDATE
function XPerl_Player_Events:RAID_TARGET_UPDATE()
	XPerl_Player_UpdateRaidTarget(XPerl_Player)
end

-- PLAYER_TALENT_UPDATE
function XPerl_Player_Events:PLAYER_TALENT_UPDATE()
	XPerl_Player_UpdateMana(self)
end

-- UPDATE_SHAPESHIFT_FORM
function XPerl_Player_Events:UPDATE_SHAPESHIFT_FORM()
	if (playerClass == "DRUID") or (playerClass == "SHAMAN") or (playerClass == "PRIEST") then
		XPerl_Player_DruidBarUpdate(self)
	end
end

-- PLAYER_ENTER_COMBAT, PLAYER_LEAVE_COMBAT
function XPerl_Player_Events:PLAYER_ENTER_COMBAT()
	XPerl_Player_UpdateCombat(self)
end
XPerl_Player_Events.PLAYER_LEAVE_COMBAT = XPerl_Player_Events.PLAYER_ENTER_COMBAT

-- PLAYER_REGEN_ENABLED
function XPerl_Player_Events:PLAYER_REGEN_ENABLED()
	XPerl_Player_UpdateCombat(self)

	if (self:GetAttribute("unit") ~= self.partyid) then
		self:SetAttribute("unit", self.partyid)
		XPerl_Player_UpdateDisplay(self)
	end
end

-- PLAYER_REGEN_DISABLED
function XPerl_Player_Events:PLAYER_REGEN_DISABLED()
	XPerl_Player_UpdateCombat(self)
end

function XPerl_Player_Events:PLAYER_UPDATE_RESTING()
	XPerl_Player_UpdateCombat(self)
	XPerl_Player_UpdateXP(self)
end

function XPerl_Player_Events:PLAYER_SPECIALIZATION_CHANGED()
	if not InCombatLockdown() then
		if not IsClassic and GetSpecialization then
			self.state:SetAttribute("playerSpec", GetSpecialization())
		end
		XPerl_Player_Set_Bits(self)
	end

	if XPerl_Player_Buffs_Position then
		XPerl_Player_Buffs_Position(XPerl_Player)
	end
end

function XPerl_Player_Events:UNIT_AURA()
	XPerl_Player_UpdateBuffs(self)
end

-- PLAYER_CONTROL_LOST
function XPerl_Player_Events:PLAYER_CONTROL_LOST()
	if pconf.fullScreen.enable and not UnitOnTaxi("player") then
		isOutOfControl = true
	end
end

-- PLAYER_CONTROL_GAINED
function XPerl_Player_Events:PLAYER_CONTROL_GAINED()
	isOutOfControl = nil
	if (pconf.fullScreen.enable) then
		XPerl_PlayerStatus_OnUpdate(self)
	end
end

-- UNIT_ENTERED_VEHICLE
function XPerl_Player_Events:UNIT_ENTERED_VEHICLE(showVehicle)
	if showVehicle then
		self.partyid = "vehicle"
		self.unit = self.partyid
		if pconf.showRunes and self.runes then
			if self.runes.child then
				self.runes.child.unit = self.partyid
				if self.runes.child.Setup then
					self.runes.child:Setup()
				end
				if self.runes.child.OnLoad then
					self.runes.child:OnLoad()
				end
			end
			if self.runes.child3 then
				if self.runes.child3.OnLoad then
					self.runes.child3:OnLoad()
				end
			end
			if self.runes.child2 then
				self.runes.child2:Hide()
			end
		end
		if XPerl_ArcaneBar_SetUnit then
			XPerl_ArcaneBar_SetUnit(self.nameFrame, "vehicle")
		end
		XPerl_Player_UpdateDisplay(self)
		--XPerl_SetUnitNameColor(self.nameFrame.text, self.partyid)
	end
end

-- UNIT_EXITING_VEHICLE
function XPerl_Player_Events:UNIT_EXITING_VEHICLE()
	if self.partyid ~= "player" then
		self.partyid = "player"
		self.unit = self.partyid
		if pconf.showRunes and self.runes then
			if self.runes.child then
				self.runes.child.unit = self.partyid
				if self.runes.child.Setup then
					self.runes.child:Setup()
				end
				if self.runes.child.OnLoad then
					self.runes.child:OnLoad()
				end
			end
			if self.runes.child2 then
				local _, playerClass = UnitClass(self.partyid)
				if playerClass == self.runes.child2.requiredClass then
					if playerClass == "DRUID" and EclipseBarFrame then
						EclipseBarFrame:UpdateShown()
					elseif playerClass == "PALADIN" or playerClass == "WARLOCK" then
						self.runes.child2:Show()
					end
				end
			end
			if self.runes.child3 then
				if self.runes.child3.OnLoad then
					self.runes.child3:OnLoad()
				end
			end
		end
		if XPerl_ArcaneBar_SetUnit then
			XPerl_ArcaneBar_SetUnit(self.nameFrame, "player")
		end
		XPerl_Player_UpdateDisplay(self)
	end
end

function XPerl_Player_Events:UNIT_HEAL_PREDICTION(unit)
	if pconf.healprediction and unit == self.partyid then
		XPerl_SetExpectedHealth(self)
	end
end

function XPerl_Player_Events:UNIT_ABSORB_AMOUNT_CHANGED(unit)
	if (pconf.absorbs and unit == self.partyid) then
		XPerl_SetExpectedAbsorbs(self)
	end
end

function XPerl_Player_Events:INCOMING_RESURRECT_CHANGED(unit)
	if unit == self.partyid then
		XPerl_Player_UpdateResurrectionStatus(self)
	end
end

-- XPerl_Player_SetWidth
function XPerl_Player_SetWidth(self)
	pconf.size.width = max(0, pconf.size.width or 0)
	if (pconf.percent) then
		self.nameFrame:SetWidth(160 + pconf.size.width)
		self.statsFrame:SetWidth(160 + pconf.size.width)
		self.statsFrame.healthBar.percent:Show()
		self.statsFrame.manaBar.percent:Show()

		if (self.statsFrame.xpBar) then
			self.statsFrame.xpBar.percent:Show()
		end
		if (self.statsFrame.repBar) then
			self.statsFrame.repBar.percent:Show()
		end
	else
		self.nameFrame:SetWidth(128 + pconf.size.width)
		self.statsFrame:SetWidth(128 + pconf.size.width)
		self.statsFrame.healthBar.percent:Hide()
		self.statsFrame.manaBar.percent:Hide()
		if (self.statsFrame.xpBar) then
			self.statsFrame.xpBar.percent:Hide()
		end
		if (self.statsFrame.repBar) then
			self.statsFrame.repBar.percent:Hide()
		end
	end

	local h = 40 + ((((self.statsFrame.druidBar and self.statsFrame.druidBar:IsShown()) and 1 or 0) + (pconf.repBar and 1 or 0) + (pconf.xpBar and 1 or 0)) * 10)
	self.statsFrame:SetHeight(h)

	self:SetWidth(128 + (pconf.portrait and 1 or 0) * 62 + (pconf.percent and 1 or 0) * 32 + pconf.size.width)
	self:SetScale(pconf.scale)

	XPerl_StatsFrameSetup(self, {self.statsFrame.druidBar, self.statsFrame.xpBar, self.statsFrame.repBar})
	if (XPerl_Player_Buffs_Position) then
		XPerl_Player_Buffs_Position(self)
	end

	XPerl_Player_UpdateHealth(self)
	XPerl_Player_UpdateMana(self)
	XPerl_Player_UpdateXP(self)

	XPerl_SavePosition(self, true)
	XPerl_RestorePosition(self)
end

-- MakeXPBar
local function MakeXPBar(self)
	local f = CreateBar(self, "xpBar")
	local f2 = CreateBar(self, "xpRestBar")

	f2:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	f2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

	MakeXPBar = nil
end

-- XPerl_Player_Set_Bits()
function XPerl_Player_Set_Bits(self)
	if (XPerl_ArcaneBar_RegisterFrame and not self.nameFrame.castBar) then
		XPerl_ArcaneBar_RegisterFrame(self.nameFrame, "player")
	end

	if not InCombatLockdown() then
		self.state:SetAttribute("extendedPortrait", pconf.extendPortrait)
		self.state:SetAttribute("druidBarOff", pconf.noDruidBar)
		self.state:SetAttribute("xpBar", pconf.xpBar)
		self.state:SetAttribute("repBar", pconf.repBar)
		self.state:SetAttribute("spec", pconf.showRunes)
		self.state:SetAttribute("specDock", pconf.dockRunes)
	end

	if (pconf.level) then
		self.levelFrame:Show()
	else
		self.levelFrame:Hide()
	end

	XPerl_Player_UpdateClass(self)

	if (pconf.repBar) then
		if (not self.statsFrame.repBar) then
			CreateBar(self, "repBar")
		end

		self.statsFrame.repBar:Show()
	else
		if (self.statsFrame.repBar) then
			self.statsFrame.repBar:Hide()
		end
	end

	if (pconf.xpBar) then
		if (not self.statsFrame.xpBar) then
			MakeXPBar(self)
		end

		self.statsFrame.xpBar:Show()
		self.statsFrame.xpRestBar:Show()

		self:RegisterEvent("PLAYER_XP_UPDATE")
	else
		if (self.statsFrame.xpBar) then
			self.statsFrame.xpBar:Hide()
			self.statsFrame.xpRestBar:Hide()
		end

		self:UnregisterEvent("PLAYER_XP_UPDATE")
	end

	if (pconf.values) then
		self.statsFrame.healthBar.text:Show()
		self.statsFrame.manaBar.text:Show()
		if (self.statsFrame.druidBar) then
			self.statsFrame.druidBar.text:Show()
		end
		if (self.statsFrame.xpBar) then
			self.statsFrame.xpBar.text:Show()
		end
		if (self.statsFrame.repBar) then
			self.statsFrame.repBar.text:Show()
		end
	else
		self.statsFrame.healthBar.text:Hide()
		self.statsFrame.manaBar.text:Hide()
		if (self.statsFrame.druidBar) then
			self.statsFrame.druidBar.text:Hide()
		end
		if (self.statsFrame.xpBar) then
			self.statsFrame.xpBar.text:Hide()
		end
		if (self.statsFrame.repBar) then
			self.statsFrame.repBar.text:Hide()
		end
	end

	XPerl_Register_Prediction(self, pconf, function (guid)
		if guid == UnitGUID("player") then
			return "player"
		elseif guid == UnitGUID("vehicle") then
			return "vehicle"
		end
	end, "player", "vehicle")

	if (playerClass == "DRUID") or (playerClass == "SHAMAN") or (playerClass == "PRIEST") then
		XPerl_Player_DruidBarUpdate(self)
	end

	if not InCombatLockdown() then
		if (pconf.portrait) then
			self.portraitFrame:Show()
			self.portraitFrame:SetWidth(62)
			self.statsFrame.resurrect:Hide()
		else
			self.portraitFrame:Hide()
			self.portraitFrame:SetWidth(3)
		end

		XPerl_Player_SetWidth(self)

		local h1 = self.nameFrame:GetHeight() + self.statsFrame:GetHeight() - 2
		local h2 = self.portraitFrame:GetHeight()
		XPerl_SwitchAnchor(self, "TOPLEFT")
		self:SetHeight(max(h1, h2))

		if (pconf.extendPortrait) then
			local druidBarExtra
			if (UnitPowerType(self.partyid) > 0 and not pconf.noDruidBar) and ((playerClass == "DRUID") or (playerClass == "PRIEST")) then
				druidBarExtra = 1
			else
				druidBarExtra = 0
			end

			self:SetHeight(62 + druidBarExtra * 10 + (((pconf.xpBar and 1 or 0) + (pconf.repBar and 1 or 0)) * 10))
			self.portraitFrame:SetHeight(62 + druidBarExtra * 10 + (((pconf.xpBar and 1 or 0) + (pconf.repBar and 1 or 0)) * 10))
		else
			self:SetHeight(62)
			self.portraitFrame:SetHeight(62)
		end
	end

	if (self.runes) then
		if (pconf.showRunes) then
			self.runes:Show()
		else
			self.runes:Hide()
		end
	end

	self:SetAlpha(conf.transparency.frame)

	self.buffOptMix = nil
	XPerl_Player_UpdateDisplay(self)

	if (XPerl_Player_BuffSetup) then
		if (self.buffFrame) then
			self.buffOptMix = nil
			XPerl_Player_BuffSetup(XPerl_Player)
		end
	end

	if (XPerl_Voice) then
		XPerl_Voice:Register(self)
	end

	UpdateAssignedRoles(self)
end

local function MakeMoveable(frame)
	frame:SetMovable(true)
	frame:SetUserPlaced(true)
	frame:RegisterForDrag("LeftButton")

	frame:SetScript("OnDragStart", function(self)
		if (not pconf.dockRunes) then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		if (not pconf.dockRunes) then
			self:StopMovingOrSizing()
			XPerl_SavePosition(self)
		end
	end)
end
