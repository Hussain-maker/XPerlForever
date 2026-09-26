-- X-Perl UnitFrames
-- Author: Resike
-- License: GNU GPL v3, 29 June 2007 (see LICENSE.txt)

local conf, pconf
XPerl_RequestConfig(function(new)
	conf = new
	pconf = new.player
end, "$Revision:  $")

--local playerClass

--[===[@debug@
local function d(fmt, ...)
	fmt = fmt:gsub("(%%[sdqxf])", "|cFF60FF60%1|r")
	ChatFrame1:AddMessage("|cFFFF8080PlayerBuffs:|r "..format(fmt, ...), 0.8, 0.8, 0.8)
end
--@end-debug@]===]

local DebuffTypeColor = DebuffTypeColor or {
	none    = { r = 0.80, g = 0.00, b = 0.00 },
	Magic   = { r = 0.20, g = 0.60, b = 1.00 },
	Curse   = { r = 0.60, g = 0.00, b = 1.00 },
	Disease = { r = 0.60, g = 0.40, b = 0.00 },
	Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}

-- Z-Perl Forever: secret value helpers from XPerlForever.lua
local XPerl_CanAccess = XPerl_CanAccess
local XPerl_IsSecret = XPerl_IsSecret
local XPerl_UnitAuraByIndex = XPerl_UnitAuraByIndex
local XPerl_AurasSecret = XPerl_AurasSecret
local XPerl_AuraContainer_SafeToReconfigure = XPerl_AuraContainer_SafeToReconfigure
local XPerl_AuraContainer_InitButtonCommon = XPerl_AuraContainer_InitButtonCommon

-- Z-Perl Forever: retail removed SecureAuraHeaderTemplate in 10.0. When it is
-- missing, the player's buffs use Z-Perl's own buff buttons, driven exactly like
-- the target and party frames (no right-click cancelling; Blizzard's own buff
-- frame remains available for that).
local hasSecureAuraHeader = true
if (C_XMLUtil and C_XMLUtil.GetTemplateInfo) then
	hasSecureAuraHeader = C_XMLUtil.GetTemplateInfo("SecureAuraHeaderTemplate") ~= nil
end

-- XPerl_Player_Buffs_LegacySetup
local function XPerl_Player_Buffs_LegacySetup(self)
	self.buffFrame = CreateFrame("Frame", self:GetName().."buffFrame", self)
	self.buffFrame:SetSize(10, 10)
	self.buffFrame.legacy = true
	self.debuffFrame = CreateFrame("Frame", self:GetName().."debuffFrame", self)
	self.debuffFrame:SetSize(10, 10)
	self.debuffFrame.legacy = true

	self.buffSetup = {
		buffScripts = {
			OnEnter = XPerl_Unit_SetBuffTooltip,
			OnLeave = XPerl_PlayerTipHide,
		},
		debuffScripts = {
			OnEnter = XPerl_Unit_SetDeBuffTooltip,
			OnLeave = XPerl_PlayerTipHide,
		},
		updateTooltipBuff = XPerl_Unit_SetBuffTooltip,
		updateTooltipDebuff = XPerl_Unit_SetDeBuffTooltip,
		debuffParent = true,
		debuffSizeMod = 0,
		debuffAnchor1 = function(self, b)
			b:SetPoint("TOPLEFT", 0, 0)
		end,
	}
	self.buffSetup.buffAnchor1 = self.buffSetup.debuffAnchor1
end

-- Z-Perl Forever: AuraContainer fallback -- real icons while auras are secret.
-- Per-aura styling is unavailable in that state; see CLAUDE.md pattern 15.

-- XPerl_Player_AuraContainer_Setup
local function XPerl_Player_AuraContainer_Setup(self)
	if (not XPerl_HasAuraContainerNow() or hasSecureAuraHeader or self.buffContainer) then
		return
	end

	-- "mine" is per-aura data, unavailable via the container (see above), so
	-- cooldownAny can't be honoured here: show the swipe on everything or
	-- nothing.
	local showSwipe = conf.buffs.cooldown and true or false
	local lineSize = pconf.buffs.wrap and self:GetWidth() or 2000

	-- Separate buffFrame/debuffFrame rectangles here, so each holder anchors to
	-- its own. Both are 10x10 until the classic path grows them, which is why
	-- the container must never be SetAllPoints'd onto them.
	local buffContainer, buffHolder = XPerl_AuraContainer_Create(self, "buffContainerHolder",
		self:GetName().."AuraBuffs", "buffs", "HELPFUL", pconf.buffs.size, lineSize, showSwipe)
	buffHolder:ClearAllPoints()
	buffHolder:SetPoint("TOPLEFT", self.buffFrame, "TOPLEFT", 0, 0)

	local debuffContainer, debuffHolder = XPerl_AuraContainer_Create(self, "debuffContainerHolder",
		self:GetName().."AuraDebuffs", "debuffs", "HARMFUL", pconf.debuffs.size, lineSize, showSwipe)
	debuffHolder:ClearAllPoints()
	debuffHolder:SetPoint("TOPLEFT", self.debuffFrame, "TOPLEFT", 0, 0)

	self.buffContainer, self.debuffContainer = buffContainer, debuffContainer
end

-- XPerl_Player_AuraContainer_Rebuild
-- Tears down and recreates the containers so an option change reaches fresh
-- buttons through their one safe styling window (initializeFrame) -- an
-- already-adopted button can reject live restyling while auras are secret
-- (confirmed against TPerl's own AuraContainer code, not copied from it).
-- Deferred via self.auraContainerPending when that's the case right now.
local function XPerl_Player_AuraContainer_Rebuild(self)
	if (not XPerl_HasAuraContainerNow() or hasSecureAuraHeader) then
		return
	end
	-- Z-Perl Forever: build even while secret when there's no container yet --
	-- nothing live to disturb, and it's the one case SafeToReconfigure's own
	-- rule allows. See the matching comment in XPerlForever_Target.lua.
	if (not self.buffContainer) then
		XPerl_Player_AuraContainer_Setup(self)
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
	XPerl_Player_AuraContainer_Setup(self)
end

-- XPerl_Player_AuraContainer_Show / _Hide
-- Switches the player frame between the classic by-index icons and this
-- fallback; _Hide also applies a rebuild that arrived while auras were secret.
local function XPerl_Player_AuraContainer_Show(self)
	XPerl_AuraContainer_ShowPair(self, pconf.buffs.enable, pconf.buffs.enable and pconf.debuffs.enable)
end

local function XPerl_Player_AuraContainer_Hide(self)
	self.buffContainer:Hide()
	self.debuffContainer:Hide()
	if (self.auraContainerPending) then
		XPerl_Player_AuraContainer_Rebuild(self)
	end
end

-- XPerl_Player_Buffs_Update
-- Refreshes the legacy buff buttons; does nothing while the secure header is in use
function XPerl_Player_Buffs_Update(self)
	if (not self or not self.buffFrame or not self.buffFrame.legacy or not self.conf or not pconf) then
		return
	end

	-- Hand over to the container while secret; the classic path resumes after.
	-- Hiding buffFrame/debuffFrame hides every classic icon (they parent them);
	-- XPerl_Unit_UpdateBuffs re-Shows them itself, so handback needs nothing.
	if (self.buffContainer and XPerl_AurasSecret()) then
		self.buffFrame:Hide()
		self.debuffFrame:Hide()
		XPerl_Player_AuraContainer_Show(self)
		return
	elseif (self.buffContainer) then
		XPerl_Player_AuraContainer_Hide(self)
	end

	if (pconf.buffs.enable or pconf.debuffs.enable) then
		XPerl_Unit_UpdateBuffs(self, nil, nil, pconf.buffs.castable, pconf.debuffs.curable)
		XPerl_Unit_BuffPositions(self, self.buffFrame.buff, self.buffFrame.debuff, pconf.buffs.size, pconf.debuffs.size)
	end
end

-- setCommon
local function setCommon(self, filter, buffTemplate)
	if (self.legacy) then
		return
	end
	self:SetAttribute("template", buffTemplate)
	self:SetAttribute("weaponTemplate", buffTemplate)
	self:SetAttribute("useparent-unit", true)

	self:SetAttribute("filter", filter)
	self:SetAttribute("separateOwn", 1)
	
	if (filter == "HELPFUL") then
		self:SetAttribute("includeWeapons", 1)
	end
	
	self:SetAttribute("point", pconf.buffs.above and "BOTTOMLEFT" or "TOPLEFT")
	if (pconf.buffs.wrap) then
		self:SetAttribute("wrapAfter", max(1, floor(XPerl_Player:GetWidth() / pconf.buffs.size)))	-- / XPerl_Player:GetEffectiveScale()
	else
		self:SetAttribute("wrapAfter", 0)
	end
	self:SetAttribute("maxWraps", pconf.buffs.rows)
	self:SetAttribute("xOffset", 32)
	self:SetAttribute("yOffset", 0)
	self:SetAttribute("wrapXOffset", 0)
	self:SetAttribute("wrapYOffset", pconf.buffs.above and 32 or -32)

	self:SetAttribute("minWidth", 32)
	self:SetAttribute("minHeight", 32)

	self:SetAttribute("initial-width", pconf.buffs.size)
	self:SetAttribute("initial-height", pconf.buffs.size)
	-- Workaround: We can't set the initial-width/height (beacuse the api ignores this so far)
	-- So, we'll scale the parent frame so the effective size matches our setting

	if (filter == "HELPFUL" and pconf.buffs) then
		local needScale = pconf.buffs.size / 32
		self:SetScale(needScale)
	elseif (pconf.debuffs) then
		local needScale = pconf.debuffs.size / pconf.buffs.size
		self:SetScale(needScale)
	end
end

-- XPerl_Player_Buffs_Position
function XPerl_Player_Buffs_Position(self)
	if (self.buffFrame and not InCombatLockdown()) then
		self.buffFrame:ClearAllPoints()
		self.debuffFrame:ClearAllPoints()

		if (pconf.buffs.above) then
			self.buffFrame:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 3, 0)
		else
			local _, playerClass = UnitClass("player")
			local extraBar

			if (playerClass == "DRUID" and UnitPowerType(self.partyid) > 0 and not pconf.noDruidBar) or (playerClass == "PRIEST" and UnitPowerType(self.partyid) > 0 and not pconf.noDruidBar) then
				extraBar = 1
			else
				extraBar = 0
			end

			local offset = ((extraBar + (pconf.repBar and 1 or 0) + (pconf.xpBar and 1 or 0)) * 13.5)

			if (self.runes and self.runes:IsShown() and ((self.runes.child and self.runes.child:IsShown()) or (self.runes.child2 and self.runes.child2:IsShown())) and pconf.dockRunes) then
				if pconf.extendPortrait then
					self.buffFrame:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 5, 0 - 28)
				else
					self.buffFrame:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 5, 0 - offset - 28)
				end
			else
				if pconf.extendPortrait then
					self.buffFrame:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 5, 0)
				else
					self.buffFrame:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 5, 0 - offset)
				end
			end
		end

		if (pconf.buffs.above) then
			self.debuffFrame:SetPoint("BOTTOMLEFT", self.buffFrame, "TOPLEFT", 0, 2)
		else
			self.debuffFrame:SetPoint("TOPLEFT", self.buffFrame, "BOTTOMLEFT", 0, -2)
		end

		XPerl_Unit_BuffPositions(self, self.buffFrame.buff, self.buffFrame.debuff, pconf.buffs.size, pconf.debuffs.size)
	end
end

-- XPerl_Player_BuffSetup
function XPerl_Player_BuffSetup(self)
	if (not self) then
		return
	end

	if (InCombatLockdown()) then
		XPerl_OutOfCombatQueue[XPerl_Player_BuffSetup] = self
		return
	end

	if (not self.buffFrame) then
		if (not hasSecureAuraHeader) then
			XPerl_Player_Buffs_LegacySetup(self)
		else
			self.buffFrame = CreateFrame("Frame", self:GetName().."buffFrame", self, "SecureAuraHeaderTemplate")
			self.debuffFrame = CreateFrame("Frame", self:GetName().."debuffFrame", self.buffFrame, "SecureAuraHeaderTemplate")

			self.buffFrame:SetAttribute("frameStrata", "DIALOG")

			self.buffFrame.BuffFrameUpdateTime = 0
			self.buffFrame.BuffFrameFlashTime = 0
			self.buffFrame.BuffFrameFlashState = 1
			self.buffFrame.BuffAlphaValue = 1
		end
	end

	if (self.buffFrame) then
		if pconf.buffs.enable then
			setCommon(self.buffFrame, "HELPFUL", (C_CVar.GetCVar("ActionButtonUseKeyDown") == "1" and "XPerl_Secure_Classic_Down_BuffTemplate" or "XPerl_Secure_Classic_BuffTemplate"))
			self.buffFrame:Show()
		else
			self.buffFrame:Hide()
		end
	end

	if (self.debuffFrame) then
		if pconf.buffs.enable and pconf.debuffs.enable then
			setCommon(self.debuffFrame, "HARMFUL", (C_CVar.GetCVar("ActionButtonUseKeyDown") == "1" and "XPerl_Secure_Classic_Down_BuffTemplate" or "XPerl_Secure_Classic_BuffTemplate"))
			self.debuffFrame:Show()
		else
			self.debuffFrame:Hide()
		end
	end

	-- Z-Perl Forever: (re)build the AuraContainer fallback so it picks up any
	-- option change; no-ops on clients without it, deferred while secret.
	XPerl_Player_AuraContainer_Rebuild(self)

	XPerl_Player_Buffs_Position(self)
	XPerl_Player_Buffs_Update(self)

	if (not pconf.buffs.enable) then
		if (self.buffFrame) then
			self.buffFrame:Hide()
			self.debuffFrame:Hide()
		end
	end

	if (pconf.buffs.hideBlizzard) then
		BuffFrame:UnregisterEvent("UNIT_AURA")
		BuffFrame:Hide()
		-- Use the secure attribute driver to keep BuffFrame hidden even during combat,
		-- preventing game updates (e.g. PLAYER_REGEN_DISABLED) from re-showing it.
		RegisterAttributeDriver(BuffFrame, "state-visibility", "hide")
		if _G.TemporaryEnchantFrame then
			_G.TemporaryEnchantFrame:Hide()
			RegisterAttributeDriver(_G.TemporaryEnchantFrame, "state-visibility", "hide")
		end
	else
		UnregisterAttributeDriver(BuffFrame, "state-visibility")
		BuffFrame:Show()
		BuffFrame:RegisterEvent("UNIT_AURA")
		if _G.TemporaryEnchantFrame then
			UnregisterAttributeDriver(_G.TemporaryEnchantFrame, "state-visibility")
			_G.TemporaryEnchantFrame:Show()
		end
	end
end

local function XPerl_Player_Buffs_Set_Bits(self)
	if (InCombatLockdown()) then
		XPerl_OutOfCombatQueue[XPerl_Player_Buffs_Set_Bits] = self
		return
	end

	--local _, class = UnitClass("player")
	--playerClass = class

	XPerl_Player_BuffSetup(self)

	self.state:SetFrameRef("ZPerlPlayerBuffs", self.buffFrame)
	self.state:SetAttribute("buffsAbove", pconf.buffs.above)

	local buffs = self.buffFrame
	if buffs then
		if pconf.buffs.enable then
			setCommon(buffs, "HELPFUL", (C_CVar.GetCVar("ActionButtonUseKeyDown") == "1" and "XPerl_Secure_Classic_Down_BuffTemplate" or "XPerl_Secure_Classic_BuffTemplate"))
			buffs:Show()
		else
			buffs:Hide()
		end
	end

	local debuffs = self.debuffFrame
	if debuffs then
		if pconf.buffs.enable and pconf.debuffs.enable then
			setCommon(debuffs, "HARMFUL", (C_CVar.GetCVar("ActionButtonUseKeyDown") == "1" and "XPerl_Secure_Classic_Down_BuffTemplate" or "XPerl_Secure_Classic_BuffTemplate"))
			debuffs:Show()
		else
			debuffs:Hide()
		end
	end

	XPerl_Player_Buffs_Position(self)
end

local function DoEnchant(self, slotID, hasEnchant, expire, charges)
	if (hasEnchant) then
		-- Z-Perl Forever: a secret expiry cannot be used for the timer
		if (not XPerl_CanAccess(expire)) then
			expire = nil
		end
		if (not self.fullDuration and expire) then
			self.fullDuration = expire - GetTime()
			if (self.fullDuration > 1 * 60) then
				self.fullDuration = 10 * 60
			end
		end

		--self:Show()

		local textureName = GetInventoryItemTexture("player", slotID) -- Weapon Icon
		self.icon:SetTexture(textureName)
		self:SetAlpha(1)
		self.border:SetVertexColor(0.7, 0, 0.7)

		-- Handle cooldowns
		if (self.cooldown and expire and self.fullDuration and conf.buffs.cooldown and pconf.buffs.cooldown) then
			local timeEnd = GetTime() + (expire / 1000)
			local timeStart = timeEnd - self.fullDuration --(30 * 60)
			XPerl_CooldownFrame_SetTimer(self.cooldown, timeStart, self.fullDuration, 1)
		else
			self.cooldown:Hide()
			--self.endTime = nil
		end
	else
		self.fullDuration = nil
		if not InCombatLockdown() then
			self:Hide()
		end
	end
end

--local function setupButton(self)
--end

function XPerl_PlayerBuffs_Show(self)
	self:RegisterEvent("UNIT_AURA")
	--self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	XPerl_PlayerBuffs_Update(self)
end

function XPerl_PlayerBuffs_Hide(self)
	self:UnregisterEvent("UNIT_AURA")
	--self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
	XPerl_PlayerBuffs_Update(self)
end

function XPerl_PlayerBuffs_OnEvent(self, event, ...)
	if (event == "UNIT_AURA") then
		local unit = ...
		if (unit == "player" or unit == "pet" or unit == "vehicle") then
			XPerl_PlayerBuffs_Update(self)
		end
	end
end

function XPerl_PlayerBuffs_OnAttrChanged(self, attr, value)
	if (attr == "index" or attr == "filter" or attr == "target-slot") then
		XPerl_PlayerBuffs_Update(self)
	end
end

function XPerl_PlayerBuffs_OnEnter(self)
	if (conf.tooltip.enableBuffs and XPerl_TooltipModiferPressed(true)) then
		if (not conf.tooltip.hideInCombat or not InCombatLockdown()) then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 0, 0)

			local slot = self:GetAttribute("target-slot")
			if (slot) then
				GameTooltip:SetInventoryItem("player", slot)
			else
				local partyid = SecureButton_GetUnit(self:GetParent()) or "player"
				if (self:GetAttribute("filter") == "HELPFUL") then
					XPerl_TooltipSetUnitBuff(GameTooltip, partyid, self:GetID(), "HELPFUL")
				else
					XPerl_TooltipSetUnitDebuff(GameTooltip, partyid, self:GetID(), "HARMFUL")
				end
				self.UpdateTooltip = XPerl_PlayerBuffs_OnEnter
			end
		end
	end
end

function XPerl_PlayerBuffs_OnLeave(self)
	GameTooltip:Hide()
end

function XPerl_PlayerBuffs_Update(self)
	local slot = self:GetAttribute("target-slot")
	if slot then
		-- Weapon Enchant
		local hasMainHandEnchant, mainHandExpiration, mainHandCharges, mainHandEnchantID, hasOffHandEnchant, offHandExpiration, offHandCharges, offHandEnchantId = GetWeaponEnchantInfo()
		if slot == 16 then
			DoEnchant(self, 16, hasMainHandEnchant, mainHandExpiration, mainHandCharges)
		else
			DoEnchant(self, 17, hasOffHandEnchant, offHandExpiration, offHandCharges)
		end
	else
		-- Aura
		local index = self:GetAttribute("index")
		local filter = self:GetAttribute("filter")
		local unit = SecureButton_GetUnit(self:GetParent()) or "player"

		if filter and unit then
			local name, icon, applications, dispelName, duration, expirationTime, sourceUnit, _, _, _, auraInstanceID
			name, icon, applications, dispelName, duration, expirationTime, sourceUnit, _, _, _, auraInstanceID = XPerl_UnitAuraByIndex(unit, index, filter)
			self.filter = filter
			self:SetAlpha(1)

			if name and filter == "HARMFUL" then
				self.border:Show()
				if (XPerl_IsSecret(dispelName) and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor and XPerl_DispelColourCurve()) then
					-- Z-Perl Forever: Blizzard resolves the dispel colour from the curve
					local c = C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, XPerl_DispelColourCurve())
					if (c) then
						self.border:SetVertexColor(c.r, c.g, c.b)
					end
				else
					local borderColor = DebuffTypeColor[(XPerl_CanAccess(dispelName) and dispelName) or "none"] or DebuffTypeColor.none
					self.border:SetVertexColor(borderColor.r, borderColor.g, borderColor.b)
				end
			else
				self.border:Hide()
			end

			self.icon:SetTexture(icon)
			if (XPerl_IsSecret(applications)) then
				self.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 2))
				self.count:Show()
			elseif (applications or 0) > 1 then
				self.count:SetText(applications)
				self.count:Show()
			else
				self.count:Hide()
			end

			-- Handle cooldowns
			local mine = XPerl_CanAccess(sourceUnit) and sourceUnit ~= nil
			if self.cooldown and (XPerl_IsSecret(duration) or XPerl_IsSecret(expirationTime)) then
				-- Z-Perl Forever: secret aura times, let Blizzard drive the swipe
				if (conf.buffs.cooldown and (mine or conf.buffs.cooldownAny)) then
					XPerl_CooldownFrame_SetAura(self.cooldown, unit, auraInstanceID)
				else
					self.cooldown:Hide()
				end
			elseif self.cooldown and (duration or 0) ~= 0 and conf.buffs.cooldown and (mine or conf.buffs.cooldownAny) then
				local start = expirationTime - duration
				XPerl_CooldownFrame_SetTimer(self.cooldown, start, duration, 1, mine)
			else
				self.cooldown:Hide()
				--self.endTime = nil
			end
			-- TODO: Variable this
			self.cooldown:SetDrawEdge(false)
			self.cooldown:SetDrawBling(false)
			-- Blizzard Cooldown Text Support
			if not conf.buffs.blizzard then
				self.cooldown:SetHideCountdownNumbers(true)
			else
				self.cooldown:SetHideCountdownNumbers(false)
			end
			-- OmniCC Support
			if not conf.buffs.omnicc then
				self.cooldown.noCooldownCount = true
			else
				self.cooldown.noCooldownCount = nil
			end
		end
	end
end

function XPerl_PlayerBuffs_OnLoad(self)
	XPerl_SetChildMembers(self)
end


XPerl_RegisterOptionChanger(XPerl_Player_Buffs_Set_Bits, XPerl_Player)
