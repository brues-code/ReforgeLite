---@type string, AddonTable
local _, addonTable = ...

local function GetCurrentSpecID()
  local treeIndex = GetPrimaryTalentTree and GetPrimaryTalentTree()
  local byTree = addonTable.SPEC_IDS_BY_TREE and addonTable.SPEC_IDS_BY_TREE[addonTable.playerClass]
  return treeIndex and byTree and byTree[treeIndex] or nil
end

addonTable.compat = {
  GetCurrentSpecID = GetCurrentSpecID,
  GetSpecInfoByID = function(specID)
    if specID then return GetSpecializationInfoForSpecID(specID) end
  end,
  GetActiveSpecGroup = function()
    return (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
  end,
  -- JSON via the bundled rxi json (Cata/json.lua sets addonTable.json).
  SerializeJSON = function(value) return addonTable.json.encode(value) end,
  DeserializeJSON = function(str) return addonTable.json.decode(str) end,
}
