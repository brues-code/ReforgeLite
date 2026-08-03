local _, addonTable = ...

local AmplificationItems = {
  [104976] = true, -- Prismatic Prison of Pride, Raid Finder
  [104727] = true, -- Prismatic Prison of Pride, Flexible
  [102299] = true, -- Prismatic Prison of Pride
  [105225] = true, -- Prismatic Prison of Pride, Warforged
  [104478] = true, -- Prismatic Prison of Pride, Heroic
  [105474] = true, -- Prismatic Prison of Pride, Heroic Warforged

  [104924] = true, -- Purified Bindings of Immerseus, Raid Finder
  [104675] = true, -- Purified Bindings of Immerseus, Flexible
  [102293] = true, -- Purified Bindings of Immerseus
  [105173] = true, -- Purified Bindings of Immerseus, Warforged
  [104426] = true, -- Purified Bindings of Immerseus, Heroic
  [105422] = true, -- Purified Bindings of Immerseus, Heroic Warforged

  [105111] = true, -- Thok's Tail Tip, Raid Finder
  [104862] = true, -- Thok's Tail Tip, Flexible
  [102305] = true, -- Thok's Tail Tip
  [105360] = true, -- Thok's Tail Tip, Warforged
  [104613] = true, -- Thok's Tail Tip, Heroic
  [105609] = true, -- Thok's Tail Tip, Heroic Warforged
}

---Gets the Amplify equip-bonus multiplier for an item (nil if it isn't an amplification trinket)
---The amp effect scales off a server-side float budget, not the integer RandPropPoints table,
---and is not rounded. This curve reconstructs that budget (fitted by wowsims against live
---character-sheet readings) so it matches the game's applied value at every item level.
---@param itemInfo table Item info with itemId and ilvl
---@return number factor Stat multiplier (e.g. 1.05) for Haste/Mastery/Spirit
function addonTable.GetAmplificationFactor(itemInfo)
    if AmplificationItems[itemInfo.itemId] then
        return 1 + 22.78695 * exp(0.00932545 * itemInfo.ilvl) * 0.00176999997 / 100
    end
end
