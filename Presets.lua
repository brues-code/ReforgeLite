---@type string, AddonTable
local _, addonTable = ...
local L = addonTable.L
local ReforgeLite = addonTable.ReforgeLite
local GUI = addonTable.GUI

local StatHit = addonTable.statIds.HIT
local StatCrit = addonTable.statIds.CRIT
local StatHaste = addonTable.statIds.HASTE
local StatExp = addonTable.statIds.EXP

local function CreateIconMarkup(icon)
  -- 4.4.2 may not have the texcoord form of CreateTextureMarkup; fall back to the simple one.
  if CreateTextureMarkup then
    return CreateTextureMarkup(icon, 64, 64, 18, 18, 0.07, 0.93, 0.07, 0.93, 0, 0) .. " "
  end
  return CreateSimpleTextureMarkup(icon, 18, 18) .. " "
end
addonTable.CreateIconMarkup = CreateIconMarkup

-- Cap presets, haste breakpoints, cap-set constants, preset builders, and the class
-- preset tables (addonTable.classPresets / ReforgeLite.capPresets / addonTable.CAPS)
-- are flavor-specific and live in <Flavor>/Presets.lua, loaded after this file.

local specInfo
local function UpdateSpecInfo(ids)
  for _, id in pairs(ids) do
    local _, tabName, _, icon = addonTable.compat.GetSpecInfoByID(id)
    specInfo[id] = { name = tabName, icon = icon }
  end
end

---Initializes class-specific stat weight and cap presets
---Loads presets for all specs of the player's class (or all classes in debug mode)
---@return nil
function ReforgeLite:InitClassPresets()
  self.presets = wipe(self.presets or {})
  specInfo = wipe(specInfo or {})
  if self.db.debug then
    for classFile, className in pairs(LOCALIZED_CLASS_NAMES_MALE) do
      self.presets[className] = addonTable.classPresets[classFile]
    end
    TableUtil.Execute(addonTable.SPEC_IDS, UpdateSpecInfo)
  else
    for specId, preset in pairs(addonTable.classPresets[addonTable.playerClass]) do
      self.presets[specId] = preset
    end
    UpdateSpecInfo(addonTable.SPEC_IDS[addonTable.playerClass])
  end
end

local DYNAMIC_PRESETS = tInvert( { "Pawn", CUSTOM } )

---Initializes custom user-created presets from saved variables
---@return nil
function ReforgeLite:InitCustomPresets()
  local customPresets = {}
  for k, v in pairs(self.cdb.customPresets) do
    local preset = CopyTable(v)
    preset.name = k
    tinsert(customPresets, preset)
  end
  self.presets[CUSTOM] = customPresets
end

---Initializes all dynamic presets (class and custom)
---@return nil
function ReforgeLite:InitDynamicPresets()
  self:InitClassPresets()
  self:InitCustomPresets()
end

---Initializes all presets including Pawn integration and preset menu
---Sets up class presets, custom presets, Pawn integration, and menu generator
---@return nil
function ReforgeLite:InitPresets()
  self:InitDynamicPresets()
  if PawnVersion then
    self.presets["Pawn"] = function ()
      if not PawnCommon or not PawnCommon.Scales then return {} end
      local result = {}
      for k, v in pairs (PawnCommon.Scales) do
        if v.ClassID == addonTable.playerClassID then
          local preset = {name = v.LocalizedName or k}
          preset.weights = {}
          local raw = v.Values or {}
          preset.weights[addonTable.statIds.SPIRIT] = raw["Spirit"] or 0
          preset.weights[addonTable.statIds.DODGE] = raw["DodgeRating"] or 0
          preset.weights[addonTable.statIds.PARRY] = raw["ParryRating"] or 0
          preset.weights[StatHit] = raw["HitRating"] or 0
          preset.weights[StatCrit] = raw["CritRating"] or 0
          preset.weights[StatHaste] = raw["HasteRating"] or 0
          preset.weights[StatExp] = raw["ExpertiseRating"] or 0
          preset.weights[addonTable.statIds.MASTERY] = raw["MasteryRating"] or 0
          local total = 0
          local average = 0
          for i = 1, addonTable.itemStatCount do
            if preset.weights[i] ~= 0 then
              total = total + 1
              average = average + preset.weights[i]
            end
          end
          if total > 0 and average > 0 then
            local factor = 1
            while factor * average / total < 10 do
              factor = factor * 100
            end
            while factor * average / total > 1000 do
              factor = factor / 10
            end
            for i = 1, addonTable.itemStatCount do
              preset.weights[i] = preset.weights[i] * factor
            end
            tinsert(result, preset)
          end
        end
      end
      return result
    end
  end

  self.presetMenuGenerator = function(owner, rootDescription)
    GUI:ClearEditFocus()

    local saveButton = rootDescription:CreateButton(SAVE, function()
      GUI.CreateStaticPopup("SAVE_PRESET",
        L["Enter the preset name"],
        function(popup)
          self.cdb.customPresets[popup:GetEditBox():GetText()] = {
            caps = CopyTable(self.pdb.caps),
            weights = CopyTable(self.pdb.weights)
          }
          self:InitCustomPresets()
        end, { hasEditBox = 1 })
    end)

    saveButton:SetTitleAndTextTooltip(L["Save current stat weights and caps as a custom preset"], L["Custom presets are shared across all characters of this class"])

    rootDescription:CreateDivider()

    local function GetCapPreset(presetValue)
      return FindValueInTableIf(self.capPresets, function(preset) return preset.value == presetValue end) or {}
    end

    local function FormatWeightsTooltip(tooltip, element, preset)
      if not preset or not preset.weights then return end
      local statWeights = {}
      for i, weight in ipairs(preset.weights) do
        if weight and weight > 0 then
          tinsert(statWeights, {stat = addonTable.itemStats[i].long, weight = weight, index = i})
        end
      end
      local rightR, rightG, rightB = addonTable.COLORS.white:GetRGB()
      if statWeights[1] then
        tooltip:AddLine(element.text, rightR, rightG, rightB)
        sort(statWeights, function(a, b)
          if a.weight == b.weight then
            return a.index < b.index
          end
          return a.weight > b.weight
        end)
        for _, entry in ipairs(statWeights) do
          tooltip:AddDoubleLine(entry.stat, entry.weight, nil, nil, nil, rightR, rightG, rightB)
        end
      end
      if preset.caps then
        local methodNames = {
          [addonTable.StatCapMethods.AtLeast] = L["At least"],
          [addonTable.StatCapMethods.AtMost] = L["At most"],
          [addonTable.StatCapMethods.Exactly] = L["Exactly"],
        }
        for i, cap in ipairs(preset.caps) do
          if cap and cap.stat and cap.stat > 0 and cap.points and cap.points[1] then
            local statName = addonTable.itemStats[cap.stat] and addonTable.itemStats[cap.stat].long or ""
            local pt = cap.points[1]
            local presetInfo = GetCapPreset(pt.preset)
            local methodName = methodNames[pt.method] or ""
            local capText
            if presetInfo and pt.preset ~= addonTable.CAPS.ManualCap then
              capText = ("%s %s"):format(methodName, presetInfo.name)
            else
              capText = ("%s %d"):format(methodName, pt.value or 0)
            end
            tooltip:AddLine(L["Cap %d - %s"]:format(i, statName))
            tooltip:AddLine("  " .. capText, rightR, rightG, rightB)
          end
        end
      end
    end

    local function AddPresetButton(desc, info)
      if info.hasDelete then
        local button = desc:CreateButton(info.text, function(mouseButton)
          if IsShiftKeyDown() then
            GUI.CreateStaticPopup("DELETE_PRESET",
              L["Delete preset '%s'?"]:format(info.presetName),
              function()
                self.cdb.customPresets[info.presetName] = nil
                self:InitCustomPresets()
              end, { button1 = DELETE })
          else
            if info.value.targetLevel then
              self.pdb.targetLevel = info.value.targetLevel
              self.targetLevel:SetValue(info.value.targetLevel)
            end
            self:SetStatWeights(info.value.weights, info.value.caps or {})
          end
        end)
        button:SetTooltip(function(tooltip, element)
          FormatWeightsTooltip(tooltip, element, info.value)
          tooltip:AddLine(" ")
          GameTooltip_AddColoredLine(tooltip, L["Shift+Click to delete"], addonTable.COLORS.red)
        end)
      else
        local button = desc:CreateButton(info.text, function()
          if info.value.targetLevel then
            self.pdb.targetLevel = info.value.targetLevel
            self.targetLevel:SetValue(info.value.targetLevel)
          end
          self:SetStatWeights(info.value.weights, info.value.caps or {})
        end)
        button:SetTooltip(function(tooltip, element)
          FormatWeightsTooltip(tooltip, element, info.value)
        end)
      end
    end

    local menuList = {}
    for k in pairs(self.presets) do
      local v = GetValueOrCallFunction(self.presets, k)
      local isClassMenu = type(v) == "table" and not v.weights and not v.caps

      if isClassMenu then
        local classInfo = {
          sortKey = specInfo[k] and specInfo[k].name or k,
          text = specInfo[k] and specInfo[k].name or k,
          prioritySort = DYNAMIC_PRESETS[k] or 0,
          key = k,
          isSubmenu = true,
          submenuItems = {}
        }
        if specInfo[k] then
          classInfo.text = CreateIconMarkup(specInfo[k].icon) .. specInfo[k].name
        end

        for specId in pairs(v) do
          local preset = GetValueOrCallFunction(v, specId)
          local hasSubPresets = type(preset) == "table" and not preset.weights and not preset.caps

          if hasSubPresets then
            local specSubmenu = {
              sortKey = (specInfo[specId] and specInfo[specId].name) or tostring(specId),
              text = (specInfo[specId] and specInfo[specId].name) or tostring(specId),
              prioritySort = 0,
              isSubmenu = true,
              submenuItems = {}
            }
            if specInfo[specId] then
              specSubmenu.text = CreateIconMarkup(specInfo[specId].icon) .. specInfo[specId].name
            end

            for subK, subPreset in pairs(preset) do
              if type(subPreset) == "table" and (subPreset.weights or subPreset.caps) then
                local subSubInfo = {
                  sortKey = subK,
                  text = subK,
                  prioritySort = DYNAMIC_PRESETS[subK] or 0,
                  value = subPreset,
                }
                if subPreset.icon then
                  subSubInfo.text = CreateIconMarkup(subPreset.icon) .. subSubInfo.text
                end
                tinsert(specSubmenu.submenuItems, subSubInfo)
              end
            end

            if #specSubmenu.submenuItems > 0 then
              sort(specSubmenu.submenuItems, function (a, b)
                if a.prioritySort ~= b.prioritySort then
                  return a.prioritySort > b.prioritySort
                end
                return tostring(a.sortKey) < tostring(b.sortKey)
              end)
              tinsert(classInfo.submenuItems, specSubmenu)
            end
          else
            local subInfo = {
              sortKey = preset.name or (specInfo[specId] and specInfo[specId].name) or tostring(specId),
              text = preset.name or (specInfo[specId] and specInfo[specId].name) or tostring(specId),
              prioritySort = DYNAMIC_PRESETS[k] or 0,
              value = preset,
              hasDelete = (k == CUSTOM),
              presetName = preset.name,
            }
            if specInfo[specId] then
              subInfo.text = CreateIconMarkup(specInfo[specId].icon) .. specInfo[specId].name
              subInfo.sortKey = specInfo[specId].name
            end
            if preset.icon then
              subInfo.text = CreateIconMarkup(preset.icon) .. subInfo.text
            end
            tinsert(classInfo.submenuItems, subInfo)
          end
        end

        sort(classInfo.submenuItems, function (a, b)
          if a.prioritySort ~= b.prioritySort then
            return a.prioritySort > b.prioritySort
          end
          return tostring(a.sortKey) < tostring(b.sortKey)
        end)

        tinsert(menuList, classInfo)
      else
        local info = {
          sortKey = v.name or k,
          text = v.name or k,
          prioritySort = DYNAMIC_PRESETS[k] or 0,
          value = v,
        }
        if specInfo[k] then
          info.text = CreateIconMarkup(specInfo[k].icon) .. specInfo[k].name
          info.sortKey = specInfo[k].name
        end
        if v.icon then
          info.text = CreateIconMarkup(v.icon) .. info.text
        end
        tinsert(menuList, info)
      end
    end

    sort(menuList, function (a, b)
      if a.prioritySort ~= b.prioritySort then
        return a.prioritySort > b.prioritySort
      end
      return tostring(a.sortKey) < tostring(b.sortKey)
    end)

    local function AddMenuItems(desc, items)
      for _, info in ipairs(items) do
        if info.isSubmenu then
          local submenu = desc:CreateButton(info.text)
          if #info.submenuItems == 0 then
            submenu:SetEnabled(false)
          end
          AddMenuItems(submenu, info.submenuItems)
        elseif info.value and (info.value.caps or info.value.weights) then
          AddPresetButton(desc, info)
        end
      end
    end

    AddMenuItems(rootDescription, menuList)
  end
end
