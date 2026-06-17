---@type string, AddonTable
local _, addonTable = ...

-- Mists (5.4.4) compatibility layer. The shared code calls addonTable.compat.* so the Cata
-- flavor can supply its own implementations of APIs the 4.4.2 client lacks; on a modern
-- client these map straight to the native APIs.
addonTable.compat = {
  GetCurrentSpecID = PlayerUtil.GetCurrentSpecID,
  GetSpecInfoByID = GetSpecializationInfoByID,
  GetActiveSpecGroup = C_SpecializationInfo.GetActiveSpecGroup,
  SerializeJSON = C_EncodingUtil.SerializeJSON,
  DeserializeJSON = C_EncodingUtil.DeserializeJSON,
}
