---@type string, AddonTable
local addonName, addonTable = ...
local ReforgeLite = addonTable.ReforgeLite
local statIds = addonTable.statIds

-- Cata (4.4.2) reforge detection. Unlike MoP, the item link carries no reforge ID, so the
-- current reforge is read by scanning the item's tooltip and diffing each stat against the
-- item's BASE stats (GetItemStats returns the unreforged values on this client):
--   * a stat shown in the tooltip but absent from the base item  -> reforge destination
--   * a stat shown lower than its base value                     -> reforge source
-- (source, destination) then maps to a reforgeTable index. Ported from the 4.4.2 ReforgeLite
-- SearchTooltipForReforgeID, including its per-stat tooltip parsers: rating stats match their
-- localized "ITEM_MOD_*_RATING" line (value captured from the %s slot); spirit/mastery match
-- the white "+N Name" line. Installed as addonTable.GetReforgeIDForSlot, which the shared
-- GetReforgeID consults.

-- EquipPredicate prefixes the rating lines; "" on enUS (inherited by most locales),
-- ITEM_SPELL_TRIGGER_ONEQUIP on zhTW/koKR (matches the 4.4.2 ReforgeLite locales).
local EquipPredicate = (addonTable.CurrentLocale == "zhTW" or addonTable.CurrentLocale == "koKR") and (ITEM_SPELL_TRIGGER_ONEQUIP .. " ") or ""

local function RatingPattern(longConst)
  return EquipPredicate .. (_G[longConst] or ""):gsub("%%s", "(.+)")
end

local function PlusPattern(shortConst)
  return ("^+(%d+) %s$"):gsub("%%s", _G[shortConst] or "")
end

-- Spirit shows as a white "+N Spirit" line; the white-color check avoids matching other
-- references to Spirit (e.g. set bonuses).
local function MatchSpirit(region)
  if CreateColor and WHITE_FONT_COLOR and CreateColor(region:GetTextColor()):IsEqualTo(WHITE_FONT_COLOR) then
    return (region:GetText() or ""):match(PlusPattern("ITEM_MOD_SPIRIT_SHORT"))
  end
end

local statParsers = {
  [statIds.SPIRIT]  = MatchSpirit,
  [statIds.DODGE]   = RatingPattern("ITEM_MOD_DODGE_RATING"),
  [statIds.PARRY]   = RatingPattern("ITEM_MOD_PARRY_RATING"),
  [statIds.HIT]     = RatingPattern("ITEM_MOD_HIT_RATING"),
  [statIds.CRIT]    = RatingPattern("ITEM_MOD_CRIT_RATING"),
  [statIds.HASTE]   = RatingPattern("ITEM_MOD_HASTE_RATING"),
  [statIds.EXP]     = RatingPattern("ITEM_MOD_EXPERTISE_RATING"),
  [statIds.MASTERY] = PlusPattern("ITEM_MOD_MASTERY_RATING_SHORT"),
}

-- Scan a given (already-populated) tooltip for its item's current reforge.
-- Used both for equipped-slot detection and for the on-tooltip reforge summary.
local function SearchTooltipForReforgeID(tip)
  local _, link = tip:GetItem()
  if not link then return end

  local baseStats = GetItemStats(link) or {}
  local srcStat, destStat
  for _, region in ipairs({ tip:GetRegions() }) do
    if region:GetObjectType() == "FontString" then
      local text = region:GetText()
      if text then
        for statId, statInfo in ipairs(addonTable.itemStats) do
          local parser = statParsers[statId]
          local captured
          if type(parser) == "function" then
            captured = parser(region)
          elseif parser then
            captured = text:match(parser)
          end
          if captured then
            local statValue = tonumber((tostring(captured):gsub(",", "")))
            local base = baseStats[statInfo.name]
            if not base then
              destStat = statId
            elseif statValue and base - statValue > 0 then
              srcStat = statId
            end
          end
        end
        if srcStat and destStat then break end
      end
    end
  end

  local idx = ReforgeLite:GetReforgeTableIndex(srcStat, destStat)
  if idx and idx > 0 then
    return idx
  end
end
addonTable.SearchTooltipForReforgeID = SearchTooltipForReforgeID

local scanTooltip
local function GetReforgeIDForSlot(slotId)
  if not scanTooltip then
    scanTooltip = CreateFrame("GameTooltip", addonName .. "ReforgeScanTooltip", nil, "GameTooltipTemplate")
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  scanTooltip:SetInventoryItem("player", slotId)
  return SearchTooltipForReforgeID(scanTooltip)
end

addonTable.GetReforgeIDForSlot = GetReforgeIDForSlot
