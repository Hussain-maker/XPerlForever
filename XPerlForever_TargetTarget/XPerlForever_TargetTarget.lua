-- Z-Perl UnitFrames
-- Author: Resike
-- License: GNU GPL v3, 18 October 2014

local max = max
local pairs = pairs
local strfind = strfind
local tonumber = tonumber

local CreateFrame = CreateFrame
local GetDifficultyColor = GetDifficultyColor or GetQuestDifficultyColor
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local RegisterUnitWatch = RegisterUnitWatch
local UnitAffectingCombat = UnitAffectingCombat
local UnitAura = UnitAura
local UnitClassification = UnitClassification
local UnitExists = UnitExists
local UnitFactionGroup = UnitFactionGroup
local UnitGUID = UnitGUID
local UnitHealthMax = UnitHealthMax
local UnitIsAFK = UnitIsAFK
local UnitIsCharmed = UnitIsCharmed
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsFriend = UnitIsFriend
local UnitIsGhost = UnitIsGhost
local UnitIsPlayer = UnitIsPlayer
local UnitIsPVP = UnitIsPVP
local UnitIsPVPFreeForAll = UnitIsPVPFreeForAll
local UnitIsVisible = UnitIsVisible
local UnitLevel = UnitLevel
local UnitName = UnitName
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitUsingVehicle = UnitUsingVehicle
local UnregisterUnitWatch = UnregisterUnitWatch

local UIParent = UIParent

-- Z-Perl Forever: secret value helpers from XPerlForever.lua
local XPerl_CanAccess = XPerl_CanAccess
local XPerl_IsSecret = XPerl_IsSecret
local XPerl_SafeBool = XPerl_SafeBool
local XPerl_UnitAuraByIndex = XPerl_UnitAuraByIndex
local XPerl_SetAlphaFromBoolean = XPerl_SetAlphaFromBoolean
local XPerl_AurasSecret = XPerl_AurasSecret
local XPerl_AuraContainer_SafeToReconfigure = XPerl_AuraContainer_SafeToReconfigure

--local feignDeath = GetSpellInfo and GetSpellInfo(5384) or (C_Spell.GetSpellInfo(5384) and C_Spell.GetSpellInfo(5384).name)

local conf
XPerl_RequestConfig(function(new)
	conf = new
	if XPerl_TargetTarget then
		XPerl_TargetTarget.conf = conf.targettarget
	end
	if XPerl_TargetTargetTarget then
		XPerl_TargetTargetTarget.conf = conf.targettargettarget
	end
	if XPerl_FocusTarget then
		XPerl_FocusTarget.conf = conf.focustarget
	end
	if XPerl_PetTarget then
		XPerl_PetTarget.conf = conf.pettarget
	end
end, "$Revision:  $")

local buffSetup

-- ZPerl_TargetTarget_OnLoad
function ZPerl_TargetTarget_OnLoad(self)
	self:RegisterForClicks("AnyUp")
	self:RegisterForDrag("LeftButton")
	XPerl_SetChildMembers(self)

	local events = {
		XPerl_ForeverAPI.healthEvent,
		"UNIT_POWER_FREQUENT",
		"UNIT_AURA",
		"UNIT_TARGET",
		"INCOMING_RESURRECT_CHANGED",
	}

	self.guid = 0

	-- Events
	self:RegisterEvent("RAID_TARGET_UPDATE")
	if (self == XPerl_TargetTarget) then
		self.parentid = "target"
		self.partyid = "targettarget"
		self:RegisterEvent("PLAYER_TARGET_CHANGED")
		for i, event in pairs(events) do
			XPerl_RegisterUnitEventSafe(self, event, "target")
		end
		XPerl_Register_Prediction(self, conf.targettarget, function(guid)
			if guid == UnitGUID("targettarget") then
				return "targettarget"
			end
		end, "target")
		self:SetScript("OnUpdate", XPerl_TargetTarget_OnUpdate)
	elseif (self == XPerl_FocusTarget) then
		self.parentid = "focus"
		self.partyid = "focustarget"
		self:RegisterEvent("PLAYER_FOCUS_CHANGED")
		for i, event in pairs(events) do
			XPerl_RegisterUnitEventSafe(self, event, "focus")
		end
		XPerl_Register_Prediction(self, conf.targettarget, function(guid)
			if guid == UnitGUID("focustarget") then
				return "focustarget"
			end
		end, "focus")
		self:SetScript("OnUpdate", XPerl_TargetTarget_OnUpdate)
	elseif (self == XPerl_PetTarget) then
		self.parentid = "pet"
		self.partyid = "pettarget"
		for i, event in pairs(events) do
			XPerl_RegisterUnitEventSafe(self, event, "pet")
		end
		XPerl_Register_Prediction(self, conf.targettarget, function(guid)
			if guid == UnitGUID("pettarget") then
				return "pettarget"
			end
		end, "pet")
		self:SetScript("OnUpdate", XPerl_TargetTarget_OnUpdate)
	else
		self.parentid = "targettarget"
		self.partyid = "targettargettarget"
		for i, event in pairs(events) do
			XPerl_RegisterUnitEventSafe(self, event, "target")
		end
		XPerl_Register_Prediction(self, conf.targettarget, function(guid)
			if guid == UnitGUID("targettargettarget") then
				return "targettargettarget"
			end
		end, "targettarget")
		self:SetScript("OnUpdate", XPerl_TargetTargetTarget_OnUpdate)
	end

	XPerl_SecureUnitButton_OnLoad(self, self.partyid, XPerl_ShowGenericMenu)
	XPerl_SecureUnitButton_OnLoad(self.nameFrame, self.partyid, XPerl_ShowGenericMenu)

	--RegisterUnitWatch(self)

	local BuffOnUpdate, DebuffOnUpdate, BuffUpdateTooltip, DebuffUpdateTooltip
	BuffUpdateTooltip = XPerl_Unit_SetBuffTooltip
	DebuffUpdateTooltip = XPerl_Unit_SetDeBuffTooltip

	if buffSetup then
		self.buffSetup = buffSetup
	else
		self.buffSetup = {
			buffScripts = {
				OnEnter = XPerl_Unit_SetBuffTooltip,
				OnUpdate = BuffOnUpdate,
				OnLeave = XPerl_PlayerTipHide,
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

	self.targetname = ""
	self.lastUpdate = 0

	--XPerl_InitFadeFrame(self)
	XPerl_RegisterHighlight(self.highlight, 2)
	XPerl_RegisterPerlFrames(self, {self.nameFrame, self.statsFrame, self.levelFrame})

	if XPerlDB then
		self.conf = XPerlDB[self.partyid]
	end

	XPerl_Highlight:Register(XPerl_TargetTarget_HighlightCallback, self)

	if self == XPerl_TargetTarget then
		XPerl_RegisterOptionChanger(XPerl_TargetTarget_Set_Bits, "TargetTarget")
	end

	if XPerl_TargetTarget and XPerl_FocusTarget and XPerl_PetTarget and XPerl_TargetTargetTarget then
		ZPerl_TargetTarget_OnLoad = nil
	end
end

-- XPerl_TargetTarget_HighlightCallback
function XPerl_TargetTarget_HighlightCallback(self, updateGUID)
	local partyid = self.partyid
	local guid = UnitGUID(partyid)
	if guid and XPerl_CanAccess(guid) and guid == updateGUID and UnitIsFriend("player", partyid) then
		XPerl_Highlight:SetHighlight(self, updateGUID)
	end
end

-------------------------
-- The Update Function --
-------------------------
local function XPerl_TargetTarget_UpdatePVP(self)
	local partyid = self.partyid
	-- Z-Perl Forever: indirect units can return secret flags; no icon in that case
	local ffa, isPvP, faction = UnitIsPVPFreeForAll(partyid), UnitIsPVP(partyid), UnitFactionGroup(partyid)
	if (not XPerl_CanAccess(ffa) or not XPerl_CanAccess(isPvP) or (faction ~= nil and not XPerl_CanAccess(faction))) then
		self.nameFrame.pvpIcon:Hide()
		return
	end
	local pvp = self.conf.pvpIcon and ((ffa and "FFA") or (isPvP and (faction ~= "Neutral") and faction))
	if pvp then
		self.nameFrame.pvpIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-"..pvp)
		self.nameFrame.pvpIcon:Show()
	else
		self.nameFrame.pvpIcon:Hide()
	end
end

-- XPerl_TargetTarget_BuffPositions
local function XPerl_TargetTarget_BuffPositions(self)
	if (self.partyid and XPerl_SafeBool(UnitCanAttack("player", self.partyid), false)) then
		XPerl_Unit_BuffPositions(self, self.buffFrame.debuff, self.buffFrame.buff, self.conf.debuffs.size, self.conf.buffs.size)
	else
		XPerl_Unit_BuffPositions(self, self.buffFrame.buff, self.buffFrame.debuff, self.conf.buffs.size, self.conf.debuffs.size)
	end
end

-- Z-Perl Forever: AuraContainer fallback -- real icons while auras are secret.
-- buffFrame and debuffFrame share one XML rectangle, so each takes half, with
-- hostile units putting debuffs first as the classic layout above does.
-- See CLAUDE.md pattern 15 before changing this.

-- XPerl_TargetTarget_AuraContainer_Setup
local function XPerl_TargetTarget_AuraContainer_Setup(self)
	if (not XPerl_HasAuraContainerNow() or self.buffContainer) then
		return
	end

	local debuffsFirst = XPerl_SafeBool(UnitCanAttack("player", self.partyid), false)
	local showSwipe = conf.buffs.cooldown and true or false
	-- Wrap at the frame's full width and cap the rows, like the normal layout
	local lineSize = 2000
	if (self.conf.buffs.wrap) then
		lineSize = self.statsFrame:GetWidth()
		if (self.levelFrame and self.levelFrame:IsShown()) then
			lineSize = lineSize - 2 + self.levelFrame:GetWidth()
		end
	end
	local rows = self.conf.buffs.rows
	local function MaxIcons(size)
		if (self.conf.buffs.wrap and rows and rows > 0) then
			return min(40, max(1, floor((lineSize + 1) / (size + 1))) * rows)
		end
	end

	local buffContainer, buffHalf = XPerl_AuraContainer_Create(self, "buffHalfFrame",
		self:GetName().."AuraBuffs", "buffs", "HELPFUL", self.conf.buffs.size, lineSize, showSwipe, MaxIcons(self.conf.buffs.size))
	local debuffContainer, debuffHalf = XPerl_AuraContainer_Create(self, "debuffHalfFrame",
		self:GetName().."AuraDebuffs", "debuffs", "HARMFUL", self.conf.debuffs.size, lineSize, showSwipe, MaxIcons(self.conf.debuffs.size))

	local firstHalf, secondHalf = buffHalf, debuffHalf
	if (debuffsFirst) then
		firstHalf, secondHalf = debuffHalf, buffHalf
	end
	firstHalf:ClearAllPoints()
	firstHalf:SetPoint("TOPLEFT", self.buffFrame, "TOPLEFT", 0, 0)
	firstHalf:SetPoint("BOTTOMRIGHT", self.buffFrame, "RIGHT", 0, 0)
	secondHalf:ClearAllPoints()
	secondHalf:SetPoint("TOPLEFT", self.buffFrame, "LEFT", 0, 0)
	secondHalf:SetPoint("BOTTOMRIGHT", self.buffFrame, "BOTTOMRIGHT", 0, 0)

	self.buffContainer, self.debuffContainer = buffContainer, debuffContainer
end

-- XPerl_TargetTarget_AuraContainer_Rebuild
local function XPerl_TargetTarget_AuraContainer_Rebuild(self)
	if (not XPerl_HasAuraContainerNow()) then
		return
	end
	if (not self.buffContainer) then
		XPerl_TargetTarget_AuraContainer_Setup(self)
		return
	end
	if (not XPerl_AuraContainer_SafeToReconfigure()) then
		self.auraContainerPending = true
		return
	end
	self.auraContainerPending = nil
	self.buffContainer:Hide()
	self.debuffContainer:Hide()
	self.buffContainer, self.debuffContainer = nil, nil
	XPerl_TargetTarget_AuraContainer_Setup(self)
end

local function XPerl_TargetTarget_AuraContainer_Hide(self)
	self.buffContainer:Hide()
	self.debuffContainer:Hide()
	if (self.auraContainerPending) then
		XPerl_TargetTarget_AuraContainer_Rebuild(self)
	end
end

-- XPerl_TargetTarget_Buff_UpdateAll
local function XPerl_TargetTarget_Buff_UpdateAll(self)
	XPerl_TargetTarget_AuraContainer_Rebuild(self)

	if (self.buffContainer and XPerl_AurasSecret()) then
		self.buffFrame:Hide()
		self.debuffFrame:Hide()
		XPerl_AuraContainer_ShowPair(self, self.conf.buffs.enable, self.conf.debuffs.enable)
		return
	elseif (self.buffContainer) then
		XPerl_TargetTarget_AuraContainer_Hide(self)
	end

	if self.conf.buffs.enable then
		self.buffFrame:Show()
	else
		self.buffFrame:Hide()
	end
	if self.conf.debuffs.enable then
		self.debuffFrame:Show()
	else
		self.debuffFrame:Hide()
	end
	if self.conf.buffs.enable or self.conf.debuffs.enable then
		--XPerl_Targets_BuffUpdate(self)
		XPerl_Unit_UpdateBuffs(self, nil, nil, self.conf.buffs.castable, self.conf.debuffs.curable)
		XPerl_TargetTarget_BuffPositions(self)
	end
end

-- XPerl_TargetTarget_RaidIconUpdate
local function XPerl_TargetTarget_RaidIconUpdate(self)
	local frameRaidIcon = self.nameFrame.raidIcon
	local frameNameFrame = self.nameFrame

	XPerl_Update_RaidIcon(frameRaidIcon, self.partyid)

	frameRaidIcon:ClearAllPoints()
	if conf.target.raidIconAlternate then
		frameRaidIcon:SetHeight(16)
		frameRaidIcon:SetWidth(16)
		frameRaidIcon:SetPoint("CENTER", frameNameFrame, "TOPRIGHT", -5, -4)
	else
		frameRaidIcon:SetHeight(32)
		frameRaidIcon:SetWidth(32)
		frameRaidIcon:SetPoint("CENTER", frameNameFrame, "CENTER", 0, 0)
	end
end

-- XPerl_TargetTarget_UpdateDisplay
function XPerl_TargetTarget_UpdateDisplay(self, force)
	if not self.conf then
		self.conf = XPerlDB and XPerlDB[self.partyid]
		if not self.conf then
			return
		end
	end
	local partyid = self.partyid
	if not partyid then
		self.targethp = 0
		self.targethpmax = 0
		self.targetmanatype = 0
		self.targetmana = 0
		self.targetmanamax = 0
		self.afk = false
		self.guid = nil
		return
	end
	if self.conf.enable and UnitExists(self.parentid) and XPerl_SafeBool(UnitIsConnected(partyid), true) then
		-- Z-Perl Forever: full "First Last" (or "First-Realm") display name
		self.targetname = XPerl_UnitFullName(partyid)
		if self.targetname then
			local t = GetTime()
			if not force and t < (self.lastUpdate + 0.3) then
				return
			end
			XPerl_Highlight:RemoveHighlight(self)
			self.lastUpdate = t

			XPerl_TargetTarget_UpdatePVP(self)

			-- Save these, so we know whether to update the frame later
			--self.targethp = UnitIsGhost(partyid) and 1 or (UnitIsDead(partyid) and 0 or XPerl_Unit_GetHealth(self))
			--self.targethpmax = UnitHealthMax(partyid)
			--self.targetmanatype = UnitPowerType(partyid)
			--self.targetmana = UnitPower(partyid)
			--self.targetmanamax = UnitPowerMax(partyid)
			--self.afk = UnitIsAFK(partyid) and conf.showAFK
			self.guid = UnitGUID(partyid)

			XPerl_SetUnitNameColor(self.nameFrame.text, partyid)

			if self.conf.level then
				local TargetTargetLevel = UnitLevel(partyid)
				local classification = UnitClassification(partyid)

				self.levelFrame.text:Show()
				self.levelFrame.skull:Hide()
				if (not XPerl_CanAccess(TargetTargetLevel) or not XPerl_CanAccess(classification)) then
					-- Z-Perl Forever: creature levels are secret inside instances
					self.levelFrame:SetWidth(27)
					self.levelFrame.text:SetText(TargetTargetLevel)
					self.levelFrame.text:SetTextColor(1, 1, 1)
				else
					local color = GetDifficultyColor(TargetTargetLevel)
					if TargetTargetLevel == -1 then
						if classification == "worldboss" then
							TargetTargetLevel = "Boss"
						else
							self.levelFrame.text:Hide()
							self.levelFrame.skull:Show()
						end
					elseif (strfind(classification or "", "elite")) then
						TargetTargetLevel = TargetTargetLevel.."+"
						self.levelFrame:SetWidth(33)
					else
						self.levelFrame:SetWidth(27)
					end

					self.levelFrame.text:SetText(TargetTargetLevel)

					if TargetTargetLevel == "Boss" then
						-- Z-Perl Forever: GetStringWidth() can be secret even
						-- for plain text (section 3 taint-propagation nuance)
						XPerl_SafeSetWidthFromText(self.levelFrame, self.levelFrame.text, 6, 33)
						color = {r = 1, g = 0, b = 0}
					end

					self.levelFrame.text:SetTextColor(color.r, color.g, color.b)
				end
			end

			-- Set name - Must do after level as the NameFrame can change size just above here.
			local TargetTargetname = self.targetname
			self.nameFrame.text:SetText(TargetTargetname)

			-- Set health
			XPerl_Target_UpdateHealth(self)

			-- Set mana
			if not self.statsFrame.greyMana then
				XPerl_Target_SetManaType(self)
			end
			XPerl_Target_SetMana(self)

			XPerl_TargetTarget_RaidIconUpdate(self)

			--XPerl_TargetTarget_BuffPositions(self)		-- Moved to option set to save garbage production
			XPerl_TargetTarget_Buff_UpdateAll(self)

			XPerl_UpdateSpellRange(self, partyid)
			XPerl_Highlight:SetHighlight(self, UnitGUID(partyid))
			return
		end
	end

	self.targetname = ""
	XPerl_Highlight:RemoveHighlight(self)
end

-- XPerl_TargetTarget_Update_Control
local function XPerl_TargetTarget_Update_Control(self)
	local partyid = self.partyid
	-- Z-Perl Forever: indirect units can return secret flags; no icon in that case
	if XPerl_SafeBool(UnitIsVisible(partyid), false) and XPerl_SafeBool(UnitIsCharmed(partyid), false) and XPerl_SafeBool(UnitIsPlayer(self.partyid), false) then
		self.nameFrame.warningIcon:Show()
	else
		self.nameFrame.warningIcon:Hide()
	end
end

-- XPerl_TargetTarget_Update_Combat
local function XPerl_TargetTarget_Update_Combat(self)
	local inCombat = UnitAffectingCombat(self.partyid)
	if (XPerl_IsSecret(inCombat)) then
		-- Z-Perl Forever: let the widget resolve the secret boolean
		self.nameFrame.combatIcon:Show()
		XPerl_SetAlphaFromBoolean(self.nameFrame.combatIcon, inCombat, 1, 0)
	elseif inCombat then
		self.nameFrame.combatIcon:SetAlpha(1)
		self.nameFrame.combatIcon:Show()
	else
		self.nameFrame.combatIcon:Hide()
	end
end

-- XPerl_TargetTarget_SecretPoll
-- Z-Perl Forever: when the unit's values are secret nothing can be compared to
-- decide whether something changed, so the bars are refreshed on a short timer.
local function XPerl_TargetTarget_SecretPoll(self, elapsed)
	self.secretTime = elapsed + (self.secretTime or 0)
	if (self.secretTime >= 0.2) then
		self.secretTime = 0
		XPerl_Target_UpdateHealth(self)
		XPerl_Target_SetManaType(self)
		XPerl_Target_SetMana(self)
	end
end

-- XPerl_TargetTarget_GuidChanged
local function XPerl_TargetTarget_GuidChanged(self, newGuid)
	if (not XPerl_CanAccess(newGuid) or not XPerl_CanAccess(self.guid)) then
		return false
	end
	return newGuid ~= self.guid
end

-- XPerl_TargetTarget_OnUpdate
function XPerl_TargetTarget_OnUpdate(self, elapsed)
	local partyid = self.partyid

	local newGuid = UnitGUID(partyid)
	local newHP, newHPMax = XPerl_Unit_GetHealth(self)
	local newManaType = UnitPowerType(partyid)
	local newMana = UnitPower(partyid)
	local newManaMax = UnitPowerMax(partyid)
	local newAFK = XPerl_SafeBool(UnitIsAFK(partyid), false)

	if (XPerl_IsSecret(newHP) or XPerl_IsSecret(newHPMax) or XPerl_IsSecret(newMana) or XPerl_IsSecret(newManaMax)) then
		XPerl_TargetTarget_SecretPoll(self, elapsed)
	else
		if (conf.showAFK and newAFK ~= self.afk) or (newHP ~= self.targethp) or (newHPMax ~= self.targethpmax) then
			XPerl_Target_UpdateHealth(self)
		end

		if (newManaType ~= self.targetmanatype) then
			XPerl_Target_SetManaType(self)
			XPerl_Target_SetMana(self)
		end

		if (newMana ~= self.targetmana) or (newManaMax ~= self.targetmanamax) then
			XPerl_Target_SetMana(self)
		end
	end

	if (XPerl_TargetTarget_GuidChanged(self, newGuid)) then
		XPerl_TargetTarget_UpdateDisplay(self)
	else
		self.time = elapsed + (self.time or 0)
		if self.time >= 0.5 then
			XPerl_TargetTarget_Update_Combat(self)
			XPerl_TargetTarget_Update_Control(self)
			XPerl_TargetTarget_UpdatePVP(self)
			if self.conf.buffs.enable or self.conf.debuffs.enable then
				XPerl_Unit_UpdateBuffs(self, nil, nil, self.conf.buffs.castable, self.conf.debuffs.curable)
				XPerl_TargetTarget_BuffPositions(self)
			end
			--XPerl_TargetTarget_Buff_UpdateAll(self)
			XPerl_SetUnitNameColor(self.nameFrame.text, partyid)
			XPerl_UpdateSpellRange(self, partyid)
			if (not XPerl_CanAccess(newGuid)) then
				-- Secret GUID: target changes cannot be spotted, so refresh here
				XPerl_TargetTarget_UpdateDisplay(self)
			end
			--XPerl_Highlight:SetHighlight(self, UnitGUID(partyid))
			self.time = 0
		end
	end
end

-- XPerl_TargetTargetTarget_OnUpdate
function XPerl_TargetTargetTarget_OnUpdate(self, elapsed)
	local partyid = self.partyid

	local newGuid = UnitGUID(partyid)
	local newHP, newHPMax = XPerl_Unit_GetHealth(self)
	local newManaType = UnitPowerType(partyid)
	local newMana = UnitPower(partyid)
	local newAFK = XPerl_SafeBool(UnitIsAFK(partyid), false)

	if (XPerl_IsSecret(newHP) or XPerl_IsSecret(newHPMax) or XPerl_IsSecret(newMana)) then
		XPerl_TargetTarget_SecretPoll(self, elapsed)
	else
		if (conf.showAFK and newAFK ~= self.afk) or (newHP ~= self.targethp) then
			XPerl_Target_UpdateHealth(self)
		end

		if (newManaType ~= self.targetmanatype) then
			XPerl_Target_SetManaType(self)
			XPerl_Target_SetMana(self)
		end

		if (newMana ~= self.targetmana) then
			XPerl_Target_SetMana(self)
		end
	end

	if (XPerl_TargetTarget_GuidChanged(self, newGuid)) then
		XPerl_TargetTarget_UpdateDisplay(self)
	else
		self.time = elapsed + (self.time or 0)
		if self.time >= 0.5 then
			XPerl_TargetTarget_Update_Combat(self)
			XPerl_TargetTarget_Update_Control(self)
			XPerl_TargetTarget_UpdatePVP(self)
			if self.conf.buffs.enable or self.conf.debuffs.enable then
				XPerl_Unit_UpdateBuffs(self, nil, nil, self.conf.buffs.castable, self.conf.debuffs.curable)
				XPerl_TargetTarget_BuffPositions(self)
			end
			--XPerl_TargetTarget_Buff_UpdateAll(self)
			XPerl_SetUnitNameColor(self.nameFrame.text, partyid)
			XPerl_UpdateSpellRange(self, partyid)
			if (not XPerl_CanAccess(newGuid)) then
				XPerl_TargetTarget_UpdateDisplay(self)
			end
			--XPerl_Highlight:SetHighlight(self, UnitGUID(partyid))
			self.time = 0
		end
	end

	--XPerl_TargetTarget_OnUpdate(self, elapsed)
end

-------------------
-- Event Handler --
-------------------
function XPerl_TargetTarget_OnEvent(self, event, unitID, ...)
	if event == "RAID_TARGET_UPDATE" then
		XPerl_TargetTarget_RaidIconUpdate(self)
	elseif event == "PLAYER_TARGET_CHANGED" then
		XPerl_TargetTarget_UpdateDisplay(self, true)
	elseif event == "PLAYER_FOCUS_CHANGED" then
		XPerl_TargetTarget_UpdateDisplay(self, true)
	elseif event == "INCOMING_RESURRECT_CHANGED" then
		XPerl_Target_UpdateResurrectionStatus(self)
	elseif strfind(event, "^UNIT_") then
		if (unitID == "target") and (self == XPerl_TargetTarget or self == XPerl_TargetTargetTarget) then
			XPerl_NoFadeBars(true)
			XPerl_TargetTarget_UpdateDisplay(self, true)
			if XPerl_FocusTarget and XPerl_FocusTarget:IsShown() then
				XPerl_TargetTarget_UpdateDisplay(XPerl_FocusTarget, true)
			end
			XPerl_NoFadeBars()
		elseif unitID == "focus" and self == XPerl_FocusTarget then
			XPerl_NoFadeBars(true)
			XPerl_TargetTarget_UpdateDisplay(self, true)
			XPerl_NoFadeBars()
		elseif unitID == "pet" and self == XPerl_PetTarget then
			XPerl_NoFadeBars(true)
			XPerl_TargetTarget_UpdateDisplay(self, true)
			if XPerl_FocusTarget and XPerl_FocusTarget:IsShown() then
				XPerl_TargetTarget_UpdateDisplay(XPerl_FocusTarget, true)
			end
			XPerl_NoFadeBars()
		end
	end
end

-- XPerl_TargetTarget_Update
function XPerl_TargetTarget_Update(self)
	local offset = -3
	if self.conf.buffs.enable then
		if UnitExists("targettarget") then
			if XPerl_UnitBuff("targettarget", 1) then
				if (offset == -3) then
					offset = 0
				end
				offset = offset + 20
				local name = XPerl_UnitAuraByIndex("targettarget", 9, "HELPFUL")
				if name then
					offset = offset + 20
				end
			end
			if XPerl_UnitDebuff("targettarget", 1) then
				if (offset == -3) then
					offset = 0
				end
				offset = offset + 24
			end
		end
	end
end

-- EnableDisable
local function EnableDisable(self)
	if self.conf.enable then
		if not self.virtual then
			RegisterUnitWatch(self)
		end
	else
		UnregisterUnitWatch(self)
		self:Hide()
	end
end

-- XPerl_TargetTarget_SetWidth
function XPerl_TargetTarget_SetWidth(self)

	self.conf.size.width = max(0, self.conf.size.width or 0)
	local bonus = self.conf.size.width

	if self.conf.percent then
		if (not InCombatLockdown()) then
			self:SetWidth(160 + bonus)
			self.nameFrame:SetWidth(160 + bonus)
			self.statsFrame:SetWidth(160 + bonus)
		end
		self.statsFrame.healthBar.percent:Show()
		self.statsFrame.manaBar.percent:Show()
	else
		if (not InCombatLockdown()) then
			self:SetWidth(128 + bonus)
			self.nameFrame:SetWidth(128 + bonus)
			self.statsFrame:SetWidth(128 + bonus)
		end
		self.statsFrame.healthBar.percent:Hide()
		self.statsFrame.manaBar.percent:Hide()
	end

	self.conf.scale = self.conf.scale or 0.8
	if (not InCombatLockdown()) then
		self:SetScale(self.conf.scale)
	end

	XPerl_SavePosition(self, true)

	XPerl_StatsFrameSetup(self)
end

-- Set
local function Set(self)
	if not self.conf then
		self.conf = XPerlDB and XPerlDB[self.partyid]
		if not self.conf then
			return
		end
	end
	if self.conf.level then
		self.levelFrame:Show()
		self.levelFrame:SetWidth(27)
	else
		self.levelFrame:Hide()
	end

	if self.conf.mana then
		self.statsFrame.manaBar:Show()
		self.statsFrame:SetHeight(40)
	else
		self.statsFrame.manaBar:Hide()
		self.statsFrame:SetHeight(30)
	end

	if self.conf.values then
		self.statsFrame.healthBar.text:Show()
		self.statsFrame.manaBar.text:Show()
	else
		self.statsFrame.healthBar.text:Hide()
		self.statsFrame.manaBar.text:Hide()
	end

	self.buffFrame:ClearAllPoints()
	if self.conf.buffs.above then
		self.buffFrame:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 2, 0)
	else
		self.buffFrame:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 2, 0)
	end
	self.buffOptMix = nil
	self.conf.buffs.size = tonumber(self.conf.buffs.size) or 20

	XPerl_SetBuffSize(self)

	XPerl_TargetTarget_SetWidth(self)

	XPerl_ProtectedCall(EnableDisable, self)

	if self:IsShown() then
		XPerl_TargetTarget_UpdateDisplay(self, true)
	end
end

-- XPerl_TargetTarget_Set_Bits
function XPerl_TargetTarget_Set_Bits()
	if not XPerl_TargetTarget then
		return
	end

	if conf.targettargettarget.enable then
		if not XPerl_TargetTargetTarget then
			local ttt = CreateFrame("Button", "XPerl_TargetTargetTarget", UIParent, "ZPerl_TargetTarget_Template")
			ttt:ClearAllPoints()
			ttt:SetPoint("TOPLEFT", XPerl_TargetTarget.statsFrame, "TOPRIGHT", 5, 0)
		end
	end

	if conf.focustarget.enable then
		if not XPerl_FocusTarget then
			local ft = CreateFrame("Button", "XPerl_FocusTarget", UIParent, "ZPerl_TargetTarget_Template")
			ft:ClearAllPoints()
			ft:SetPoint("TOPLEFT", XPerl_Focus.levelFrame, "TOPRIGHT", 5, 0)
		end
	end

	if conf.pettarget.enable and XPerl_Player_Pet then
		if not XPerl_PetTarget then
			local pt = CreateFrame("Button", "XPerl_PetTarget", XPerl_Player_Pet, "ZPerl_TargetTarget_Template")
			pt:ClearAllPoints()
			pt:SetPoint("BOTTOMLEFT", XPerl_Player_Pet.statsFrame, "BOTTOMRIGHT", 5, 0)
		end
		if (not InCombatLockdown()) then
			XPerl_PetTarget:Show()
		end
	end

	Set(XPerl_TargetTarget)
	if XPerl_TargetTargetTarget then
		Set(XPerl_TargetTargetTarget)
	end
	if XPerl_FocusTarget then
		Set(XPerl_FocusTarget)
	end
	if XPerl_PetTarget then
		Set(XPerl_PetTarget)
	end
end
