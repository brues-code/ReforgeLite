---@type string, AddonTable
local addonName, addonTable = ...
local ReforgeLite = addonTable.ReforgeLite

-- Cata (4.4.2) reforge detection. Unlike MoP, the item link carries no reforge ID, so
-- the current reforge is read by scanning the item's tooltip and diffing each stat against
-- the item's BASE stats (GetItemStats returns the unreforged values on this client):
--   * a stat shown in the tooltip but absent from the base item  -> reforge destination
--   * a stat shown lower than its base value                     -> reforge source
-- Then (source, destination) maps to a reforgeTable index. Ported from the 4.4.2
-- ReforgeLite SearchTooltipForReforgeID, reusing the shared itemStats:getTooltipPatterns().
-- Installed as addonTable.GetReforgeIDForSlot, which the shared GetReforgeID consults.

local scanTooltip
local function GetReforgeIDForSlot(slotId)
  if not scanTooltip then
    scanTooltip = CreateFrame("GameTooltip", addonName .. "ReforgeScanTooltip", nil, "GameTooltipTemplate")
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  scanTooltip:SetInventoryItem("player", slotId)
  local _, link = scanTooltip:GetItem()
  if not link then return end

  print(link)

  local baseStats = GetItemStats(link) or {}
  local srcStat, destStat
  for _, region in ipairs({ scanTooltip:GetRegions() }) do
    if region:GetObjectType() == "FontString" then
      local text = region:GetText()
      if text then
        for statId, statInfo in ipairs(addonTable.itemStats) do
          local statValue
          for _, pattern in ipairs(statInfo:getTooltipPatterns()) do
            local captured = text:match(pattern)
            if captured then
              statValue = tonumber((captured:gsub(",", "")))
              break
            end
          end
          if statValue then
            local base = baseStats[statInfo.name]
            if not base then
              destStat = statId
            elseif base - statValue > 0 then
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

addonTable.GetReforgeIDForSlot = GetReforgeIDForSlot
