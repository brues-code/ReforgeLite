---@type string, AddonTable
local _, addonTable = ...
local L = addonTable.L
local ReforgeLite = addonTable.ReforgeLite

local SPEC_IDS = addonTable.SPEC_IDS
local CreateIconMarkup = addonTable.CreateIconMarkup
local playerRace = select(2, UnitRace("player"))

local StatHit = addonTable.statIds.HIT
local StatCrit = addonTable.statIds.CRIT
local StatHaste = addonTable.statIds.HASTE
local StatExp = addonTable.statIds.EXP
local StatSpellHit = addonTable.statIds.SPELLHIT

-- Cataclysm (4.4.2) cap presets, per-class haste breakpoints, and class/spec stat-weight
-- presets, ported from the 4.4.2 ReforgeLite. Provides ReforgeLite.capPresets,
-- addonTable.CAPS, and addonTable.classPresets for the shared Presets.lua machinery.
-- Loaded by ReforgeLite_Cata.toc after Presets.lua (needs addonTable.CreateIconMarkup).
--
-- NOTE: tank specs (blood DK, protection paladin/warrior, the bear-tank feral variant)
-- are intentionally omitted for now - they relied on the 4.4.2 tanking/mitigation model
-- (SetTankingModel) which the shared MoP engine no longer provides. Revisit once the rest
-- is validated in-client.

local AtLeast = addonTable.StatCapMethods.AtLeast
local AtMost = addonTable.StatCapMethods.AtMost
local CAPS = EnumUtil.MakeEnum(
  "ManualCap", "MeleeHitCap", "SpellHitCap", "MeleeDWHitCap", "ExpSoftCap", "ExpHardCap",
  "FirstHasteBreak", "SecondHasteBreak", "ThirdHasteBreak", "FourthHasteBreak", "FifthHasteBreak"
)
addonTable.CAPS = CAPS

ReforgeLite.capPresets = {
  {
    value = CAPS.ManualCap,
    name = TRACKER_SORT_MANUAL,
    getter = nil
  },
  {
    value = CAPS.MeleeHitCap,
    name = L["Melee hit cap"],
    getter = function ()
      return ReforgeLite:RatingPerPoint(StatHit) * (ReforgeLite:GetNeededMeleeHit() - ReforgeLite:GetMeleeHitBonus())
    end,
    category = StatHit
  },
  {
    value = CAPS.SpellHitCap,
    name = L["Spell hit cap"],
    getter = function ()
      return ReforgeLite:RatingPerPoint(StatSpellHit) * (ReforgeLite:GetNeededSpellHit() - ReforgeLite:GetSpellHitBonus())
    end,
    category = StatHit
  },
  {
    value = CAPS.MeleeDWHitCap,
    name = L["Melee DW hit cap"],
    getter = function ()
      return ReforgeLite:RatingPerPoint(StatHit) * (ReforgeLite:GetNeededMeleeHit() + 19 - ReforgeLite:GetMeleeHitBonus())
    end,
    category = StatHit
  },
  {
    value = CAPS.ExpSoftCap,
    name = L["Expertise soft cap"],
    getter = function ()
      return ReforgeLite:RatingPerPoint(StatExp) * (ReforgeLite:GetNeededExpertiseSoft() - ReforgeLite:GetExpertiseBonus())
    end,
    category = StatExp
  },
  {
    value = CAPS.ExpHardCap,
    name = L["Expertise hard cap"],
    getter = function ()
      return ReforgeLite:RatingPerPoint(StatExp) * (ReforgeLite:GetNeededExpertiseHard() - ReforgeLite:GetExpertiseBonus())
    end,
    category = StatExp
  },
}

local function GetActiveItemSet()
  local itemSets = {}
  for _,v in ipairs({INVSLOT_HEAD,INVSLOT_SHOULDER,INVSLOT_CHEST,INVSLOT_LEGS,INVSLOT_HAND}) do
    local item = Item:CreateFromEquipmentSlot(v)
    if not item:IsItemEmpty() then
      local itemSetId = select(16, C_Item.GetItemInfo(item:GetItemID()))
      if itemSetId then
        itemSets[itemSetId] = (itemSets[itemSetId] or 0) + 1
      end
    end
  end
  return itemSets
end

local function GetSpellHasteRequired(percentNeeded)
  return function()
    local hasteMod = ReforgeLite:GetSpellHasteBonus()
    return ceil((percentNeeded - (hasteMod - 1) * 100) * ReforgeLite:RatingPerPoint(StatHaste) / hasteMod)
  end
end

local function GetRangedHasteRequired(percentNeeded)
  return function()
    local hasteMod = ReforgeLite:GetRangedHasteBonus()
    return ceil((percentNeeded - (hasteMod - 1) * 100) * ReforgeLite:RatingPerPoint(StatHaste) / hasteMod)
  end
end

do
  local nameFormat = "%s%s%% +%s %s "
  local nameFormatWithTicks = nameFormat..L["ticks"]
  if addonTable.playerClass == "DRUID" then
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.FirstHasteBreak,
      category = StatHaste,
      name = nameFormatWithTicks:format(CreateIconMarkup(136081), 18.74, 2, C_Spell.GetSpellName(774)),
      getter = GetSpellHasteRequired(12.51),
    })
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.SecondHasteBreak,
      category = StatHaste,
      name = nameFormatWithTicks:format(CreateIconMarkup(236153)..CreateIconMarkup(134222), 21.43, 1, C_Spell.GetSpellName(48438) .. " / " .. C_Spell.GetSpellName(81269)),
      getter = GetSpellHasteRequired(21.4345),
    })
  elseif addonTable.playerClass == "PRIEST" then
    local devouringPlague, devouringPlagueMarkup = C_Spell.GetSpellName(2944), CreateIconMarkup(252997)
    local shadowWordPain, shadowWordPainMarkup = C_Spell.GetSpellName(589), CreateIconMarkup(136207)
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.FirstHasteBreak,
      category = StatHaste,
      name = nameFormatWithTicks:format(devouringPlagueMarkup, 18.74, 2, devouringPlague),
      getter = GetSpellHasteRequired(18.74),
    })
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.SecondHasteBreak,
      category = StatHaste,
      name = nameFormatWithTicks:format(shadowWordPainMarkup, 24.97, 2, shadowWordPain),
      getter = GetSpellHasteRequired(24.97),
    })
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.ThirdHasteBreak,
      category = StatHaste,
      name = nameFormatWithTicks:format(CreateIconMarkup(135978), 30.01, 2, C_Spell.GetSpellName(589)),
      getter = GetSpellHasteRequired(30.01),
    })
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.FourthHasteBreak,
      category = StatHaste,
      name = nameFormatWithTicks:format(devouringPlagueMarkup, 31.26, 3, devouringPlague),
      getter = GetSpellHasteRequired(31.26),
    })
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.FifthHasteBreak,
      category = StatHaste,
      name = nameFormatWithTicks:format(shadowWordPainMarkup, 41.67, 3, shadowWordPain),
      getter = GetSpellHasteRequired(41.675),
    })
  elseif addonTable.playerClass == "MAGE" then
    local combustion, combustionMarkup = C_Spell.GetSpellName(11129), CreateIconMarkup(135824)
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.FirstHasteBreak,
      category = StatHaste,
      name = nameFormatWithTicks:format(combustionMarkup, 15, 2, combustion),
      getter = GetSpellHasteRequired(15.01),
    })
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.SecondHasteBreak,
      category = StatHaste,
      name = nameFormatWithTicks:format(combustionMarkup, 25, 3, combustion),
      getter = GetSpellHasteRequired(25.08),
    })
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.ThirdHasteBreak,
      category = StatHaste,
      name = ("%s %s %s"):format(CreateIconMarkup(135735), D_SECONDS:format(1), C_Spell.GetSpellName(30451)),
      getter = function()
        local percentNeeded = 13.86
        local firelordCount = GetActiveItemSet()[931] or 0
        if playerRace == "Goblin" then
          if firelordCount >= 4 then
            percentNeeded = 2.43
          else
            percentNeeded = 12.68
          end
        elseif firelordCount >= 4 then
          percentNeeded = 3.459
        end
        return ceil(ReforgeLite:RatingPerPoint(StatHaste) * percentNeeded)
      end,
    })
  elseif addonTable.playerClass == "HUNTER" then
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.FirstHasteBreak,
      category = StatHaste,
      name = nameFormat:format(CreateIconMarkup(461114), 20, 3, C_Spell.GetSpellName(77767)),
      getter = GetRangedHasteRequired(19.99),
    })
  elseif addonTable.playerClass == "SHAMAN" then
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.FirstHasteBreak,
      category = StatHaste,
      name = nameFormatWithTicks:format(CreateIconMarkup(462328), 12.51, 1, C_Spell.GetSpellName(51730)),
      getter = GetSpellHasteRequired(12.51),
    })
    tinsert(ReforgeLite.capPresets, {
      value = CAPS.SecondHasteBreak,
      category = StatHaste,
      name = nameFormatWithTicks:format(CreateIconMarkup(252995), 21.44, 2, C_Spell.GetSpellName(61295)),
      getter = GetSpellHasteRequired(21.4345),
    })
  end
end

local HitCap = { stat = StatHit, points = { { method = AtLeast, preset = CAPS.MeleeHitCap } } }
local HitCapSpell = { stat = StatHit, points = { { method = AtLeast, preset = CAPS.SpellHitCap } } }
local SoftExpCap = { stat = StatExp, points = { { method = AtLeast, preset = CAPS.ExpSoftCap } } }
local MeleeCaps = { HitCap, SoftExpCap }
local RangedCaps = { HitCap }
local CasterCaps = { HitCapSpell }

addonTable.classPresets = {
  ["DEATHKNIGHT"] = {
    [SPEC_IDS.DEATHKNIGHT.frost] = {
      [C_Spell.GetSpellName(49020)] = { -- Obliterate
        icon = 135771,
        weights = { 0, 0, 0, 200, 120, 160, 50, 90 },
        caps = { HitCap },
      },
      [L["Masterfrost"]] = {
        icon = 135833,
        weights = { 0, 0, 0, 200, 120, 150, 100, 180 },
        caps = CasterCaps,
      },
    },
    [SPEC_IDS.DEATHKNIGHT.unholy] = function()
      local gurth = C_Item.IsEquippedItem(77191) or C_Item.IsEquippedItem(78478) or C_Item.IsEquippedItem(78487)
      return {
        weights = gurth and { 0, 0, 0, 350, 263, 301, 165, 248 } or { 0, 0, 0, 261, 233, 240, 113, 187 },
        caps = { HitCap },
      }
    end,
  },
  ["DRUID"] = {
    [SPEC_IDS.DRUID.balance] = {
      weights = { 0, 0, 0, 200, 100, 150, 0, 130 },
      caps = CasterCaps,
    },
    [SPEC_IDS.DRUID.feralcombat] = {
      [("%s (%s)"):format(C_Spell.GetSpellName(5487), STAT_DPS_SHORT)] = { -- Bear Form (DPS)
        icon = 132276,
        weights = { 0, -6, 0, 100, 50, 25, 100, -1 },
        caps = MeleeCaps,
      },
      [("%s (%s)"):format(C_Spell.GetSpellName(768), L["Monocat"])] = { -- Cat Form (Monocat)
        icon = 132115,
        weights = { 0, 0, 0, 30, 31, 28, 30, 31 },
        caps = {
          { stat = StatHit, points = { { method = AtMost, preset = CAPS.MeleeHitCap } } },
          { stat = StatExp, points = { { method = AtMost, preset = CAPS.ExpSoftCap } } },
        },
      },
      [("%s (%s)"):format(C_Spell.GetSpellName(768), L["Bearweave"])] = { -- Cat Form (Bearweave)
        icon = 132115,
        weights = { 0, 0, 0, 33, 31, 26, 32, 30 },
        caps = MeleeCaps,
      },
    },
    [SPEC_IDS.DRUID.restoration] = {
      [MANA_REGEN_ABBR] = {
        weights = { 150, 0, 0, 0, 130, 160, 0, 140 },
        caps = { { stat = StatHaste, points = { { method = AtLeast, preset = CAPS.FirstHasteBreak, after = 120 } } } },
      },
      [BONUS_HEALING] = {
        weights = { 140, 0, 0, 0, 130, 160, 0, 150 },
        caps = { { stat = StatHaste, points = { { method = AtLeast, preset = CAPS.FirstHasteBreak, after = 120 } } } },
      },
    },
  },
  ["HUNTER"] = {
    [SPEC_IDS.HUNTER.beastmastery] = {
      weights = { 0, 0, 0, 200, 150, 80, 0, 110 },
      caps = RangedCaps,
    },
    [SPEC_IDS.HUNTER.marksmanship] = {
      weights = { 0, 0, 0, 200, 150, 110, 0, 80 },
      caps = RangedCaps,
    },
    [SPEC_IDS.HUNTER.survival] = {
      weights = { 0, 0, 0, 200, 110, 80, 0, 40 },
      caps = {
        HitCap,
        { stat = StatHaste, points = { { method = AtMost, preset = CAPS.FirstHasteBreak, after = 0 } } },
      },
    },
  },
  ["MAGE"] = {
    [SPEC_IDS.MAGE.arcane] = {
      weights = { 0, 0, 0, 5, 1, 4, 0, 3 },
      caps = {
        HitCapSpell,
        { stat = StatHaste, points = { { method = AtLeast, preset = CAPS.ThirdHasteBreak, after = 2 } } },
      },
    },
    [SPEC_IDS.MAGE.fire] = {
      [PERCENTAGE_STRING:format(15) .. " " .. STAT_HASTE] = {
        weights = { 0, 0, 0, 5, 3, 4, 0, 1 },
        caps = {
          HitCapSpell,
          { stat = StatHaste, points = { { method = AtLeast, preset = CAPS.FirstHasteBreak, after = 2 } } },
        },
      },
      [PERCENTAGE_STRING:format(25) .. " " .. STAT_HASTE] = {
        weights = { 0, 0, 0, 5, 3, 4, 0, 1 },
        caps = {
          HitCapSpell,
          { stat = StatHaste, points = { { method = AtLeast, preset = CAPS.SecondHasteBreak, after = 2 } } },
        },
      },
    },
    [SPEC_IDS.MAGE.frost] = {
      weights = { 0, 0, 0, 200, 180, 140, 0, 130 },
      caps = {
        HitCapSpell,
        { stat = StatCrit, points = { { method = AtMost, value = playerRace == "Worgen" and 2922 or 3101, after = 100 } } },
      },
    },
  },
  ["PALADIN"] = {
    [SPEC_IDS.PALADIN.holy] = {
      weights = { 160, 0, 0, 0, 80, 200, 0, 120 },
    },
    [SPEC_IDS.PALADIN.retribution] = {
      weights = { 0, 0, 0, 200, 135, 110, 180, 150 },
      caps = MeleeCaps,
    },
  },
  ["PRIEST"] = {
    [SPEC_IDS.PRIEST.discipline] = {
      weights = { 150, 0, 0, 0, 100, 120, 0, 80 },
    },
    [SPEC_IDS.PRIEST.holy] = {
      weights = { 150, 0, 0, 0, 80, 120, 0, 100 },
    },
    [SPEC_IDS.PRIEST.shadow] = {
      weights = { 0, 0, 0, 200, 100, 140, 0, 130 },
      caps = CasterCaps,
    },
  },
  ["ROGUE"] = {
    [SPEC_IDS.ROGUE.assassination] = {
      weights = { 0, 0, 0, 200, 110, 130, 120, 140 },
      caps = {
        { stat = StatHit, points = { { method = AtLeast, preset = CAPS.SpellHitCap, after = 82 } } },
        { stat = StatExp, points = { { method = AtMost, preset = CAPS.ExpSoftCap } } },
      },
    },
    [SPEC_IDS.ROGUE.combat] = {
      weights = { 0, 0, 0, 200, 125, 170, 215, 150 },
      caps = {
        { stat = StatExp, points = { { method = AtLeast, preset = CAPS.ExpSoftCap } } },
        { stat = StatHit, points = { { method = AtLeast, preset = CAPS.SpellHitCap, after = 100 } } },
      },
    },
    [SPEC_IDS.ROGUE.subtlety] = {
      weights = { 0, 0, 0, 155, 145, 155, 130, 90 },
      caps = {
        { stat = StatHit, points = {
          { method = AtLeast, preset = CAPS.MeleeHitCap, after = 110 },
          { preset = CAPS.SpellHitCap, after = 80 },
        } },
        { stat = StatExp, points = { { preset = CAPS.ExpSoftCap } } },
      },
    },
  },
  ["SHAMAN"] = {
    [SPEC_IDS.SHAMAN.elemental] = {
      weights = { 0, 0, 0, 200, 80, 140, 0, 120 },
      caps = CasterCaps,
    },
    [SPEC_IDS.SHAMAN.enhancement] = {
      weights = { 0, 0, 0, 250, 120, 80, 190, 150 },
      caps = {
        { stat = StatHit, points = { { method = AtLeast, preset = CAPS.SpellHitCap, after = 50 } } },
        { stat = StatExp, points = { { method = AtLeast, preset = CAPS.ExpSoftCap } } },
      },
    },
    [SPEC_IDS.SHAMAN.restoration] = {
      weights = { 130, 0, 0, 0, 100, 100, 0, 100 },
    },
  },
  ["WARLOCK"] = {
    [SPEC_IDS.WARLOCK.affliction] = {
      weights = { 0, 0, 0, 200, 140, 160, 0, 120 },
      caps = CasterCaps,
    },
    [SPEC_IDS.WARLOCK.destruction] = {
      weights = { 0, 0, 0, 200, 140, 160, 0, 120 },
      caps = CasterCaps,
    },
    [SPEC_IDS.WARLOCK.demonology] = {
      weights = { 0, 0, 0, 200, 120, 160, 0, 140 },
      caps = CasterCaps,
    },
  },
  ["WARRIOR"] = {
    [SPEC_IDS.WARRIOR.arms] = {
      weights = { 0, 0, 0, 200, 150, 100, 200, 120 },
      caps = MeleeCaps,
    },
    [SPEC_IDS.WARRIOR.fury] = {
      [C_Spell.GetSpellName(46917)] = { -- Titan's Grip
        icon = 236316,
        weights = { 0, 0, 0, 200, 150, 100, 180, 130 },
        caps = {
          { stat = StatHit, points = { { method = AtLeast, preset = CAPS.MeleeHitCap, after = 140 } } },
          SoftExpCap,
        },
      },
      [C_Spell.GetSpellName(81099)] = { -- Single-Minded Fury
        icon = 458974,
        weights = { 0, 0, 0, 200, 150, 100, 180, 130 },
        caps = {
          { stat = StatHit, points = { { method = AtLeast, preset = CAPS.MeleeHitCap, after = 140 } } },
          SoftExpCap,
        },
      },
    },
  },
}
