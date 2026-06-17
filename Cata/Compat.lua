---@type string, AddonTable
local _, addonTable = ...

-- Compatibility shims for the 4.4.2 (Cata Classic) client, which lacks some of
-- the modern APIs the shared code relies on. Loaded only by ReforgeLite_Cata.toc,
-- ahead of any file that consumes these globals.

-- C_EncodingUtil: 4.4.2 has no JSON (de)serialization API. Back it with the
-- bundled rxi json (Cata/json.lua). Only SerializeJSON/DeserializeJSON are used.
if not C_EncodingUtil then
  C_EncodingUtil = {
    SerializeJSON = function(value) return addonTable.json.encode(value) end,
    DeserializeJSON = function(str) return addonTable.json.decode(str) end,
  }
end

-- CreateTextureMarkup signature differs; the shared code calls the 6-arg+texcoord
-- form, 4.4.2 ships CreateSimpleTextureMarkup. Provide the modern name.
if not CreateTextureMarkup and CreateSimpleTextureMarkup then
  CreateTextureMarkup = function(file, _fileWidth, _fileHeight, width, height)
    return CreateSimpleTextureMarkup(file, width, height)
  end
end

-- Specialization API: this client has no GetSpecialization / C_SpecializationInfo /
-- GetSpecializationInfo(ByID), but it does have GetPrimaryTalentTree (current tree 1-3)
-- and GetSpecializationInfoForSpecID. Rebuild the API our shared code uses on top of those.
-- GetSpecialization() returns the talent-tree index; GetSpecializationInfo(treeIndex)
-- maps that index (for the player's class) to a spec ID and resolves it via ForSpecID.
local function CurrentTreeIndex()
  return GetPrimaryTalentTree and GetPrimaryTalentTree() or nil
end

local function SpecIDForTree(treeIndex)
  local byTree = addonTable.SPEC_IDS_BY_TREE and addonTable.SPEC_IDS_BY_TREE[addonTable.playerClass]
  return treeIndex and byTree and byTree[treeIndex] or nil
end

if not GetSpecialization then
  GetSpecialization = CurrentTreeIndex
end

if not GetSpecializationInfo and GetSpecializationInfoForSpecID then
  GetSpecializationInfo = function(treeIndex)
    local specID = SpecIDForTree(treeIndex)
    if specID then return GetSpecializationInfoForSpecID(specID) end
  end
end

if not GetSpecializationInfoByID and GetSpecializationInfoForSpecID then
  GetSpecializationInfoByID = function(specID) return GetSpecializationInfoForSpecID(specID) end
end

C_SpecializationInfo = C_SpecializationInfo or {}
if not C_SpecializationInfo.GetSpecialization then
  C_SpecializationInfo.GetSpecialization = GetSpecialization
end
if not C_SpecializationInfo.GetSpecializationInfo then
  C_SpecializationInfo.GetSpecializationInfo = GetSpecializationInfo
end
-- Active spec group (dual-spec slot 1/2). Cata uses GetActiveTalentGroup.
if not C_SpecializationInfo.GetActiveSpecGroup then
  C_SpecializationInfo.GetActiveSpecGroup = function()
    return (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
  end
end

-- C_AddOns.GetAddOnTitle is absent here; derive it from the Title metadata.
if C_AddOns and not C_AddOns.GetAddOnTitle and C_AddOns.GetAddOnMetadata then
  C_AddOns.GetAddOnTitle = function(name) return C_AddOns.GetAddOnMetadata(name, "Title") end
end

-- LinkUtil.SplitLinkOptions (matches Blizzard_SharedXML/LinkUtil.lua). The item-link
-- reforge ID lives at field 10 on 4.4.2 too (the old 4.4.2 addon used the same).
LinkUtil = LinkUtil or {}
if not LinkUtil.SplitLinkOptions then
  function LinkUtil.SplitLinkOptions(linkOptions)
    return string.split(":", linkOptions)
  end
end
