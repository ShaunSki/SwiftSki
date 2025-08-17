-- SwiftSki_Core.lua — Core
-- Core responsibilities only:
--   • Global table + colors + chat helper
--   • Window + tabs (incl. creating About tab/container)
--   • Minimap button, slash commands, load flow
--   • NO About content here (moved to SwiftSki_About.lua)

local ADDON_NAME = "SwiftSki"
local SS = _G.SwiftSki or {}
_G.SwiftSki = SS

------------------------------------------------------------
-- Colors + tiny helpers
------------------------------------------------------------
SS.COL_LIME = SS.COL_LIME or "32CD32"
SS.COL_TEAL = SS.COL_TEAL or "66D9FF"
SS.COL_RED  = SS.COL_RED  or "FF5555"

function SS:lime(t) return "|cff"..self.COL_LIME..(t or "").."|r" end
function SS:teal(t) return "|cff"..self.COL_TEAL..(t or "").."|r" end
function SS:red(t)  return "|cff"..self.COL_RED ..(t or "").."|r" end

------------------------------------------------------------
-- Safe chat output
------------------------------------------------------------
function SS:Chat(msg, r, g, b)
  local f = DEFAULT_CHAT_FRAME
  if not f then return end
  local ok = pcall(f.AddMessage, f, tostring(msg or ""), r, g, b)
  if not ok and UIErrorsFrame then
    UIErrorsFrame:AddMessage(tostring(msg or ""), 0.1, 1, 0.1, 1)
  end
end

function SS:Print(msg) self:Chat("|cff"..self.COL_LIME.."[SwiftSki]|r "..(msg or "")) end

------------------------------------------------------------
-- SavedVariables bootstrap
------------------------------------------------------------
local function EnsureDB()
  _G.SwiftSkiDB = _G.SwiftSkiDB or { options = {} }
  SwiftSkiDB.mmPos = SwiftSkiDB.mmPos or { x = nil, y = nil }
end

------------------------------------------------------------
-- Sounds
------------------------------------------------------------
local function TryPlay(s) if s and PlaySound then pcall(PlaySound, s) end end
function SS:PlayOpen()        TryPlay("igCharacterInfoOpen") end
function SS:PlayClose()       TryPlay("igMainMenuClose")     end
function SS:PlayTab()         TryPlay("igCharacterInfoTab")  end
function SS:PlayCheckbox(on)  TryPlay(on and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff") end

------------------------------------------------------------
-- UI helpers
------------------------------------------------------------
function SS:AnnounceToggle(label, on)
  local state = on and ("|cff"..self.COL_LIME.."ON|r") or ("|cff"..self.COL_RED.."OFF|r")
  self:Print(self:teal(label..": ")..state)
end

function SS:WireCheckSound(check, handler, label)
  if not check then return end
  check:SetScript("OnClick", function(selfBtn)
    local checked = selfBtn:GetChecked() and true or false
    if handler then handler(selfBtn) end
    SS:PlayCheckbox(checked)
    if label then SS:AnnounceToggle(label, checked) end
  end)
end

function SS:AttachTip(frame, title, text)
  if not frame then return end
  frame:EnableMouse(true)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if title then GameTooltip:AddLine(title,1,1,1) end
    if text  then GameTooltip:AddLine(text,.8,.8,.8,true) end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function SS:AddSeparator(parent, lp, to, rp)
  local box = CreateFrame("Frame", nil, parent)
  box:SetPoint("TOPLEFT",  lp or 8,   to or -18)
  box:SetPoint("BOTTOMRIGHT", rp or -8, 10)
  box:SetBackdrop({
    bgFile  = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile= "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left=8, right=8, top=8, bottom=8 }
  })
  box:SetBackdropColor(0,0,0,0.2)
  box:SetBackdropBorderColor(.8,.8,.8,.8)
  return box
end

------------------------------------------------------------
-- Main window + tabs
------------------------------------------------------------
SS.tabs = {}
SS.MainContainer, SS.QuestingContainer, SS.VendorContainer, SS.ItemLockContainer, SS.AscensionContainer = nil,nil,nil,nil,nil
SS.SettingsContainer, SS.AboutContainer = nil, nil

local function CreateTab(frame, id, text, xOff)
  local name = frame:GetName().."Tab"..id
  local tab  = CreateFrame("Button", name, frame, "OptionsFrameTabButtonTemplate")
  tab:SetID(id)
  tab:SetText(text)
  PanelTemplates_TabResize(tab, 0)
  if id == 1 then
    tab:SetPoint("TOPLEFT", frame, "TOPLEFT", xOff or 18, -28)
  else
    tab:SetPoint("LEFT", SS.tabs[id-1], "RIGHT", -8, 0)
  end
  tab:SetScript("OnClick", function(self)
    SS:PlayTab()
    PanelTemplates_SetTab(frame, self:GetID())
    SS:ShowTab(self:GetID())
  end)
  return tab
end

function SS:ShowTab(id)
  if self.MainContainer      then self.MainContainer:Hide()      end
  if self.QuestingContainer  then self.QuestingContainer:Hide()  end
  if self.VendorContainer    then self.VendorContainer:Hide()    end
  if self.ItemLockContainer  then self.ItemLockContainer:Hide()  end
  if self.AscensionContainer then self.AscensionContainer:Hide() end
  if self.SettingsContainer  then self.SettingsContainer:Hide()  end
  if self.AboutContainer     then self.AboutContainer:Hide()     end

  if     id==1 and self.MainContainer      then self.MainContainer:Show()
  elseif id==2 and self.QuestingContainer  then self.QuestingContainer:Show()
  elseif id==3 and self.VendorContainer    then self.VendorContainer:Show()
  elseif id==4 and self.ItemLockContainer  then self.ItemLockContainer:Show()
  elseif id==5 and self.AscensionContainer then self.AscensionContainer:Show()
  elseif id==6 and self.SettingsContainer  then self.SettingsContainer:Show()
  elseif id==7 and self.AboutContainer     then
    self.AboutContainer:Show()
    if self.BuildAboutPanel then self:BuildAboutPanel(self.AboutContainer) end -- content lives in SwiftSki_About.lua
  end
end

function SS:CreateUI()
  if self.frame then return end

  local f = CreateFrame("Frame", "SwiftSki_MainFrame", UIParent)
  f:SetSize(720, 440)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
  f:SetBackdrop({
    bgFile  = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile= "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left=8, right=8, top=8, bottom=8 }
  })
  UISpecialFrames = UISpecialFrames or {}
  table.insert(UISpecialFrames, f:GetName())

  -- Centered header (two lines: name + byline)
  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  title:SetJustifyH("CENTER")
  do
    local face, _ = GameFontNormalLarge:GetFont()
    title:SetFont(face, 18, "")
    title:SetText("|cff32CD32SwiftSki|r")
    title:SetShadowColor(0,0,0,1)
    title:SetShadowOffset(1,-1)
  end

  local titleSub = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  titleSub:SetPoint("TOP", title, "BOTTOM", 0, -2)
  titleSub:SetJustifyH("CENTER")
  do
    local face, size = GameFontHighlight:GetFont()
    titleSub:SetFont(face, 13, "")
  end
  titleSub:SetText("|cff32CD32by ShaunSki • DevSki|r")
  titleSub:SetShadowColor(0,0,0,1)
  titleSub:SetShadowOffset(1,-1)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)
  SS:AttachTip(close, "Close", "Click to close. (ESC)")

  -- Content containers
  local c1 = CreateFrame("Frame", "SwiftSki_MainFrameContent1", f); c1:SetPoint("TOPLEFT",12,-48); c1:SetPoint("BOTTOMRIGHT",-12,12)
  local c2 = CreateFrame("Frame", "SwiftSki_MainFrameContent2", f); c2:SetPoint("TOPLEFT",12,-48); c2:SetPoint("BOTTOMRIGHT",-12,12)
  local c3 = CreateFrame("Frame", "SwiftSki_MainFrameContent3", f); c3:SetPoint("TOPLEFT",12,-48); c3:SetPoint("BOTTOMRIGHT",-12,12)
  local c4 = CreateFrame("Frame", "SwiftSki_MainFrameContent4", f); c4:SetPoint("TOPLEFT",12,-48); c4:SetPoint("BOTTOMRIGHT",-12,12)
  local c5 = CreateFrame("Frame", "SwiftSki_MainFrameContent5", f); c5:SetPoint("TOPLEFT",12,-48); c5:SetPoint("BOTTOMRIGHT",-12,12)
  local c6 = CreateFrame("Frame", "SwiftSki_MainFrameContent6", f); c6:SetPoint("TOPLEFT",12,-48); c6:SetPoint("BOTTOMRIGHT",-12,12)
  local c7 = CreateFrame("Frame", "SwiftSki_MainFrameContent7", f); c7:SetPoint("TOPLEFT",12,-48); c7:SetPoint("BOTTOMRIGHT",-12,12)

  SS.MainContainer, SS.QuestingContainer, SS.VendorContainer, SS.ItemLockContainer, SS.AscensionContainer, SS.SettingsContainer, SS.AboutContainer
    = c1, c2, c3, c4, c5, c6, c7

  -- Tabs
  SS.tabs[1] = CreateTab(f, 1, "|cff32CD32Main|r", 18)
  SS.tabs[2] = CreateTab(f, 2, "|cffffd100Questing|r")
  SS.tabs[3] = CreateTab(f, 3, "|cff1E90FFVendor|r")
  SS.tabs[4] = CreateTab(f, 4, "|cffDC143CItem Lock|r")
  SS.tabs[5] = CreateTab(f, 5, "|cffffa500Ascension|r")
  SS.tabs[6] = CreateTab(f, 6, "|cffffffffSettings|r")
  SS.tabs[7] = CreateTab(f, 7, "|cff9d9d9dAbout|r") -- Junk grey label

  PanelTemplates_SetNumTabs(f, 7)
  PanelTemplates_SetTab(f, 1)

  if type(SS.BuildMainPanel)      == "function" then SS:BuildMainPanel(c1)      end
  if type(SS.BuildQuestingPanel)  == "function" then SS:BuildQuestingPanel(c2)  end
  if type(SS.BuildVendorPanel)    == "function" then SS:BuildVendorPanel(c3)    end
  if type(SS.BuildItemLockPanel)  == "function" then SS:BuildItemLockPanel(c4)  end
  if type(SS.BuildAscensionPanel) == "function" then SS:BuildAscensionPanel(c5) end
  if type(SS.BuildSettingsPanel)  == "function" then SS:BuildSettingsPanel(c6)  end
  if type(SS.BuildAboutPanel)     == "function" then SS:BuildAboutPanel(c7)     end

  SS:ShowTab(1)
  self.frame = f
end

function SS:OpenUI()
  if not self.frame then self:CreateUI() end
  self.frame:Show()
  SS:PlayOpen()
end

------------------------------------------------------------
-- Minimap button (simple free drag)
------------------------------------------------------------
do
  local function GetMMPos()
    EnsureDB()
    local pos = SwiftSkiDB.mmPos or {}
    return pos.x, pos.y
  end
  local function SetMMPos(x, y)
    EnsureDB()
    SwiftSkiDB.mmPos = { x = x, y = y }
  end
  local function DefaultMMPos() return -66.1, -22.6 end
  local function PlaceAtSaved(btn)
    local x, y = GetMMPos()
    if x == nil or y == nil then x, y = DefaultMMPos(); SetMMPos(x, y) end
    btn:ClearAllPoints(); btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end
  local function ShowTooltip(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    GameTooltip:AddLine(SS:lime("SwiftSki"))
    GameTooltip:AddLine(SS:teal("Left-Click:").." Open", 1,1,1)
    GameTooltip:AddLine(SS:teal("Right-Click + drag:").." Move freely", 1,1,1)
    GameTooltip:Show()
  end

  function SS:Minimap_Update()
    if self and self.minimap and self.minimap.button then PlaceAtSaved(self.minimap.button) end
  end

  function SS:CreateMinimapButton()
    if self.minimap and self.minimap.button then return end
    EnsureDB()
    local b = CreateFrame("Button", "SwiftSki_MinimapButton", Minimap)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel()+8)
    b:SetSize(32, 32)

    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetPoint("CENTER")
    ring:SetSize(54, 54)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetPoint("CENTER", -10, 12)
    icon:SetSize(19, 19)

    b:RegisterForDrag("RightButton")
    b:SetScript("OnDragStart", function(self)
      self._drag = true
      self:SetScript("OnUpdate", function(me)
        local s = Minimap:GetEffectiveScale() or 1
        local px, py = GetCursorPosition(); px, py = px / s, py / s
        local cx, cy = Minimap:GetCenter()
        local x, y = px - cx, py - cy
        me:ClearAllPoints(); me:SetPoint("CENTER", Minimap, "CENTER", x, y)
        SetMMPos(x, y)
      end)
    end)
    b:SetScript("OnDragStop", function(self)
      if not self._drag then return end
      self._drag = nil
      self:SetScript("OnUpdate", nil)
      local s = Minimap:GetEffectiveScale() or 1
      local px, py = GetCursorPosition(); px, py = px / s, py / s
      local cx, cy = Minimap:GetCenter()
      SetMMPos(px - cx, py - cy)
    end)

    b:SetScript("OnMouseDown", function(_, btn)
      if btn == "LeftButton" then
        if not SS.frame or not SS.frame:IsShown() then SS:OpenUI() else SS.frame:Hide(); SS:PlayClose() end
      end
    end)
    b:SetScript("OnEnter", function(self) ShowTooltip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnShow", function(self) PlaceAtSaved(self) end)

    SS.minimap = { button = b }
    PlaceAtSaved(b)
  end

  function SS:IsMinimapDisabled()
    return _G.SwiftSkiDB and SwiftSkiDB.options and SwiftSkiDB.options.disableMinimap
  end

  function SS:ApplyMinimapVisibility()
    EnsureDB()
    local disabled = self:IsMinimapDisabled()
    if disabled then
      if self.minimap and self.minimap.button then self.minimap.button:Hide() end
    else
      self:CreateMinimapButton()
      if self.minimap and self.minimap.button then self.minimap.button:Show() end
    end
  end

  function CreateMinimapButton() if SS and SS.CreateMinimapButton then SS:CreateMinimapButton() end end
  function MinimapUpdate()       if SS and SS.Minimap_Update    then SS:Minimap_Update()    end end
end

------------------------------------------------------------
-- Slash + load flow
------------------------------------------------------------
local function FirstOpenDelay()
  local f, t = CreateFrame("Frame"), 0
  f:SetScript("OnUpdate", function(self, e)
    t = t + e
    if t > 0.2 then self:SetScript("OnUpdate", nil); self:Hide(); SS:OpenUI() end
  end)
end

local function ToggleWindow()
  if not SS.frame or not SS.frame:IsShown() then SS:OpenUI()
  else SS.frame:Hide(); SS:PlayClose() end
end

SLASH_SSOL1 = "/ss"
SLASH_SSOL2 = "/SwiftSki"
SlashCmdList["SSOL"] = function(msg)
  EnsureDB()
  msg = (msg and string.lower(msg):gsub("^%s*(.-)%s*$","%1")) or ""
  if msg == "help" or msg == "?" then
    SS:Print("Commands:")
    SS:Print("|cffffff00/ss|r or |cffffff00/SwiftSki|r — toggle window")
    SS:Print("|cffffff00/ss fresh|r — test first-run (/reload)")
    return
  elseif msg == "fresh" then
    SwiftSkiDB.firstRunShown = nil
    SS:Print("First-run flag cleared. /reload to auto-open.")
    return
  end
  ToggleWindow()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, e, a1)
  if e == "ADDON_LOADED" and a1 == ADDON_NAME then
    EnsureDB()
    ev:UnregisterEvent("ADDON_LOADED")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("MINIMAP_UPDATE_ZOOM")
  elseif e == "PLAYER_LOGIN" then
    if SS.ApplyMinimapVisibility then SS:ApplyMinimapVisibility() else CreateMinimapButton() end
    if SwiftSkiDB.firstRunShown == nil then
      SwiftSkiDB.firstRunShown = true
      FirstOpenDelay()
    end
    local f, t = CreateFrame("Frame"), 0
    f:SetScript("OnUpdate", function(self, elapsed)
      t = t + elapsed
      if t >= 1.2 then
        self:SetScript("OnUpdate", nil); self:Hide()
        SS:Chat("|cff32CD32[SwiftSki]|r Core Loaded Successfully. Type |cffffff00/ss|r to open the GUI.")
      end
    end)
  elseif e == "PLAYER_ENTERING_WORLD" or e == "MINIMAP_UPDATE_ZOOM" then
    MinimapUpdate()
  end
end)
