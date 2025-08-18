-- SwiftSki_Vendor.lua — Vendor tab, filters, auto-sell with coin burst FX

local SS = _G.SwiftSki
local VENDOR_HEX = "1E90FF"
local RED_HEX    = "FF5555"
local function Vc(t) return "|cff"..VENDOR_HEX..(t or "").."|r" end

------------------------------------------------------------
-- Saved options (with defaults)
------------------------------------------------------------
local function VOpt()
  _G.SwiftSkiDB = _G.SwiftSkiDB or { options = {} }
  local o = SwiftSkiDB.options
  o.vendor            = o.vendor or {}
  local v             = o.vendor
  if v.enabled        == nil then v.enabled        = true  end
  if v.safeSell       == nil then v.safeSell       = true  end  -- NEW: limit to 10 per visit when on
  v.quality           = v.quality or {}
  if v.quality[0]     == nil then v.quality[0]     = true  end
  if v.quality[1]     == nil then v.quality[1]     = true  end
  if v.quality[2]     == nil then v.quality[2]     = false end
  if v.quality[3]     == nil then v.quality[3]     = false end
  if v.quality[4]     == nil then v.quality[4]     = false end
  if v.quality[5]     == nil then v.quality[5]     = false end
  if v.quality[6]     == nil then v.quality[6]     = false end
  if v.quality[7]     == nil then v.quality[7]     = false end
  v.mats              = v.mats or {}
  local m             = v.mats
  if m.Herb           == nil then m.Herb           = true end
  if m.MetalStone     == nil then m.MetalStone     = true end
  if m.Cloth          == nil then m.Cloth          = true end
  if m.Leather        == nil then m.Leather        = true end
  if m.Elemental      == nil then m.Elemental      = true end
  if m.Enchanting     == nil then m.Enchanting     = true end
  if m.Jewelcrafting  == nil then m.Jewelcrafting  = true end
  if m.Cooking        == nil then m.Cooking        = true end
  if m.Parts          == nil then m.Parts          = true end
  return v
end

------------------------------------------------------------
-- Chat tags + print helpers
------------------------------------------------------------
local function VTag() return "["..SS:lime("SwiftSki").."-"..Vc("Vendor").."] " end
local function VPrint(msg) SS:Chat(VTag()..msg) end

------------------------------------------------------------
-- Utils
------------------------------------------------------------
local function After(delay, fn)
  local f, t = CreateFrame("Frame"), 0
  f:SetScript("OnUpdate", function(self, e)
    t = t + e
    if t >= (delay or 0) then self:SetScript("OnUpdate", nil); self:Hide(); pcall(fn) end
  end)
end

local function MoneyStringIcons(copper)
  local floor = math.floor
  local g = floor(copper / 10000)
  local s = floor((copper % 10000) / 100)
  local c = copper % 100
  local t = {}
  table.insert(t, g.."|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t")
  if s > 0 or g > 0 then table.insert(t, s.."|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t") end
  table.insert(t, c.."|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t")
  return table.concat(t, " ")
end

local QUAL_NAMES = {
  [0] = "|cff9d9d9dJunk|r",[1] = "|cffffffffCommon|r",[2] = "|cff1eff00Uncommon|r",
  [3] = "|cff0070ddRare|r",[4] = "|cffa335eeEpic|r",[5] = "|cffff8000Legendary|r",
  [6] = "|cffe6cc80Artifact|r",[7] = "|cffe6cc80Heirloom|r",
}

local TRADEGOODS = _G.ITEM_CLASS_TRADEGOODS or "Trade Goods"
local SUBTYPE_MAP = {
  Herb          = _G.ITEM_SUBCLASS_TRADEGOODS_HERB        or "Herb",
  MetalStone    = _G.ITEM_SUBCLASS_TRADEGOODS_METAL_STONE or "Metal & Stone",
  Cloth         = _G.ITEM_SUBCLASS_TRADEGOODS_CLOTH       or "Cloth",
  Leather       = _G.ITEM_SUBCLASS_TRADEGOODS_LEATHER     or "Leather",
  Elemental     = _G.ITEM_SUBCLASS_TRADEGOODS_ELEMENTAL   or "Elemental",
  Enchanting    = _G.ITEM_SUBCLASS_TRADEGOODS_ENCHANTING  or "Enchanting",
  Jewelcrafting = _G.ITEM_SUBCLASS_TRADEGOODS_JEWELCRAFTING or "Jewelcrafting",
  Cooking       = _G.ITEM_SUBCLASS_TRADEGOODS_COOKING     or "Cooking",
  Parts         = _G.ITEM_SUBCLASS_TRADEGOODS_PARTS       or "Parts",
}

local function IsProtectedMaterial(itemType, itemSubType)
  if itemType ~= TRADEGOODS then return false end
  local v = VOpt()
  for key, subName in pairs(SUBTYPE_MAP) do
    if v.mats[key] and itemSubType == subName then return true end
  end
  return false
end

local function IsLockedByUser(itemID)
  if not itemID or itemID == 0 then return false end
  if SS and SS.IsItemLockedID then
    local ok, val = pcall(SS.IsItemLockedID, SS, itemID)
    if ok and val then return true end
  end
  if _G.SwiftSkiDB and _G.SwiftSkiDB.locked and _G.SwiftSkiDB.locked[itemID] then return true end
  return false
end

if not SS.CoinBurst then function SS:CoinBurst() end end

------------------------------------------------------------
-- Enable/disable greying of subordinate controls
------------------------------------------------------------
function SS:Vendor_SetControlsEnabled(enabled)
  local c = self.VendorContainer
  if not c then return end
  local function apply(list)
    if not list then return end
    for _, cb in ipairs(list) do
      if enabled then if cb.Enable then cb:Enable() end; cb:SetAlpha(1.0)
      else if cb.Disable then cb:Disable() end; cb:SetAlpha(0.35) end
    end
  end
  apply(c._qualChecks); apply(c._matChecks)
  -- NEW: also gate the Safe-Sell checkbox
  if c._safeSellCheck then
    if enabled then c._safeSellCheck:Enable(); c._safeSellCheck:SetAlpha(1.0)
    else c._safeSellCheck:Disable(); c._safeSellCheck:SetAlpha(0.35) end
  end
end

------------------------------------------------------------
-- Dynamic label + tooltip for master Enable Auto-Vendor
------------------------------------------------------------
local function SetVendorEnableLabel(cb, isOn)
  if not cb then return end
  local fs = _G[cb:GetName().."Text"]; if not fs then return end
  fs:SetText((isOn and "|cff"..VENDOR_HEX or "|cff"..RED_HEX).."Enable Auto-Vendor|r")
end

local function WireVendorEnableTooltip(cb, descText)
  if not cb then return end
  cb._tipTitle = "Enable Auto-Vendor"
  cb._tipDesc  = descText or ""

  local function RefreshTooltip(self)
    if not GameTooltip then return end
    if not GameTooltip:IsOwned(self) then GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    else GameTooltip:ClearLines() end
    if self:GetChecked() then
      GameTooltip:AddLine("|cff"..VENDOR_HEX..self._tipTitle.."|r")
    else
      GameTooltip:AddLine("|cff"..RED_HEX..self._tipTitle.."|r")
    end
    GameTooltip:AddLine(self._tipDesc, .8,.8,.8, true) -- gray desc
    GameTooltip:Show()
  end

  cb._refreshTooltip = RefreshTooltip
  cb:EnableMouse(true)
  cb:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); self:_refreshTooltip() end)
  cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  cb:HookScript("OnClick", function(self) if self._refreshTooltip then self:_refreshTooltip() end end)
end

------------------------------------------------------------
-- NEW: Dynamic label + tooltip for Safe-Sell
------------------------------------------------------------
local function SetSafeSellLabel(cb, isOn)
  if not cb then return end
  local fs = _G[cb:GetName().."Text"]; if not fs then return end
  fs:SetText((isOn and "|cff"..VENDOR_HEX or "|cff"..RED_HEX).."Safe-Sell (max 10 items)|r")
end

local function WireSafeSellTooltip(cb, descText)
  if not cb then return end
  cb._tipTitle = "Safe-Sell (max 10 items)"
  cb._tipDesc  = descText or "While enabled, SwiftSki sells at most 10 items per merchant visit. Turn off to sell all items that match your filters."

  local function RefreshTooltip(self)
    if not GameTooltip then return end
    if not GameTooltip:IsOwned(self) then GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    else GameTooltip:ClearLines() end
    if self:GetChecked() then
      GameTooltip:AddLine("|cff"..VENDOR_HEX..self._tipTitle.."|r")
    else
      GameTooltip:AddLine("|cff"..RED_HEX..self._tipTitle.."|r")
    end
    GameTooltip:AddLine(self._tipDesc, .8,.8,.8, true)
    GameTooltip:Show()
  end

  cb._refreshTooltip = RefreshTooltip
  cb:EnableMouse(true)
  cb:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); self:_refreshTooltip() end)
  cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  cb:HookScript("OnClick", function(self) if self._refreshTooltip then self:_refreshTooltip() end end)
end

------------------------------------------------------------
-- UI: Vendor panel
------------------------------------------------------------
function SS:BuildVendorPanel(container)
  local v = VOpt()
  local box = self:AddSeparator(container, 8, -18, -8)
  local y = -18

  -- Enable Auto-Vendor
  local chkEnable = CreateFrame("CheckButton", "SwiftSki_AutoVendor", container, "InterfaceOptionsCheckButtonTemplate")
  chkEnable:SetPoint("TOPLEFT", box, "TOPLEFT", 14, y)
  chkEnable:SetChecked(v.enabled)
  SetVendorEnableLabel(chkEnable, v.enabled)
  WireVendorEnableTooltip(chkEnable, "When visiting a merchant, sells items that match your filters once per visit.")

  self:WireCheckSound(chkEnable, function(btn)
    local on = btn:GetChecked() and true or false
    VOpt().enabled = on
    SetVendorEnableLabel(chkEnable, on)
    if chkEnable._refreshTooltip then chkEnable:_refreshTooltip() end
    VPrint("Auto-Vendor: "..(on and SS:lime("ON") or SS:red("OFF")))
    SS:Vendor_SetControlsEnabled(on)
  end, "Auto-Vendor")

  y = y - 28

  -- NEW: Safe-Sell (max 10 items) under the main enable
  local chkSafe = CreateFrame("CheckButton", "SwiftSki_Vendor_SafeSell", container, "InterfaceOptionsCheckButtonTemplate")
  chkSafe:SetPoint("TOPLEFT", box, "TOPLEFT", 34, y) -- slight indent beneath the master toggle
  chkSafe:SetChecked(v.safeSell)
  SetSafeSellLabel(chkSafe, v.safeSell)
  WireSafeSellTooltip(chkSafe)

  self:WireCheckSound(chkSafe, function(btn)
    local on = btn:GetChecked() and true or false
    VOpt().safeSell = on
    SetSafeSellLabel(chkSafe, on)
    if chkSafe._refreshTooltip then chkSafe:_refreshTooltip() end
    VPrint("Safe-Sell: "..(on and SS:lime("ON (max 10 per visit)") or SS:red("OFF (no limit)")))
  end, "Vendor: Safe-Sell")

  container._safeSellCheck = chkSafe

  y = y - 26

  local function Header(parent, text, px, py)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", box, "TOPLEFT", px, py)
    local font, size = GameFontNormalLarge:GetFont()
    fs:SetFont(font, size, "OUTLINE")
    fs:SetText(Vc(text))
    return fs
  end

  Header(container, "Sell rarities:", 14, y); y = y - 24

  local columnOffset = 130
  container._qualChecks = container._qualChecks or {}
  local function NewQualCheck(q, col, row)
    local cb = CreateFrame("CheckButton", "SwiftSki_Vendor_Qual"..q, container, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", box, "TOPLEFT", 18 + (col-1)*columnOffset, y - (row-1)*26)
    _G[cb:GetName().."Text"]:SetText(QUAL_NAMES[q] or ("Q"..q))
    cb:SetChecked(v.quality[q])
    SS:AttachTip(cb, "Sell "..(QUAL_NAMES[q] or ("Q"..q)):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""),
      "If checked, items of this rarity are eligible to be sold unless protected below.")
    SS:WireCheckSound(cb, function(btn) VOpt().quality[q] = btn:GetChecked() and true or false end, "Vendor: rarity")
    table.insert(container._qualChecks, cb)
  end

  NewQualCheck(0,1,1); NewQualCheck(1,2,1); NewQualCheck(2,3,1); NewQualCheck(3,4,1)
  NewQualCheck(4,1,2); NewQualCheck(5,2,2); NewQualCheck(6,3,2); NewQualCheck(7,4,2)

  y = y - 26*2 - 8
  Header(container, "Do not sell materials:", 14, y); y = y - 20

  local mats = {
    {"Herb","Herbs"},{"MetalStone","Metal & Stone"},{"Cloth","Cloth"},{"Leather","Leather"},
    {"Elemental","Elemental"},{"Enchanting","Enchanting"},{"Jewelcrafting","Jewelcrafting"},
    {"Cooking","Cooking"},{"Parts","Engineering Parts"},
  }

  container._matChecks = container._matChecks or {}
  local col, row = 1, 1
  for i=1,#mats do
    local key, label = mats[i][1], mats[i][2]
    local cb = CreateFrame("CheckButton", nil, container, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", box, "TOPLEFT", 14 + (col-1)*220, y - (row-1)*26)
    local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0); fs:SetText("|cffffffff"..label.."|r")
    cb.Text = fs
    cb:SetChecked(v.mats[key] and true or false)
    SS:AttachTip(cb, label, "Protects only materials under Trade Goods: "..label..".")
    cb:SetScript("OnClick", function(selfBtn)
      VOpt().mats[key] = selfBtn:GetChecked() and true or false
      SS:PlayCheckbox(selfBtn:GetChecked())
      VPrint("Do not sell "..label..": "..(selfBtn:GetChecked() and SS:lime("ON") or SS:red("OFF")))
    end)
    table.insert(container._matChecks, cb)
    col = col + 1; if col > 2 then col = 1; row = row + 1 end
  end

  SS.VendorContainer = container
  SS.chkVEnable = chkEnable
  SS:Vendor_WireEvents()
  SS:Vendor_SetControlsEnabled(v.enabled)
end

------------------------------------------------------------
-- Selling pass
------------------------------------------------------------
local function SellItem(bag, slot) UseContainerItem(bag, slot) end

function SS:Vendor_RunOnce()
  if self._vendorBusy then return end
  self._vendorBusy = true

  local v = VOpt()
  local soldAny, totalCopper, lines = false, 0, {}
  local hadUncached = false

  -- NEW: Safe-Sell limit for this pass (respects what was already sold this visit)
  local already = self._safeSoldThisVisit or 0
  local limit   = v.safeSell and math.max(0, 10 - already) or math.huge
  local soldNow = 0
  local stop    = false

  for bag=0,4 do
    if stop then break end
    local slots = GetContainerNumSlots(bag)
    for slot=1,slots do
      if stop then break end
      local link = GetContainerItemLink(bag, slot)
      if link then
        local name, _, quality, _, _, itemType, itemSubType, _, _, _, sellPrice = GetItemInfo(link)
        local _, itemCount, locked = GetContainerItemInfo(bag, slot)
        local itemID = tonumber(string.match(link, "item:(%d+)") or 0)

        if sellPrice == nil then GetItemInfo(link); hadUncached = true end

        if not locked and not IsLockedByUser(itemID) and sellPrice and sellPrice > 0 then
          local allowed = v.quality[quality] and true or false
          local matProtected = IsProtectedMaterial(itemType, itemSubType)
          if allowed and not matProtected then
            if soldNow < limit then
              SellItem(bag, slot)
              soldAny = true
              soldNow = soldNow + 1
              local count = itemCount or 1
              local thisCopper = sellPrice * count
              totalCopper = totalCopper + thisCopper
              table.insert(lines, string.format("%s x%d sold for %s", link, count, MoneyStringIcons(thisCopper)))
            else
              stop = true
            end
          end
        end
      end
    end
  end

  if soldAny then
    VPrint("Auto-Vendor: "..SS:lime("Applied."))
    for i=1,#lines do VPrint(lines[i]) end
    VPrint("Total: "..MoneyStringIcons(totalCopper))
    if v.safeSell and (already + soldNow) >= 10 then
      VPrint(SS:teal("Safe-Sell limit reached (10 items max this visit)."))
    end
    SS:CoinBurst(totalCopper)
  else
    if v.safeSell and limit == 0 then
      VPrint("Auto-Vendor: "..SS:teal("Safe-Sell limit already reached for this visit."))
    else
      VPrint("Auto-Vendor: No items matched filters.")
    end
  end

  -- track visit-wide sold count for Safe-Sell
  self._safeSoldThisVisit = already + soldNow

  self._lastVendorRunAt = GetTime()
  self._vendorBusy = false

  -- If some items were uncached, try again shortly (same visit). Safe-Sell respected via remaining limit.
  if hadUncached and MerchantFrame and MerchantFrame:IsShown() then
    After(0.25, function() if MerchantFrame and MerchantFrame:IsShown() then SS:Vendor_RunOnce() end end)
  end
end

------------------------------------------------------------
-- Event wiring for vendor logic (now wired at login too)
------------------------------------------------------------
function SS:Vendor_WireEvents()
  if self._vendorEvt then return end
  local f = CreateFrame("Frame")
  f:RegisterEvent("MERCHANT_SHOW")
  f:SetScript("OnEvent", function()
    local v = VOpt()
    if not v.enabled then return end
    -- reset per-visit Safe-Sell tally
    SS._safeSoldThisVisit = 0
    if self._lastVendorRunAt and (GetTime() - self._lastVendorRunAt) < 0.2 then return end
    -- small delay to let GetItemInfo resolve more items on first open
    After(0.05, function() SS:Vendor_RunOnce() end)
  end)
  self._vendorEvt = f
end

-- Ensure vendor events are active even if the UI panel was never opened
do
  local init = CreateFrame("Frame")
  init:RegisterEvent("PLAYER_LOGIN")
  init:SetScript("OnEvent", function() VOpt(); if SS and SS.Vendor_WireEvents then SS:Vendor_WireEvents() end end)
end

------------------------------------------------------------
-- COIN BURST FX (jackpot-style) — renders on UIParent, near MerchantFrame center
------------------------------------------------------------
do
  local ICON = {
    gold   = "Interface\\MoneyFrame\\UI-GoldIcon",
    silver = "Interface\\MoneyFrame\\UI-SilverIcon",
    copper = "Interface\\MoneyFrame\\UI-CopperIcon",
  }

  local function ensureFX(self)
    if self._coinFX then return self._coinFX end
    local fx = CreateFrame("Frame", "SwiftSki_CoinFX", UIParent)
    fx:SetFrameStrata("TOOLTIP")
    fx:SetAllPoints(UIParent)
    fx:Hide()
    fx.particles, fx.pool = {}, {}
    fx.emitTimer, fx.pendingSets = 0, 0
    fx.cx, fx.cy = 0, 0

    local function acquire(texPath, size)
      local t = table.remove(fx.pool) or fx:CreateTexture(nil, "OVERLAY")
      t:SetTexture(texPath); t:SetSize(size, size); t:SetAlpha(1); t:Show(); return t
    end

    local function release(t)
      if not t then return end
      t:Hide(); t:ClearAllPoints(); t:SetTexture(nil)
      t._vx, t._vy, t._x, t._y, t._life, t._ttl = nil
      table.insert(fx.pool, t)
    end

    fx:SetScript("OnUpdate", function(_, dt)
      fx.emitTimer = fx.emitTimer - dt
      if fx.pendingSets > 0 and fx.emitTimer <= 0 then
        fx.emitTimer = 0.05
        fx.pendingSets = fx.pendingSets - 1

        local startX, startY = fx.cx, fx.cy
        local function spawn(tex, baseSpeed, size)
          local t = acquire(tex, size)
          t._x, t._y = startX, startY
          local ang = (math.random() * 70 - 35) * math.pi/180  -- cone
          local spd = baseSpeed + math.random()*120
          t._vx = math.sin(ang) * spd
          t._vy = math.cos(ang) * spd
          t._ttl = 1.0 + math.random()*0.6
          t._life = 0
          t:SetPoint("CENTER", UIParent, "CENTER", t._x, t._y)
          table.insert(fx.particles, t)
        end

        spawn(ICON.gold,   360, 22)
        spawn(ICON.silver, 320, 20)
        spawn(ICON.copper, 300, 18)
      end

      local GRAV = 780
      for i = #fx.particles, 1, -1 do
        local t = fx.particles[i]
        t._life = t._life + dt
        t._vy = t._vy - GRAV * dt
        t._x  = t._x + t._vx * dt
        t._y  = t._y + t._vy * dt

        local a = 1
        if t._life > t._ttl * 0.6 then
          a = 1 - (t._life - t._ttl*0.6) / (t._ttl*0.4); if a < 0 then a = 0 end
        end
        t:SetAlpha(a)
        t:SetPoint("CENTER", UIParent, "CENTER", t._x, t._y)

        if t._life >= t._ttl then
          release(t); table.remove(fx.particles, i)
        end
      end

      if fx.pendingSets <= 0 and #fx.particles == 0 and GetTime() > (fx.stopAt or 0) then
        fx:Hide()
      end
    end)

    self._coinFX = fx
    return fx
  end

  local function centerOnUI(frame)
    if not frame or not frame.GetCenter then return UIParent:GetCenter() end
    local x, y = frame:GetCenter()
    if not x then return UIParent:GetCenter() end
    local s  = frame:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale() or 1
    return (x * s) / us, (y * s) / us
  end

  function SS:CoinBurst(totalCopper)
    local sets = math.floor((totalCopper or 0) / 10000) -- per 1g
    if sets <= 0 then return end

    local fx = ensureFX(self)

    -- Position near merchant center (scaled to UIParent), or screen center
    local ax, ay
    if MerchantFrame and MerchantFrame:IsShown() then
      ax, ay = centerOnUI(MerchantFrame)
    else
      ax, ay = UIParent:GetCenter()
    end
    local pcx, pcy = UIParent:GetCenter()
    fx.cx, fx.cy = (ax - pcx), (ay - pcy) - 40

    local maxSets = 60
    fx.pendingSets = (fx.pendingSets or 0) + math.min(sets, maxSets)
    fx.stopAt = GetTime() + 0.9 + math.min(sets * 0.05, 3.0)

    fx:Show()
  end
end