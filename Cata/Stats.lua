---@type string, AddonTable
local _, addonTable = ...
local ReforgeLite = addonTable.ReforgeLite
local statIds = addonTable.statIds
local L = addonTable.L

-- Cataclysm (4.4.2) stat math: rating-per-point (formula-based, no ScalingTable),
-- the talent/racial stat-bonus getters, haste-buff detection, and the cap need-formulas.
-- Ported from the 4.4.2 ReforgeLite. Loaded by ReforgeLite_Cata.toc before Presets.
--
-- Haste-buff detection uses the shared CheckForPlayerAura pattern (the 4.4.2 addon read
-- these out of a combined GetPlayerBuffs scan; only the haste/darkIntent flags matter here).
local SPELL_HASTE_BUFFS = {
  49868, -- Mind Quickening
  24907, -- Moonkin Aura
  2895,  -- Wrath of Air Totem
}

local MELEE_HASTE_BUFFS = {
  53290, -- Hunting Party
  55610, -- Improved Icy Talons
  8515,  -- Windfury Totem
}

local DARK_INTENT_BUFFS = {
  85768,
  85767,
}

local function CheckForPlayerAura(buffTable)
  return ContainsIf(buffTable, C_UnitAuras.GetPlayerAuraBySpellID)
end

---@return boolean hasSpellHaste True if any spell haste buff is active
function ReforgeLite:PlayerHasSpellHasteBuff()
  return CheckForPlayerAura(SPELL_HASTE_BUFFS)
end

---@return boolean hasMeleeHaste True if any melee haste buff is active
function ReforgeLite:PlayerHasMeleeHasteBuff()
  return CheckForPlayerAura(MELEE_HASTE_BUFFS)
end

---@return boolean hasDarkIntent True if Dark Intent is active
function ReforgeLite:PlayerHasDarkIntentBuff()
  return CheckForPlayerAura(DARK_INTENT_BUFFS)
end

---Gets the rating required per 1% of a stat at a given level (Cata DBC formula)
---@param stat number The stat ID
---@param level? number The target level (defaults to player level)
---@return number rating Rating points needed per 1% of stat
function ReforgeLite:RatingPerPoint(stat, level)
  level = level or UnitLevel("player")
  local factor
  if level <= 34 and (stat == statIds.DODGE or stat == statIds.PARRY) then
    factor = 0.5
  elseif level <= 10 then
    factor = 1 / 26
  elseif level <= 60 then
    factor = (level - 8) / 52
  elseif level <= 70 then
    factor = 82 / (262 - 3 * level)
  elseif level <= 80 then
    factor = (82 / 52) * ((131 / 63) ^ ((level - 70) / 10))
  else
    factor = (82 / 52) * (131 / 63)
    if level == 81 then
      factor = factor * 1.31309
    elseif level == 82 then
      factor = factor * 1.72430
    elseif level == 83 then
      factor = factor * 2.26519
    elseif level == 84 then
      factor = factor * 2.97430
    elseif level == 85 then
      factor = factor * 3.90537
    end
  end
  if stat == statIds.DODGE or stat == statIds.PARRY then
    return factor * 13.8
  elseif stat == statIds.HIT then
    return factor * 9.37931
  elseif stat == statIds.SPELLHIT then
    return factor * 8
  elseif stat == statIds.HASTE then
    return factor * 10
  elseif stat == statIds.CRIT then
    return factor * 14
  elseif stat == statIds.EXP then
    return factor * 2.34483
  elseif stat == statIds.MASTERY then
    return factor * 14
  end
  return 0
end

---@return number bonus Melee hit percentage bonus
function ReforgeLite:GetMeleeHitBonus()
  return GetHitModifier() or 0
end

---@return number bonus Spell hit percentage bonus
function ReforgeLite:GetSpellHitBonus()
  return GetSpellHitModifier() or 0
end

---@return number bonus Expertise bonus (in expertise points), incl. Paladin Seal of Truth
function ReforgeLite:GetExpertiseBonus()
  local bonus = GetExpertise() - floor(GetCombatRatingBonus(CR_EXPERTISE))
  if addonTable.playerClass == "PALADIN" and IsPlayerSpell(56416)
     and not (C_UnitAuras.GetPlayerAuraBySpellID(31801) or C_UnitAuras.GetPlayerAuraBySpellID(20154)) then
    bonus = bonus + 10
  end
  return bonus
end

---Mastery bonus for the cap tooltip. Cata exposes only GetMastery() (mastery points,
---no per-spec effect coefficient like MoP's GetMasteryEffect), so this reports mastery
---in points with a 1:1 per-rating coefficient. Display-only; the optimizer uses
---RatingPerPoint(MASTERY).
---@return number baseMastery Non-rating mastery points
---@return number coeff Mastery points per rating point (1)
function ReforgeLite:GetMasteryBonus()
  local mastery = GetMastery()
  return mastery - GetCombatRatingBonus(CR_MASTERY), 1
end

---@param hasteFunc function Function to get base haste (GetMeleeHaste or GetRangedHaste)
---@param ratingBonusId number Combat rating type (CR_HASTE_MELEE or CR_HASTE_RANGED)
---@return number bonus Haste multiplier bonus from buffs
function ReforgeLite:GetNonSpellHasteBonus(hasteFunc, ratingBonusId)
  local baseBonus = RoundToSignificantDigits((hasteFunc() + 100) / (GetCombatRatingBonus(ratingBonusId) + 100), 4)
  if self.pdb.meleeHaste and not self:PlayerHasMeleeHasteBuff() then
    baseBonus = baseBonus * 1.1
  end
  return baseBonus
end

---@return number bonus Melee haste multiplier from buffs
function ReforgeLite:GetMeleeHasteBonus()
  return self:GetNonSpellHasteBonus(GetMeleeHaste, CR_HASTE_MELEE)
end

---@return number bonus Ranged haste multiplier from buffs
function ReforgeLite:GetRangedHasteBonus()
  return self:GetNonSpellHasteBonus(GetRangedHaste, CR_HASTE_RANGED)
end

---@return number bonus Spell haste multiplier from buffs (incl. Dark Intent)
function ReforgeLite:GetSpellHasteBonus()
  local baseBonus = (UnitSpellHaste('PLAYER') + 100) / (GetCombatRatingBonus(CR_HASTE_SPELL) + 100)
  if self.pdb.spellHaste and not self:PlayerHasSpellHasteBuff() then
    baseBonus = baseBonus * 1.05
  end
  if self.pdb.darkIntent and not self:PlayerHasDarkIntentBuff() then
    baseBonus = baseBonus * 1.03
  end
  return RoundToSignificantDigits(baseBonus, 6)
end

---@return number meleeBonus, number rangedBonus, number spellBonus
function ReforgeLite:GetHasteBonuses()
  return self:GetMeleeHasteBonus(), self:GetRangedHasteBonus(), self:GetSpellHasteBonus()
end

---@param haste number Base haste rating
---@param hasteBonus number Haste multiplier from buffs
---@return number effectiveHaste Effective haste percentage
function ReforgeLite:CalcHasteWithBonus(haste, hasteBonus)
  return ((hasteBonus - 1) * 100) + haste * hasteBonus
end

---@param haste number Base haste rating
---@return number meleeHaste, number rangedHaste, number spellHaste
function ReforgeLite:CalcHasteWithBonuses(haste)
  local meleeBonus, rangedBonus, spellBonus = self:GetHasteBonuses()
  return self:CalcHasteWithBonus(haste, meleeBonus), self:CalcHasteWithBonus(haste, rangedBonus), self:CalcHasteWithBonus(haste, spellBonus)
end

---@return number hitPercent Required melee hit percentage for target level
function ReforgeLite:GetNeededMeleeHit()
  local diff = self.pdb.targetLevel
  if diff <= 2 then
    return max(0, 5 + 0.5 * diff)
  else
    return 2 + 2 * diff
  end
end

---@return number hitPercent Required spell hit percentage for target level
function ReforgeLite:GetNeededSpellHit()
  local diff = self.pdb.targetLevel
  if diff <= 2 then
    return max(0, 4 + diff)
  else
    return 11 * diff - 16
  end
end

---@return number expertise Required expertise (in 0.25% units) for soft cap (dodge)
function ReforgeLite:GetNeededExpertiseSoft()
  local diff = self.pdb.targetLevel
  return ceil(max(0, 5 + 0.5 * diff) / 0.25)
end

---@return number expertise Required expertise (in 0.25% units) for hard cap (parry)
function ReforgeLite:GetNeededExpertiseHard()
  local diff = self.pdb.targetLevel
  if diff <= 2 then
    return ceil(max(0, 5 + 0.5 * diff) / 0.25)
  else
    return ceil(14 / 0.25)
  end
end

---Buff toggle options shown in the Buffs dropdown. The shared UI consumes this list and
---calls each entry's selected(self) to auto-detect an active buff. Cata buffs: Dark Intent,
---spell haste, melee haste (kings/flask/food stat buffs are not modeled by the shared engine).
---@return table[] options
function addonTable.GetBuffOptions()
  return {
    { key = 'darkIntent', text = addonTable.CreateIconMarkup(463285) .. C_Spell.GetSpellName(80398), selected = ReforgeLite.PlayerHasDarkIntentBuff },
    { key = 'spellHaste', text = addonTable.CreateIconMarkup(136092) .. L["Spell Haste"], selected = ReforgeLite.PlayerHasSpellHasteBuff },
    { key = 'meleeHaste', text = addonTable.CreateIconMarkup(236181) .. L["Melee Haste"], selected = ReforgeLite.PlayerHasMeleeHasteBuff },
  }
end
