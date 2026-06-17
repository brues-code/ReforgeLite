---@type string, AddonTable
local _, addonTable = ...
local statIds = addonTable.statIds

-- Mists of Pandaria (5.4.4) flavor data. Loaded only by ReforgeLite.toc, after
-- ReforgeLite.lua (which defines statIds) and before ReforgeEngine/Presets.

addonTable.SPEC_IDS = {
  DEATHKNIGHT = { blood = 250, frost = 251, unholy = 252 },
  DRUID = { balance = 102, feralcombat = 103, guardian = 104, restoration = 105 },
  HUNTER = { beastmastery = 253, marksmanship = 254, survival = 255 },
  MAGE = { arcane = 62, fire = 63, frost = 64 },
  MONK = { brewmaster = 268, mistweaver = 270, windwalker = 269 },
  PALADIN = { holy = 65, protection = 66, retribution = 70 },
  PRIEST = { discipline = 256, holy = 257, shadow = 258 },
  ROGUE = { assassination = 259, combat = 260, subtlety = 261 },
  SHAMAN = { elemental = 262, enhancement = 263, restoration = 264 },
  WARLOCK = { affliction = 265, demonology = 266, destruction = 267 },
  WARRIOR = { arms = 71, fury = 72, protection = 73 }
}

local SPEC_IDS = addonTable.SPEC_IDS

local CASTER_SPEC = {[statIds.EXP] = {[statIds.HIT] = 1}}
local HYBRID_SPEC = {[statIds.SPIRIT] = {[statIds.HIT] = 1}, [statIds.EXP] = {[statIds.HIT] = 1}}

addonTable.STAT_CONVERSIONS = {
  DRUID = {
    specs = {
      [SPEC_IDS.DRUID.balance] = HYBRID_SPEC,
      [SPEC_IDS.DRUID.restoration] = CASTER_SPEC -- Resto
    }
  },
  MAGE = { base = CASTER_SPEC },
  MONK = {
    specs = {
      [SPEC_IDS.MONK.mistweaver] = {
        [statIds.SPIRIT] = {[statIds.HIT] = 0.5, [statIds.EXP] = 0.5},
        [statIds.HASTE] = {[statIds.HASTE] = 0.5},
      }
    }
  },
  PALADIN = {
    specs = {
      [SPEC_IDS.PALADIN.holy] = CASTER_SPEC -- Holy
    }
  },
  PRIEST = {
    base = CASTER_SPEC,
    specs = {
      [SPEC_IDS.PRIEST.shadow] = HYBRID_SPEC -- Shadow
    }
  },
  SHAMAN = {
    specs = {
      [SPEC_IDS.SHAMAN.elemental] = HYBRID_SPEC, -- Ele
      [SPEC_IDS.SHAMAN.restoration] = CASTER_SPEC -- Resto
    }
  },
  WARLOCK = { base = CASTER_SPEC },
}
