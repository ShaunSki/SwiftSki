--[[--------------------------------------------------------------------
  SwiftSki_ItemLock.lua
  Item Lock UI & bag hooks.
  - ALT+Left-Click to lock/unlock items (if enabled)
  - Search box + quality filters
  - “X” button in the list to unlock
  - Master checkbox: Enable Item Lock
  - Greys out/blocks everything when disabled
----------------------------------------------------------------------]]

local SS = _G.SwiftSki
if not SS then return end

-- Theme color (Crimson) for tab/tag printing
local IL_HEX = "DC143C"
local function Ic(t) return "|cff"..IL_HEX..(t or "").."|r" end

----------------------------------------------------------------------
-- Saved data + defaults
----------------------------------------------------------------------
local function LDB()
  _G.SwiftSkiDB = _G.SwiftSkiDB or { options = {} }
  local db = SwiftSkiDB
  db.locked = db.locked or {}                   -- [itemID] = true
  db.itemLockFilters = db.itemLockFilters or {} -- [quality] = bool
  if db.options.itemLockEnabled == nil then db.options.itemLockEnabled = true end
  for q = 0, 7 do if db.itemLockFilters[q] == nil then db.itemLockFilters[q] = true end end
  return db
end
local function LOPT() LDB(); return SwiftSkiDB.options end
function SS:ItemLock_IsEnabled() local o = LOPT(); return (o and o.itemLockEnabled) and true or false end

----------------------------------------------------------------------
-- Tag + print helpers
----------------------------------------------------------------------
local function LTag() return "["..SS:lime("SwiftSki").."-"..Ic("Item Lock").."] " end
local function LPrint(msg) SS:Chat(LTag()..msg) end

----------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------
local function After(delay, fn)
  local f, t = CreateFrame("Frame"), 0
  f:SetScript("OnUpdate", function(self, e)
    t = t + e
    if t >= delay then self:SetScript("OnUpdate", nil); self:Hide(); pcall(fn) end
  end)
end
local function ItemIDFromLink(link) return tonumber(string.match(link or "", "item:(%d+)") or 0) end
local function HexForQuality(q)
  local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]
  if c and c.hex then return c.hex end
  if c then return string.format("|cff%02x%02x%02x", (c.r or 1)*255, (c.g or 1)*255, (c.b or 1)*255) end
  return "|cffffffff"
end
local function RGBForQuality(q)
  local c = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q]
  if c then return c.r or 1, c.g or 1, c.b or 1 end
  return 1,1,1
end
local function ColoredItemNameBrackets(id)
  local name, _, quality = GetItemInfo(id)
  local hex = HexForQuality(quality or 1)
  name = name or ("item:"..id)
  return hex.."["..name.."]|r"
end
local function SafeItemLink(id)
  local name, link = GetItemInfo(id)
  if link then return link end
  local fallbackName = "item:"..id
  return "|Hitem:"..id..":0:0:0:0:0:0:0:0|h["..fallbackName.."]|h"
end

----------------------------------------------------------------------
-- Public API (used by Vendor)
----------------------------------------------------------------------
function SS:IsItemLockedID(itemID)
  if not itemID then return false end
  local db = LDB()
  return db.locked[itemID] and true or false
end

----------------------------------------------------------------------
-- Lock / unlock core
----------------------------------------------------------------------
function SS:ItemLock_ToggleByID(itemID, announce)
  if not self:ItemLock_IsEnabled() then return end
  local db = LDB()
  if not itemID or itemID == 0 then return end

  if db.locked[itemID] then
    db.locked[itemID] = nil
    if announce then
      LPrint(SS:lime("UNLOCKED").." "..ColoredItemNameBrackets(itemID).." |cffaaaaaa(ID "..itemID..")|r")
    end
  else
    db.locked[itemID] = true
    if announce then
      LPrint(SS:red("LOCKED").." "..ColoredItemNameBrackets(itemID).." |cffaaaaaa(ID "..itemID..")|r")
    end
  end
  self:ItemLock_RebuildFiltered()
  self:ItemLock_Refresh()
end

function SS:ItemLock_ShowRefTooltip(id)
  if not id then return end
  local link = SafeItemLink(id)
  local raw  = link:match("|H([^|]+)|h") or ("item:"..id)
  SetItemRef(raw, link, "LeftButton")
end

----------------------------------------------------------------------
-- ALT+Left-Click hooks in bags + cursor tooltip
----------------------------------------------------------------------
local function HookContainerClicks()
  if SS._ilHooked then return end
  SS._ilHooked = true

  hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(frame, btn)
    if not SS:ItemLock_IsEnabled() then return end
    if not IsAltKeyDown() or btn ~= "LeftButton" then return end
    if not frame or not frame:GetParent() then return end
    local bag  = frame:GetParent():GetID()
    local slot = frame:GetID()
    local link = (bag and slot) and GetContainerItemLink(bag, slot)
    if not link then return end
    local itemID = ItemIDFromLink(link)
    if itemID and itemID > 0 then SS:ItemLock_ToggleByID(itemID, true) end
  end)

  hooksecurefunc("ContainerFrameItemButton_OnEnter", function(frame)
    if not frame or not frame:GetParent() then return end
    if not SS:ItemLock_IsEnabled() then return end
    local bag  = frame:GetParent():GetID()
    local slot = frame:GetID()
    local link = (bag and slot) and GetContainerItemLink(bag, slot)
    if not link then return end
    local id = ItemIDFromLink(link)
    GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
    GameTooltip:SetBagItem(bag, slot)
    if id and id > 0 then
      if SS:IsItemLockedID(id) then
        GameTooltip:AddLine("|cffff5555[LOCKED]|r - ALT+Left Click to |cff32CD32Unlock|r")
      else
        GameTooltip:AddLine("|cff32CD32[UNLOCKED]|r - ALT+Left Click to |cffff5555Lock|r")
      end
    end
    GameTooltip:Show()
  end)
end

----------------------------------------------------------------------
-- UI: Item Lock page (search + list + filters)
----------------------------------------------------------------------
local ROWS, ROW_HEIGHT, LIST_PADY = 10, 20, 8
local QUAL_NAMES = { [0]="Junk",[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",[5]="Legendary",[6]="Artifact",[7]="Heirloom" }

function SS:ItemLock_RebuildFiltered()
  local db = LDB()
  local filters = db.itemLockFilters
  local text = (self.ItemLockSearch and self.ItemLockSearch:GetText() or ""):lower()
  local showAll = (text == nil) or (text == "")

  local list = {}
  for id in pairs(db.locked) do
    local name, _, quality = GetItemInfo(id)
    if not name then self._ilNeedsRetry = true end

    local okQ = filters[quality or 1]
    local okS = true
    if not showAll then
      okS = tostring(id):find(text, 1, true) ~= nil
      if not okS and name then okS = name:lower():find(text, 1, true) ~= nil end
    end
    if okQ and okS then table.insert(list, id) end
  end

  table.sort(list, function(a,b)
    local na = (GetItemInfo(a)) or ("item:"..a)
    local nb = (GetItemInfo(b)) or ("item:"..b)
    if na == nb then return a < b end
    return na < nb
  end)
  self._ItemLockFiltered = list
end

function SS:ItemLock_SearchChanged()
  self:ItemLock_RebuildFiltered()
  self:ItemLock_Refresh()
end

-- Update greys + dynamic master label color
function SS:ItemLock_UpdateEnabledState(enabled)
  local c = self.ItemLockContainer
  if not c then return end
  local alpha = enabled and 1 or 0.35

  -- Master label color: green when ON, red when OFF
  if self.ItemLockEnableCheck then
    local txt = _G[self.ItemLockEnableCheck:GetName().."Text"]
    if txt then
      if enabled then
        txt:SetText("|cff32CD32Enable Item Lock|r")
      else
        txt:SetText("|cffff5555Enable Item Lock|r")
      end
    end
  end

  if self.ItemLockSearch then
    self.ItemLockSearch:SetEnabled(enabled)
    self.ItemLockSearch:SetAlpha(alpha)
  end

  if c._qualChecks then
    for _, cb in ipairs(c._qualChecks) do
      if enabled then if cb.Enable then cb:Enable() end else if cb.Disable then cb:Disable() end end
      cb:SetAlpha(alpha)
    end
  end

  if self.ItemLockRows then
    for _, row in ipairs(self.ItemLockRows) do
      row:EnableMouse(enabled)
      if row.remove then
        if enabled and row.remove.Enable then row.remove:Enable() end
        if (not enabled) and row.remove.Disable then row.remove:Disable() end
        row.remove:SetAlpha(alpha)
      end
      row:SetAlpha(alpha)
    end
  end
end

function SS:BuildItemLockPanel(container)
  HookContainerClicks()
  LDB()

  -- No per-tab title. Compact content box.
  local box = self:AddSeparator(container, 8, -18, -8)

  -- Master enable/disable
  local chkEnable = CreateFrame("CheckButton", "SwiftSki_ItemLock_Enable", container, "InterfaceOptionsCheckButtonTemplate")
  chkEnable:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -18)
  _G[chkEnable:GetName().."Text"]:SetText("|cff32CD32Enable Item Lock|r") -- corrected by UpdateEnabledState
  chkEnable:SetChecked(self:ItemLock_IsEnabled())
  chkEnable:SetScript("OnClick", function(btn)
    local on = btn:GetChecked() and true or false
    LOPT().itemLockEnabled = on
    SS:PlayCheckbox(on)
    LPrint("Item Lock: "..(on and SS:lime("ON") or SS:red("OFF")))
    SS:ItemLock_UpdateEnabledState(on)
  end)
  self.ItemLockEnableCheck = chkEnable

  -- Tip
  local tip = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  tip:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -46)
  tip:SetText("ALT+Left-Click items to ".."|cffff5555lock|r/".."|cff32CD32unlock|r".. " them. |cffff5555Locked|r items cannot be auto/manually sold.")

  -- Search box
  local eb = CreateFrame("EditBox", "SwiftSki_ItemLock_Search", container, "InputBoxTemplate")
  eb:SetAutoFocus(false)
  eb:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -70)
  eb:SetSize(280, 22)
  eb:SetScript("OnTextChanged", function() SS:ItemLock_SearchChanged() end)
  eb:SetText("")
  self.ItemLockSearch = eb

  -- Rarity filters (keep quality colors)
  container._qualChecks = container._qualChecks or {}
  local baseX, baseY = 10, -98
  local function brighten(v) v=v+0.12; if v>1 then v=1 end; return v end

  local function NewQualCheck(qual, col, row)
    local cb = CreateFrame("CheckButton", nil, container, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", box, "TOPLEFT", baseX + (col-1)*140, baseY - (row-1)*22)

    local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetText(QUAL_NAMES[qual]); fs:SetShadowOffset(1,-1); fs:SetShadowColor(0,0,0,1)
    local f, s, fl = GameFontHighlight:GetFont(); if f then fs:SetFont(f, (s or 12)+1, fl) end
    local r,g,b = RGBForQuality(qual); fs:SetTextColor(r,g,b)
    cb.Text = fs; cb._baseColor = {r,g,b}

    cb:SetChecked(LDB().itemLockFilters[qual] and true or false)
    cb:SetScript("OnEnter", function(selfBtn)
      local br,bg,bb = brighten(r), brighten(g), brighten(b)
      fs:SetTextColor(br,bg,bb)
      GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
      GameTooltip:ClearLines()
      GameTooltip:AddLine("Filter: "..QUAL_NAMES[qual], r,g,b)
      GameTooltip:AddLine("Show or hide locked items of this rarity in the list.", .9,.9,.9, true)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() fs:SetTextColor(r,g,b); GameTooltip:Hide() end)
    cb:SetScript("OnClick", function(selfBtn)
      LDB().itemLockFilters[qual] = selfBtn:GetChecked() and true or false
      SS:PlayCheckbox(selfBtn:GetChecked())
      SS:ItemLock_SearchChanged()
    end)
    table.insert(container._qualChecks, cb)
  end

  NewQualCheck(0,1,1); NewQualCheck(1,2,1); NewQualCheck(2,3,1); NewQualCheck(3,4,1)
  NewQualCheck(4,1,2); NewQualCheck(5,2,2); NewQualCheck(6,3,2); NewQualCheck(7,4,2)

  -- List frame + rows
  local listFrame = CreateFrame("Frame", nil, container)
  listFrame:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -140)
  listFrame:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, -8)

  local scroll = CreateFrame("ScrollFrame", "SwiftSki_ItemLock_Scroll", listFrame, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -LIST_PADY)
  scroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -26, LIST_PADY)
  self.ItemLockScroll = scroll

  self.ItemLockRows = self.ItemLockRows or {}
  for i=1, ROWS do
    local row = CreateFrame("Button", nil, listFrame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 12, -8 - (i-1)*ROW_HEIGHT)
    row:SetPoint("RIGHT", scroll, "RIGHT", -8, 0)

    local txt = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    txt:SetPoint("LEFT", row, "LEFT", 0, 0)
    txt:SetJustifyH("LEFT")
    txt:SetText("")
    row.text = txt

    local x = CreateFrame("Button", nil, row, "UIPanelCloseButton")
    x:SetWidth(18); x:SetHeight(18)
    x:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    x:GetNormalTexture():SetVertexColor(1,.25,.25)
    x:GetPushedTexture():SetVertexColor(1,.10,.10)
    x:GetHighlightTexture():SetVertexColor(1,.50,.50)
    row.remove = x

    x:SetScript("OnClick", function(selfBtn)
      if not SS:ItemLock_IsEnabled() then return end
      local r = selfBtn:GetParent()
      if r and r._id then SS:ItemLock_ToggleByID(r._id, true) end
    end)

    row:SetScript("OnEnter", function(selfRow)
      if not selfRow._id then return end
      GameTooltip:SetOwner(selfRow, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink("item:"..selfRow._id)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(selfRow, btn)
      if not SS:ItemLock_IsEnabled() then return end
      if not selfRow._id then return end
      local id = selfRow._id
      local link = SafeItemLink(id)

      if IsShiftKeyDown() and ChatEdit_GetActiveWindow() then ChatEdit_InsertLink(link); return end
      if IsControlKeyDown() and DressUpItemLink then DressUpItemLink(link); return end
      if btn == "RightButton" then SS:ItemLock_ToggleByID(id, true); return end
      GameTooltip:Hide(); SS:ItemLock_ShowRefTooltip(id)
    end)

    self.ItemLockRows[i] = row
  end
  scroll:SetScript("OnVerticalScroll", function(selfScr, offset)
    FauxScrollFrame_OnVerticalScroll(selfScr, offset, ROW_HEIGHT, function() SS:ItemLock_Refresh() end)
  end)

  self.ItemLockContainer = container
  self:ItemLock_RebuildFiltered()
  self:ItemLock_Refresh()
  self:ItemLock_UpdateEnabledState(self:ItemLock_IsEnabled())
end

function SS:ItemLock_Refresh()
  if not self.ItemLockRows then return end
  local list = self._ItemLockFiltered or {}
  FauxScrollFrame_Update(self.ItemLockScroll, #list, #self.ItemLockRows, ROW_HEIGHT)

  local offset = FauxScrollFrame_GetOffset(self.ItemLockScroll)
  for i=1,#self.ItemLockRows do
    local idx = i + offset
    local row = self.ItemLockRows[i]
    local id  = list[idx]
    if id then
      row._id = id
      local name, _, quality = GetItemInfo(id)
      local hex = HexForQuality(quality or 1)
      name = name or ("item:"..id)
      row.text:SetText(hex.."["..name.."]|r |cffaaaaaa(ID "..id..")|r")
      row:Show()
    else
      row._id = nil
      row.text:SetText("")
      row:Hide()
    end
  end

  if self._ilNeedsRetry then
    self._ilNeedsRetry = nil
    After(0.25, function() SS:ItemLock_RebuildFiltered(); SS:ItemLock_Refresh() end)
  end
end
