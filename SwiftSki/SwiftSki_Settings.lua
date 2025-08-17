-- SwiftSki_Settings.lua — Settings tab (white theme)

local SS = _G.SwiftSki
if not SS then return end

-- Settings defaults
local function SOpt()
  _G.SwiftSkiDB = _G.SwiftSkiDB or { options = {} }
  local o = SwiftSkiDB.options
  if o.disableMinimap == nil then o.disableMinimap = false end
  return o
end

-- Colors
local HEX_WHITE = "FFFFFF"
local HEX_RED   = "FF5555"
local GRAY_RGB  = {0.8, 0.8, 0.8}
local function color(hex, text) return "|cff"..hex..(text or "").."|r" end

-- Label color (white when enabled, red when disabled)
local function SetLabelColor(cb)
  if not cb then return end
  local fs = _G[cb:GetName().."Text"]; if not fs then return end
  local disabled = cb:GetChecked() and true or false
  fs:SetText(color(disabled and HEX_RED or HEX_WHITE, cb._rawLabel or ""))
end

-- Tooltip title follows state; description is gray
local function ShowStateTooltip(cb)
  if not cb then return end
  local title = cb._rawLabel or ""
  local desc  = cb._rawTip   or ""
  local disabled = cb:GetChecked() and true or false

  if not GameTooltip:IsOwned(cb) then
    GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
  else
    GameTooltip:ClearLines()
  end

  GameTooltip:AddLine(color(disabled and HEX_RED or HEX_WHITE, title))
  if desc ~= "" then GameTooltip:AddLine(desc, GRAY_RGB[1], GRAY_RGB[2], GRAY_RGB[3], true) end
  GameTooltip:Show()
end

-- Live tooltip/title & label recolor while hovered
local function WireLiveTooltip(cb)
  cb:EnableMouse(true)
  cb:HookScript("OnEnter", function(self)
    self.__last = self:GetChecked()
    ShowStateTooltip(self)
    self:SetScript("OnUpdate", function(s)
      if not s:IsMouseOver() then return end
      local now = s:GetChecked()
      if now ~= s.__last then
        s.__last = now
        SetLabelColor(s)
        ShowStateTooltip(s)
      end
    end)
  end)
  cb:HookScript("OnLeave", function(self)
    self:SetScript("OnUpdate", nil)
    GameTooltip:Hide()
  end)
  cb:HookScript("OnClick", function(self)
    SetLabelColor(self)
    if GameTooltip:IsOwned(self) then ShowStateTooltip(self) end
  end)
end

function SS:BuildSettingsPanel(container)
  local o = SOpt()

  -- Content box (same spacing as other tabs)
  local box = self:AddSeparator(container, 8, -18, -8)

  -- Title (white)
  local title = container:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  title:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -14)
  title:SetText("|cffffffffSettings|r")

  local y = -48

  -- Disable Minimap Button
  local cb = CreateFrame("CheckButton", "SwiftSki_DisableMinimap", container, "InterfaceOptionsCheckButtonTemplate")
  cb:SetPoint("TOPLEFT", box, "TOPLEFT", 14, y)
  cb._rawLabel = "Disable Minimap Button"
  cb._rawTip   = "Hides the SwiftSki minimap button. Re-enable via this checkbox or use /ss to open the UI."
  -- We own the tooltip so don't call AttachTip here
  local fs = _G["SwiftSki_DisableMinimapText"]; if fs then fs:SetText(cb._rawLabel) end

  cb:SetChecked(o.disableMinimap and true or false)
  SetLabelColor(cb)
  WireLiveTooltip(cb)

  -- Toggle logic
  SS:WireCheckSound(cb, function(btn)
    local disabled = btn:GetChecked() and true or false
    SwiftSkiDB.options.disableMinimap = disabled
    if SS.ApplyMinimapVisibility then SS:ApplyMinimapVisibility() end
    SetLabelColor(btn)
    if GameTooltip:IsOwned(btn) then ShowStateTooltip(btn) end
  end, "Disable Minimap Button")
end
