---@type string, AddonTable
local _, addonTable = ...
local L = addonTable.L
local ReforgeLite = addonTable.ReforgeLite

local SPEC_IDS = addonTable.SPEC_IDS
local CreateIconMarkup = addonTable.CreateIconMarkup

local StatHit = addonTable.statIds.HIT
local StatHaste = addonTable.statIds.HASTE
local StatExp = addonTable.statIds.EXP

-- Mists of Pandaria (5.4.4) cap presets, haste breakpoints, and class/spec stat-weight
-- presets. Provides ReforgeLite.capPresets, addonTable.CAPS, and addonTable.classPresets,
-- which the shared Presets.lua machinery (InitClassPresets, preset menu) consumes.
-- Loaded by ReforgeLite.toc after Presets.lua (needs addonTable.CreateIconMarkup).

local AtLeast = addonTable.StatCapMethods.AtLeast
local AtMost = addonTable.StatCapMethods.AtMost
local CAPS = EnumUtil.MakeEnum("ManualCap", "MeleeHitCap", "SpellHitCap", "MeleeDWHitCap", "ExpSoftCap", "ExpHardCap")
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
      return ReforgeLite:RatingPerPoint(StatHit) * (ReforgeLite:GetNeededSpecialMeleeHit() - ReforgeLite:GetMeleeHitBonus())
    end,
    category = StatHit
  },
  {
    value = CAPS.SpellHitCap,
    name = L["Spell hit cap"],
    getter = function ()
      return ReforgeLite:RatingPerPoint (addonTable.statIds.SPELLHIT) * (ReforgeLite:GetNeededSpellHit () - ReforgeLite:GetSpellHitBonus ())
    end,
    category = StatHit
  },
  {
    value = CAPS.MeleeDWHitCap,
    name = L["Melee DW hit cap"],
    getter = function ()
      return ReforgeLite:RatingPerPoint(StatHit) * (ReforgeLite:GetNeededNormalMeleeHit() - ReforgeLite:GetMeleeHitBonus())
    end,
    category = StatHit
  },
  {
    value = CAPS.ExpSoftCap,
    name = L["Expertise soft cap"],
    getter = function ()
      return ReforgeLite:RatingPerPoint (StatExp) * (ReforgeLite:GetNeededExpertiseSoft() - ReforgeLite:GetExpertiseBonus())
    end,
    category = StatExp
  },
  {
    value = CAPS.ExpHardCap,
    name = L["Expertise hard cap"],
    getter = function ()
      return ReforgeLite:RatingPerPoint (StatExp) * (ReforgeLite:GetNeededExpertiseHard() - ReforgeLite:GetExpertiseBonus())
    end,
    category = StatExp
  },
}

local function GetSpellHasteRequired(percentNeeded)
  return function()
    local hasteMod = ReforgeLite:GetSpellHasteBonus()
    return ceil((percentNeeded - (hasteMod - 1) * 100) * ReforgeLite:RatingPerPoint(addonTable.statIds.HASTE) / hasteMod)
  end
end

local function AddHasteBreakpoint(name, getter, classID, specID)
  if classID ~= addonTable.playerClass then return CAPS.ManualCap end
  local newIndex = #ReforgeLite.capPresets + 1
  tinsert(ReforgeLite.capPresets, {
    category = StatHaste,
    name = name,
    getter = getter,
    classID = classID,
    specID = specID,
    value = newIndex
  })
  return newIndex
end

local nameFormat = "%s%s%% +%s %s "
local nameFormatWithTicks = nameFormat..L["ticks"]

local HASTE_BREAKS = setmetatable({}, {
  __index = function(t, k)
    rawset(t,k, {})
    return t[k]
  end
})

HASTE_BREAKS.DRUID.WILD_MUSHROOM = AddHasteBreakpoint(
  ("%s%s %s%%"):format(CreateIconMarkup(236152), C_Spell.GetSpellName(79577), 24.22),
  GetSpellHasteRequired(24.215),
  "DRUID",
  SPEC_IDS.DRUID.balance
)
HASTE_BREAKS.DRUID.REJUV_LIFEBLOOM = AddHasteBreakpoint(
  nameFormatWithTicks:format(CreateIconMarkup(136081)..CreateIconMarkup(136107), 12.52, 1, C_Spell.GetSpellName(774) .. " / " .. C_Spell.GetSpellName(740)),
  GetSpellHasteRequired(12.52),
  "DRUID",
  SPEC_IDS.DRUID.restoration
)

local eternalFlame, eternalFlameMarkup = C_Spell.GetSpellName(114163), CreateIconMarkup(135433)
local sacredShield, sacredShieldMarkup = C_Spell.GetSpellName(20925), CreateIconMarkup(236249)
AddHasteBreakpoint(
  nameFormatWithTicks:format(eternalFlameMarkup, 4.99, 1, eternalFlame),
  GetSpellHasteRequired(4.986880),
  "PALADIN",
  SPEC_IDS.PALADIN.holy
)
AddHasteBreakpoint(
  nameFormatWithTicks:format(sacredShieldMarkup, 10.00, 1, sacredShield),
  GetSpellHasteRequired(10.000919),
  "PALADIN",
  SPEC_IDS.PALADIN.holy
)
AddHasteBreakpoint(
  nameFormatWithTicks:format(eternalFlameMarkup, 15.01, 2, eternalFlame),
  GetSpellHasteRequired(15.008630),
  "PALADIN",
  SPEC_IDS.PALADIN.holy
)
HASTE_BREAKS.PALADIN.ETERNAL_FLAME_3 = AddHasteBreakpoint(
  nameFormatWithTicks:format(eternalFlameMarkup, 25.03, 3, eternalFlame),
  GetSpellHasteRequired(25.026052),
  "PALADIN",
  SPEC_IDS.PALADIN.holy
)
AddHasteBreakpoint(
  nameFormatWithTicks:format(sacredShieldMarkup, 30.00, 2, sacredShield),
  GetSpellHasteRequired(29.996753),
  "PALADIN",
  SPEC_IDS.PALADIN.holy
)
AddHasteBreakpoint(
  nameFormatWithTicks:format(eternalFlameMarkup, 34.99, 4, eternalFlame),
  GetSpellHasteRequired(34.983133),
  "PALADIN",
  SPEC_IDS.PALADIN.holy
)

local renew, renewMarkup = C_Spell.GetSpellName(139), CreateIconMarkup(135953)
AddHasteBreakpoint(
  nameFormatWithTicks:format(renewMarkup, 12.51, 1, renew),
  GetSpellHasteRequired(12.51),
  "PRIEST"
)
AddHasteBreakpoint(
  nameFormatWithTicks:format(renewMarkup, 37.52, 2, renew),
  GetSpellHasteRequired(37.52),
  "PRIEST"
)
AddHasteBreakpoint(
  nameFormatWithTicks:format(renewMarkup, 62.53, 3, renew),
  GetSpellHasteRequired(62.53),
  "PRIEST"
)
AddHasteBreakpoint(
  nameFormatWithTicks:format(renewMarkup, 87.44, 4, renew),
  GetSpellHasteRequired(87.44),
  "PRIEST"
)

local doom, doomMarkup = C_Spell.GetSpellName(603), CreateIconMarkup(136122)
AddHasteBreakpoint( -- Doom
  nameFormatWithTicks:format(doomMarkup, 12.50, 1, doom),
  GetSpellHasteRequired(12.498595),
  "WARLOCK",
  SPEC_IDS.WARLOCK.demonology
)
AddHasteBreakpoint( -- Doom
  nameFormatWithTicks:format(doomMarkup, 24.92, 2, doom),
  GetSpellHasteRequired(24.921939),
  "WARLOCK",
  SPEC_IDS.WARLOCK.demonology
)
AddHasteBreakpoint( -- Shadowflame
  nameFormatWithTicks:format(CreateIconMarkup(425954), 37.50, 2, C_Spell.GetSpellName(47960)),
  GetSpellHasteRequired(37.494845),
  "WARLOCK",
  SPEC_IDS.WARLOCK.demonology
)
local immolate, immolateMarkup = C_Spell.GetSpellName(348), CreateIconMarkup(135817)
AddHasteBreakpoint( -- Immolate
  nameFormatWithTicks:format(immolateMarkup, 9.99, 1, immolate),
  GetSpellHasteRequired(9.990838),
  "WARLOCK",
  SPEC_IDS.WARLOCK.destruction
)
AddHasteBreakpoint( -- Immolate
  nameFormatWithTicks:format(immolateMarkup, 30.01, 2, immolate),
  GetSpellHasteRequired(30.010840),
  "WARLOCK",
  SPEC_IDS.WARLOCK.destruction
)
local unstableAffliction, unstableAfflictionMarkup = C_Spell.GetSpellName(30108), CreateIconMarkup(136228)
AddHasteBreakpoint( -- Unstable Affliction
  nameFormatWithTicks:format(unstableAfflictionMarkup, 21.40, 2, unstableAffliction),
  GetSpellHasteRequired(21.396062),
  "WARLOCK",
  SPEC_IDS.WARLOCK.affliction
)
local agony, agonyMarkup = C_Spell.GetSpellName(980), CreateIconMarkup(136139)
AddHasteBreakpoint( -- Agony
  nameFormatWithTicks:format(agonyMarkup, 29.16, 4, agony),
  GetSpellHasteRequired(29.157257),
  "WARLOCK",
  SPEC_IDS.WARLOCK.affliction
)
AddHasteBreakpoint( -- Unstable Affliction
  nameFormatWithTicks:format(unstableAfflictionMarkup, 35.73, 3, unstableAffliction),
  GetSpellHasteRequired(35.731261),
  "WARLOCK",
  SPEC_IDS.WARLOCK.affliction
)
AddHasteBreakpoint( -- Agony
  nameFormatWithTicks:format(agonyMarkup, 37.51, 5, agony),
  GetSpellHasteRequired(37.504306),
  "WARLOCK",
  SPEC_IDS.WARLOCK.affliction
)
AddHasteBreakpoint( -- Corruption
  nameFormatWithTicks:format(CreateIconMarkup(136118), 38.94, 4, C_Spell.GetSpellName(172)),
  GetSpellHasteRequired(38.937141),
  "WARLOCK",
  SPEC_IDS.WARLOCK.affliction
)

local HitCap = { stat = StatHit, points = { { method = AtLeast, preset = CAPS.MeleeHitCap } } }

local HitCapSpell = { stat = StatHit, points = { { method = AtLeast, preset = CAPS.SpellHitCap } } }

local SoftExpCap = { stat = StatExp, points = { { method = AtLeast, preset = CAPS.ExpSoftCap } } }

local HardExpCap = { stat = StatExp, points = { { method = AtLeast, preset = CAPS.ExpHardCap } } }

local MeleeCaps = { HitCap, SoftExpCap }

local AtMostMeleeCaps = {
  { stat = StatHit, points = { { method = AtMost, preset = CAPS.MeleeHitCap } } },
  { stat = StatExp, points = { { method = AtMost, preset = CAPS.ExpSoftCap } } }
}

local TankCaps = { HitCap, HardExpCap }

local CasterCaps = { HitCapSpell }

-- Preset builder functions
local function Preset(spirit, dodge, parry, hit, crit, haste, exp, mastery, caps, icon)
  return {
    weights = {spirit or 0, dodge or 0, parry or 0, hit or 0, crit or 0, haste or 0, exp or 0, mastery or 0},
    caps = caps,
    icon = icon,
  }
end

local function MeleePreset(hit, crit, haste, exp, mastery)
  return Preset(0, 0, 0, hit, crit, haste, exp, mastery, MeleeCaps)
end

local function TankPreset(spirit, dodge, parry, hit, crit, haste, exp, mastery, caps)
  return Preset(spirit, dodge, parry, hit, crit, haste, exp, mastery, caps or TankCaps)
end

local function CasterPreset(hit, crit, haste, mastery)
  return Preset(0, 0, 0, hit, crit, haste, 0, mastery, CasterCaps)
end

local function HealerPreset(spirit, crit, haste, mastery)
  return Preset(spirit, 0, 0, 0, crit, haste, 0, mastery)
end

addonTable.classPresets = {
  ["DEATHKNIGHT"] = {
    [SPEC_IDS.DEATHKNIGHT.blood] = {
      [L["Defensive"]] = Preset(0, 140, 150, 100, 50, 75, 95, 200, AtMostMeleeCaps),
      [L["Balanced"]] = Preset(0, 140, 150, 200, 100, 125, 200, 25, MeleeCaps),
      [L["Offensive"]] = {
        weights = {0, 90, 100, 200, 150, 125, 200, 0},
        caps = {
          HitCap,
          { stat = StatExp, points = { { method = AtLeast, preset = CAPS.ExpSoftCap, after = 50 } } }
        },
      },
    },
    [SPEC_IDS.DEATHKNIGHT.frost] = {
      [C_Spell.GetSpellName(49020)] = Preset(0, 0, 0, 82, 44, 45, 82, 35, MeleeCaps, 135771), -- Obliterate
      [L["Masterfrost"]] = Preset(0, 0, 0, 84, 36, 37, 83, 53, MeleeCaps, 135833),
    },
    [SPEC_IDS.DEATHKNIGHT.unholy] = MeleePreset(73, 47, 43, 73, 40),
  },
  ["DRUID"] = {
    [SPEC_IDS.DRUID.balance] = {
      weights = {0, 0, 0, 88, 54, 55, 0, 46},
      caps = {
        HitCapSpell,
        {
          stat = StatHaste,
          points = {
            {
              method = AtLeast,
              preset = HASTE_BREAKS.DRUID.WILD_MUSHROOM,
              after = 46,
            }
          }
        }
      },
    },
    [SPEC_IDS.DRUID.feralcombat] = Preset(0, 0, 0, 44, 49, 42, 44, 39, AtMostMeleeCaps),
    [SPEC_IDS.DRUID.guardian] = TankPreset(0, 53, 0, 116, 105, 37, 116, 73),
    [SPEC_IDS.DRUID.restoration] = {
      weights = {150, 0, 0, 0, 100, 200, 0, 150},
      caps = {
        {
          stat = StatHaste,
          points = {
            {
              method = AtLeast,
              preset = HASTE_BREAKS.DRUID.REJUV_LIFEBLOOM,
              after = 50,
            }
          }
        }
      },
    },
  },
  ["HUNTER"] = {
    [SPEC_IDS.HUNTER.beastmastery] = MeleePreset(30, 28, 29, 30, 25),
    [SPEC_IDS.HUNTER.marksmanship] = MeleePreset(44, 43, 35, 44, 19),
    [SPEC_IDS.HUNTER.survival] = MeleePreset(33, 32, 27, 33, 21),
  },
  ["MAGE"] = {
    [SPEC_IDS.MAGE.arcane] = CasterPreset(145, 59, 64, 70),
    [SPEC_IDS.MAGE.fire] = CasterPreset(121, 94, 95, 59),
    [SPEC_IDS.MAGE.frost] = CasterPreset(155, 54, 81, 52),
  },
  ["MONK"] = {
    [SPEC_IDS.MONK.brewmaster] = {
      [PET_DEFENSIVE] = TankPreset(0, 0, 0, 150, 50, 50, 130, 100),
      [PET_AGGRESSIVE] = TankPreset(0, 0, 0, 141, 46, 57, 99, 39),
    },
    [SPEC_IDS.MONK.mistweaver] = HealerPreset(80, 200, 40, 30),
    [SPEC_IDS.MONK.windwalker] = {
      [C_Spell.GetSpellName(114355)] = Preset(0, 0, 0, 141, 44, 49, 99, 39, MeleeCaps, 132147), -- Dual Wield
      [AUCTION_SUBCATEGORY_TWO_HANDED] = Preset(0, 0, 0, 141, 64, 63, 141, 62, MeleeCaps, 135145), -- Two-Handed
    },
  },
  ["PALADIN"] = {
    [SPEC_IDS.PALADIN.holy] = {
      weights = {200, 0, 0, 0, 50, 125, 0, 100},
      caps = {
        {
          stat = StatHaste,
          points = {
            {
              method = AtLeast,
              preset = HASTE_BREAKS.PALADIN.ETERNAL_FLAME_3,
              after = 75,
            }
          }
        }
      },
    },
    [SPEC_IDS.PALADIN.protection] = {
      [PET_DEFENSIVE] = TankPreset(0, 50, 50, 200, 25, 100, 200, 125),
      [PET_AGGRESSIVE] = TankPreset(0, 5, 5, 200, 75, 125, 200, 25),
    },
    [SPEC_IDS.PALADIN.retribution] = MeleePreset(100, 50, 52, 87, 51),
  },
  ["PRIEST"] = {
    [SPEC_IDS.PRIEST.discipline] = HealerPreset(120, 120, 40, 80),
    [SPEC_IDS.PRIEST.holy] = HealerPreset(150, 120, 40, 80),
    [SPEC_IDS.PRIEST.shadow] = CasterPreset(85, 46, 59, 44),
  },
  ["ROGUE"] = {
    [SPEC_IDS.ROGUE.assassination] = MeleePreset(46, 37, 35, 42, 41),
    [SPEC_IDS.ROGUE.combat] = MeleePreset(70, 29, 39, 56, 32),
    [SPEC_IDS.ROGUE.subtlety] = MeleePreset(54, 31, 32, 35, 26),
  },
  ["SHAMAN"] = {
    [SPEC_IDS.SHAMAN.elemental] = {
      [L["Single Target"]] = Preset(0, 0, 0, 110, 37, 47, 0, 44, CasterCaps, 136048),
      [L["AoE"]] = Preset(0, 0, 0, 118, 71, 48, 0, 73, CasterCaps, 136015),
    },
    [SPEC_IDS.SHAMAN.enhancement] = MeleePreset(97, 41, 42, 97, 46),
    [SPEC_IDS.SHAMAN.restoration] = HealerPreset(120, 100, 150, 75),
  },
  ["WARLOCK"] = {
    [SPEC_IDS.WARLOCK.affliction] = CasterPreset(90, 56, 73, 68),
    [SPEC_IDS.WARLOCK.destruction] = CasterPreset(93, 55, 50, 61),
    [SPEC_IDS.WARLOCK.demonology] = CasterPreset(400, 60, 66, 63),
  },
  ["WARRIOR"] = {
    [SPEC_IDS.WARRIOR.arms] = MeleePreset(188, 65, 30, 139, 49),
    [SPEC_IDS.WARRIOR.fury] = {
      [C_Spell.GetSpellName(46917)] = Preset(0, 0, 0, 162, 107, 41, 142, 70, MeleeCaps, 236316), -- Titan's Grip
      [C_Spell.GetSpellName(81099)] = Preset(0, 0, 0, 137, 94, 41, 119, 59, MeleeCaps, 458974), -- Single-Minded Fury
    },
    [SPEC_IDS.WARRIOR.protection] = TankPreset(0, 140, 150, 200, 25, 50, 200, 100),
  },
}
