--[[--------------------------------------------------------------------
  SwiftSki_Ascension.lua
  Ascension-only: bag appearance auto-collect, fast roulette, auto-heirlooms,
  Manastorm 2h-buff helper, and a small options UI section.
----------------------------------------------------------------------]]

local SS = _G.SwiftSki
if not SS then return end

----------------------------------------------------------------------
-- Color helpers & chat prefix
----------------------------------------------------------------------
local HEX = {
  ORANGE = "FFA500",
  RED    = "FF5555",
  GRAY   = "777777",
  WHITE  = "FFFFFF",
}
local function color(hex, text) return "|cff"..hex..(text or "").."|r" end
function SS:orange(t) return "|cff"..HEX.ORANGE..(t or "").."|r" end

local function ATag()
  return "["..SS:lime("SwiftSki").."–"..SS:orange("Ascension").."] "
end
local function PrintA(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(ATag()..msg)
  else print(ATag()..msg) end
end

----------------------------------------------------------------------
-- Realm detection
----------------------------------------------------------------------
function SS:IsAscensionRealmName(want)
  local rn = GetRealmName and GetRealmName() or ""
  if not rn or rn == "" then return false end
  rn = rn:lower()
  if type(want) == "string" and want ~= "" then
    return rn:find(want:lower(), 1, true) and true or false
  end
  return false
end

function SS:IsAscensionRealm()
  if self:IsAscensionRealmName("elune")   then return true end
  if self:IsAscensionRealmName("area 52") then return true end
  local rl = GetCVar and GetCVar("realmList") or ""
  if rl and rl:find("162%.19%.28%.88", 1, true) then return true end
  return false
end

----------------------------------------------------------------------
-- Options (with safe defaults)
----------------------------------------------------------------------
local function Opt()
  _G.SwiftSkiDB = _G.SwiftSkiDB or { options = {} }
  local o = SwiftSkiDB.options
  if o.autoCollect   == nil then o.autoCollect   = true  end
  if o.fastRoulette  == nil then o.fastRoulette  = true  end
  if o.autoHeirlooms == nil then o.autoHeirlooms = true  end
  if o.msBuffs       == nil then o.msBuffs       = true  end
  return o
end

----------------------------------------------------------------------
-- Small UI helpers (labels, tooltips, and consistent fonts)
----------------------------------------------------------------------
local function SameFontLike(ref, others)
  local lbl = ref and (_G[ref:GetName().."Text"] or ref.Text or ref.text)
  if not lbl or not lbl.GetFont then return end
  local face, size, flags = lbl:GetFont()
  if not face then return end
  for _, cb in ipairs(others or {}) do
    local L = cb and (_G[cb:GetName().."Text"] or cb.Text or cb.text)
    if L then L:SetFont(face, size, flags) end
  end
end

local function SetLabelColor(cb)
  if not cb then return end
  local fs = _G[cb:GetName().."Text"]
  if not fs or not cb._rawLabel then return end
  local hex = (not cb:IsEnabled()) and HEX.GRAY
           or (cb:GetChecked() and HEX.ORANGE or HEX.RED)
  fs:SetText(color(hex, cb._rawLabel))
end

local function ShowStateTooltip(cb)
  if not cb then return end
  local title = cb._rawLabel or ""
  local tip   = cb._rawTip   or ""
  local hex   = (not cb:IsEnabled()) and HEX.GRAY
             or (cb:GetChecked() and HEX.ORANGE or HEX.RED)

  GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine(color(hex, title))
  if tip ~= "" then GameTooltip:AddLine(tip, 0.8,0.8,0.8, true) end
  GameTooltip:Show()
end

local function WireHoverLiveTooltip(cb)
  cb:HookScript("OnEnter", function(self)
    self.__lastChecked = self:GetChecked()
    ShowStateTooltip(self)
    self:SetScript("OnUpdate", function(s)
      if not s:IsMouseOver() then return end
      local now = s:GetChecked()
      if now ~= s.__lastChecked then
        s.__lastChecked = now
        SetLabelColor(s)
        if GameTooltip:IsOwned(s) then ShowStateTooltip(s) end
      end
    end)
  end)
  cb:HookScript("OnLeave", function(self)
    self:SetScript("OnUpdate", nil)
    GameTooltip:Hide()
    SetLabelColor(self)
  end)
end

local function WireAsc(cb, label, onToggle)
  if not cb then return end
  cb:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    if onToggle then onToggle(on) end
    SS:PlayCheckbox(on)
    SetLabelColor(self)
    if GameTooltip:IsOwned(self) then ShowStateTooltip(self) end
    PrintA(label..": "..(on and SS:lime("ON") or SS:red("OFF")))
  end)
  WireHoverLiveTooltip(cb)
end

----------------------------------------------------------------------
-- Auto Collect Appearance (bag watcher using C_Appearance*)
----------------------------------------------------------------------
if not SS.ToggleBagWatcher then
  local function CollectBagsOnce()
    local ok1, CAC = pcall(function() return C_AppearanceCollection end)
    local ok2, CAP = pcall(function() return C_Appearance end)
    if not (ok1 and ok2 and CAC and CAP) then return end
    for bag=0,4 do
      local slots = GetContainerNumSlots(bag)
      for slot=1,slots do
        local itemID = GetContainerItemID(bag, slot)
        if itemID then
          local appID = CAP.GetItemAppearanceID(itemID)
          if appID and not CAC.IsAppearanceCollected(appID) then
            CAC.CollectItemAppearance(itemID)
          end
        end
      end
    end
  end

  function SS:ToggleBagWatcher(on)
    if on then
      if not self.bagWatcher then
        local f = CreateFrame("Frame")
        f:RegisterEvent("BAG_UPDATE")
        f:RegisterEvent("PLAYER_LOGIN")
        f:SetScript("OnEvent", CollectBagsOnce)
        self.bagWatcher = f
      end
      CollectBagsOnce()
    else
      if self.bagWatcher then
        self.bagWatcher:UnregisterAllEvents()
        self.bagWatcher = nil
      end
    end
  end
end

----------------------------------------------------------------------
-- Fast Roulette (Elune: shorten roulette duration)
----------------------------------------------------------------------
if not SS.ApplyFastRoulette then
  function SS:ApplyFastRoulette(silent)
    if not SwiftSkiDB or not SwiftSkiDB.options then return end
    if SwiftSkiDB.options.fastRoulette then
      _G.DEBUG_WC_ROULETTE_DURATION = 0
      if not silent then PrintA(SS:teal("Fast Roulette: ")..SS:lime("ON")) end
    else
      _G.DEBUG_WC_ROULETTE_DURATION = nil
      if not silent then PrintA(SS:teal("Fast Roulette: ")..SS:red("OFF")) end
    end
  end
end

----------------------------------------------------------------------
-- Auto-equip Heirlooms on Prestige (level 1 + debuff)
-- - Scans bags, equips heirlooms, and fills Shirt/Tabard if empty.
-- - Queue driver handles ring/trinket double-slots cleanly.
----------------------------------------------------------------------
if not SS.CheckPrestigeAutoEquip then
  local PRESTIGE_DEBUFF_ID   = 9930831
  local PRESTIGE_DEBUFF_NAME = "Prestige Challenge"

  local INVSLOT = {
    HEAD=1, NECK=2, SHOULDER=3, SHIRT=4, CHEST=5, WAIST=6, LEGS=7, FEET=8,
    WRIST=9, HANDS=10, FINGER1=11, FINGER2=12, TRINKET1=13, TRINKET2=14,
    BACK=15, MAINHAND=16, OFFHAND=17, RANGED=18, TABARD=19,
  }

  local function HasPrestigeDebuff()
    for i=1,40 do
      local name, _, _, _, _, _, _, _, _, _, spellId = UnitDebuff("player", i)
      if not name then break end
      if (spellId and spellId == PRESTIGE_DEBUFF_ID) or name == PRESTIGE_DEBUFF_NAME then
        return true
      end
    end
    return false
  end

  local function GetItemInfoSafe(link)
    if not link then return end
    local name, _, quality, _, _, _, _, _, equipLoc = GetItemInfo(link)
    return name, quality, equipLoc
  end

  -- Simple equip queue (bag → cursor → slot)
  local function EQ_Reset()
    SS._equipQ = {}
    SS._eqFrame = SS._eqFrame or CreateFrame("Frame")
    SS._eqFrame:Hide()
    SS._eqDelay = 0
  end
  local function EQ_Enqueue(bag, slot, targetSlot)
    table.insert(SS._equipQ, {bag=bag, slot=slot, target=targetSlot})
  end
  local function EQ_Start()
    if not SS._eqFrame then EQ_Reset() end
    if SS._eqFrame:IsShown() then return end
    SS._eqDelay = 0
    SS._eqFrame:SetScript("OnUpdate", function(_, elapsed)
      if SS._eqDelay and SS._eqDelay > 0 then SS._eqDelay = SS._eqDelay - elapsed; return end
      local job = SS._equipQ and SS._equipQ[1]
      if not job then SS._eqFrame:Hide(); return end

      -- Skip if slot is already filled (covers dual ring/trinket)
      if job.target and GetInventoryItemLink("player", job.target) then
        table.remove(SS._equipQ, 1); SS._eqDelay = 0.05; return
      end

      local linkNow = GetContainerItemLink(job.bag, job.slot)
      if not linkNow then
        table.remove(SS._equipQ, 1); SS._eqDelay = 0.05; return
      end

      PickupContainerItem(job.bag, job.slot)
      if CursorHasItem() then
        if job.target then EquipCursorItem(job.target) else AutoEquipCursorItem() end
        ClearCursor()
      end
      table.remove(SS._equipQ, 1)
      SS._eqDelay = 0.12
    end)
    SS._eqFrame:Show()
  end

  function SS:EquipHeirloomsOnce()
    EQ_Reset()

    local ringBags, trinketBags, others = {}, {}, {}
    local shirtBag, tabardBag

    for bag=0,4 do
      local slots = GetContainerNumSlots(bag)
      for slot=1,slots do
        local link = GetContainerItemLink(bag, slot)
        if link then
          local _, quality, equipLoc = GetItemInfoSafe(link)
          if equipLoc == "INVTYPE_BODY"   and not shirtBag  then shirtBag  = {bag=bag, slot=slot, link=link} end
          if equipLoc == "INVTYPE_TABARD" and not tabardBag then tabardBag = {bag=bag, slot=slot, link=link} end
          if quality == 7 then
            if     equipLoc == "INVTYPE_FINGER"   then table.insert(ringBags,    {bag=bag, slot=slot, link=link})
            elseif equipLoc == "INVTYPE_TRINKET"  then table.insert(trinketBags, {bag=bag, slot=slot, link=link})
            else table.insert(others, link) end
          end
        end
      end
    end

    -- Equip the generic heirlooms (client picks slots)
    for i=1,#others do EquipItemByName(others[i]) end

    -- Fill both ring/trinket slots if possible
    local emptyRing1    = not GetInventoryItemLink("player", INVSLOT.FINGER1)
    local emptyRing2    = not GetInventoryItemLink("player", INVSLOT.FINGER2)
    local emptyTrinket1 = not GetInventoryItemLink("player", INVSLOT.TRINKET1)
    local emptyTrinket2 = not GetInventoryItemLink("player", INVSLOT.TRINKET2)

    local rIdx = 1
    if emptyRing1 and ringBags[rIdx] then EQ_Enqueue(ringBags[rIdx].bag, ringBags[rIdx].slot, INVSLOT.FINGER1); rIdx = rIdx + 1 end
    if emptyRing2 and ringBags[rIdx] then EQ_Enqueue(ringBags[rIdx].bag, ringBags[rIdx].slot, INVSLOT.FINGER2); rIdx = rIdx + 1 end

    local tIdx = 1
    if emptyTrinket1 and trinketBags[tIdx] then EQ_Enqueue(trinketBags[tIdx].bag, trinketBags[tIdx].slot, INVSLOT.TRINKET1); tIdx = tIdx + 1 end
    if emptyTrinket2 and trinketBags[tIdx] then EQ_Enqueue(trinketBags[tIdx].bag, trinketBags[tIdx].slot, INVSLOT.TRINKET2); tIdx = tIdx + 1 end

    if not GetInventoryItemLink("player", INVSLOT.SHIRT)  and shirtBag  then EQ_Enqueue(shirtBag.bag,  shirtBag.slot,  INVSLOT.SHIRT)  end
    if not GetInventoryItemLink("player", INVSLOT.TABARD) and tabardBag then EQ_Enqueue(tabardBag.bag, tabardBag.slot, INVSLOT.TABARD) end

    if #SS._equipQ > 0 then EQ_Start() end
  end

  function SS:CheckPrestigeAutoEquip()
    local o = SwiftSkiDB and SwiftSkiDB.options
    if not (o and o.autoHeirlooms) then return end
    if UnitLevel("player") ~= 1 then SS._prestigeActive = false; return end
    if HasPrestigeDebuff() then
      if not self._prestigeActive then
        self._prestigeActive = true
        self:EquipHeirloomsOnce()
      end
    else
      self._prestigeActive = false
    end
  end
end

----------------------------------------------------------------------
-- Manastorm 2h Buffs
-- - Shows a single click button once per Arcane Dizziness "epoch".
-- - Button persists across portals (no re-show) until clicked or debuff ends.
----------------------------------------------------------------------
if not SS.MS_UpdateButton then
  local MS_DEBUFF = "Arcane Dizziness"
  local MS_BUFFS  = {
    "Manastorm: Incantation Intensifier",
    "Manastorm: Long Haul Liquid",
    "Manastorm: Harm Repellant Remedy",
    "Manastorm: Rage Rush Solution",
    "Manastorm: Taunting Tonic",
  }

  function SS:EnsureMSButton()
    if self._msBtn then return self._msBtn end
    local btn = CreateFrame("Button", "SwiftSki_MSClick", UIParent, "UIPanelButtonTemplate,SecureActionButtonTemplate")
    btn:SetFrameStrata("DIALOG"); btn:SetToplevel(true)
    btn:SetSize(420,44); btn:SetPoint("CENTER"); btn:Hide()
    local text = _G[btn:GetName().."Text"]
    text:SetText("|cff32CD32CLICK:|r Manastorm 2h Buffs")
    text:SetFontObject(GameFontNormalLarge)
    text:SetShadowColor(0,0,0,1); text:SetShadowOffset(1,-1)
    btn:SetAttribute("type","macro")
    btn:SetAttribute("macrotext",
      "/cast Manastorm: Incantation Intensifier\n" ..
      "/cast Manastorm: Long Haul Liquid\n" ..
      "/cast Manastorm: Harm Repellant Remedy\n" ..
      "/cast Manastorm: Rage Rush Solution\n" ..
      "/cast Manastorm: Taunting Tonic"
    )
    btn:SetScript("PostClick", function(self)
      SS._msClickedThisEntry = true
      if InCombatLockdown() then
        self:SetAlpha(0); self:EnableMouse(false); SS._msHideQueued = true
      else
        self:Hide()
      end
    end)
    self._msBtn = btn
    return btn
  end

  -- Returns: hasDebuff(bool), expirationTime(number or nil)
  local function MS_HasEntryDebuff()
    for i=1,40 do
      local name, _, _, _, _, duration, expirationTime = UnitDebuff("player", i)
      if not name then break end
      if name == MS_DEBUFF then
        return true, (expirationTime or 0)
      end
    end
    return false, nil
  end

  -- Show once per debuff epoch; don't re-show across portals.
  function SS:MS_UpdateButton()
    local o = SwiftSkiDB and SwiftSkiDB.options
    if not (o and o.msBuffs and SS:IsAscensionRealm()) then
      if self._msBtn then self._msBtn:Hide() end
      return
    end

    local has, expTs = MS_HasEntryDebuff()
    local now = GetTime and GetTime() or 0

    if has then
      -- Refresh known expiration when it increases (newer reading)
      if expTs and (not SS._msDebuffExpire or expTs > SS._msDebuffExpire) then
        SS._msDebuffExpire = expTs
      end

      if not self._msShownForEpoch then
        local btn = self:EnsureMSButton()
        btn:SetAlpha(1); btn:EnableMouse(true); btn:Show()
        self._msShownForEpoch = true
      end
      -- If already shown and UI hid during loading, we intentionally do not force re-show.
    else
      -- Only reset epoch if we're truly past the stored expiration.
      if SS._msDebuffExpire and now >= (SS._msDebuffExpire - 0.5) then
        self._msShownForEpoch    = false
        self._msClickedThisEntry = false
        SS._msDebuffExpire       = nil
      end

      if self._msBtn then
        if InCombatLockdown() then
          self._msBtn:SetAlpha(0); self._msBtn:EnableMouse(false); SS._msHideQueued = true
        else
          self._msBtn:Hide()
        end
      end
    end
  end

  function SS:MS_WireEvents()
    if self._msEvt then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_AURA")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event, arg1)
      if not SS:IsAscensionRealm() then return end
      if event == "UNIT_AURA" and arg1 == "player" then
        local had        = SS._msHad or false
        local has, expTs = MS_HasEntryDebuff()
        local now        = GetTime and GetTime() or 0

        -- True new debuff if:
        --  (a) we didn't have it and prior epoch is over, or
        --  (b) expiration jumps forward noticeably (not portal jitter).
        local isNew = false
        if has and (not had) then
          if (not SS._msDebuffExpire) or now >= (SS._msDebuffExpire - 0.5) then
            isNew = true
          end
        elseif has and expTs and SS._msDebuffExpire and (expTs > SS._msDebuffExpire + 2) then
          isNew = true
        end

        if has and expTs then SS._msDebuffExpire = expTs end

        if isNew then
          SS._msClickedThisEntry = false
          self._msShownForEpoch  = false
          local t, d, h = 0, 5, CreateFrame("Frame")
          h:SetScript("OnUpdate", function(self, e)
            t = t + e
            if t >= d then
              self:SetScript("OnUpdate", nil); self:Hide()
              SS:MS_UpdateButton()
            end
          end)
        end

        SS._msHad = has
        SS:MS_UpdateButton()
        SS:CheckPrestigeAutoEquip()
      elseif event == "PLAYER_REGEN_ENABLED" then
        if SS._msHideQueued and SS._msBtn then
          SS._msHideQueued = nil
          SS._msBtn:SetAlpha(1); SS._msBtn:EnableMouse(true); SS._msBtn:Hide()
        end
      else
        SS:MS_UpdateButton(); SS:CheckPrestigeAutoEquip()
      end
    end)
    self._msEvt = f
  end
end

----------------------------------------------------------------------
-- Options panel (Ascension tab)
----------------------------------------------------------------------
function SS:BuildAscensionPanel(container)
  local o, asc = Opt(), self:IsAscensionRealm()
  if not asc then
    local box = self:AddSeparator(container, 8, -18, -8)
    local fs  = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -14)
    fs:SetText("|cff888888This page is only available on Ascension realms.|r")
    return
  end

  local box = self:AddSeparator(container, 8, -18, -8)
  local function NewCheck(name, label, tip, yOff)
    local cb = CreateFrame("CheckButton", name, container, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", box, "TOPLEFT", 14, yOff)
    cb._rawLabel, cb._rawTip = label, tip
    local txt = _G[name.."Text"]; if txt then txt:SetText(label) end
    return cb
  end

  local y = -18
  -- Auto Collect Appearance
  local chkCollect = NewCheck("SwiftSki_AutoCollect", "Auto Collect Appearance",
    "Automatically learns eligible appearances when obtained.", y)
  chkCollect:SetChecked(o.autoCollect)
  SetLabelColor(chkCollect)
  WireAsc(chkCollect, "Auto Collect Appearance", function(on)
    SwiftSkiDB.options.autoCollect = on
    if asc then SS:ToggleBagWatcher(on) end
  end)

  -- Fast Roulette (Elune only)
  y = y - 38
  local chkFR = NewCheck("SwiftSki_FastRoulette", "Fast Roulette (Elune)",
    "Accelerates the Elune roulette UI. Disabled on non-Elune realms.", y)
  chkFR:SetChecked(o.fastRoulette)
  local onElune = self:IsAscensionRealmName("elune")
  chkFR:SetEnabled(onElune)
  SetLabelColor(chkFR)
  WireAsc(chkFR, "Fast Roulette (Elune)", function(on)
    SwiftSkiDB.options.fastRoulette = on
    if asc then SS:ApplyFastRoulette(true) end
  end)

  -- Auto-equip Heirlooms
  y = y - 38
  local chkHL = NewCheck("SwiftSki_AutoHeirlooms", "Auto-equip Heirlooms (on prestige)",
    "When you prestige (level 1 + debuff), equips heirlooms + Shirt/Tabard.", y)
  chkHL:SetChecked(o.autoHeirlooms)
  SetLabelColor(chkHL)
  WireAsc(chkHL, "Auto-equip Heirlooms", function(on)
    SwiftSkiDB.options.autoHeirlooms = on
    if asc then SS:CheckPrestigeAutoEquip() end
  end)

  -- Auto-use MS Buffs
  y = y - 38
  local chkMS = NewCheck("SwiftSki_AutoMSBuffs", "Auto-use MS Buffs",
    "Shows a center button in Manastorm to apply your 2h buffs.", y)
  chkMS:SetChecked(o.msBuffs)
  SetLabelColor(chkMS)
  WireAsc(chkMS, "Auto-use MS Buffs", function(on)
    SwiftSkiDB.options.msBuffs = on
    if asc then SS:MS_UpdateButton() end
  end)

  SameFontLike(chkCollect, { chkFR, chkHL, chkMS })

  container:HookScript("OnShow", function()
    SetLabelColor(chkCollect)
    SetLabelColor(chkFR)
    SetLabelColor(chkHL)
    SetLabelColor(chkMS)
  end)
end

----------------------------------------------------------------------
-- Login wiring (Ascension only)
----------------------------------------------------------------------
do
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_LOGIN")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function(_, evt)
    if not SS:IsAscensionRealm() then return end
    local o = Opt()
    if evt == "PLAYER_LOGIN" then
      SS:ToggleBagWatcher(o.autoCollect)
      SS:ApplyFastRoulette(true)
      SS:MS_WireEvents(); SS:MS_UpdateButton(); SS:CheckPrestigeAutoEquip()
      PrintA(SS:teal("Auto Collect Appearance: ")..(o.autoCollect   and SS:lime("ON") or SS:red("OFF")))
      PrintA(SS:teal("Fast Roulette: ")        ..(o.fastRoulette  and SS:lime("ON") or SS:red("OFF")))
      PrintA(SS:teal("Auto-equip Heirlooms: ") ..(o.autoHeirlooms and SS:lime("ON") or SS:red("OFF")))
      PrintA(SS:teal("Auto-use MS Buffs: ")    ..(o.msBuffs       and SS:lime("ON") or SS:red("OFF")))
    else
      SS:MS_UpdateButton(); SS:CheckPrestigeAutoEquip()
    end
  end)
end