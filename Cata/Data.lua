---@type string, AddonTable
local _, addonTable = ...
local statIds = addonTable.statIds

-- Cataclysm (4.4.2) flavor data. Loaded only by ReforgeLite_Cata.toc, after
-- ReforgeLite.lua and before ReforgeEngine/Presets.
--
-- Spec IDs are the Cata talent-set IDs accepted by GetSpecializationInfoForSpecID
-- (ported from the 4.4.2 ReforgeLite). Note: no MONK (MoP class), and Cata's
-- "feralcombat" tab covers both bear and cat (MoP later split off "guardian").

addonTable.SPEC_IDS = {
  DEATHKNIGHT = { blood = 398, frost = 399, unholy = 400 },
  DRUID = { balance = 752, feralcombat = 750, restoration = 748 },
  HUNTER = { beastmastery = 811, marksmanship = 807, survival = 809 },
  MAGE = { arcane = 799, fire = 851, frost = 823 },
  PALADIN = { holy = 831, protection = 839, retribution = 855 },
  PRIEST = { discipline = 760, holy = 813, shadow = 795 },
  ROGUE = { assassination = 182, combat = 181, subtlety = 183 },
  SHAMAN = { elemental = 261, enhancement = 263, restoration = 262 },
  WARLOCK = { affliction = 871, demonology = 867, destruction = 865 },
  WARRIOR = { arms = 746, fury = 815, protection = 845 }
}

local SPEC_IDS = addonTable.SPEC_IDS

-- Talent-tree index (1-3, from GetPrimaryTalentTree) -> spec ID, in Cata tree order.
-- Used by the Cata spec-API compat shim, since this client has no GetSpecialization.
addonTable.SPEC_IDS_BY_TREE = {
  DEATHKNIGHT = { SPEC_IDS.DEATHKNIGHT.blood, SPEC_IDS.DEATHKNIGHT.frost, SPEC_IDS.DEATHKNIGHT.unholy },
  DRUID = { SPEC_IDS.DRUID.balance, SPEC_IDS.DRUID.feralcombat, SPEC_IDS.DRUID.restoration },
  HUNTER = { SPEC_IDS.HUNTER.beastmastery, SPEC_IDS.HUNTER.marksmanship, SPEC_IDS.HUNTER.survival },
  MAGE = { SPEC_IDS.MAGE.arcane, SPEC_IDS.MAGE.fire, SPEC_IDS.MAGE.frost },
  PALADIN = { SPEC_IDS.PALADIN.holy, SPEC_IDS.PALADIN.protection, SPEC_IDS.PALADIN.retribution },
  PRIEST = { SPEC_IDS.PRIEST.discipline, SPEC_IDS.PRIEST.holy, SPEC_IDS.PRIEST.shadow },
  ROGUE = { SPEC_IDS.ROGUE.assassination, SPEC_IDS.ROGUE.combat, SPEC_IDS.ROGUE.subtlety },
  SHAMAN = { SPEC_IDS.SHAMAN.elemental, SPEC_IDS.SHAMAN.enhancement, SPEC_IDS.SHAMAN.restoration },
  WARLOCK = { SPEC_IDS.WARLOCK.affliction, SPEC_IDS.WARLOCK.demonology, SPEC_IDS.WARLOCK.destruction },
  WARRIOR = { SPEC_IDS.WARRIOR.arms, SPEC_IDS.WARRIOR.fury, SPEC_IDS.WARRIOR.protection },
}

-- Cata Spirit->Hit conversion, expressed in the shared GetConversion model. The 4.4.2
-- engine did this via a talent-point-driven s2hFactor applied to STATS.HIT; here each
-- caster spec is a function that reads the live talent rank and returns the proportional
-- conversion (so a partially-talented player correctly gets 33%/50%/66%, not a flat 100%).
-- GetConversion resolves the function via GetValueOrCallFunction. The Human spiritBonus is
-- handled by GetConversion's playerRace == "Human" branch, so it needs no flavor path.
local function SpiritToHit(getFactor)
  return function()
    local factor = getFactor()
    if factor and factor > 0 then
      return {[statIds.SPIRIT] = {[statIds.HIT] = factor}}
    end
    return {}
  end
end

local function TalentRank(tab, index)
  return select(5, GetTalentInfo(tab, index)) or 0
end

addonTable.STAT_CONVERSIONS = {
  DRUID = { -- Balance of Power
    specs = { [SPEC_IDS.DRUID.balance] = SpiritToHit(function() return TalentRank(1, 7) * 0.5 end) }
  },
  PALADIN = { -- Holy: Enlightened Judgements
    specs = { [SPEC_IDS.PALADIN.holy] = SpiritToHit(function() return TalentRank(1, 4) * 0.5 end) }
  },
  PRIEST = { -- Twisted Faith
    specs = { [SPEC_IDS.PRIEST.shadow] = SpiritToHit(function() return TalentRank(3, 20) * 0.5 end) }
  },
  SHAMAN = { -- Elemental Precision
    specs = { [SPEC_IDS.SHAMAN.elemental] = SpiritToHit(function()
      local pts = TalentRank(1, 9)
      return pts == 3 and 1 or pts * 0.33
    end) }
  },
}
