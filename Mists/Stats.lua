---@type string, AddonTable
local _, addonTable = ...
local ReforgeLite = addonTable.ReforgeLite
local L = addonTable.L

local StatHit = addonTable.statIds.HIT

-- Mists of Pandaria (5.4.4) stat math: rating-per-point (via ScalingTable), the
-- talent/racial stat-bonus getters, haste-buff detection, and the cap need-formulas.
-- These ReforgeLite methods are flavor-specific; the shared capPresets/cap-display code
-- calls them. Loaded by ReforgeLite.toc before Presets.lua.

local SPELL_HASTE_BUFFS = {
  51470,  -- Elemental Oath
  135678, -- Energizing Spores
  49868,  -- Mind Quickening
  24907,  -- Moonkin Aura
}

local MELEE_HASTE_BUFFS = {
  128432, -- Cackling Howl
  128433, -- Serpent's Swiftness
  113742, -- Swiftblade's Cunning
  55610,  -- Unholy Aura
  30809,  -- Unleashed Rage
}

local MASTERY_BUFFS = {
  19740,  -- Blessing of Might
  116956, -- Grace of Air
  93435,  -- Roar of Courage
  128997, -- Spirit Beast Blessing
}

local CRIT_BUFFS = {
  1459,   -- Arcane Brilliance
  24604,  -- Furious Howl
  17007,  -- Leader of the Pack
  116781, -- Legacy of the White Tiger
  126309, -- Still Water
  90309,  -- Terrifying Roar
}

local function CheckForPlayerAura(buffTable)
  return ContainsIf(buffTable, C_UnitAuras.GetPlayerAuraBySpellID)
end

---Checks if player has a spell haste buff active
---@return boolean hasSpellHaste True if any spell haste buff is active
function ReforgeLite:PlayerHasSpellHasteBuff()
  return CheckForPlayerAura(SPELL_HASTE_BUFFS)
end

---Checks if player has a melee haste buff active
---@return boolean hasMeleeHaste True if any melee haste buff is active
function ReforgeLite:PlayerHasMeleeHasteBuff()
  return CheckForPlayerAura(MELEE_HASTE_BUFFS)
end

---Checks if player has a mastery buff active
---@return boolean hasMastery True if any mastery buff is active
function ReforgeLite:PlayerHasMasteryBuff()
  return CheckForPlayerAura(MASTERY_BUFFS)
end

---Checks if player has a crit buff active
---@return boolean hasCrit True if any crit buff is active
function ReforgeLite:PlayerHasCritBuff()
  return CheckForPlayerAura(CRIT_BUFFS)
end

---Gets the rating required per 1% of a stat at a given level
---@param stat number The stat ID
---@param level? number The target level (defaults to player level)
---@return number rating Rating points needed per 1% of stat
function ReforgeLite:RatingPerPoint (stat, level)
  level = level or UnitLevel("player")
  if stat == addonTable.statIds.SPELLHIT then
    stat = StatHit
  end
  return addonTable.ScalingTable[stat][level] or 0
end
---Gets the melee hit bonus from talents and other sources
---@return number bonus Melee hit percentage bonus
function ReforgeLite:GetMeleeHitBonus ()
  return GetHitModifier () or 0
end
---Gets the spell hit bonus from talents and other sources
---@return number bonus Spell hit percentage bonus
function ReforgeLite:GetSpellHitBonus ()
  return GetSpellHitModifier () or 0
end
---Gets the expertise bonus from talents and racials
---@return number bonus Expertise percentage bonus
function ReforgeLite:GetExpertiseBonus()
  local mhExpertise, _, rangedExpertise = GetExpertise()
  local expertise = addonTable.playerClass == "HUNTER" and rangedExpertise or mhExpertise
  return RoundToSignificantDigits(expertise - GetCombatRatingBonus(CR_EXPERTISE), 4)
end
---Calculates haste bonus from buffs for melee/ranged haste
---@param hasteFunc function Function to get base haste (GetMeleeHaste or GetRangedHaste)
---@param ratingBonusId number Combat rating type (CR_HASTE_MELEE or CR_HASTE_RANGED)
---@return number bonus Haste multiplier bonus from buffs
function ReforgeLite:GetNonSpellHasteBonus(hasteFunc, ratingBonusId)
  local baseBonus = RoundToSignificantDigits((hasteFunc()+100)/(GetCombatRatingBonus(ratingBonusId)+100), 4)
  if self.pdb.meleeHaste and not self:PlayerHasMeleeHasteBuff() then
    baseBonus = baseBonus * 1.1
  end
  return baseBonus
end
---Gets melee haste bonus multiplier from buffs
---@return number bonus Melee haste multiplier from buffs
function ReforgeLite:GetMeleeHasteBonus()
  return self:GetNonSpellHasteBonus(GetMeleeHaste, CR_HASTE_MELEE)
end
---Gets ranged haste bonus multiplier from buffs
---@return number bonus Ranged haste multiplier from buffs
function ReforgeLite:GetRangedHasteBonus()
  return self:GetNonSpellHasteBonus(GetRangedHaste, CR_HASTE_RANGED)
end
function ReforgeLite:GetMasteryBonus()
  local mastery, bonusCoeff = GetMasteryEffect()
  return mastery - GetCombatRatingBonus(CR_MASTERY) * bonusCoeff, bonusCoeff
end
---Gets spell haste bonus multiplier from buffs
---@return number bonus Spell haste multiplier from buffs
function ReforgeLite:GetSpellHasteBonus()
  local baseBonus = (UnitSpellHaste('PLAYER')+100)/(GetCombatRatingBonus(CR_HASTE_SPELL)+100)
  if self.pdb.spellHaste and not self:PlayerHasSpellHasteBuff() then
    baseBonus = baseBonus * 1.05
  end
  return RoundToSignificantDigits(baseBonus, 6)
end
---Gets all haste bonus multipliers (melee, ranged, spell)
---@return number meleeBonus Melee haste multiplier
---@return number rangedBonus Ranged haste multiplier
---@return number spellBonus Spell haste multiplier
function ReforgeLite:GetHasteBonuses()
  return self:GetMeleeHasteBonus(), self:GetRangedHasteBonus(), self:GetSpellHasteBonus()
end
---Calculates effective haste with a given bonus multiplier
---@param haste number Base haste rating
---@param hasteBonus number Haste multiplier from buffs
---@return number effectiveHaste Effective haste percentage
function ReforgeLite:CalcHasteWithBonus(haste, hasteBonus)
  return ((hasteBonus - 1) * 100) + haste * hasteBonus
end
---Calculates effective haste for all types (melee, ranged, spell)
---@param haste number Base haste rating
---@return number meleeHaste Effective melee haste percentage
---@return number rangedHaste Effective ranged haste percentage
---@return number spellHaste Effective spell haste percentage
function ReforgeLite:CalcHasteWithBonuses(haste)
  local meleeBonus, rangedBonus, spellBonus = self:GetHasteBonuses()
  return self:CalcHasteWithBonus(haste, meleeBonus), self:CalcHasteWithBonus(haste, rangedBonus), self:CalcHasteWithBonus(haste, spellBonus)
end

---Calculates required special melee hit percentage for target level
---@return number hitPercent Required melee hit percentage
function ReforgeLite:GetNeededSpecialMeleeHit()
  return max(0, 3 + 1.5 * self.pdb.targetLevel)
end

---Calculates required normal melee hit percentage for target level
---@return number hitPercent Required melee hit percentage
function ReforgeLite:GetNeededNormalMeleeHit()
  return max(0, 22 + 1.5 * self.pdb.targetLevel)
end
---Calculates required spell hit percentage for target level
---@return number hitPercent Required spell hit percentage
function ReforgeLite:GetNeededSpellHit ()
  local diff = self.pdb.targetLevel
  if diff <= 3 then
    return max(0, 6 + 3 * diff)
  else
    return 11 * diff - 18
  end
end

---Calculates required expertise percentage for soft cap (dodge)
---@return number expertisePercent Required expertise percentage for soft cap
function ReforgeLite:GetNeededExpertiseSoft()
  return max(0, 3 + 1.5 * self.pdb.targetLevel)
end

---Calculates required expertise percentage for hard cap (parry)
---@return number expertisePercent Required expertise percentage for hard cap
function ReforgeLite:GetNeededExpertiseHard()
  return max(0, 6 + 3 * self.pdb.targetLevel)
end

---Buff toggle options shown in the Buffs dropdown. The shared UI consumes this list and
---calls each entry's selected(self) to auto-detect an active buff.
---@return table[] options
function addonTable.GetBuffOptions()
  return {
    { key = 'spellHaste', text = addonTable.CreateIconMarkup(136092) .. L["5% Spell Haste"], selected = ReforgeLite.PlayerHasSpellHasteBuff },
    { key = 'meleeHaste', text = addonTable.CreateIconMarkup(133076) .. L["10% Melee Haste"], selected = ReforgeLite.PlayerHasMeleeHasteBuff },
    { key = 'mastery', text = ("%s+%s %s"):format(addonTable.CreateIconMarkup(136046), addonTable.MASTERY_BY_LEVEL[UnitLevel('player')], STAT_MASTERY), selected = ReforgeLite.PlayerHasMasteryBuff },
    { key = 'crit', text = addonTable.CreateIconMarkup(136112) .. "5% " .. CRIT_ABBR, selected = ReforgeLite.PlayerHasCritBuff },
  }
end
