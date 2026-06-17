---@type string, AddonTable
local addonName, addonTable = ...
local GUI = {}
addonTable.GUI = GUI
LibStub("AceHook-3.0"):Embed(GUI)

---Global callback registry for addon events
---
---Available callback events:
--- - "PreCalculateStart" - Fired before computation begins (locks UI)
--- - "OnCalculateStart" - Fired when computation starts
--- - "OnCalculateFinish" - Fired when computation completes (unlocks UI)
--- - "ToggleDebug" - Fired when debug mode is toggled
---
---Usage:
--- callbacks:RegisterCallback("OnCalculateFinish", function() print("Done!") end)
--- callbacks:RegisterCallback("OnCalculateFinish", function(owner) print(owner, "Done!") end, "MyAddon")
--- callbacks:TriggerEvent("OnCalculateFinish")
--- callbacks:UnregisterCallback("OnCalculateFinish", "MyAddon")
local callbacks = CreateFromMixins(CallbackRegistryMixin)
callbacks:OnLoad()
callbacks:GenerateCallbackEvents({ "OnCalculateFinish", "PreCalculateStart", "OnCalculateStart", "ToggleDebug" })

addonTable.callbacks = callbacks

addonTable.COLORS = {
  darkyellow = DARKYELLOW_FONT_COLOR,
  gold = GOLD_FONT_COLOR,
  green = CreateColor(0.6, 1, 0.6),
  grey = INACTIVE_COLOR,
  lightgrey = TUTORIAL_FONT_COLOR,
  normal = NORMAL_FONT_COLOR,
  maroon = CreateColor(0.6, 0, 0),
  panel = PANEL_BACKGROUND_COLOR,
  red = CreateColor(1, 0.4, 0.4),
  white = WHITE_FONT_COLOR,
}

---Clears focus from all edit boxes
---@return nil
function GUI:ClearEditFocus()
  if self.focusedEditBox then
    self.focusedEditBox:ClearFocus()
  end
end

---Locks all GUI widgets to prevent interaction during computation
---Disables buttons, edit boxes, checkboxes, sliders, and dropdowns
---@return nil
function GUI:Lock()
  for _, pool in ipairs(self.pools) do
    for frame in pool:EnumerateActive() do
      frame:LockWidget()
    end
  end
end

---Unlocks all GUI widgets after computation completes
---@return nil
function GUI:Unlock()
  for _, pool in ipairs(self.pools) do
    for frame in pool:EnumerateActive() do
      frame:UnlockWidget()
    end
  end
end

---Sets a tooltip on a widget
---@param widget Frame The widget to add tooltip to
---@param tip? string|function Tooltip text or function returning tooltip text
---@param opts? {wrap: boolean} Options table
---@return nil
function GUI:SetTooltip (widget, tip, opts)
  if tip then
    widget:HookScript ("OnEnter", function (tipFrame)
      local tooltipFunc = "AddLine"
      local tipText
      if type(tip) == "function" then
        tipText = tip(tipFrame)
      else
        tipText = tip
      end
      if type(tipText) == "table" then
        if tipText.spellID ~= nil then
          tooltipFunc = "SetSpellByID"
          tipText = tipText.spellID
        end
      end
      if tipText then
        local wrap = not opts or opts.wrap ~= false
        GameTooltip:SetOwner(tipFrame, "ANCHOR_LEFT")
        GameTooltip[tooltipFunc](GameTooltip, tipText, nil, nil, nil, wrap)
        GameTooltip:Show()
      end
    end)
    widget:HookScript ("OnLeave", GameTooltip_Hide)
  else
    widget:SetScript ("OnEnter", nil)
    widget:SetScript ("OnLeave", nil)
  end
end

GUI.pools = {}

-- Frame:ClearScripts() doesn't exist on older clients (e.g. 4.4.2); fall back to
-- clearing the script handlers our pooled widgets set.
local POOLED_SCRIPTS = {
  "OnClick", "PostClick", "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp",
  "OnShow", "OnHide", "OnUpdate", "OnValueChanged", "OnTextChanged",
  "OnEditFocusGained", "OnEditFocusLost", "OnEnterPressed", "OnEscapePressed",
  "OnSizeChanged", "OnDragStart", "OnDragStop",
}
local function ClearFrameScripts(frame)
  if frame.ClearScripts then
    frame:ClearScripts()
    return
  end
  for _, script in ipairs(POOLED_SCRIPTS) do
    if frame:HasScript(script) then
      frame:SetScript(script, nil)
    end
  end
end

local function PoolResetFrame(_, frame)
  frame:Hide()
  frame:ClearAllPoints()
  ClearFrameScripts(frame)
  frame:SetParent(UIParent)
end

local WidgetLockMixin = {}
function WidgetLockMixin:LockWidget()
  if not self.preventLock and (not self.IsEnabled or self:IsEnabled()) then
    self.locked = true
    if self.Disable then self:Disable() end
    if self:IsMouseEnabled() then
      self:EnableMouse(false)
      self.mouseDisabled = true
    elseif self:IsMouseMotionEnabled() then
      self:SetMouseMotionEnabled(false)
      self.mouseMotionDisabled = true
    end
    if self.SetTextColor then
      self.prevColor = {self:GetTextColor()}
      self:SetTextColor(addonTable.COLORS.grey:GetRGB())
    end
    if self.lockTexture then self.lockTexture:SetDesaturated(true) end
  end
end

function WidgetLockMixin:UnlockWidget()
  if self.locked then
    if self.Enable then self:Enable() end
    self.locked = nil
    if self.mouseDisabled then
      self:EnableMouse(true)
      self.mouseDisabled = nil
    elseif self.mouseMotionDisabled then
      self:SetMouseMotionEnabled(true)
      self.mouseMotionDisabled = nil
    end
    if self.prevColor then
      self:SetTextColor(unpack(self.prevColor))
      self.prevColor = nil
    end
    if self.lockTexture then self.lockTexture:SetDesaturated(false) end
  end
end

local function MakeRecyclablePool(...)
  local pool = CreateUnsecuredFramePool(...)
  local originalAcquire = pool.Acquire
  pool.Acquire = function(self)
    local widget, isNew = originalAcquire(self)
    if isNew then
      widget.Recycle = function(w) pool:Release(w) end
    end
    return widget, isNew
  end
  tinsert(GUI.pools, pool)
  return pool
end


GUI.editBoxPool = MakeRecyclablePool("EditBox", UIParent, "InputBoxTemplate", PoolResetFrame)
---Creates a numeric edit box with recycling support
---@param parent Frame Parent frame
---@param width number Width in pixels
---@param height number Height in pixels
---@param default number Default value
---@param setter? function Callback when value changes (value)
---@param opts? table Options: OnTabPressed callback
---@return EditBox box The created edit box
function GUI:CreateEditBox (parent, width, height, default, setter, opts)
  opts = opts or {}
  local box, isNew = self.editBoxPool:Acquire()
  if isNew then
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetNumeric()
    box:SetTextInsets(0, 0, 3, 3)
    box:SetMaxLetters(8)
    Mixin(box, WidgetLockMixin)
  end
  box:SetParent(parent)
  box:Show()
  box:SetTextColor(addonTable.COLORS.white:GetRGB())
  box:EnableMouse(true)
  if width then
    box:SetWidth(width)
  end
  if height then
    box:SetHeight(height)
  end
  box:SetText(default)
  box:SetScript("OnEnterPressed", box.ClearFocus)
  box:SetScript("OnEditFocusGained", function(frame)
    self.focusedEditBox = frame
    frame.prevValue = tonumber(frame:GetText())
    frame:HighlightText()
  end)
  box:SetScript("OnEditFocusLost", function(frame)
    self.focusedEditBox = nil
    local value = tonumber(frame:GetText())
    if not value then
      value = frame.prevValue or 0
    end
    frame:SetText (value)
    if setter then
      setter (value)
    end
    frame.prevValue = nil
  end)
  box:SetScript("OnTabPressed", opts.OnTabPressed)
  return box
end


GUI.dropdownPool = MakeRecyclablePool("DropdownButton", UIParent, "WowStyle1DropdownTemplate",
  function(_, sel)
    sel:Hide()
    sel:ClearAllPoints()
    sel.setter = nil
    sel.value = nil
    sel.selectedName = nil
    sel.selectedID = nil
    sel.selectedValue = nil
    sel.menuItemEnabled = nil
    sel.menuItemHidden = nil
    sel.values = nil
    if sel.Text then
      sel.Text:SetText("")
    end
    sel:SetParent(UIParent)
  end
)
GUI.filterDropdownPool = MakeRecyclablePool("DropdownButton", UIParent, "WowStyle1FilterDropdownTemplate",
  function(_, dropdown)
    dropdown:Hide()
    dropdown:ClearAllPoints()
    dropdown.resizeToTextPadding = dropdown.defaultResizeToTextPadding
    dropdown:SetParent(UIParent)
  end
)
---Creates a WowStyle1FilterDropdownTemplate button with recycling support
---@param parent Frame Parent frame
---@param text string Button text
---@param options? table Options: resizeToTextPadding (number)
---@return DropdownButton dropdown The created filter dropdown
function GUI:CreateFilterDropdown (parent, text, options)
  options = options or {}
  local dropdown, isNew = self.filterDropdownPool:Acquire()
  if isNew then
    dropdown.defaultResizeToTextPadding = dropdown.resizeToTextPadding
    Mixin(dropdown, WidgetLockMixin)
  end
  dropdown:SetParent(parent)
  dropdown:Show()
  dropdown:SetEnabled(true)
  if options.resizeToTextPadding then
    dropdown.resizeToTextPadding = options.resizeToTextPadding
  end
  dropdown:SetText(text)
  return dropdown
end

---Creates a dropdown menu with recycling support
---@param parent Frame Parent frame
---@param values table|function Array of {value, name} pairs or function returning the array
---@param options table Options: default, setter(dropdown, value, oldValue), width, hideArrow
---@return DropdownButton dropdown The created dropdown
function GUI:CreateDropdown (parent, values, options)
  local sel, isNew = self.dropdownPool:Acquire()
  if isNew then
    if sel.Text then
      sel.Text:ClearAllPoints()
      sel.Text:SetPoint("RIGHT", sel.Arrow, "LEFT")
      sel.Text:SetPoint("LEFT", sel, "LEFT", 9, 0)
      sel.Text:SetTextColor(addonTable.COLORS.white:GetRGB())
    end
    sel.GetValues = function(frame) return GetValueOrCallFunction(frame, 'values') end
    sel.SetValue = function(dropdown, value)
      dropdown.value = value
      dropdown.selectedValue = value
      local vals = dropdown:GetValues()
      if not vals then
        if dropdown.Text then dropdown.Text:SetText("") end
        return
      end
      for _, v in ipairs(vals) do
        if v.value == value then
          if dropdown.Text then dropdown.Text:SetText(v.name) end
          return
        end
      end
      if dropdown.Text then dropdown.Text:SetText("") end
    end
    sel:SetHeight(20)
    Mixin(sel, WidgetLockMixin)
  end
  sel:SetParent(parent)
  sel:Show()
  sel:SetEnabled(true)

  sel.values = values
  sel.setter = options.setter
  sel.menuItemEnabled = options.menuItemEnabled
  sel.menuItemHidden = options.menuItemHidden

  -- Setup menu with MenuUtil (always needs to be called, even for recycled dropdowns)
  sel:SetupMenu(function(dropdown, rootDescription)
    GUI:ClearEditFocus()
    local values = dropdown:GetValues()
    if not values then
      return
    end
    for _, item in ipairs(values) do
      if not (dropdown.menuItemHidden and dropdown.menuItemHidden(item)) then
        local isSelected = function(i) return dropdown.value == i.value end
        local setSelected = function(i)
          local oldValue = dropdown.value
          dropdown.value = i.value
          dropdown.selectedValue = i.value
          if dropdown.Text then
            dropdown.Text:SetText(i.name)
          end
          if dropdown.setter then
            dropdown.setter(dropdown, i.value, oldValue)
          end
        end
        local button = rootDescription:CreateRadio(item.name, isSelected, setSelected, item)
        if dropdown.menuItemEnabled then
          button.IsEnabled = function(btn)
            return dropdown.menuItemEnabled(btn.data.value)
          end
        end
      end
    end
  end)

  sel:SetValue(options.default)
  if options.width then
    sel:SetWidth(options.width)
  end
  return sel
end

GUI.checkButtonPool = MakeRecyclablePool("CheckButton", UIParent, "UICheckButtonTemplate", PoolResetFrame)
---Creates a checkbox with recycling support
---@param parent Frame Parent frame
---@param text string Label text
---@param default boolean Default checked state
---@param setter? function Callback when toggled (checked)
---@param opts? table Options: tooltip
---@return CheckButton btn The created checkbox
function GUI:CreateCheckButton (parent, text, default, setter, opts)
  opts = opts or {}
  local btn, isNew = self.checkButtonPool:Acquire()
  if isNew then
    Mixin(btn, WidgetLockMixin)
  end
  btn:SetParent(parent)
  btn:Show()
  btn.Text:SetText(text)
  btn:SetChecked (default)
  if setter then
    btn:SetScript ("OnClick", function (self)
      setter(self:GetChecked ())
    end)
  end
  btn:SetScript("OnEnable", function(self)
    self.Text:SetTextColor(unpack(self.Text.originalFontColor))
    self.Text.originalFontColor = nil
  end)
  btn:SetScript("OnDisable", function(self)
    self.Text.originalFontColor = {self.Text:GetTextColor()}
    self.Text:SetTextColor(addonTable.COLORS.grey:GetRGB())
  end)
  self:SetTooltip(btn, opts.tooltip)
  return btn
end

GUI.imgButtonPool = MakeRecyclablePool("Button", UIParent, nil, PoolResetFrame)
---Creates an image button with recycling support
---@param parent Frame Parent frame
---@param width number Width in pixels
---@param height number Height in pixels
---@param img string|number Normal texture path or file ID
---@param opts? table Options: hlt, disabledTexture, OnClick, tooltip, pus
---@return Button btn The created image button
function GUI:CreateImageButton (parent, width, height, img, opts)
  opts = opts or {}
  local btn, isNew = self.imgButtonPool:Acquire()
  if isNew then
    Mixin(btn, WidgetLockMixin)
  end
  btn:SetParent(parent)
  btn:Show()
  btn:SetNormalTexture(img)
  btn:SetPushedTexture(opts.pus or img)
  btn:SetHighlightTexture (opts.hlt or img)
  btn:SetSize(width, height)
  btn:SetScript ("OnClick", opts.OnClick)

  if opts.disabledTexture then
    btn:SetDisabledTexture(opts.disabledTexture)
  else
    btn:SetDisabledTexture(img)
    local disabledTexture = btn:GetDisabledTexture()
    if disabledTexture then
      disabledTexture:SetDesaturated(true)
    end
  end

  self:SetTooltip(btn, opts.tooltip)
  return btn
end

GUI.panelButtonPool = MakeRecyclablePool("Button", UIParent, "UIPanelButtonTemplate",
  function(_, btn)
    btn:SetText("")
    btn:Hide()
    btn:ClearAllPoints()
    btn:SetScript("OnClick", nil)
    btn:SetScript("PreClick", nil)
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    for event in pairs(callbacks.Event) do
      callbacks:UnregisterCallback(event, btn)
    end
    btn:SetParent(UIParent)
  end
)
---Creates a standard panel button with recycling support
---@param parent Frame Parent frame
---@param text string Button text
---@param handler? function OnClick callback
---@param opts? table Options: tooltip
---@return Button btn The created panel button
function GUI:CreatePanelButton(parent, text, handler, opts)
  opts = opts or {}
  local btn, isNew = self.panelButtonPool:Acquire()
  if isNew then
    Mixin(btn, WidgetLockMixin)
    btn.RenderText = function(f, ...)
      f:SetText(...)
      f:FitToText()
    end
  end
  btn:SetParent(parent)
  btn:Show()
  btn:Enable()
  btn.preventLock = opts.preventLock
  for event in pairs(callbacks.Event) do
    if opts[event] then
      callbacks:RegisterCallback(event, function(_, frame) opts[event](frame) end, btn, btn)
    end
  end
  btn:RenderText(text)
  btn:SetScript("OnClick", handler)
  btn:SetScript("PreClick", opts.PreClick)
  self:SetTooltip(btn, opts.tooltip)
  return btn
end

GUI.colorPickerPool = MakeRecyclablePool("Frame", UIParent, nil,
  function(_, box)
    box:Hide()
    box:ClearAllPoints()
    box:SetScript("OnMouseDown", nil)
    if box.glow then box.glow:Hide() end
    box:SetParent(UIParent)
  end
)

---Creates a color picker button
---@param parent Frame Parent frame
---@param width number Width in pixels
---@param height number Height in pixels
---@param color table RGB color array {r, g, b}
---@param handler? function Callback when color changes
---@return Frame box The color picker frame
function GUI:CreateColorPicker(parent, width, height, color, handler)
  local box, isNew = self.colorPickerPool:Acquire()
  if isNew then
    box:EnableMouse(true)
    box.texture = box:CreateTexture(nil, "OVERLAY")
    box.texture:SetAllPoints()
    box.glow = box:CreateTexture(nil, "BACKGROUND")
    box.glow:SetPoint("TOPLEFT", -2, 2)
    box.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    box.glow:SetColorTexture(addonTable.COLORS.grey:GetRGB())
    box.glow:Hide()
    box:SetScript("OnEnter", function(b) b.glow:Show() end)
    box:SetScript("OnLeave", function(b) b.glow:Hide() end)
    Mixin(box, WidgetLockMixin)
    box.lockTexture = box.texture
  end
  box:SetParent(parent)
  box:Show()
  box:SetSize(width, height)
  box.texture:SetColorTexture(unpack(color))
  box:SetScript("OnMouseDown", function(b)
    local function applyColor(func)
      return function()
        local prevR, prevG, prevB = func(ColorPickerFrame)
        color[1], color[2], color[3] = prevR, prevG, prevB
        b.texture:SetColorTexture(prevR, prevG, prevB)
        if handler then
          handler()
        end
      end
    end
    ColorPickerFrame:SetupColorPickerAndShow({
      r = color[1], g = color[2], b = color[3],
      swatchFunc = applyColor(ColorPickerFrame.GetColorRGB),
      cancelFunc = applyColor(ColorPickerFrame.GetPreviousValues),
    })
    ColorPickerFrame.prevPoint = {
      point = SafePack(ColorPickerFrame:GetPoint()),
      strata = ColorPickerFrame:GetFrameStrata()
    }
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    ColorPickerFrame:ClearAllPoints()
    ColorPickerFrame:SetPoint("CENTER", addonTable.ReforgeLite, "CENTER")
    if not GUI:IsHooked(ColorPickerFrame, "OnHide") then
      GUI:HookScript(ColorPickerFrame, "OnHide", function(f)
        if f.prevPoint then
          f:SetFrameStrata(f.prevPoint.strata)
          f:ClearAllPoints()
          f:SetPoint(SafeUnpack(f.prevPoint.point))
          f.prevPoint = nil
        end
        GUI:Unhook(f, "OnHide")
      end)
    end
  end)
  return box
end

GUI.helpButtons = {}
---Creates a help button (question mark icon)
---@param parent Frame Parent frame
---@param tooltip string Help tooltip text
---@param opts? table Options: scale (default 0.6), tooltipWidth (default 320)
---@return Button btn The help button
function GUI:CreateHelpButton(parent, tooltip, opts)
  opts = opts or {}
  local btn = CreateFrame("Button", nil, parent, "MainHelpPlateButton")
  btn:SetFrameLevel(btn:GetParent():GetFrameLevel() + 1)
  btn:SetScale(opts.scale or 0.6)
  local width = opts.tooltipWidth or 320
  btn.ShowTooltip = function(b)
    HelpPlateTooltip.LingerAndFade:Stop()
    HelpPlateTooltip:SetWidth(width)
    HelpPlateTooltip.Text:SetWidth(width - 30)
    HelpPlateTooltip:Init(b, tooltip, "DOWN")
  end
  btn:HookScript("OnLeave", function() HelpPlateTooltip:Hide() end)
  btn:HookScript("OnHide",  function() HelpPlateTooltip:Hide() end)
  tinsert(self.helpButtons, btn)
  return btn
end

---Shows or hides all help buttons
---@param shown boolean True to show, false to hide
---@return nil
function GUI:SetHelpButtonsShown(shown)
  for _, btn in ipairs(self.helpButtons) do
    btn:SetShown(btn:IsEnabled() and shown)
  end
end

GUI.sliderPool = MakeRecyclablePool("Slider", UIParent, "UISliderTemplateWithLabels",
  function(_, slider)
    slider.Text:SetText("")
    slider:Hide()
    slider:ClearAllPoints()
    slider:SetScript("OnValueChanged", nil)
    slider:SetScript("OnEnable", nil)
    slider:SetScript("OnDisable", nil)
    slider:SetParent(UIParent)
  end
)
---Creates a slider with recycling support
---@param parent Frame Parent frame
---@param text string Label text
---@param value number Default value
---@param max number Maximum value
---@param onChange function Callback when value changes (value)
---@return Slider slider The created slider
function GUI:CreateSlider(parent, text, value, max, onChange, width, height)
  local slider, isNew = self.sliderPool:Acquire()
  if isNew then
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(false)
    slider:SetValueStep(1)
    Mixin(slider, WidgetLockMixin)
  end
  slider:SetSize(width or 150, height or 15)
  slider:SetParent(parent)
  slider:Show()
  slider:Enable()
  slider:SetMinMaxValues(1, max)
  slider:SetValue(value)
  slider:SetScript("OnValueChanged", onChange)
  slider.Text:SetText(text)
  slider:SetScript("OnEnable", function(self)
    for _, v in ipairs({self.Text, self.Low, self.High}) do
      v:SetTextColor(unpack(v.originalFontColor))
      v.originalFontColor = nil
    end
  end)
  slider:SetScript("OnDisable", function(self)
    for _, v in ipairs({self.Text, self.Low, self.High}) do
      v.originalFontColor = {v:GetTextColor()}
      v:SetTextColor(addonTable.COLORS.grey:GetRGB())
    end
  end)

  return slider
end

GUI.itemIconPool = MakeRecyclablePool("Button", UIParent, "ItemButtonTemplate",
  function(_, frame)
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    frame.icon:SetTexture(nil)
    frame.IconBorder:Hide()
    frame.searchOverlay:Hide()
    if frame.lockOverlay then frame.lockOverlay:Hide() end
    frame.itemInfo = {}
  end
)

---Creates an item icon button for the item table
---@param parent Frame Parent frame
---@param slot string Inventory slot name (e.g. "HeadSlot")
---@param options? table Options: size (number), onMouseDown (function), onRightClick (function), onDragStart (function)
---@return Button frame The item icon button
function GUI:CreateItemIcon(parent, slot, options)
  options = options or {}
  local frame, isNew = self.itemIconPool:Acquire()

  if isNew then
    Mixin(frame, WidgetLockMixin)

    frame:GetNormalTexture():SetTexture(nil)
    frame.IconBorder:SetAllPoints(frame)
    frame.lockTexture = frame.icon

    frame.lockOverlay = frame:CreateTexture(nil, "OVERLAY")
    frame.lockOverlay:SetAllPoints(frame)
    frame.lockOverlay:SetTexture(255353)

    frame.itemInfo = {}
    frame.stats = {}
    frame:SetScript("OnLeave", GameTooltip_Hide)
    frame:SetScript("OnEnter", function(f)
      GameTooltip:SetOwner(f, "ANCHOR_LEFT")
      local hasItem = GameTooltip:SetInventoryItem("player", f.slotId)
      if not hasItem then
        GameTooltip:SetText(_G[strupper(f.slot)])
      end
      GameTooltip:Show()
    end)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnMouseDown", function(f, button)
      if button == "LeftButton" and f.onMouseDown then
        f.onMouseDown(f)
      elseif button == "RightButton" and f.onRightClick then
        f.onRightClick(f)
      end
    end)
  end

  frame.onMouseDown = options.onMouseDown
  frame.onRightClick = options.onRightClick
  frame:SetScript("OnDragStart", options.onDragStart)
  frame.slot = slot
  frame.slotId, frame.slotTexture = GetInventorySlotInfo(slot)
  frame.icon:SetTexture(frame.slotTexture)
  frame.lockOverlay:Hide()
  local size = options.size or 24
  frame:SetSize(size, size)
  frame:SetParent(parent)
  frame:Show()
  return frame
end

-------------------------------------------------------------------------------

---Creates a horizontal line
---@param x1 number Start X coordinate
---@param x2 number End X coordinate
---@param y number Y coordinate
---@param w number Line width/thickness
---@param color table RGB color array
---@param parent? Frame Parent frame (defaults to defaultParent)
---@return Texture line The line texture
function GUI:CreateHLine (x1, x2, y, w, color, parent)
  parent = parent or self.defaultParent
  local line = parent:CreateTexture (nil, "ARTWORK")
  line:SetDrawLayer ("ARTWORK")
  line:SetColorTexture (unpack(color))
  if x1 > x2 then
    x1, x2 = x2, x1
  end
  line:ClearAllPoints ()
  line:SetTexCoord (0, 0, 0, 1, 1, 0, 1, 1)
  line.width = w
  line:SetPoint ("BOTTOMLEFT", parent, "TOPLEFT", x1, y - w / 2)
  line:SetPoint ("TOPRIGHT", parent, "TOPLEFT", x2, y + w / 2)
  line:Show ()
  line.SetPos = function (self, x1, x2, y)
    if x1 > x2 then
      x1, x2 = x2, x1
    end
    self:ClearAllPoints ()
    self:SetPoint ("BOTTOMLEFT", parent, "TOPLEFT", x1, y - self.width / 2)
    self:SetPoint ("TOPRIGHT", parent, "TOPLEFT", x2, y + self.width / 2)
  end
  return line
end

---Creates a vertical line
---@param x number X coordinate
---@param y1 number Start Y coordinate
---@param y2 number End Y coordinate
---@param w number Line width/thickness
---@param color table RGB color array
---@param parent? Frame Parent frame (defaults to defaultParent)
---@return Texture line The line texture
function GUI:CreateVLine (x, y1, y2, w, color, parent)
  parent = parent or self.defaultParent
  local line = parent:CreateTexture (nil, "ARTWORK")
  line:SetDrawLayer ("ARTWORK")
  line:SetColorTexture (unpack(color))
  if y1 > y2 then
    y1, y2 = y2, y1
  end
  line:ClearAllPoints ()
  line:SetTexCoord (1, 0, 0, 0, 1, 1, 0, 1)
  line.width = w
  line:SetPoint ("BOTTOMLEFT", parent, "TOPLEFT", x - w / 2, y1)
  line:SetPoint ("TOPRIGHT", parent, "TOPLEFT", x + w / 2, y2)
  line:Show ()
  line.SetPos = function (self, x, y1, y2)
    if y1 > y2 then
      y1, y2 = y2, y1
    end
    self:ClearAllPoints ()
    self:SetPoint ("BOTTOMLEFT", parent, "TOPLEFT", x - self.width / 2, y1)
    self:SetPoint ("TOPRIGHT", parent, "TOPLEFT", x + self.width / 2, y2)
  end
  return line
end

--------------------------------------------------------------------------------

---Creates a table widget with dynamic row/column management
---@param rows number Initial number of rows
---@param cols number Number of columns
---@param firstRow? number First row height (defaults to 0)
---@param firstColumn? number First column width (defaults to 0)
---@param gridColor? table RGB color for grid lines
---@param parent? Frame Parent frame (defaults to defaultParent)
---@return table table The table object with methods: SetCell, SetCellText, AddRow, DeleteRow, SetRowHeight, SetColumnWidth, etc.
function GUI:CreateTable (rows, cols, firstRow, firstColumn, gridColor, parent)
  parent = parent or self.defaultParent
  firstRow = firstRow or 0
  firstColumn = firstColumn or 0

  local t = CreateFrame ("Frame", nil, parent)
  t:ClearAllPoints ()
  t:SetSize(400, 400)
  t:SetPoint ("TOPLEFT")

  t.rows = rows
  t.cols = cols
  t.gridColor = gridColor
  t.rowPos = {}
  t.colPos = {}
  t.rowHeight = {}
  t.colWidth = {}
  t.autoWidthColumns = {}
  t.rowPos[-1] = 0
  t.rowPos[0] = firstRow
  t.colPos[-1] = 0
  t.colPos[0] = firstColumn
  t.rowHeight[0] = firstRow
  t.colWidth[0] = firstColumn

  t.SetRowHeight = function (self, n, h)
    if h then
      if n < 0 or n > self.rows then
        return
      end
      self.rowHeight[n] = h
      if n == 0 and self.hlines then
        self.hlines[-1]:SetShown(h ~= 0)
      end
    else
      for i = 1, self.rows do
        self.rowHeight[i] = n
      end
    end
    self:OnUpdateFix ()
  end
  t.SetColumnWidth = function (self, n, w)
    if w then
      if n < 0 or n > self.cols then
        return
      end
      self.colWidth[n] = w
      if n == 0 and self.vlines then
        self.vlines[-1]:SetShown(w ~= 0)
      end
    else
      for i = 1, self.cols do
        self.colWidth[i] = n
      end
    end
    self:OnUpdateFix ()
  end
  t.SetColumnAutoWidth = function (self, n, enabled)
    if n < 0 or n > self.cols then
      return
    end
    if type(self.colWidth[n]) == "number" then
      self.autoWidthColumns[n] = self.colWidth[n]
    else
      self.autoWidthColumns[n] = enabled
    end
  end
  t.EnableColumnAutoWidth = function (self, ...)
    for _, v in ipairs({...}) do
      self:SetColumnAutoWidth(v, true)
    end
  end
  t.AddRow = function (self, i, n)
    i = i or (self.rows + 1)
    n = n or 1
    local height = ((i == self.rows + 1) and self.rowHeight[i - 1] or self.rowHeight[i])
    for r = self.rows, i, -1 do
      self.cells[r + n] = self.cells[r]
      self.rowHeight[r + n] = self.rowHeight[r]
    end
    for r = i, i + n - 1 do
      self.cells[r] = {}
      self.rowHeight[r] = height
      self.rows = self.rows + 1
      if self.gridColor then
        if self.hlines[self.rows] then
          self.hlines[self.rows]:Show ()
        else
          self.hlines[self.rows] = GUI:CreateHLine (0, 0, 0, 1.5, self.gridColor, self)
        end
      end
    end
    self:OnUpdateFix ()
  end
  t.MoveRow = function (self, i, to)
    local height = self.row[i] - self.rowPos[i - 1]
    local cells = self.cells[i]
    if to > i then
      for r = i + 1, to do
        self.cells[r - 1] = self.cells[r]
        self.rowHeight[r - 1] = self.rowHeight[r]
      end
    elseif to < i then
      for r = i - 1, to, -1 do
        self.cells[r + 1] = self.cells[r]
        self.rowHeight[r + 1] = self.rowHeight[r]
      end
    end
    self.cells[to] = cells
    self.rowHeight[to] = height
    self:OnUpdateFix ()
  end
  t.DeleteRow = function (self, i)
    for j = 0, self.cols do
      if self.cells[i][j] then
        if type (self.cells[i][j].Recycle) == "function" then
          self.cells[i][j]:Recycle ()
        else
          self.cells[i][j]:Hide ()
        end
      end
    end
    for r = i + 1, self.rows do
      self.cells[r - 1] = self.cells[r]
      self.rowHeight[r - 1] = self.rowHeight[r]
    end
    if self.hlines and self.hlines[self.rows] then
      self.hlines[self.rows]:Hide ()
    end
    self.rows = self.rows - 1
    self:OnUpdateFix ()
  end
  t.ClearCells = function (self)
    for i = 0, self.rows do
      for j = 0, self.cols do
        if self.cells[i][j] then
          if type (self.cells[i][j].Recycle) == "function" then
            self.cells[i][j]:Recycle ()
          else
            self.cells[i][j]:Hide ()
          end
        end
      end
      self.cells[i] = {}
    end
  end

  t.GetCellY = function (self, i)
    local n = ceil (i)
    if n < 0 then n = 0 end
    if n > self.rows then n = self.rows end
    return - (self.rowPos[n] + (self.rowPos[n - 1] - self.rowPos[n]) * (n - i))
  end
  t.GetCellX = function (self, j)
    local n = ceil (j)
    if n < 0 then n = 0 end
    if n > self.cols then n = self.cols end
    return self.colPos[n] + (self.colPos[n - 1] - self.colPos[n]) * (n - j)
  end
  t.GetRowHeight = function (self, i)
    return self.rowPos[i] - self.rowPos[i - 1]
  end
  t.GetColumnWidth = function (self, j)
    return self.colPos[j] - self.colPos[j - 1]
  end
  t.AlignCell = function (self, i, j)
    local cell = self.cells[i][j]
    local x = cell.offsX or 0
    local y = cell.offsY or 0
    local align = cell.align

    if align == "FILL" then
      cell:SetPoint("TOPLEFT", self, "TOPLEFT", self:GetCellX(j - 1) + x, self:GetCellY(i - 1) + y)
      cell:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", self:GetCellX(j) + x, self:GetCellY(i) + y)
      return
    end

    local M = 2
    local xPos, yPos

    if align:find("LEFT", 1, true) then
      xPos = self:GetCellX(j - 1) + M
    elseif align:find("RIGHT", 1, true) then
      xPos = self:GetCellX(j) - M
    else
      xPos = self:GetCellX(j - 0.5)
    end

    if align:find("TOP", 1, true) then
      yPos = self:GetCellY(i - 1) - M
    elseif align:find("BOTTOM", 1, true) then
      yPos = self:GetCellY(i) + M
    else
      yPos = self:GetCellY(i - 0.5)
    end

    cell:SetPoint(align, self, "TOPLEFT", xPos + x, yPos + y)
  end
  t.OnUpdateFix = function (self)
    self:SetScript ("OnSizeChanged", nil)

    local numAutoRows = 0
    local totalHeight = 0
    for i = 0, self.rows do
      if self.rowHeight[i] == "AUTO" then
        numAutoRows = numAutoRows + 1
      else
        totalHeight = totalHeight + self.rowHeight[i]
      end
    end
    if numAutoRows == 0 then
      self:SetHeight (totalHeight)
    end
    local remHeight = self:GetHeight () - totalHeight
    for i = 0, self.rows do
      if self.rowHeight[i] == "AUTO" then
        self.rowPos[i] = self.rowPos[i - 1] + remHeight / numAutoRows
      else
        self.rowPos[i] = self.rowPos[i - 1] + self.rowHeight[i]
      end
    end
    local numAutoCols = 0
    local totalWidth = 0
    for i = 0, self.cols do
      if self.colWidth[i] == "AUTO" then
        numAutoCols = numAutoCols + 1
      else
        totalWidth = totalWidth + self.colWidth[i]
      end
    end
    if numAutoCols == 0 then
      self:SetWidth (totalWidth)
    end
    local remWidth = self:GetWidth () - totalWidth
    for i = 0, self.cols do
      if self.colWidth[i] == "AUTO" then
        self.colPos[i] = self.colPos[i - 1] + remWidth / numAutoCols
      else
        self.colPos[i] = self.colPos[i - 1] + self.colWidth[i]
      end
    end

    if self.gridColor then
      for i = -1, self.rows do
        self.hlines[i]:SetPos (0, self.colPos[self.cols], -self.rowPos[i])
      end
      for i = -1, self.cols do
        self.vlines[i]:SetPos (self.colPos[i], 0, -self.rowPos[self.rows])
      end
    end
    for i = -1, self.rows do
      for j = -1, self.cols do
        if self.cells[i][j] then
          self:AlignCell (i, j)
        end
      end
    end

    self:SetScript ("OnSizeChanged", function (self)
      RunNextFrame(function() self:OnUpdateFix() end)
    end)

    if self.OnUpdate then
      self:OnUpdate ()
    end
  end

  if gridColor then
    t.hlines = {}
    t.vlines = {}
    for i = -1, rows do
      t.hlines[i] = self:CreateHLine (0, 0, 0, 1.5, gridColor, t)
    end
    for i = -1, cols do
      t.vlines[i] = self:CreateVLine (0, 0, 0, 1.5, gridColor, t)
    end
    if firstRow == 0 then
      t.hlines[-1]:Hide ()
    end
    if firstColumn == 0 then
      t.vlines[-1]:Hide ()
    end
  end
  t.cells = {}
  for i = -1, rows do
    t.cells[i] = {}
  end

  for i = 1, t.rows do
    t.rowHeight[i] = "AUTO"
  end
  for j = 1, t.cols do
    t.colWidth[j] = "AUTO"
  end
  t:OnUpdateFix ()

  t:SetScript ("OnSizeChanged", function (self)
    RunNextFrame(function() self:OnUpdateFix() end)
  end)

  t.AutoSizeColumns = function(self, columnIndex)
    -- Auto-adjust column width if enabled for this column
    local columnsToProcess = {}
    if columnIndex then
      if self.autoWidthColumns[columnIndex] then
        columnsToProcess[columnIndex] = self.autoWidthColumns[columnIndex]
      end
    else
      columnsToProcess = self.autoWidthColumns
    end

    local maxWidths = {}
    for _, row in pairs(self.cells) do
      for colIndex, width in pairs(columnsToProcess) do
        local cell = row[colIndex]
        if cell then
          local foundWidth = 0
          if cell.GetStringWidth then
            foundWidth = cell:GetStringWidth()
          elseif cell.GetWidth then
            foundWidth = cell:GetWidth()
          end
          if type(width) == "number" then
            foundWidth = max(foundWidth, width)
          end
          local currentMax = maxWidths[colIndex] or 0
          if foundWidth > currentMax then
            maxWidths[colIndex] = ceil(foundWidth) + 4
          end
        end
      end
    end

    for colIndex, width in pairs(maxWidths) do
      self.colWidth[colIndex] = width
    end
    self:OnUpdateFix()
  end

  t.SetCell = function (self, i, j, value, align, offsX, offsY)
    align = align or "CENTER"
    self.cells[i][j] = value
    self.cells[i][j].align = align
    self.cells[i][j].offsX = offsX
    self.cells[i][j].offsY = offsY
    self:AlignCell (i, j)
    self:AutoSizeColumns(j)
  end
  t.textTagPool = {}
  t.SetCellText = function(self, i, j, text, align, color, font)
    align = align or "CENTER"
    color = color or addonTable.COLORS.white
    font = font or "GameFontNormalSmall"

    local cell = self.cells[i][j]
    if cell and not cell.istag then
      if type(cell.Recycle) == "function" then cell:Recycle() else cell:Hide() end
      cell = nil
    end

    if not cell then
      if #self.textTagPool > 0 then
        cell = tremove(self.textTagPool)
      else
        cell = self:CreateFontString(nil, "OVERLAY", font)
        cell.Recycle = function(tag)
          tag:Hide()
          tinsert(self.textTagPool, tag)
        end
      end
      self.cells[i][j] = cell
    end

    cell.istag = true
    cell:SetFontObject(font)
    cell:Show()
    cell:SetTextColor(color:GetRGB())
    cell:SetText(text)
    cell.align = align
    self:AlignCell(i, j)
    self:AutoSizeColumns(j)
  end
  t.CollapseRow = function(self, i)
    if not self.collapsedRows then
      self.collapsedRows = {}
    end
    if self.collapsedRows[i] then
      return
    end
    self.collapsedRows[i] = self.rowHeight[i]
    self.rowHeight[i] = 0
    for j = 0, self.cols do
      self.cells[i][j]:SetAlpha(0)
    end
    self:OnUpdateFix()
  end
  t.ExpandRow = function(self, i)
    if self.collapsedRows and self.collapsedRows[i] then
      self.rowHeight[i] = self.collapsedRows[i]
      self.collapsedRows[i] = nil
      for j = 0, self.cols do
        self.cells[i][j]:SetAlpha(1)
      end
      self:OnUpdateFix()
    end
  end
  t.SetRowExpanded = function(self, i, expanded)
    if expanded then
      self:ExpandRow(i)
    else
      self:CollapseRow(i)
    end
  end
  t.CollapseColumn = function(self, j)
    if not self.collapsedColumns then
      self.collapsedColumns = {}
    end
    if self.collapsedColumns[j] then
      return
    end
    self.collapsedColumns[j] = self.colWidth[j]
    self.colWidth[j] = 0
    for i = 0, self.rows do
      self.cells[i][j]:SetAlpha(0)
    end
    self:OnUpdateFix()
  end
  t.ExpandColumn = function(self, j)
    if self.collapsedColumns and self.collapsedColumns[j] then
      self.colWidth[j] = self.collapsedColumns[j]
      self.collapsedColumns[j] = nil
      for i = 0, self.rows do
        self.cells[i][j]:SetAlpha(1)
      end
      self:OnUpdateFix()
    end
  end

  return t
end

---Creates a static popup dialog
---@param name string Unique popup name
---@param text string Popup message text
---@param OnAccept function Callback when accepted (receives edit box text if hasEditBox)
---@param opts? table Options: button1 (text), hasEditBox (boolean)
---@return nil
function GUI.CreateStaticPopup(name, text, OnAccept, opts)
  name = addonName:upper() .. '_' .. name
  opts = opts or {}
  StaticPopupDialogs[name] = {
    text = text,
    button1 = opts.button1 or ACCEPT,
    button2 = CANCEL,
    hasEditBox = opts.hasEditBox,
    timeout = 0,
    whileDead = 1,
    OnAccept = OnAccept,
    OnShow = function(self)
      if self:GetEditBox():IsVisible() then
        self:GetButton1():Disable()
        self:GetEditBox():SetFocus()
      end
      self:GetButton2():Enable()
    end,
    EditBoxOnEnterPressed = function(self)
      local parent = self:GetParent()
      if parent:GetButton1():IsEnabled() then
        OnAccept(parent)
        parent:Hide()
      end
    end,
    EditBoxOnTextChanged = function(self)
      self:GetParent():GetButton1():SetEnabled(self:GetText() ~= "")
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  }
    StaticPopup_Show(name)
end

callbacks:RegisterCallback("PreCalculateStart", function(_, self) self:Lock() end, "GUI", GUI)
callbacks:RegisterCallback("OnCalculateFinish", function(_, self) self:Unlock() end, "GUI", GUI)
