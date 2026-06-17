local _, addonTable = ...

addonTable.AmplificationItems = {
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

addonTable.RandPropPoints = {
    [463] = 1710,
    [528] = 3134,
    [529] = 3163,
    [530] = 3193,
    [531] = 3223,
    [532] = 3253,
    [533] = 3283,
    [534] = 3314,
    [535] = 3345,
    [536] = 3376,
    [537] = 3408,
    [538] = 3440,
    [539] = 3472,
    [540] = 3505,
    [541] = 3537,
    [542] = 3571,
    [543] = 3604,
    [544] = 3638,
    [545] = 3672,
    [546] = 3706,
    [547] = 3741,
    [548] = 3776,
    [549] = 3811,
    [550] = 3847,
    [551] = 3883,
    [552] = 3919,
    [553] = 3956,
    [554] = 3993,
    [555] = 4030,
    [556] = 4068,
    [557] = 4106,
    [558] = 4145,
    [559] = 4183,
    [560] = 4222,
    [561] = 4262,
    [562] = 4302,
    [563] = 4342,
    [564] = 4383,
    [565] = 4424,
    [566] = 4465,
    [567] = 4507,
    [568] = 4549,
    [569] = 4592,
    [570] = 4635,
    [571] = 4678,
    [572] = 4722,
    [573] = 4766,
    [574] = 4811,
    [575] = 4856,
    [576] = 4901,
    [577] = 4947,
    [578] = 4994,
    [579] = 5040,
    [580] = 5087,
}

---Gets the Amplify equip-bonus multiplier for an amplification trinket's item level
---@param iLvl number Item level
---@return number factor Stat multiplier (e.g. 1.05) for Haste/Mastery/Spirit
function addonTable.GetAmplificationFactor(iLvl)
    return 1 + 0.01 * floor((addonTable.RandPropPoints[iLvl] or 0) * 0.00177)

end
