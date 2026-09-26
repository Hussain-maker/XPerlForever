-- X-Perl UnitFrames
-- Author: Resike
-- License: GNU GPL v3, 29 June 2007 (see LICENSE.txt)

local XPerl_Target_Events = { }
local conf, tconf, fconf
XPerl_RequestConfig(function(new)
	conf = new
	tconf = conf.target
	fconf = conf.focus
	if (XPerl_Target) then
		XPerl_Target.conf = conf.target
	end
	if (XPerl_Focus) then
		XPerl_Focus.conf = conf.focus
	end
	if (XPerl_TargetTarget) then
		XPerl_TargetTarget.conf = conf.targettarget
	end
	if (XPerl_FocusTarget) then
		XPerl_FocusTarget.conf = conf.focustarget
	end
	if (XPerl_PetTarget) then
		XPerl_PetTarget.conf = conf.pettarget
	end
end, "$Revision:  $")

local IsVanillaClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC

-- Z-Perl Forever: secret value helpers from XPerlForever.lua
local XPerl_CanAccess = XPerl_CanAccess
local XPerl_IsSecret = XPerl_IsSecret
local XPerl_GetPowerPercent = XPerl_GetPowerPercent
local XPerl_GetHealthPercent = XPerl_GetHealthPercent
local XPerl_SetAlphaFromBoolean = XPerl_SetAlphaFromBoolean
local XPerl_SafeBool = XPerl_SafeBool
local XPerl_AurasSecret = XPerl_AurasSecret
local XPerl_AuraContainer_SafeToReconfigure = XPerl_AuraContainer_SafeToReconfigure

local LCD = IsVanillaClassic and XPerl_ForeverAPI and XPerl_ForeverAPI.combatLog and LibStub and LibStub("LibClassicDurations", true)
if LCD then
	LCD.RegisterCallback("ZPerl", "UNIT_BUFF", function(event, unit)
		if unit ~= "target" then
			return
		end
		XPerl_Target_Events:UNIT_AURA(event, unit)
	end)
end

-- Upvalues
local _G = _G
local bit_band = bit.band
local format = format
local max = max
local pairs = pairs
local pcall = pcall
local select = select
local string = string
local tinsert = tinsert
local tonumber = tonumber
local tostring = tostring
local type = type
local unpack = unpack
local setmetatable = setmetatable
local hooksecurefunc = hooksecurefunc

local Enum = Enum

local CanInspect = CanInspect
local CheckInteractDistance = CheckInteractDistance
local CombatFeedbackText = CombatFeedbackText
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local GetComboPoints = GetComboPoints
local GetDifficultyColor = GetDifficultyColor or GetQuestDifficultyColor
local GetInspectSpecialization = GetInspectSpecialization
local GetLootMethod = GetLootMethod or C_PartyInfo.GetLootMethod
local GetNumGroupMembers = GetNumGroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local GetSpecializationInfoByID = GetSpecializationInfoByID
local GetSpellInfo = GetSpellInfo
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local NotifyInspect = NotifyInspect
local PlaySound = PlaySound
local RegisterUnitWatch = RegisterUnitWatch
local UnitAffectingCombat = UnitAffectingCombat
local UnitBattlePetType = UnitBattlePetType
local UnitCanAssist = UnitCanAssist
local UnitCanAttack = UnitCanAttack
local UnitClass = UnitClass
local UnitClassBase = UnitClassBase
local UnitClassification = UnitClassification
local UnitCreatureType = UnitCreatureType
local UnitExists = UnitExists
local UnitFactionGroup = UnitFactionGroup
local UnitGUID = UnitGUID
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitInParty = UnitInParty
local UnitInRaid = UnitInRaid
local UnitInRange = UnitInRange
local UnitInVehicle = UnitInVehicle
local UnitIsAFK = UnitIsAFK
local UnitIsBattlePet = UnitIsBattlePet
local UnitIsBattlePetCompanion = UnitIsBattlePetCompanion
local UnitIsCharmed = UnitIsCharmed
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsEnemy = UnitIsEnemy
local UnitIsFriend = UnitIsFriend
local UnitIsGhost = UnitIsGhost
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsMercenary = UnitIsMercenary
local UnitIsPlayer = UnitIsPlayer
local UnitIsPVP = UnitIsPVP
local UnitIsPVPFreeForAll = UnitIsPVPFreeForAll
local UnitIsUnit = UnitIsUnit
local UnitIsVisible = UnitIsVisible
local UnitIsWildBattlePet = UnitIsWildBattlePet
local UnitLevel = UnitLevel
local UnitName = UnitName
local UnitPlayerControlled = UnitPlayerControlled
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnregisterUnitWatch = UnregisterUnitWatch

local CombatFeedback_Initialize = CombatFeedback_Initialize
local CombatFeedback_OnUpdate = CombatFeedback_OnUpdate
local CombatFeedback_OnCombatEvent = CombatFeedback_OnCombatEvent

local percD = "%d"..PERCENT_SYMBOL
local buffSetup
local lastInspectPending = 0

--local feignDeath = GetSpellInfo and GetSpellInfo(5384) or (C_Spell.GetSpellInfo(5384) and C_Spell.GetSpellInfo(5384).name)

local ComboEventFrame = CreateFrame("Frame")
-- Forever protects combo-point values. Reparenting or registering Blizzard's
-- ComboFrame from addon code taints its own update path, so leave that frame
-- entirely under Blizzard control and use X-Perl's independent displays.
local canManageBlizzardComboFrame = ComboFrame and type(issecretvalue) ~= "function"

-- Forever still creates Blizzard's legacy combo-point widget, but touching that
-- protected frame from addon code taints its secret-value update path.  The
-- client CVar is the safe, supported way to suppress it while our replacement
-- is active (1 = target, 2 = player, 0 = hidden).
local function XPerlForever_HideBlizzardComboDisplay()
	if canManageBlizzardComboFrame then
		return
	end

	-- Some Forever builds expose this CVar but clamp/ignore its hidden value.
	-- Keep setting it for builds which honor it, then make the legacy artwork
	-- transparent as a fallback.  SetAlpha does not alter the frame's event
	-- registration, parent, unit data, or protected update flow.
	if SetCVar and GetCVar then
		local ok, value = pcall(GetCVar, "comboPointLocation")
		if ok and value ~= nil and value ~= "" and value ~= "0" then
			pcall(SetCVar, "comboPointLocation", 0)
		end
	end

	if ComboFrame and ComboFrame.SetAlpha then
		pcall(ComboFrame.SetAlpha, ComboFrame, 0)
	end
end

-- Native X-Perl Forever combo points. Each point is its own StatusBar with a
-- one-point range, so Blizzard can safely feed a protected combo value into it
-- without addon code comparing or inspecting that value.
local function XPerlForever_CreateComboDisplay(self)
	if self.foreverCombo then
		return
	end

	local holder = CreateFrame("Frame", self:GetName().."ForeverCombo", self)
	holder:SetSize(110, 10)
	holder:SetPoint("BOTTOMLEFT", self.nameFrame, "TOPLEFT", 4, 3)
	holder:SetFrameLevel(self.nameFrame:GetFrameLevel() + 3)
	holder.points = {}

	for i = 1, 7 do
		local point = CreateFrame("StatusBar", nil, holder, BackdropTemplateMixin and "BackdropTemplate")
		point:SetSize(14, 8)
		point:SetPoint("LEFT", holder, "LEFT", (i - 1) * 16, 0)
		point:SetStatusBarTexture(XPerl_GetBarTexture())
		point:SetMinMaxValues(i - 1, i)
		point:SetValue(0)
		point:SetStatusBarColor(1, 0.78, 0, 1)
		if point.SetBackdrop then
			point:SetBackdrop({edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 6})
			point:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
		end
		local background = point:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints()
		background:SetColorTexture(0.06, 0.06, 0.06, 0.9)
		holder.points[i] = point
	end

	holder:Hide()
	self.foreverCombo = holder
end

----------------------
-- Loading Function --
----------------------
function XPerl_Target_OnLoad(self, partyid)
	self:RegisterForClicks("AnyUp")
	self:RegisterForDrag("LeftButton")
	XPerl_SetChildMembers(self)

	CombatFeedback_Initialize(self, self.hitIndicator.text, 30)

	self.hitIndicator.text:SetPoint("CENTER", self.portraitFrame, "CENTER", 0, 0)

	local events = {
		"UNIT_COMBAT",
		"PLAYER_FLAGS_CHANGED",
		"UNIT_CONNECTION",
		"UNIT_PHASE",
		"RAID_TARGET_UPDATE",
		"GROUP_ROSTER_UPDATE",
		"PARTY_LEADER_CHANGED",
		"PARTY_LOOT_METHOD_CHANGED",
		"UNIT_THREAT_LIST_UPDATE",
		"UNIT_FACTION",
		"UNIT_FLAGS",
		"UNIT_CLASSIFICATION_CHANGED",
		"UNIT_PORTRAIT_UPDATE",
		"UNIT_AURA",
		XPerl_ForeverAPI.healthEvent,
		"UNIT_MAXHEALTH",
		"UNIT_POWER_FREQUENT",
		"UNIT_MAXPOWER",
		"UNIT_LEVEL",
		"UNIT_DISPLAYPOWER",
		"UNIT_NAME_UPDATE",
		--"PET_BATTLE_OPENING_START"
		--"PET_BATTLE_CLOSE",
		"INCOMING_RESURRECT_CHANGED",
	}
	for i, event in pairs(events) do
		if string.find(event, "^UNIT_") or string.find(event, "^INCOMING") then
			if pcall(self.RegisterUnitEvent, self, event, partyid) then
				self:RegisterUnitEvent(event, partyid)
			end
		else
			if pcall(self.RegisterEvent, self, event) then
				self:RegisterEvent(event)
			end
		end
	end

	XPerl_Highlight:Register(XPerl_Target_HighlightCallback, self)

	self.partyid = partyid
	if (partyid == "target") then
		XPerlForever_CreateComboDisplay(self)
		XPerl_BlizzFrameDisable(TargetFrame)
		XPerl_BlizzFrameDisable(TargetofTargetFrame)

		self.statsFrame.focusTarget:SetVertexColor(0.7, 1, 1, 0.5)

		self:RegisterEvent("PLAYER_TARGET_CHANGED")
		self:RegisterEvent("PLAYER_FOCUS_CHANGED")

		if (XPerl_Target_Events.INSPECT_READY) then
			self:RegisterEvent("INSPECT_READY")
		end

		self.nameFrame.cpMeter:SetFrameLevel(2)
		self.nameFrame.cpMeter:GetStatusBarTexture():SetHorizTile(false)
		self.nameFrame.cpMeter:GetStatusBarTexture():SetVertTile(false)

		-- Z-Perl Forever: retail has no ComboFrame (combo points live on the
		-- player frame there); the Blizzard combo option only works on Classic.
		if (canManageBlizzardComboFrame) then
			local parenting
			hooksecurefunc(ComboFrame, "SetParent", function(self)
				if parenting then
					return
				end
				if not InCombatLockdown() then
					parenting = true
					self:SetParent(XPerl_Target)
					parenting = nil
				end
			end)

			ComboFrame:SetParent(XPerl_Target)
		end

		self.combatMask = 0x00010000
	else
		XPerl_BlizzFrameDisable(FocusFrame)

		self:RegisterEvent("PLAYER_FOCUS_CHANGED")
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		--self:SetScript("OnShow", XPerl_Target_UpdateDisplay)
		self.combatMask = 0x00020000
	end
	--self:RegisterEvent("UNIT_COMBO_POINTS") -- Not a standard unit event, becuase we want events for "player" even tho it's "target" or "focus" unit frame
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")

	local BuffOnUpdate, DebuffOnUpdate, BuffUpdateTooltip, DebuffUpdateTooltip
	BuffUpdateTooltip = XPerl_Unit_SetBuffTooltip
	DebuffUpdateTooltip = XPerl_Unit_SetDeBuffTooltip

	if (buffSetup) then
		self.buffSetup = buffSetup
	else
		self.buffSetup = {
			rightClickable = true,
			buffScripts = {
				OnEnter = XPerl_Unit_SetBuffTooltip,
				OnUpdate = BuffOnUpdate,
				OnLeave = XPerl_PlayerTipHide,
				OnClick = function(self, button)
					if button == "RightButton" then
						local unitFrame = self:GetParent():GetParent()
						if unitFrame and unitFrame.partyid and UnitIsUnit(unitFrame.partyid, "player") then
							CancelUnitBuff("player", self:GetID(), self.filter)
						end
					end
				end,
			},
			debuffScripts = {
				OnEnter = XPerl_Unit_SetDeBuffTooltip,
				OnUpdate = DebuffOnUpdate,
				OnLeave = XPerl_PlayerTipHide,
			},
			updateTooltipBuff = BuffUpdateTooltip,
			updateTooltipDebuff = DebuffUpdateTooltip,
			debuffParent = true,
			debuffSizeMod = 0.2,
			debuffAnchor1 = function(self, b)
				b:SetPoint("TOPLEFT", 0, 0)
			end,
		}
		self.buffSetup.buffAnchor1 = self.buffSetup.debuffAnchor1
		buffSetup = self.buffSetup
	end

	--XPerl_SecureUnitButton_OnLoad(self.nameFrame, partyid, nil, TargetFrameDropDown, XPerl_ShowGenericMenu)		--TargetFrame.menu)
	--XPerl_SecureUnitButton_OnLoad(self, partyid, nil, TargetFrameDropDown, XPerl_ShowGenericMenu)				--TargetFrame.menu)
	--self.nameFrame:SetAttribute("useparent-unit", true)
	self.nameFrame:SetAttribute("*type1", "target")
	self.nameFrame:SetAttribute("type2", "togglemenu")
	self.nameFrame:SetAttribute("unit", partyid)

	self:SetAttribute("*type1", "target")
	self:SetAttribute("type2", "togglemenu")
	self:SetAttribute("unit", partyid)

	XPerl_RegisterClickCastFrame(self.nameFrame)
	XPerl_RegisterClickCastFrame(self)

	--RegisterUnitWatch(self)

	--self.PlayerFlash = 0
	self.perlBuffs, self.perlDebuffs, self.time = 0, 0, 0

	--XPerl_InitFadeFrame(self)

	if (partyid == "target" and XPerl_Target_AssistFrame) then
		-- Since target module is loaded after raid helper, we have to attach this manually
		-- because the target frame did not exist when this frame was created
		XPerl_Target_AssistFrame:SetParent(self)
		XPerl_Target_AssistFrame:ClearAllPoints()
		XPerl_Target_AssistFrame:SetPoint("TOPLEFT", self.portraitFrame, "TOPRIGHT", -2, -20)
		XPerl_Target_AssistFrame:Raise()
	end

	XPerl_RegisterHighlight(self.highlight, 3)
	XPerl_RegisterPerlFrames(self, {self.nameFrame, self.statsFrame, self.levelFrame, self.portraitFrame, self.typeFramePlayer, self.creatureTypeFrame, self.bossFrame, self.cpFrame})

	self.FlashFrames = {self.portraitFrame, self.nameFrame, self.levelFrame, self.statsFrame, self.bossFrame, self.typeFramePlayer, self.typeFrame}

	if (XPerl_ArcaneBar_RegisterFrame) then
		XPerl_ArcaneBar_RegisterFrame(self.nameFrame, partyid)
	end

	if (XPerlDB) then
		self.conf = XPerlDB[partyid]
	end

	XPerl_RegisterOptionChanger(XPerl_Target_Set_Bits, self)

	if (XPerl_Target and XPerl_Focus) then
		XPerl_Target_OnLoad = nil
	end
end

-- XPerl_Raid_HighlightCallback
function XPerl_Target_HighlightCallback(self, updateGUID)
	local guid = UnitGUID(self.partyid)
	if (guid and XPerl_CanAccess(guid) and guid == updateGUID and UnitIsFriend("player", self.partyid)) then
		XPerl_Highlight:SetHighlight(self, updateGUID)
	end
end

--------------------
-- Buff Functions --
--------------------

-- XPerl_Target_BuffPositions
local function XPerl_Target_BuffPositions(self)
	-- Z-Perl Forever: this raw UnitCanAttack matches the exact shape already
	-- fixed via XPerl_SafeBool in the sibling XPerl_TargetTarget_BuffPositions
	-- (pattern 12); ported here too, since self.partyid ("target"/"focus") is
	-- a direct unit whose identity -- and so this call -- can still be secret
	-- inside an instance (section 3).
	if (self.partyid and not self.conf.buffs.first and XPerl_SafeBool(UnitCanAttack("player", self.partyid), false)) then
		XPerl_Unit_BuffPositions(self, self.buffFrame.debuff, self.buffFrame.buff, self.conf.debuffs.size, self.conf.buffs.size)
	else
		XPerl_Unit_BuffPositions(self, self.buffFrame.buff, self.buffFrame.debuff, self.conf.buffs.size, self.conf.debuffs.size)
	end
end

-- Z-Perl Forever: AuraContainer fallback -- real icons while auras are secret.
-- See CLAUDE.md pattern 15 before changing any of this.

-- XPerl_Target_AuraContainer_Setup
local function XPerl_Target_AuraContainer_Setup(self)
	if (not XPerl_HasAuraContainerNow() or self.buffContainer) then
		return
	end

	local canAttack = XPerl_SafeBool(UnitCanAttack("player", self.partyid), false)
	local buffsFirst = self.conf.buffs.first or not canAttack
	-- Same rules as XPerl_Unit_UpdateBuffs: "only mine" is for friendly buffs and
	-- enemy debuffs, "curable" only for friendly debuffs. Blizzard applies them.
	local buffFilter = "HELPFUL"..(self.conf.buffs.castable == 1 and "|RAID" or "")..((self.conf.buffs.onlyMine and not canAttack) and "|PLAYER" or "")
	local debuffFilter = "HARMFUL"..((not canAttack and self.conf.debuffs.curable == 1) and "|RAID" or "")..((self.conf.debuffs.onlyMine and canAttack) and "|PLAYER" or "")
	-- XPerlDB.buffs.cooldown is a single global setting shared by buffs and
	-- debuffs by design (its own options-panel description says so) -- there
	-- is no XPerlDB.debuffs table. Do not split this into a per-type value.
	local showSwipe = conf.buffs.cooldown and true or false
	-- Wrap at the frame's full width, the same row width as the normal layout
	-- (XPerl_Unit_BuffSpacing), not the narrower buffFrame
	local lineSize = 2000
	if (self.conf.buffs.wrap) then
		lineSize = self.statsFrame:GetWidth()
		if (self.portraitFrame and self.portraitFrame:IsShown()) then
			lineSize = lineSize - 2 + self.portraitFrame:GetWidth()
		end
		if (self.levelFrame and self.levelFrame:IsShown()) then
			lineSize = lineSize - 2 + self.levelFrame:GetWidth()
		end
	end

	-- Same row limit as the normal layout ("Target Buff Rows"): at most that many
	-- rows of icons per group when wrapping
	local rows = self.conf.buffs.rows
	local function MaxIcons(size)
		if (self.conf.buffs.wrap and rows and rows > 0) then
			return min(40, max(1, floor((lineSize + 1) / (size + 1))) * rows)
		end
	end
	local buffMax, debuffMax = MaxIcons(self.conf.buffs.size), MaxIcons(self.conf.debuffs.size)
	-- "Key Enemy Buffs": on enemies show only important buffs, then purgeable ones
	-- (a second group, so an aura that is both appears once)
	local keyBuffs = self.conf.buffs.keyOnly and canAttack
	if (keyBuffs) then
		buffFilter = "HELPFUL|IMPORTANT"
	end

	-- buffFrame and debuffFrame are one XML rectangle, so each container takes
	-- half, friend/enemy deciding which goes on top.
	local buffContainer, buffHalf = XPerl_AuraContainer_Create(self, "buffHalfFrame",
		self:GetName().."AuraBuffs", "buffs", buffFilter, self.conf.buffs.size, lineSize, showSwipe, buffMax)
	if (keyBuffs) then
		XPerl_AuraContainer_AddGroup(self, buffContainer, "buffsPurgeable", "HELPFUL|DISPELLABLE|!IMPORTANT", self.conf.buffs.size, showSwipe, buffMax, 2)
	end
	local debuffContainer, debuffHalf = XPerl_AuraContainer_Create(self, "debuffHalfFrame",
		self:GetName().."AuraDebuffs", "debuffs", debuffFilter, self.conf.debuffs.size, lineSize, showSwipe, debuffMax)

	local firstHalf, secondHalf = buffHalf, debuffHalf
	if (not buffsFirst) then
		firstHalf, secondHalf = debuffHalf, buffHalf
	end
	firstHalf:ClearAllPoints()
	firstHalf:SetPoint("TOPLEFT", self.buffFrame, "TOPLEFT", 0, 0)
	firstHalf:SetPoint("BOTTOMRIGHT", self.buffFrame, "RIGHT", 0, 0)
	-- The second group starts right below the first group's icons, so it moves
	-- up into the first row when the first group is empty
	local firstContainer = buffsFirst and buffContainer or debuffContainer
	secondHalf:ClearAllPoints()
	secondHalf:SetPoint("TOPLEFT", firstContainer, "BOTTOMLEFT", 0, -1)
	secondHalf:SetPoint("RIGHT", self.buffFrame, "RIGHT", 0, 0)
	secondHalf:SetHeight(1)

	self.buffContainer, self.debuffContainer = buffContainer, debuffContainer
end

-- XPerl_Target_AuraContainer_Rebuild
local function XPerl_Target_AuraContainer_Rebuild(self)
	if (not XPerl_HasAuraContainerNow()) then
		return
	end
	-- Nothing live to disturb yet, so build even while secret -- otherwise a
	-- container nil'd mid-fight stays blank until combat ends.
	if (not self.buffContainer) then
		XPerl_Target_AuraContainer_Setup(self)
		return
	end
	if (not XPerl_AuraContainer_SafeToReconfigure()) then
		self.auraContainerPending = true
		return
	end
	self.auraContainerPending = nil
	if (self.buffContainer) then
		self.buffContainer:Hide()
		self.debuffContainer:Hide()
		self.buffContainer, self.debuffContainer = nil, nil
	end
	XPerl_Target_AuraContainer_Setup(self)
end

-- XPerl_Target_AuraContainer_Show / _Hide
local function XPerl_Target_AuraContainer_Show(self)
	XPerl_AuraContainer_ShowPair(self, self.conf.buffs.enable, self.conf.debuffs.enable)
end

local function XPerl_Target_AuraContainer_Hide(self)
	self.buffContainer:Hide()
	self.debuffContainer:Hide()
	if (self.auraContainerPending) then
		XPerl_Target_AuraContainer_Rebuild(self)
	end
end

-- XPerl_Targets_BuffUpdate
function XPerl_Targets_BuffUpdate(self)
	if (not self.conf.buffs.enable and not self.conf.debuffs.enable) then
		self.buffFrame:Hide()
		self.debuffFrame:Hide()
		if (self.buffContainer) then
			XPerl_Target_AuraContainer_Hide(self)
		end
	elseif (self.buffContainer and XPerl_AurasSecret()) then
		self.buffFrame:Hide()
		self.debuffFrame:Hide()
		XPerl_Target_AuraContainer_Show(self)
	else
		if (self.buffContainer) then
			XPerl_Target_AuraContainer_Hide(self)
			self.buffFrame:Show()
			self.debuffFrame:Show()
		end
		XPerl_Unit_UpdateBuffs(self, nil, nil, self.conf.buffs.castable, self.conf.debuffs.curable)
		XPerl_Target_BuffPositions(self)
	end
end

-- GetComboColor
local function GetComboColor(num)
	if (num == 10) then
		return 0.3, 0, 1
	elseif (num == 9) then
		return 0.5, 0, 1
	elseif (num == 8) then
		return 0.7, 0, 1
	elseif (num == 7) then
		return 1, 0, 1
	elseif (num == 6) then
		return 1, 0, 0.5
	elseif (num == 5) then
		return 1, 0, 0
	elseif (num == 4) then
		return 1, 0.5, 0
	elseif (num == 3) then
		return 1, 1, 0
	elseif (num == 2) then
		return 0.5, 1, 0
	elseif (num == 1) then
		return 0, 1, 0
	end
end

---------------
-- Combo Points
---------------
local function XPerl_Target_UpdateCombo(self)
	local comboPoints = UnitPower("player", Enum.PowerType.ComboPoints)
	local maxComboPoints = UnitPowerMax("player", Enum.PowerType.ComboPoints)
	local hostile = XPerl_SafeBool(UnitCanAttack(UnitHasVehicleUI("player") and "vehicle" or "player", "target"), true)
	local dead = XPerl_SafeBool(UnitIsDeadOrGhost("target"), false)
	local showForeverCombo = tconf.combo.enable or tconf.comboindicator.enable or (tconf.combo.blizzard and not canManageBlizzardComboFrame)

	if self.foreverCombo then
		if showForeverCombo and hostile and not dead then
			local visiblePoints = 5
			if XPerl_CanAccess(maxComboPoints) then
				visiblePoints = max(1, min(7, maxComboPoints))
			end
			for i, point in ipairs(self.foreverCombo.points) do
				if i <= visiblePoints then
					point:SetMinMaxValues(i - 1, i)
					point:SetValue(comboPoints)
					if i == visiblePoints then
						point:SetStatusBarColor(1, 0.18, 0.05, 1)
					else
						point:SetStatusBarColor(1, 0.78, 0, 1)
					end
					point:Show()
				else
					point:Hide()
				end
			end
			self.foreverCombo:Show()
		else
			self.foreverCombo:Hide()
		end
	end

	-- Z-Perl Forever: comboPoints can be secret; GetComboColor's num == n chain can't
	-- run on it, but StatusBar:SetValue / FontString:SetText below accept it raw
	local r, g, b
	if not XPerl_IsSecret(comboPoints) then
		r, g, b = GetComboColor(comboPoints)
	end
	if tconf.combo.enable and not XPerl_IsSecret(comboPoints) and not dead and hostile then
		self.nameFrame.cpMeter:SetValue(comboPoints)
		self.nameFrame.cpMeter:Show()
		if r and g and b then
			self.nameFrame.cpMeter:SetStatusBarColor(r, g, b, 0.7)
		else
			self.nameFrame.cpMeter:Hide()
		end
	else
		self.nameFrame.cpMeter:Hide()
	end

	if tconf.comboindicator.enable and not XPerl_IsSecret(comboPoints) and not dead and hostile then
		self.cpFrame:Show()
		self.cpFrame.text:SetText(comboPoints)
		if r and g and b then
			self.cpFrame.text:SetTextColor(r, g, b)
		else
			self.cpFrame:Hide()
		end
	else
		self.cpFrame:Hide()
	end
end

-------------------------
-- The Update Functions--
-------------------------
local function XPerl_Target_UpdatePVP(self)
	local partyid = self.partyid

	local pvpIcon = self.nameFrame.pvp

	local factionGroup, factionName = UnitFactionGroup(partyid)

	if self.conf.pvpIcon and XPerl_SafeBool(UnitIsPVPFreeForAll(partyid), false) then
		pvpIcon.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-FFA")
		pvpIcon:Show()
	elseif self.conf.pvpIcon and factionGroup and factionGroup ~= "Neutral" and XPerl_SafeBool(UnitIsPVP(partyid), false) then
		pvpIcon.icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-"..factionGroup)

		if type(UnitIsMercenary) == "function" and XPerl_SafeBool(UnitIsMercenary(partyid), false) then
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

	if (self.conf.reactionHighlight) then
		local c = XPerl_ReactionColour(partyid)
		self.nameFrame:SetBackdropColor(c.r, c.g, c.b)

		if (conf.colour.class and UnitPlayerControlled(partyid)) then
			XPerl_SetUnitNameColor(self.nameFrame.text, partyid)
		else
			self.nameFrame.text:SetTextColor(1, 1, 1, conf.transparency.text)
		end
	else
		if not self.conf.highlightDebuffs.enable then
			self.nameFrame:SetBackdropColor(conf.colour.frame.r, conf.colour.frame.g, conf.colour.frame.b, conf.colour.frame.a)
		end
		XPerl_SetUnitNameColor(self.nameFrame.text, partyid)
	end

	-- Z-Perl Forever: indirect units can return secret flags; no icon in that case
	if XPerl_SafeBool(UnitIsVisible(partyid), false) and XPerl_SafeBool(UnitIsCharmed(partyid), false) and XPerl_SafeBool(UnitIsPlayer(partyid), false) then
		self.nameFrame.warningIcon:Show()
	else
		self.nameFrame.warningIcon:Hide()
	end
end

-- XPerl_Target_UpdateName
local function XPerl_Target_UpdateName(self)
	-- Z-Perl Forever: UnitName's second value used to be a rare cross-realm
	-- suffix; on Forever it's a mandatory surname that's sent for every player
	-- who has chosen to show it, so it can no longer be silently dropped here
	self.nameFrame.text:SetText(XPerl_UnitFullName(self.partyid))
	XPerl_Target_UpdatePVP(self)
end

-- XPerl_Target_UpdateLevel
local function XPerl_Target_UpdateLevel(self)
	local targetlevel = UnitLevel(self.partyid)
	self.levelFrame.text:SetText(targetlevel)
	-- Set Level
	if (self.conf.level) then
		self.levelFrame:Show()
		self.levelFrame.skull:Hide()
		self.levelFrame:SetWidth(27)
		if (not XPerl_CanAccess(targetlevel)) then
			-- Z-Perl Forever: creature levels are secret inside instances
			self.levelFrame.text:SetTextColor(1, 1, 1)
			self.levelFrame.text:Show()
		elseif (targetlevel < 0) then
			self.levelFrame.text:Hide()
			self.levelFrame.skull:Show()
		else
			local color = GetDifficultyColor(targetlevel)
			self.levelFrame.text:SetTextColor(color.r, color.g, color.b)
			self.levelFrame.text:Show()
			local classification = UnitClassification(self.partyid)
			if (not self.conf.elite and XPerl_CanAccess(classification) and (classification == "elite" or classification == "worldboss")) then
				self.levelFrame.text:SetFormattedText("%d+", targetlevel)
				self.levelFrame:SetWidth(33)
			end
		end
	end
end

-- XPerl_Target_UpdateClassification
local function XPerl_Target_UpdateClassification(self)
	local partyid = self.partyid
	local targetclassification = UnitClassification(partyid)
	local bossType, eliteGfx

	if (not XPerl_CanAccess(targetclassification)) then
		-- Z-Perl Forever: the classification is secret, nothing can be decided
		self.bossFrame:Hide()
		self.eliteFrame:Hide()
		self.typeFramePlayer:Hide()
		return
	end

	if (targetclassification == "normal" and UnitPlayerControlled(partyid)) then
		if (not UnitIsPlayer(partyid)) then
			bossType = XPERL_TYPE_PET
			self.bossFrame.text:SetTextColor(1, 1, 1)
			self.typeFramePlayer:Hide()
		end

	elseif (self.conf.level or targetclassification == "rareelite" or targetclassification == "rare" or targetclassification == "elite" or targetclassification == "worldboss") then
	--elseif ((self.conf.level and self.conf.elite) or targetclassification == "Rare+" or targetclassification == "Rare") then
		if (self.conf.eliteGfx) then
			eliteGfx = true
			if (targetclassification == "worldboss" or targetclassification == "elite") then
				self.eliteFrame.tex:SetTexture("Interface\\AddOns\\XPerlForever\\Images\\XPerl_Elite")
				self.eliteFrame.tex:SetVertexColor(1, 1, 0, 1)
			elseif (targetclassification == "rareelite") then
				self.eliteFrame.tex:SetTexture("Interface\\AddOns\\XPerlForever\\Images\\XPerl_Elite")
				self.eliteFrame.tex:SetVertexColor(1, 1, 1, 1)
			elseif (targetclassification == "rare") then
				self.eliteFrame.tex:SetTexture("Interface\\AddOns\\XPerlForever\\Images\\XPerl_Rare")
				self.eliteFrame.tex:SetVertexColor(1, 1, 1, 1)
			else
				eliteGfx = nil
			end
		else
			if (targetclassification == "worldboss") then
				bossType = XPERL_TYPE_BOSS
				self.bossFrame.text:SetTextColor(1, 0.5, 0.5)
			elseif (targetclassification == "rareelite") then
				bossType = XPERL_TYPE_RAREPLUS
				self.bossFrame.text:SetTextColor(0.8, 0.8, 0.8)
			elseif (targetclassification == "elite") then
				bossType = XPERL_TYPE_ELITE
				self.bossFrame.text:SetTextColor(1, 1, 0.5)
			elseif (targetclassification == "rare") then
				bossType = XPERL_TYPE_RARE
				self.bossFrame.text:SetTextColor(0.8, 0.8, 0.8)
			end
		end

		self.typeFramePlayer:Hide()
	end

	if (partyid == "target" and bossType and not tconf.eliteNone) or (partyid == "focus" and bossType and not fconf.eliteNone) then
		self.bossFrame:Show()
		self.bossFrame.text:SetText(bossType)
		-- Z-Perl Forever: GetStringWidth() can be secret even for plain text
		-- (section 3 taint-propagation nuance)
		XPerl_SafeSetWidthFromText(self.bossFrame, self.bossFrame.text, 10, 70)
	else
		self.bossFrame:Hide()
	end

	if (eliteGfx) then
		self.eliteFrame:Show()
		if (partyid == "target" and XPerl_Target_AssistFrame and XPerl_Target_AssistFrame:IsShown()) then
			XPerl_Target_AssistFrame:ClearAllPoints()
			XPerl_Target_AssistFrame:SetPoint("BOTTOMRIGHT", self.portraitFrame, "BOTTOMRIGHT", 0, 0)
			XPerl_Target_AssistFrame:SetFrameLevel(self.portraitFrame:GetFrameLevel() + 2)
			self.eliteFrame.assistOutOfPlace = true
		end
		if (self.conf.level) then
			self.levelFrame:ClearAllPoints()
			self.levelFrame:SetPoint("TOPRIGHT", self.portraitFrame, "TOPRIGHT", 0, 0)
			self.levelFrame:SetFrameLevel(self.portraitFrame:GetFrameLevel() + 2)
			self.levelFrame.outOfPlace = true
		end
		-- this is hidden if the mob is elite regardless of graphics (wihout gfx it says "Elite" for example)
		--if (self.conf.classIcon) then
		--	self.typeFramePlayer:ClearAllPoints()
		--	self.typeFramePlayer:SetPoint("BOTTOMRIGHT", self.portraitFrame, "BOTTOMRIGHT", 0, 0)
		--	self.typeFramePlayer.outOfPlace = true
		--end
	else
		self.eliteFrame:Hide()
		if (partyid == "target" and self.eliteFrame.assistOutOfPlace) then
			self.eliteFrame.assistOutOfPlace = nil
			XPerl_Target_AssistFrame:ClearAllPoints()
			XPerl_Target_AssistFrame:SetPoint("TOPLEFT", self.portraitFrame, "TOPRIGHT", -2, -20)
			XPerl_Target_AssistFrame:SetFrameLevel(self.portraitFrame:GetFrameLevel())
		end
		if (self.levelFrame.outOfPlace) then
			self.levelFrame.outOfPlace = nil
			self.levelFrame:ClearAllPoints()
			self.levelFrame:SetPoint("TOPLEFT", self.portraitFrame, "TOPRIGHT", -2, 0)
			self.levelFrame:SetFrameLevel(self.portraitFrame:GetFrameLevel())
		end
		--if (self.typeFramePlayer.outOfPlace) then
		--	self.typeFramePlayer.outOfPlace = nil
		--	self.typeFramePlayer:ClearAllPoints()
		--	self.typeFramePlayer:SetPoint("BOTTOMLEFT", self.portraitFrame, "BOTTOMRIGHT", 2, 2)
		--end
	end
end

-- AdjustCreatureTypeFrame
local function AdjustCreatureTypeFrame(self)
	-- If it's too long, we anchor it to left side of portrait instead of right, to avoid it overlapping some buffs
	self.creatureTypeFrame:ClearAllPoints()
	if (self.creatureTypeFrame:GetWidth() > self.portraitFrame:GetWidth()) then
		self.creatureTypeFrame:SetPoint("TOPLEFT", self.portraitFrame, "BOTTOMLEFT", 0, 2)
	else
		self.creatureTypeFrame:SetPoint("TOPRIGHT", self.portraitFrame, "BOTTOMRIGHT", 0, 2)
	end
end

-- XPerl_Target_UpdateTalents
local XPerl_Target_UpdateTalents
do
	local function ShowSpec(self, spec)--, s1, s2, s3)
		if (self.conf.talentsAsText and type(spec) == "string") then
			self.creatureTypeFrame.text:SetText(spec)
		else
			--self.creatureTypeFrame.text:SetFormattedText("%d / %d / %d", s1, s2, s3)
			self.creatureTypeFrame.text:SetText(spec)
		end
		-- Z-Perl Forever: GetStringWidth() can be secret even for plain text
		-- (section 3 taint-propagation nuance)
		XPerl_SafeSetWidthFromText(self.creatureTypeFrame, self.creatureTypeFrame.text, 10, 70)
		self.creatureTypeFrame:Show()

		AdjustCreatureTypeFrame(self)
		XPerl_Target_BuffPositions(self)
	end

	local LGT = LibStub and LibStub("LibGroupTalents-1.0", true)
	local UpdateTalentsLGT
	if (LGT) then
		function UpdateTalentsLGT(self)
			local spec, s1, s2, s3 = LGT:GetUnitTalentSpec(self.partyid)
			if (spec) then
				ShowSpec(self, spec)--, s1, s2, s3)
				return true
			end
		end
	end

	local inspectReady
	local lastInspectTime = 0
	local lastInspectName, lastInspectUnit, lastInspectGUID
	local talentCache = setmetatable({}, {__mode = "kv"})
	local LTQ = LibStub and LibStub("LibTalentQuery-1.0", true)
	local lastInspectInvalid
	if (LTQ) then
		local function TalentQuery_Ready(e, name, realm, unit)
			if (UnitIsUnit(unit, XPerl_Target.partyid)) then
				inspectReady = true
				XPerl_Target_UpdateTalents(XPerl_Target, UnitGUID(unit))
			end
		end
		LTQ:RegisterCallback("TalentQuery_Ready", TalentQuery_Ready)
	else
		-- INSPECT_READY
		function XPerl_Target_Events:INSPECT_READY(guid)
			local unitGUID = UnitGUID(self.partyid)
			if (unitGUID and XPerl_CanAccess(unitGUID) and unitGUID == guid) then
				inspectReady = true
				XPerl_Target_UpdateTalents(self, guid)
			end
		end
	end

	function XPerl_Target_UpdateTalents(self, guid)
		if (self.conf.showTalents and self == XPerl_Target and not self.creatureTypeFrame:IsShown()) then
			if (UpdateTalentsLGT and UpdateTalentsLGT(self)) then
				return
			end

			local partyid = self.partyid
			local level = UnitLevel(partyid)
			if (UnitIsVisible(partyid) and UnitExists(partyid) and UnitIsPlayer(partyid) and XPerl_CanAccess(level) and level > 10) then
				local name = UnitName(partyid)
				if (not name or not XPerl_CanAccess(name)) then
					return
				else
					local cached = talentCache[name]
					local name1, name2, name3, group, iconTexture, background
					local unitGUID = UnitGUID(partyid)
					if (cached) then
						name1, name2, name3, group = unpack(cached)
					-- Z-Perl Forever: guard both sides before comparing, same
					-- shape as the XPerlForever.lua portrait3D fix -- guid (the
					-- inspect event's GUID argument) can be secret too, not
					-- just unitGUID; XPerl_CanAccess(nil) is false, matching
					-- this branch's existing no-op when no guid was passed.
					elseif (inspectReady and XPerl_CanAccess(unitGUID) and XPerl_CanAccess(guid) and guid == unitGUID) then
						local remoteInspectNeeded = not UnitIsUnit("player", partyid) or nil
						name1 = "None"

						inspectReady = nil
					end

					if (name1) then
						if (not cached) then
							talentCache[name] = {name1, name2, name3, group}
						end
						ShowSpec(self, name1)
					end

					if (not cached) then
						if (LTQ) then
							inspectReady = nil
							LTQ:Query(partyid)
						else
							if (lastInspectPending == 0 or GetTime() > lastInspectTime + 15) then
								if (UnitExists(partyid) and UnitIsVisible(partyid) and not InCombatLockdown() and CheckInteractDistance(partyid, 4)) then
									if (not UnitIsUnit("player", partyid)) then
										inspectReady = nil
										lastInspectInvalid = nil
										lastInspectPending = 0
										if (lastInspectName ~= XPerl_UnitFullName(partyid)) then
											NotifyInspect(partyid)
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

-- XPerl_Target_UpdateType
local function XPerl_Target_UpdateType(self)
	local partyid = self.partyid
	local targettype = UnitCreatureType(partyid)
	-- Z-Perl Forever: creature types are secret inside instances
	local typeReadable = XPerl_CanAccess(targettype)

	if (typeReadable and (targettype == XPERL_TYPE_NOT_SPECIFIED or targettype == "")) then
		targettype = nil
	end

	if (self.conf.mobType) then
		self.creatureTypeFrame:Show()
	else
		self.creatureTypeFrame:Hide()
	end

	self.typeFramePlayer:Hide()


	self.creatureTypeFrame.text:SetText(targettype)

	--if (UnitIsPlayer(partyid)) then
		local classification = UnitClassification(partyid)
		if (self.conf.classIcon and (UnitIsPlayer(partyid) or (XPerl_CanAccess(classification) and classification == "normal"))) then
			local LocalClass, PlayerClass = UnitClassBase(partyid)

			if (self.conf.classText) then
				self.bossFrame.text:SetText(LocalClass)
				self.bossFrame.text:SetTextColor(1, 1, 1)
				self.bossFrame:Show()
				-- Z-Perl Forever: GetStringWidth() can be secret even for
				-- plain text (section 3 taint-propagation nuance)
				XPerl_SafeSetWidthFromText(self.bossFrame, self.bossFrame.text, 10, 70)
			else
				if (UnitIsPlayer(partyid) or not UnitPlayerControlled(partyid)) then
					local l, r, t, b = XPerl_ClassPos(LocalClass)
					self.typeFramePlayer.classTexture:SetTexCoord(l, r, t, b)
					self.typeFramePlayer:Show()
				end
			end
		end
		if (UnitIsPlayer(partyid)) then
			self.creatureTypeFrame:Hide()
		end
	--else
		if (targettype) then
			self.creatureTypeFrame.text:SetTextColor(1, 1, 1)
			-- Z-Perl Forever: typeReadable alone is not enough -- confirmed
			-- live crashing here even with targettype readable, because
			-- GetStringWidth() picks up taint from any secret value read
			-- earlier in this same update (section 3 taint-propagation
			-- nuance). Guard the width itself instead.
			XPerl_SafeSetWidthFromText(self.creatureTypeFrame, self.creatureTypeFrame.text, 10, 70)
		else
			self.creatureTypeFrame:Hide()
		end
	--end

	AdjustCreatureTypeFrame(self)

	XPerl_Target_UpdateTalents(self)
end

-- XPerl_Target_SetManaType
function XPerl_Target_SetManaType(self)
	local unitPowerMax = UnitPowerMax(self.partyid)

	-- Z-Perl Forever: a secret maximum cannot be tested, keep the bar shown
	if ((XPerl_CanAccess(unitPowerMax) and unitPowerMax == 0) or not self.conf.mana) then
		if (self.statsFrame.manaBar:IsShown()) then
			self.statsFrame.manaBar:Hide()

			if (self == XPerl_Target or self == XPerl_Focus or self == XPerl_TargetTarget or self == XPerl_FocusTarget or self == XPerl_PetTarget or self == XPerl_TargetTargetTarget) then
				self.statsFrame:SetHeight(28 + ((conf.bar.fat or 0) * 2))
				XPerl_StatsFrameSetup(self)
			end
		end
		return
	end

	XPerl_SetManaBarType(self)

	if (not self.statsFrame.manaBar:IsShown()) then
		self.statsFrame.manaBar:Show()
		self.statsFrame.manaBar.text:Show()
		if (self == XPerl_Target or self == XPerl_Focus or self == XPerl_TargetTarget or self == XPerl_FocusTarget or self == XPerl_PetTarget or self == XPerl_TargetTargetTarget) then
			self.statsFrame:SetHeight(40)
			XPerl_StatsFrameSetup(self)
		end
	end
end

-- XPerl_Target_SetMana
function XPerl_Target_SetMana(self)
	local partyid = self.partyid
	if not partyid then
		self.targetmana = 0
		self.targetmanamax = 0
		return
	end

	local powerType = XPerl_GetDisplayedPowerType(partyid)
	local unitPower = UnitPower(partyid, powerType)
	local unitPowerMax = UnitPowerMax(partyid, powerType)

	self.targetmana = unitPower
	self.targetmanamax = unitPowerMax

	-- Z-Perl Forever: percent is plain maths when readable, Blizzard supplied otherwise
	local powerPct = XPerl_GetPowerPercent(partyid, powerType, unitPower, unitPowerMax)

	self.statsFrame.manaBar:SetMinMaxValues(0, unitPowerMax)
	self.statsFrame.manaBar:SetValue(unitPower)

	if powerType >= 1 then
		self.statsFrame.manaBar.percent:SetText(unitPower)
	else
		self.statsFrame.manaBar.percent:SetFormattedText(percD, powerPct)	--	XPerl_Percent[floor(100 * (unitPower / unitPowerMax))])
	end

	XPerl_SetValuedText(self.statsFrame.manaBar.text, unitPower, unitPowerMax)
	--self.statsFrame.manaBar.text:SetFormattedText("%d/%d", unitPower, unitPowerMax)
end

-- XPerl_Target_SetComboBar
local function XPerl_Target_SetComboBar(self)
	if not tconf.combo.enable then
		return
	end

	local comboPoints = GetComboPoints("player", "target")
	local maxComboPoints = UnitPowerMax("player", Enum.PowerType.ComboPoints)
	self.nameFrame.cpMeter:SetMinMaxValues(0, maxComboPoints)
	self.nameFrame.cpMeter:SetValue(comboPoints)
end

-- XPerl_Target_UpdateHealPrediction
local function XPerl_Target_UpdateHealPrediction(self)
	if self == XPerl_Target then
		if tconf.healprediction then
			XPerl_SetExpectedHealth(self)
		else
			self.statsFrame.expectedHealth:Hide()
		end
	elseif self == XPerl_TargetTarget or self == XPerl_TargetTargetTarget then
		if conf.targettarget.healprediction then
			XPerl_SetExpectedHealth(self)
		else
			self.statsFrame.expectedHealth:Hide()
		end
	elseif self == XPerl_Focus then
		if fconf.healprediction then
			XPerl_SetExpectedHealth(self)
		else
			self.statsFrame.expectedHealth:Hide()
		end
	elseif self == XPerl_FocusTarget then
		if conf.focustarget.healprediction then
			XPerl_SetExpectedHealth(self)
		else
			self.statsFrame.expectedHealth:Hide()
		end
	end
end

-- XPerl_Target_UpdateAbsorbPrediction
local function XPerl_Target_UpdateAbsorbPrediction(self)
	if self == XPerl_Target then
		if tconf.absorbs then
			XPerl_SetExpectedAbsorbs(self)
		else
			self.statsFrame.expectedAbsorbs:Hide()
		end
	elseif self == XPerl_TargetTarget or self == XPerl_TargetTargetTarget then
		if conf.targettarget.absorbs then
			XPerl_SetExpectedAbsorbs(self)
		else
			self.statsFrame.expectedAbsorbs:Hide()
		end
	elseif self == XPerl_Focus then
		if fconf.absorbs then
			XPerl_SetExpectedAbsorbs(self)
		else
			self.statsFrame.expectedAbsorbs:Hide()
		end
	elseif self == XPerl_FocusTarget then
		if conf.focustarget.absorbs then
			XPerl_SetExpectedAbsorbs(self)
		else
			self.statsFrame.expectedAbsorbs:Hide()
		end
	end
end

function XPerl_Target_UpdateResurrectionStatus(self)
	if (XPerl_SafeBool(UnitHasIncomingResurrection(self.partyid), false)) then
		if (self == XPerl_Target and tconf.portrait) or (self == XPerl_Focus and fconf.portrait) then
			self.portraitFrame.resurrect:Show()
		else
			self.statsFrame.resurrect:Show()
		end
	else
		if (self == XPerl_Target and tconf.portrait) or (self == XPerl_Focus and fconf.portrait) then
			self.portraitFrame.resurrect:Hide()
		else
			self.statsFrame.resurrect:Hide()
		end
	end
end

-- XPerl_Target_UpdateHealth
function XPerl_Target_UpdateHealth(self)
	local partyid = self.partyid
	if not partyid then
		self.targethp = 0
		self.targetmax = 0
		self.afk = false
		return
	end

	local hp, hpMax, percent = XPerl_Target_GetHealth(self)
	-- Z-Perl Forever: secret health goes straight to the bar, no maths here
	local readable = XPerl_CanAccess(hp) and XPerl_CanAccess(hpMax)

	self.targethp = hp
	self.targethpmax = hpMax

	-- Z-Perl Forever: indirect units (pettarget, targettarget...) can return
	-- secret booleans, which cannot be tested; treat those as "alive and normal"
	local ghost = XPerl_SafeBool(UnitIsGhost(partyid), false)
	local dead = XPerl_SafeBool(UnitIsDead(partyid), false)
	local offline = UnitExists(partyid) and not XPerl_SafeBool(UnitIsConnected(partyid), true)
	local afk = XPerl_SafeBool(UnitIsAFK(partyid), false)
	self.afk = afk and conf.showAFK == 1

	if (not readable) then
		XPerl_SetHealthBar(self, hp, hpMax)
	elseif hp and hp >= 0 and hpMax and hpMax > 0 then
		XPerl_SetHealthBar(self, hp, hpMax)
	end

	XPerl_Target_UpdateAbsorbPrediction(self)
	XPerl_Target_UpdateHealPrediction(self)
	XPerl_Target_UpdateResurrectionStatus(self)

	if (percent and readable) then
		if ghost or dead or hpMax == 0 then -- 4.3+ fix so if for some dumb reason max HP is 0, prevent any division by 0.
			self.statsFrame.healthBar.text:SetFormattedText(percD, 0)
		else
			self.statsFrame.healthBar.text:SetFormattedText(percD, 100 * hp / hpMax)
		end
	end

	local color
	if (self.conf.percent) then
		if (ghost) then
			self.statsFrame.manaBar.percent:Hide()
			self.statsFrame.healthBar.percent:SetText(XPERL_LOC_GHOST)
		elseif (dead) then
			--self.statsFrame.manaBar.percent:Hide()
			self.statsFrame.healthBar.percent:SetText(XPERL_LOC_DEAD)
		elseif (offline) then
			self.statsFrame.manaBar.percent:Hide()
			self.statsFrame.healthBar.percent:SetText(XPERL_LOC_OFFLINE)
		elseif (afk and conf.showAFK) then
			self.statsFrame.healthBar.percent:SetText(CHAT_MSG_AFK)
		else
			self.statsFrame.manaBar.percent:Show()
			color = true
		end
	else
		if (ghost) then
			self.statsFrame.healthBar.text:SetText(XPERL_LOC_GHOST)
		elseif (dead) then
			self.statsFrame.healthBar.text:SetText(XPERL_LOC_DEAD)
		elseif (offline) then
			self.statsFrame.healthBar.text:SetText(XPERL_LOC_OFFLINE)
		elseif (afk and conf.showAFK) then
			self.statsFrame.healthBar.text:SetText(CHAT_MSG_AFK)
		else
			color = true
		end
	end

	if (color) then
		if (not readable) then
			XPerl_ColourHealthBar(self, XPerl_GetHealthPercent(partyid, hp, hpMax))
		elseif hp and hp >= 0 and hpMax and hpMax > 0 then
			XPerl_ColourHealthBar(self, hp / hpMax)
		end

		if (self.statsFrame.greyMana) then
			self.statsFrame.greyMana = nil
			XPerl_Target_SetManaType(self)
		end
	else
		self.statsFrame:SetGrey()
	end
end

-- XPerl_Target_GetHealth
function XPerl_Target_GetHealth(self)
	-- Z-Perl Forever: XPerl_Unit_GetHealth already answers "is max 100" and
	-- returns false when the values are secret and cannot be compared
	local hp, hpMax, percent = XPerl_Unit_GetHealth(self)
	return hp, hpMax, percent
end

-- XPerl_Target_Update_Combat
function XPerl_Target_Update_Combat(self)
	if (UnitAffectingCombat(self.partyid)) then
		self.nameFrame.combatIcon:Show()
	else
		self.nameFrame.combatIcon:Hide()
	end
end

-- XPerl_Target_CombatFlash
local function XPerl_Target_CombatFlash(self, elapsed, argNew, argGreen)
	if (XPerl_CombatFlashSet(self, elapsed, argNew, argGreen)) then
		XPerl_CombatFlashSetFrames(self)
	end
end

-- XPerl_Target_Update_Range
function XPerl_Target_Update_Range(self)
	if not self.partyid then
		return
	end
	if not tconf.range30yard then
		self.nameFrame.rangeIcon:Hide()
		return
	end
	local range, checkedRange = UnitInRange(self.partyid)
	if (XPerl_IsSecret(range) or XPerl_IsSecret(checkedRange)) then
		-- Z-Perl Forever: secret booleans drive the icon's alpha directly
		local icon = self.nameFrame.rangeIcon
		icon:Show()
		icon:SetAlpha(1)
		XPerl_SetAlphaFromBoolean(icon, checkedRange, 1, 0)
		XPerl_SetAlphaFromBoolean(icon, range, 0, icon:GetAlpha())
		return
	end
	local inRange = false
	if not checkedRange then
		inRange = true
	end
	if not UnitIsConnected(self.partyid) or inRange then
		self.nameFrame.rangeIcon:Hide()
	else
		self.nameFrame.rangeIcon:Show()
		self.nameFrame.rangeIcon:SetAlpha(1)
	end
end

-- XPerl_Target_UpdateLeader
local function XPerl_Target_UpdateLeader(self)
	local leader
	local partyid = self.partyid

	-- UnitIsGroupLeader/UnitIsGroupAssistant can be secret booleans for a
	-- secret-identity target (pattern 12); crashed on plain click-to-target.
	if (XPerl_SafeBool(UnitIsGroupLeader(partyid), false)) then
		self.nameFrame.leaderIcon:Show()
		self.nameFrame.assistIcon:Hide()
	else
		self.nameFrame.leaderIcon:Hide()
		if (XPerl_SafeBool(UnitIsGroupAssistant(partyid), false)) then
			self.nameFrame.assistIcon:Show()
		else
			self.nameFrame.assistIcon:Hide()
		end
	end

	local masterLooter = false
	local method, partyID, raidID = GetLootMethod()

	if method and method == "master" then
		if raidID then
			if UnitIsUnit("raid"..raidID, partyid) then
				masterLooter = true
			end
		elseif partyID then
			if UnitIsUnit("party"..partyID, partyid) or (partyID == 0 and UnitIsUnit("player", partyid)) then
				masterLooter = true
			end
		end
	end

	if masterLooter then
		self.nameFrame.masterIcon:Show()
	else
		self.nameFrame.masterIcon:Hide()
	end
end

-- RaidTargetUpdate
local function RaidTargetUpdate(self)
	local raidIcon = self.nameFrame.raidIcon

	XPerl_Update_RaidIcon(raidIcon, self.partyid)

	raidIcon:ClearAllPoints()
	if (self.conf.raidIconAlternate) then
		raidIcon:SetHeight(16)
		raidIcon:SetWidth(16)
		raidIcon:SetPoint("CENTER", self.nameFrame, "TOPRIGHT", -5, -4)
	else
		raidIcon:SetHeight(32)
		raidIcon:SetWidth(32)
		raidIcon:SetPoint("CENTER", self.nameFrame, "CENTER", 0, 0)
	end
end

-- XPerl_Target_CheckDebuffs
local function XPerl_Target_CheckDebuffs(self)
	if (self.conf.highlightDebuffs.enable) then
		if (self.conf.highlightDebuffs.who == 1 or (self.conf.highlightDebuffs.who == 2 and UnitCanAssist("player", self.partyid)) or (self.conf.highlightDebuffs.who == 3 and not UnitCanAssist("player", self.partyid))) then
			XPerl_CheckDebuffs(self, self.partyid)
		else
			XPerl_CheckDebuffs(self, self.partyid, true)
		end
	end

	if (self.conf.reactionHighlight) then
		local c = XPerl_ReactionColour(self.partyid)
		self.nameFrame:SetBackdropColor(c.r, c.g, c.b)
	end
end

local function XPerl_Target_ComboFrame_Update()
	if (not canManageBlizzardComboFrame) then
		return
	end
	local comboPoints = GetComboPoints("player", "target")
	-- Z-Perl Forever: comboPoints is secret when the target's identity is secret;
	-- it can't be compared against 0 or the loop index below, so drop our display
	if XPerl_IsSecret(comboPoints) then
		ComboFrame:Hide()
		ComboFrame.lastPoints = nil
		return
	end
	if tconf.combo.blizzard and comboPoints > 0 and not UnitIsDeadOrGhost("target") and UnitCanAttack(UnitHasVehicleUI("player") and "vehicle" or "player", "target") then
		if not ComboFrame:IsShown() then
			ComboFrame:Show()
			UIFrameFadeIn(ComboFrame, COMBOFRAME_FADE_IN)
		end

		local fadeInfo = { }
		for i = 1, 5 do
			local comboPoint = _G["ComboPoint"..i]
			if i < 6 then
				comboPoint:Show()
			else
				if comboPoints >= i then
					comboPoint:Show()
				else
					comboPoint:Hide()
				end
			end
			if i <= comboPoints then
				if i > (ComboFrame.lastPoints or 0) then
					-- Fade in the highlight and set a function that triggers when it is done fading
					fadeInfo.mode = "IN"
					fadeInfo.timeToFade = COMBOFRAME_HIGHLIGHT_FADE_IN
					fadeInfo.finishedFunc = ComboPointShineFadeIn
					fadeInfo.finishedArg1 = comboPoint.Shine
					UIFrameFade(comboPoint.Highlight, fadeInfo)
				end
			else
				comboPoint.Highlight:SetAlpha(0)
				comboPoint.Shine:SetAlpha(0)
			end
		end
	else
		ComboFrame:Hide()
	end
	ComboFrame.lastPoints = comboPoints
end

-- XPerl_Target_UpdateDisplay
function XPerl_Target_UpdateDisplay(self)
	local partyid = self.partyid
	if not UnitExists(partyid) then
		return
	end

	XPerl_NoFadeBars(true)

	XPerl_Target_UpdateName(self)
	XPerl_Target_UpdateClassification(self)
	XPerl_Target_UpdateLevel(self)
	XPerl_Target_UpdateType(self)
	XPerl_Target_SetManaType(self)
	XPerl_Target_SetMana(self)
	XPerl_Target_UpdateHealth(self)
	XPerl_Target_Update_Combat(self)
	XPerl_Target_UpdateLeader(self)
	XPerl_Unit_ThreatStatus(self, partyid == "target" and "player" or nil, true)

	if self == XPerl_Target and tconf.combo.blizzard then
		XPerl_Target_ComboFrame_Update()
	end

	RaidTargetUpdate(self)

	if (self.conf.defer) then
		self.portraitFrame.portrait:Hide()
		self.portraitFrame.portrait3D:Hide()
		self.nameFrame.masterIcon:Hide()
		self.cpFrame:Hide()
		self.nameFrame.cpMeter:Hide()
		if self.foreverCombo then
			self.foreverCombo:Hide()
		end
		self.deferring = true
		self.time = -0.3
	else
		if self == XPerl_Target then
			XPerl_Target_UpdateCombo(self)
		end
		XPerl_Unit_UpdatePortrait(self)
	end

	XPerl_Highlight:SetHighlight(self, UnitGUID(partyid))

	if tconf.range30yard then
		XPerl_Target_Update_Range(self)
	else
		self.nameFrame.rangeIcon:Hide()
	end
	XPerl_UpdateSpellRange(self, partyid)

	XPerl_NoFadeBars()

	-- Some optimizing here to limit the amount of work done on a target change
	local buffOptionString = tostring(self.statsFrame.manaBar:IsShown() or 0)..tostring(self.bossFrame:IsShown() or 0)..tostring(self.creatureTypeFrame:IsShown() or 0)..tostring(self.statsFrame:GetWidth())
	if (self.buffOptionString ~= buffOptionString) then
		self.buffOptionString = buffOptionString
		-- Work out where all our buffs can fit, we only do this for a fresh target
		XPerl_Target_BuffPositions(self)
	end

	-- Z-Perl Forever: a fresh target is the most common moment the AuraContainer
	-- fallback's friend/enemy half-assignment needs to change; rebuild here (a
	-- no-op on clients without it, deferred while secret) rather than on every
	-- UNIT_AURA, which XPerl_Targets_BuffUpdate below runs on far more often.
	XPerl_Target_AuraContainer_Rebuild(self)

	XPerl_Targets_BuffUpdate(self)
	--XPerl_Target_DebuffUpdate(self)
	if (self.conf.highlightDebuffs.enable) then
		XPerl_Target_CheckDebuffs(self)
	end

	XPerl_Target_UpdatePVP(self)
end

-- XPerl_Target_OnUpdate
function XPerl_Target_OnUpdate(self, elapsed)
	local partyid = self.partyid
	if not partyid then
		return
	end

	if (tconf.hitIndicator and tconf.portrait) or (fconf.hitIndicator and fconf.portrait) then
		CombatFeedback_OnUpdate(self, elapsed)
	end

	-- Separate raw call from the guarded one in _UpdateHealth; default to
	-- self.afk when secret so this reads "no change" rather than crashing.
	local newAFK = XPerl_SafeBool(UnitIsAFK(partyid), self.afk)

	if (conf.showAFK and newAFK ~= self.afk) then
		XPerl_Target_UpdateHealth(self)
	end

	if self.deferring or conf.rangeFinder.enabled or tconf.range30yard then
		self.time = self.time + elapsed
		if (self.time > 0.2) then
			self.time = 0
			if tconf.range30yard then
				XPerl_Target_Update_Range(self)
			end
			if conf.rangeFinder.enabled then
				XPerl_UpdateSpellRange(self, partyid)
			end

			if (self.deferring) then
				self.deferring = nil
				XPerl_Target_Update_Combat(self)
				if self == XPerl_Target and (tconf.combo.enable or tconf.comboindicator.enable) then
					XPerl_Target_UpdateCombo(self)
				end
				XPerl_Unit_UpdatePortrait(self)
				RaidTargetUpdate(self)
			end
		end
	end

	if (conf.combatFlash and self.PlayerFlash) then
		XPerl_Target_CombatFlash(self, elapsed, false)
	end
end

-------------------
-- Event Handler --
-------------------
function XPerl_Target_OnEvent(self, event, ...)
	local func = XPerl_Target_Events[event]
	func(self, ...)
end


function XPerl_Target_Events:PLAYER_REGEN_ENABLED()
	XPerl_Unit_ThreatStatus(self, self.partyid == "target" and "player" or nil)
end

function XPerl_Target_Events:PLAYER_REGEN_DISABLED()
	XPerl_Unit_ThreatStatus(self, self.partyid == "target" and "player" or nil)
end

function XPerl_Target_Events:PET_BATTLE_OPENING_START()
	if (XPerl_Target) then
		XPerl_Target:Hide()
	end
	if (XPerl_Focus) then
		XPerl_Focus:Hide()
	end
	if (XPerl_PetTarget) then
		XPerl_PetTarget:Hide()
	end
	if (XPerl_TargetTarget) then
		XPerl_TargetTarget:Hide()
	end
	if (XPerl_FocusTarget) then
		XPerl_FocusTarget:Hide()
	end
end

function XPerl_Target_Events:PET_BATTLE_CLOSE()
	if (XPerl_Target and UnitExists("target")) then
		XPerl_Target:Show()
	end
	if (XPerl_Focus and XPerl_Focus.conf.enable and UnitExists("focus")) then
		XPerl_Focus:Show()
	end
	if (XPerl_PetTarget and UnitExists("pettarget")) then
		XPerl_PetTarget:Show()
	end
	if (XPerl_TargetTarget and XPerl_TargetTarget.conf.enable and UnitExists("targettarget")) then
		XPerl_TargetTarget:Show()
	end
	if (XPerl_FocusTarget and XPerl_FocusTarget.conf.enable and UnitExists("focustarget")) then
		XPerl_FocusTarget:Show()
	end
end

-- PLAYER_ENTERING_WORLD
function XPerl_Target_Events:PLAYER_ENTERING_WORLD()
	if (UnitExists("focus")) then
		--self.feigning = nil
		self.PlayerFlash = 0
		XPerl_CombatFlashSetFrames(self)
		XPerl_Target_UpdateDisplay(self)
	end
end

local amountIndex = {
	SWING_DAMAGE = 1,
	RANGE_DAMAGE = 4,
	SPELL_DAMAGE = 4,
	SPELL_PERIODIC_DAMAGE = 4,
	DAMAGE_SHIELD = 4,
	ENVIRONMENTAL_DAMAGE = 2,
}

local missIndex = {
	SWING_MISSED = 1,
	RANGE_MISSED = 4,
	SPELL_MISSED = 4,
	SPELL_PERIODIC_MISSED = 4,
}

-- UNIT_COMBAT
function XPerl_Target_Events:UNIT_COMBAT(unit, action, descriptor, damage, damageType)
	if unit ~= self.partyid then
		return
	end

	XPerl_Target_Update_Combat(self)

	if (self.conf.hitIndicator and self.conf.portrait) then
		CombatFeedback_OnCombatEvent(self, action, descriptor, damage, damageType)
	end

	if (action == "HEAL") then
		XPerl_Target_CombatFlash(self, 0, true, true)
	elseif (damage and damage > 0) then
		XPerl_Target_CombatFlash(self, 0, true)
	end
end

-- PLAYER_TARGET_CHANGED
function XPerl_Target_Events:PLAYER_TARGET_CHANGED()
	if self ~= XPerl_Target then
		return
	end
	if (self.conf.sound and UnitExists("target")) then
		if (UnitIsEnemy("target", "player")) then
			PlaySound(873)
		elseif (UnitIsFriend("player", "target")) then
			PlaySound(867)
		else
			PlaySound(871)
		end
	end

	--self.feigning = UnitBuff(self.partyid, feignDeath)
	self.PlayerFlash = 0
	XPerl_CombatFlashSetFrames(self)
	XPerl_Target_UpdateDisplay(self)

	if (UnitIsUnit("target", "focus")) then
		self.statsFrame.focusTarget:Show()
	else
		self.statsFrame.focusTarget:Hide()
	end

	if (XPerl_Focus and XPerl_Focus:IsShown() and XPerl_FocusTarget) then
		XPerl_TargetTarget_UpdateDisplay(XPerl_FocusTarget)
	end
end

-- PLAYER_FOCUS_CHANGED
function XPerl_Target_Events:PLAYER_FOCUS_CHANGED()
	if self ~= XPerl_Focus then
		return
	end
	if (self.conf.sound and UnitExists("focus")) then
		if (UnitIsEnemy("focus", "player")) then
			PlaySound(873)
		elseif (UnitIsFriend("player", "focus")) then
			PlaySound(867)
		else
			PlaySound(871)
		end
	end

	--self.feigning = UnitBuff(self.partyid, feignDeath)
	self.PlayerFlash = 0
	XPerl_CombatFlashSetFrames(self)
	XPerl_Target_UpdateDisplay(self)

	if (UnitIsUnit("target", "focus")) then
		XPerl_Target.statsFrame.focusTarget:Show()
	else
		XPerl_Target.statsFrame.focusTarget:Hide()
	end

	if (XPerl_FocusTarget) then
		XPerl_TargetTarget_UpdateDisplay(XPerl_FocusTarget)
	end
end

-- UNIT_HEALTH_FREQUENT
function XPerl_Target_Events:UNIT_HEALTH_FREQUENT()
	XPerl_Target_UpdateHealth(self)
end

-- UNIT_HEALTH
function XPerl_Target_Events:UNIT_HEALTH()
	XPerl_Target_UpdateHealth(self)
end

-- UNIT_MAXHEALTH
function XPerl_Target_Events:UNIT_MAXHEALTH()
	XPerl_Target_UpdateHealth(self)
end

-- PET_BATTLE_HEALTH_CHANGED
function XPerl_Target_Events:PET_BATTLE_HEALTH_CHANGED()
	XPerl_Target_UpdateHealth(self)
end

-- UPDATE_SUMMONPETS_ACTION
function XPerl_Target_Events:UPDATE_SUMMONPETS_ACTION()
	if UnitIsBattlePet("target") then
		XPerl_Target_UpdateHealth(XPerl_Target)
	end

	if UnitIsBattlePet("focus") then
		XPerl_Target_UpdateHealth(XPerl_Focus)
	end
end

-- UNIT_FLAGS
function XPerl_Target_Events:UNIT_FLAGS()
	XPerl_Target_UpdateName(self)
	XPerl_Target_UpdatePVP(self)
	XPerl_Target_Update_Combat(self)
end

-- RAID_TARGET_UPDATE
function XPerl_Target_Events:RAID_TARGET_UPDATE()
	RaidTargetUpdate(XPerl_Target)
	RaidTargetUpdate(XPerl_Focus)
end

-- UNIT_POWER_FREQUENT
function XPerl_Target_Events:UNIT_POWER_FREQUENT()
	XPerl_Target_SetMana(self)
end

-- UNIT_MAXPOWER
function XPerl_Target_Events:UNIT_MAXPOWER(unit)
	XPerl_Target_SetMana(self)
end

-- UNIT_DISPLAYPOWER
function XPerl_Target_Events:UNIT_DISPLAYPOWER()
	XPerl_Target_SetManaType(self)
	XPerl_Target_SetMana(self)
end

-- UNIT_PORTRAIT_UPDATE
function XPerl_Target_Events:UNIT_PORTRAIT_UPDATE()
	XPerl_Unit_UpdatePortrait(self, true)
end

-- UNIT_NAME_UPDATE
function XPerl_Target_Events:UNIT_NAME_UPDATE()
	XPerl_Target_UpdateName(self)
	XPerl_Target_UpdateHealth(self)
	XPerl_Target_UpdateClassification(self)
end

-- UNIT_LEVEL
function XPerl_Target_Events:UNIT_LEVEL()
	XPerl_Target_UpdateLevel(self)
	XPerl_Target_UpdateClassification(self)
end

-- UNIT_CLASSIFICATION_CHANGED
function XPerl_Target_Events:UNIT_CLASSIFICATION_CHANGED()
	XPerl_Target_UpdateClassification(self)
end

-- UNIT_AURA
function XPerl_Target_Events:UNIT_AURA()
	if not UnitExists(self.partyid) then
		return
	end

	if (self.conf.highlightDebuffs.enable) then
		XPerl_Target_CheckDebuffs(self)
	end

	--XPerl_Targets_BuffUpdate(self)
	if self.conf.buffs.enable or self.conf.debuffs.enable then
		-- Z-Perl Forever: hand the display to the AuraContainer fallback
		-- while auras are secret; the classic path below resumes once
		-- readable (mirrors the branch in XPerl_Targets_BuffUpdate).
		if (self.buffContainer and XPerl_AurasSecret()) then
			self.buffFrame:Hide()
			self.debuffFrame:Hide()
			XPerl_Target_AuraContainer_Show(self)
			return
		elseif (self.buffContainer) then
			XPerl_Target_AuraContainer_Hide(self)
			self.buffFrame:Show()
			self.debuffFrame:Show()
		end

		XPerl_Unit_UpdateBuffs(self, nil, nil, self.conf.buffs.castable, self.conf.debuffs.curable)
		XPerl_Target_BuffPositions(self)
	end
end

-- UNIT_FACTION
function XPerl_Target_Events:UNIT_FACTION()
	XPerl_Target_UpdatePVP(self)
	XPerl_Target_BuffPositions(self)
end

-- HONOR_PRESTIGE_UPDATE
function XPerl_Target_Events:HONOR_PRESTIGE_UPDATE()
	XPerl_Target_UpdatePVP(self)
end

-- PLAYER_FLAGS_CHANGED
function XPerl_Target_Events:PLAYER_FLAGS_CHANGED()
	XPerl_Target_Update_Combat(self)
	XPerl_Target_UpdatePVP(self)
	XPerl_Target_UpdateHealth(self)
end

-- UNIT_CONNECTION
function XPerl_Target_Events:UNIT_CONNECTION(unit, online)
	if (unit == self.partyid) then
		XPerl_Target_UpdateDisplay(self)
	end
end

-- UNIT_PHASE
function XPerl_Target_Events:UNIT_PHASE(unit)
	if (unit == self.partyid) then
		XPerl_Target_UpdateDisplay(self)
	end
end

-- PARTY_LOOT_METHOD_CHANGED
function XPerl_Target_Events:PARTY_LOOT_METHOD_CHANGED()
	XPerl_Target_UpdateLeader(self)
end
XPerl_Target_Events.GROUP_ROSTER_UPDATE = XPerl_Target_Events.PARTY_LOOT_METHOD_CHANGED
XPerl_Target_Events.PARTY_LEADER_CHANGED = XPerl_Target_Events.PARTY_LOOT_METHOD_CHANGED

function XPerl_Target_Events:UNIT_THREAT_LIST_UPDATE(unit)
	if (UnitCanAttack("player", self.partyid or "target")) then
		XPerl_Unit_ThreatStatus(self, self.partyid == "target" and "player" or nil)
	else
		XPerl_Unit_ThreatStatus(self)
	end
end

function XPerl_Target_Events:UNIT_HEAL_PREDICTION(unit)
	if self == XPerl_Target then
		if (tconf.healprediction and unit == self.partyid) then
			XPerl_SetExpectedHealth(self)
		end
	elseif self == XPerl_TargetTarget or self == XPerl_TargetTargetTarget then
		if (conf.targettarget.healprediction and unit == self.partyid) then
			XPerl_SetExpectedHealth(self)
		end
	elseif self == XPerl_Focus then
		if (fconf.healprediction and unit == self.partyid) then
			XPerl_SetExpectedHealth(self)
		end
	elseif self == XPerl_FocusTarget then
		if (conf.focustarget.healprediction and unit == self.partyid) then
			XPerl_SetExpectedHealth(self)
		end
	end
end

function XPerl_Target_Events:UNIT_ABSORB_AMOUNT_CHANGED(unit)
	if self == XPerl_Target then
		if (tconf.absorbs and unit == self.partyid) then
			XPerl_SetExpectedAbsorbs(self)
		end
	elseif self == XPerl_TargetTarget or self == XPerl_TargetTargetTarget then
		if (conf.targettarget.absorbs and unit == self.partyid) then
			XPerl_SetExpectedAbsorbs(self)
		end
	elseif self == XPerl_Focus then
		if (fconf.absorbs and unit == self.partyid) then
			XPerl_SetExpectedAbsorbs(self)
		end
	elseif self == XPerl_FocusTarget then
		if (conf.focustarget.absorbs and unit == self.partyid) then
			XPerl_SetExpectedAbsorbs(self)
		end
	end
end

function XPerl_Target_Events:INCOMING_RESURRECT_CHANGED(unit)
	if (unit == self.partyid) then
		XPerl_Target_UpdateResurrectionStatus(self)
	end
end

-- XPerl_Target_SetWidth
function XPerl_Target_SetWidth(self)
	self.conf.size.width = max(0, self.conf.size.width or 0)
	local w = 128 + ((self.conf.portrait and 1 or 0) * 62) + ((self.conf.percent and 1 or 0) * 32) + self.conf.size.width

	if not InCombatLockdown() then
		self:SetWidth(w)
	end

	if self.conf.percent then
		if not InCombatLockdown() then
			self.nameFrame:SetWidth(160 + self.conf.size.width)
			self.statsFrame:SetWidth(160 + self.conf.size.width)
		end
		self.statsFrame.healthBar.percent:Show()
		self.statsFrame.manaBar.percent:Show()
	else
		if not InCombatLockdown() then
			self.nameFrame:SetWidth(128 + self.conf.size.width)
			self.statsFrame:SetWidth(128 + self.conf.size.width)
		end
		self.statsFrame.healthBar.percent:Hide()
		self.statsFrame.manaBar.percent:Hide()
	end

	self.conf.scale = self.conf.scale or 0.8
	if not InCombatLockdown() then
		self:SetScale(self.conf.scale)
	end

	if not InCombatLockdown() then
		XPerl_SavePosition(self, true)
	end
end

-- XPerl_Target_Set_Bits
function XPerl_Target_Set_Bits(self)
	local _, playerClass = UnitClass("player")

	--self.buffOptionString = nil

	if (self.conf.portrait) then
		self.portraitFrame:Show()
		self.portraitFrame:SetWidth(62)
		self.statsFrame.resurrect:Hide()
	else
		self.portraitFrame:Hide()
		self.portraitFrame:SetWidth(3)
	end

	if (self.conf.values) then
		self.statsFrame.healthBar.text:Show()
		self.statsFrame.manaBar.text:Show()
	else
		self.statsFrame.healthBar.text:Hide()
		self.statsFrame.manaBar.text:Hide()
	end

	self.eliteFrame:SetFrameLevel(self.portraitFrame:GetFrameLevel() + 3)

	if (self.conf.level) then
		self.levelFrame:Show()
	else
		self.levelFrame:Hide()
	end

	if (self.conf.classIcon) then
		self.typeFramePlayer.classTexture:Show()
	else
		self.typeFramePlayer.classTexture:Hide()
	end

	--self.highlight:SetPoint("BOTTOMRIGHT", self.portraitFrame, "BOTTOMRIGHT", 26, -1)

	self.conf.buffs.size = tonumber(self.conf.buffs.size) or 20
	XPerl_SetBuffSize(self)

	if self == XPerl_Target then
		XPerl_Register_Prediction(self, tconf, function(guid)
			if guid == UnitGUID("target") then
				return "target"
			end
		end, "target")
	end
	if self == XPerl_Focus then
		XPerl_Register_Prediction(self, fconf, function(guid)
			if guid == UnitGUID("focus") then
				return "focus"
			end
		end, "focus")
	end
	XPerl_Target_SetWidth(self)

	if (not InCombatLockdown()) then
		if (self.conf.enable) then
			RegisterUnitWatch(self)
		else
			self:Hide()
			UnregisterUnitWatch(self)
		end
	end

	if (self == XPerl_Target) then
		XPerl_Target_Set_BlizzCPFrame(self)
	end

	XPerl_StatsFrameSetup(self)

	self.buffFrame:ClearAllPoints()
	if (self.conf.buffs.above) then
		self.buffFrame:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 2, 0)
	else
		self.buffFrame:SetPoint("TOPLEFT", self.statsFrame, "BOTTOMLEFT", 2, 0)
	end
	self.buffOptMix = nil

	if (self:IsShown()) then
		XPerl_Target_UpdateDisplay(self)
	end
end

-- XPerl_Target_RegisterComboEvents
local function XPerl_Target_RegisterComboEvents(self)
	if not tconf.combo.blizzard and not tconf.combo.enable and not tconf.comboindicator.enable then
		ComboEventFrame:UnregisterAllEvents()

		if (canManageBlizzardComboFrame) then
			ComboFrame:UnregisterAllEvents()
			ComboFrame:Hide()
		end
		self.nameFrame.cpMeter:Hide()
		self.cpFrame:Hide()
		if self.foreverCombo then
			self.foreverCombo:Hide()
		end
		return
	end

	ComboEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	ComboEventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player", "vehicle")
	ComboEventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player", "vehicle")
	ComboEventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
	ComboEventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")

	if not canManageBlizzardComboFrame then
		XPerlForever_HideBlizzardComboDisplay()
	end

	if tconf.combo.blizzard and canManageBlizzardComboFrame then
		ComboFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
		ComboFrame:RegisterEvent("UNIT_POWER_FREQUENT")
		ComboFrame:RegisterEvent("UNIT_MAXPOWER")
		ComboFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		ComboFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
		ComboFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")

		ComboFrame.unit = UnitHasVehicleUI("player") and "vehicle" or "player"

		if (ComboFrame_UpdateMax) then
			ComboFrame_UpdateMax(ComboFrame)
		end
	end

	if not tconf.combo.blizzard and canManageBlizzardComboFrame then
		ComboFrame:UnregisterAllEvents()
		ComboFrame:Hide()
	end

	if not tconf.combo.enable then
		self.nameFrame.cpMeter:Hide()
	else
		XPerl_Target_SetComboBar(self)
	end

	if not tconf.comboindicator.enable then
		self.cpFrame:Hide()
	end
end

-- Using the Blizzard Combo Point frame, but we move the buttons around a little
function XPerl_Target_Set_BlizzCPFrame(self)
	if tconf.combo.blizzard and canManageBlizzardComboFrame then
		ComboFrame:ClearAllPoints()
		for i = 1, 5 do
			local combo = _G["ComboPoint"..i]
			if i < 9 then
				combo:ClearAllPoints()

				if i < 6 then
					combo:SetAlpha(1)
				else
					combo:SetAlpha(0.5)
				end
			else
				combo:ClearAllPoints()
				combo:Hide()
			end
		end

		if tconf.combo.pos == "top" then
			ComboFrame:SetPoint("TOP", self.portraitFrame, "TOP", 98, 4)
			ComboPoint1:SetPoint("TOPLEFT", 0, 0)
			ComboPoint2:SetPoint("LEFT", ComboPoint1, "RIGHT", 0, 1)
			ComboPoint3:SetPoint("LEFT", ComboPoint2, "RIGHT", 0, 1)
			ComboPoint4:SetPoint("LEFT", ComboPoint3, "RIGHT", 0, -1)
			ComboPoint5:SetPoint("LEFT", ComboPoint4, "RIGHT", 0, -1)
		elseif tconf.combo.pos == "bottom" then
			ComboFrame:SetPoint("BOTTOM", self.portraitFrame, "BOTTOM", 98, -4)
			ComboPoint1:SetPoint("BOTTOMLEFT", 0, 0)
			ComboPoint2:SetPoint("LEFT", ComboPoint1, "RIGHT", 0, -1)
			ComboPoint3:SetPoint("LEFT", ComboPoint2, "RIGHT", 0, -1)
			ComboPoint4:SetPoint("LEFT", ComboPoint3, "RIGHT", 0, 1)
			ComboPoint5:SetPoint("LEFT", ComboPoint4, "RIGHT", 0, 1)
		elseif tconf.combo.pos == "left" then
			ComboFrame:SetPoint("BOTTOMLEFT", self.portraitFrame, "BOTTOMLEFT", -1, 0)
			ComboPoint1:SetPoint("BOTTOMLEFT", 0, 0)
			ComboPoint2:SetPoint("BOTTOM", ComboPoint1, "TOP", -1, 0)
			ComboPoint3:SetPoint("BOTTOM", ComboPoint2, "TOP", -1, 0)
			ComboPoint4:SetPoint("BOTTOM", ComboPoint3, "TOP", 1, 0)
			ComboPoint5:SetPoint("BOTTOM", ComboPoint4, "TOP", 1, 0)
		elseif tconf.combo.pos == "right" then
			ComboFrame:SetPoint("BOTTOMRIGHT", self.portraitFrame, "BOTTOMRIGHT", 2, 0)
			ComboPoint1:SetPoint("BOTTOMRIGHT", 0, 0)
			ComboPoint2:SetPoint("BOTTOM", ComboPoint1, "TOP", 1, 0)
			ComboPoint3:SetPoint("BOTTOM", ComboPoint2, "TOP", 1, 0)
			ComboPoint4:SetPoint("BOTTOM", ComboPoint3, "TOP", -1, 0)
			ComboPoint5:SetPoint("BOTTOM", ComboPoint4, "TOP", -1, 0)
		else
			ComboFrame:SetPoint("TOP", self.portraitFrame, "TOP", 98, 4)
			ComboPoint1:SetPoint("TOPLEFT", 0, 0)
			ComboPoint2:SetPoint("LEFT", ComboPoint1, "RIGHT", 0, 1)
			ComboPoint3:SetPoint("LEFT", ComboPoint2, "RIGHT", 0, 1)
			ComboPoint4:SetPoint("LEFT", ComboPoint3, "RIGHT", 0, -1)
			ComboPoint5:SetPoint("LEFT", ComboPoint4, "RIGHT", 0, -1)
		end
	end

	XPerl_Target_RegisterComboEvents(self)
end

ComboEventFrame:SetScript("OnEvent", function(self, event, unit, ...)
	local powerType = ...
	if event == "PLAYER_ENTERING_WORLD" then
		XPerlForever_HideBlizzardComboDisplay()
	end
	if event == "UNIT_POWER_FREQUENT" then
		if powerType == "COMBO_POINTS" then
			if UnitExists("target") and XPerl_Target:IsShown() then
				XPerl_Target_UpdateCombo(XPerl_Target)
				if conf.target.combo.blizzard then
					XPerl_Target_ComboFrame_Update()
				end
			end

		end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "UNIT_MAXPOWER" or event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
		if UnitExists("target") and XPerl_Target:IsShown() then
			XPerl_Target_SetComboBar(XPerl_Target)
			XPerl_Target_UpdateCombo(XPerl_Target)
			if conf.target.combo.blizzard then
				XPerl_Target_ComboFrame_Update()
			end
		end
	end
end)
