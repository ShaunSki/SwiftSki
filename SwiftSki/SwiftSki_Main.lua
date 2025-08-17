-- SwiftSki_Main.lua — Main tab + Auto-summon Companion + Missed-loot Notifier (Wrath 3.3.5a)

local SS = _G.SwiftSki
if not SS then return end

------------------------------------------------------------
-- Saved options (Main)
------------------------------------------------------------
local function Opt()
  _G.SwiftSkiDB = _G.SwiftSkiDB or { options = {} }
  local o = SwiftSkiDB.options
  if o.autoCompanion     == nil then o.autoCompanion     = true end
  if o.missedLootNotify  == nil then o.missedLootNotify  = true end -- Missed-loot Notifier
  return o
end

-- Tiny timer helper (no C_Timer in 3.3.5)
function SS:After(delay, fn)
  local f, t = CreateFrame("Frame"), 0
  f:SetScript("OnUpdate", function(_, e)
    t = t + e
    if t >= (delay or 0) then
      f:SetScript("OnUpdate", nil); f:Hide()
      if type(fn) == "function" then pcall(fn) end
    end
  end)
end

------------------------------------------------------------
-- Announcers / wiring
------------------------------------------------------------
local function MTag()  return "["..SS:lime("SwiftSki").."–"..SS:lime("Main").."] " end
local function Announce(label, on)
  SS:Chat(MTag()..label..": "..(on and SS:lime("ON") or SS:red("OFF")))
end
local function Wire(check, label, handler)
  if not check then return end
  check:SetScript("OnClick", function(selfBtn)
    local on = selfBtn:GetChecked() and true or false
    if handler then handler(selfBtn, on) end
    SS:PlayCheckbox(on)
    Announce(label, on)
  end)
end

------------------------------------------------------------
-- Reanchor tabs (unchanged)
------------------------------------------------------------
local function ReanchorTabsUnderTitle(boxFrame)
  if not SS or not SS.tabs or not SS.tabs[1] or not boxFrame then return end
  local first = SS.tabs[1]
  first:ClearAllPoints()
  first:SetPoint("BOTTOMLEFT", boxFrame, "TOPLEFT", 8, 0)
  for i = 2, #SS.tabs do
    local t = SS.tabs[i]
    t:ClearAllPoints()
    t:SetPoint("LEFT", SS.tabs[i-1], "RIGHT", -10, 0)
  end
end

------------------------------------------------------------
-- Checkbox label + tooltip coloring (green ON / red OFF / gray desc)
------------------------------------------------------------
local GREEN_HEX, RED_HEX, END_HEX = "|cff32CD32", "|cffff5555", "|r"
local GRAY_RGB = {0.8, 0.8, 0.8}

local function SetCheckLabelColor(cb, text, isOn)
  local fs = cb and (cb.Text or _G[cb:GetName().."Text"])
  if fs then fs:SetText((isOn and GREEN_HEX or RED_HEX)..text..END_HEX) end
end

local function ShowStateTooltip(cb)
  if not cb then return end
  local title = cb._rawLabel or ""
  local tip   = cb._rawTip   or ""
  local on    = cb:GetChecked()
  if not GameTooltip:IsOwned(cb) then GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
  else GameTooltip:ClearLines() end
  GameTooltip:AddLine((on and GREEN_HEX or RED_HEX)..title..END_HEX)
  if tip ~= "" then GameTooltip:AddLine(tip, GRAY_RGB[1], GRAY_RGB[2], GRAY_RGB[3], true) end
  GameTooltip:Show()
end

local function WireGreenRedTooltipLive(cb)
  if not cb then return end
  cb:HookScript("OnEnter", function(self)
    self.__lastChecked = self:GetChecked()
    ShowStateTooltip(self)
    self:SetScript("OnUpdate", function(s)
      if not s:IsMouseOver() then return end
      local now = s:GetChecked()
      if now ~= s.__lastChecked then
        s.__lastChecked = now
        SetCheckLabelColor(s, s._rawLabel or "", now)
        ShowStateTooltip(s)
      end
    end)
  end)
  cb:HookScript("OnLeave", function(self)
    self:SetScript("OnUpdate", nil)
    GameTooltip:Hide()
  end)
  cb:HookScript("OnClick", function(self)
    if GameTooltip:IsOwned(self) then ShowStateTooltip(self) end
  end)
end

------------------------------------------------------------
-- UI: Main page
------------------------------------------------------------
function SS:BuildMainPanel(container)
  local o = Opt()
  local box = self:AddSeparator(container, 8, -18, -8)
  ReanchorTabsUnderTitle(box)

  local function NewCheck(name, label, tip, yOff)
    local cb = CreateFrame("CheckButton", name, container, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", box, "TOPLEFT", 14, yOff)
    cb._rawLabel, cb._rawTip = label, tip
    local fs = _G[name.."Text"]; if fs then fs:SetText(label) end
    return cb, label
  end

  local y = -18

  -- Auto-summon Companion
  self.chkComp, self._compLabelText = NewCheck("SwiftSki_AutoCompanion",
    "Auto-summon Companion",
    "If no vanity pet is active, out of combat and not mounted, summons a learned companion.",
    y)
  self.chkComp:SetChecked(o.autoCompanion)
  SetCheckLabelColor(self.chkComp, self._compLabelText, o.autoCompanion)
  WireGreenRedTooltipLive(self.chkComp)
  Wire(self.chkComp, "Auto-summon Companion", function(_, on)
    SwiftSkiDB.options.autoCompanion = on
    SetCheckLabelColor(self.chkComp, self._compLabelText, on)
    if GameTooltip:IsOwned(self.chkComp) then ShowStateTooltip(self.chkComp) end
    SS._companionNextTry = 0
    SS:TryAutoCompanion(true)
  end)

  y = y - 38

  -- Missed-loot Notifier
  self.chkMissed, self._missedLabelText = NewCheck("SwiftSki_MissedLoot",
    "Missed-loot Notifier",
    "When your bags are full, prints which item(s) were missed and from which mob/corpse, and augments the full-inventory error with the item name.",
    y)
  self.chkMissed:SetChecked(o.missedLootNotify)
  SetCheckLabelColor(self.chkMissed, self._missedLabelText, o.missedLootNotify)
  WireGreenRedTooltipLive(self.chkMissed)
  Wire(self.chkMissed, "Missed-loot Notifier", function(_, on)
    SwiftSkiDB.options.missedLootNotify = on
    SetCheckLabelColor(self.chkMissed, self._missedLabelText, on)
    if GameTooltip:IsOwned(self.chkMissed) then ShowStateTooltip(self.chkMissed) end
    SS:MissedLoot_SetEnabled(on)
  end)

  SS._companionCD = 0
  SS:TryAutoCompanion(true)
end

------------------------------------------------------------
-- Companion helpers + memory
------------------------------------------------------------
local function HasCritterActive()
  if not GetNumCompanions then return false end
  local n = GetNumCompanions("CRITTER") or 0
  for i=1,n do local _,_,_,_,active = GetCompanionInfo("CRITTER", i); if active then return true end end
  return false
end

local function ActiveCritterIndexAndSpell()
  if not GetNumCompanions then return nil end
  local n = GetNumCompanions("CRITTER") or 0
  for i=1,n do
    local _, _, spellID, _, active = GetCompanionInfo("CRITTER", i)
    if active then return i, spellID end
  end
  return nil
end

local function FindCompanionIndexBySpellID(spellID)
  if not spellID or not GetNumCompanions then return nil end
  local n = GetNumCompanions("CRITTER") or 0
  for i=1,n do local _,_,sID = GetCompanionInfo("CRITTER", i); if sID == spellID then return i end end
  return nil
end

local function FirstCritterIndex()
  if not GetNumCompanions then return nil end
  local n = GetNumCompanions("CRITTER") or 0
  if n == 0 then return nil end
  for i=1,n do local _,_,_,_,active = GetCompanionInfo("CRITTER", i); if not active then return i end end
  return 1
end

------------------------------------------------------------
-- Feature: Auto-summon Companion (prefers remembered pet)
------------------------------------------------------------
function SS:TryAutoCompanion(force)
  local o = SwiftSkiDB and SwiftSkiDB.options
  if not o or not o.autoCompanion then return end
  if InCombatLockdown() or IsMounted() then return end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end

  local now = GetTime()
  self._companionNextTry = self._companionNextTry or 0
  if not force and now < self._companionNextTry then return end
  if HasCritterActive() then return end

  local idx = nil
  if SwiftSkiDB and SwiftSkiDB.lastCompanionSpellID then
    idx = FindCompanionIndexBySpellID(SwiftSkiDB.lastCompanionSpellID)
  end
  if not idx then idx = FirstCritterIndex() end

  if idx then
    CallCompanion("CRITTER", idx)
    self._companionNextTry = now + 15
  else
    self._companionNextTry = now + 30
  end
end

function SS:WireCompanionEvents()
  if self._compWatch then return end
  local f = CreateFrame("Frame")
  f:RegisterEvent("COMPANION_UPDATE")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:RegisterEvent("PLAYER_ALIVE")
  f:RegisterEvent("PLAYER_UNGHOST")

  f:SetScript("OnEvent", function(_, event, arg1)
    local _, spellID = ActiveCritterIndexAndSpell()
    if spellID then SwiftSkiDB.lastCompanionSpellID = spellID end

    if event == "COMPANION_UPDATE" and arg1 == "CRITTER" then
      if SwiftSkiDB and SwiftSkiDB.options and SwiftSkiDB.options.autoCompanion then
        if not InCombatLockdown() and not IsMounted() then
          if not HasCritterActive() then
            SS._companionNextTry = 0
            SS:TryAutoCompanion(true)
          end
        end
      end

    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
      SS._companionNextTry = 0
      SS:After(0.0, function() SS:TryAutoCompanion(true) end)
      SS:After(0.8, function() SS:TryAutoCompanion(true) end)
      SS:After(2.0, function() SS:TryAutoCompanion(true) end)

    else
      SS:TryAutoCompanion()
    end
  end)
  self._compWatch = f
end

-- Login wiring for Main
do
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_LOGIN")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function(_, evt)
    local o = Opt()
    if evt == "PLAYER_LOGIN" then
      SS:WireCompanionEvents()
      local _, spellID = ActiveCritterIndexAndSpell()
      if spellID then SwiftSkiDB.lastCompanionSpellID = spellID end
      SS:TryAutoCompanion(true)
      Announce("Auto-summon Companion", o.autoCompanion)

      -- Missed-loot notifier at login
      SS:MissedLoot_SetEnabled(o.missedLootNotify)
      Announce("Missed-loot Notifier", o.missedLootNotify)
    else
      SS:TryAutoCompanion()
    end
  end)
end

------------------------------------------------------------
-- MISSED-LOOT NOTIFIER: bag-full + won-item (monster loot only, de-duplicated)
------------------------------------------------------------
do
  SS._ml = {
    enabled = true,

    lastLootOpenTime = 0,
    lootActive       = false,   -- inside a corpse loot window
    currentMob       = nil,

    totalSlots   = 0,
    clearedSlots = 0,
    slotLinks    = {},          -- [slot]=link at LOOT_OPENED
    linkQuality  = {},          -- [link]=quality (rarity) captured at LOOT_OPENED

    lastWon = { t = 0, link = nil, mob = nil, reported = false, quality = nil },

    reported        = {},       -- [link]=true for current loot session (dedupe)
    _hookedUIErrors = false,

    _voCooldownUntil = 0,       -- anti-spam for our sound
  }

  local function PrintMissed(link, mob)
    if not link then return end
    SS:Chat(MTag()..SS:red("Missed Item ")..link..SS:red(" on ")..(mob or "corpse")..SS:red("."))
  end

  local function NonMonsterUIsOpen()
    if _G.MerchantFrame and MerchantFrame:IsShown() then return true end
    if _G.BankFrame and BankFrame:IsShown() then return true end
    if _G.MailFrame and MailFrame:IsShown() then return true end
    if _G.TradeFrame and TradeFrame:IsShown() then return true end
    if _G.AuctionFrame and AuctionFrame:IsShown() then return true end
    if _G.CraftFrame and CraftFrame:IsShown() then return true end
    if _G.TradeSkillFrame and TradeSkillFrame:IsShown() then return true end
    return false
  end

  local function InMonsterLootContext()
    local now = GetTime()
    if SS._ml.lootActive then return true end
    if (now - (SS._ml.lastLootOpenTime or 0)) <= 5 then return true end
    if SS._ml.lastWon.link and (now - (SS._ml.lastWon.t or 0)) <= 10 then return true end
    return false
  end

  local function addUnreported(arr, link, quality)
    if link and not SS._ml.reported[link] then
      table.insert(arr, { link = link, q = quality or 0 })
    end
  end

  local function CollectUnreportedTop(maxN)
    local arr = {}
    for _, link in pairs(SS._ml.slotLinks or {}) do
      addUnreported(arr, link, SS._ml.linkQuality[link] or 0)
    end
    if SS._ml.lastWon.link and not SS._ml.lastWon.reported
       and (GetTime() - (SS._ml.lastWon.t or 0) < 10) then
      addUnreported(arr, SS._ml.lastWon.link, SS._ml.lastWon.quality or 0)
    end
    table.sort(arr, function(a,b)
      if a.q ~= b.q then return a.q > b.q end
      return (a.link or "") < (b.link or "")
    end)
    local out = {}
    for i=1, math.min(maxN or #arr, #arr) do out[i] = arr[i] end
    return out
  end

  -- Single soft cue using Blizzard sound id (plays only if Error Speech is OFF)
  local function PlayInventoryFullCue()
    local now = GetTime()
    if now < (SS._ml._voCooldownUntil or 0) then return end
    if GetCVar and GetCVar("Sound_EnableErrorSpeech") == "1" then return end
    if PlaySound then pcall(PlaySound, 9550) end -- "Inventory is full" VO
    SS._ml._voCooldownUntil = now + 2.5
  end

  -- Hook UIErrorsFrame to show augmented lines and suppress duplicates.
  local function HookUIErrorsAugment()
    if SS._ml._hookedUIErrors or not UIErrorsFrame then return end
    local orig = UIErrorsFrame:GetScript("OnEvent")
    if not orig then return end
    UIErrorsFrame._SwiftSki_OrigOnEvent = orig

    UIErrorsFrame:SetScript("OnEvent", function(frame, event, ...)
      if event == "UI_ERROR_MESSAGE" and SS._ml.enabled then
        local a1, a2 = ...
        local err = a2 or a1
        if type(err) ~= "number" then
          if not NonMonsterUIsOpen() and InMonsterLootContext() then
            local invFull = (err == ERR_INV_FULL)
              or (type(err) == "string" and string.find(err, ERR_INV_FULL or "Inventory is full", 1, true))
              or (err == "Inventory is full.")
            if invFull then
              local toShow = CollectUnreportedTop(3)
              if #toShow > 0 then
                for _, it in ipairs(toShow) do
                  local msg = (type(err)=="string" and err or (ERR_INV_FULL or "Inventory is full.")) ..
                              " — Couldn't loot " .. it.link
                  frame:AddMessage(msg, 1, 0.35, 0.35, nil, 3.0)
                  SS._ml.reported[it.link] = true
                  if SS._ml.lastWon.link == it.link then SS._ml.lastWon.reported = true end
                  PrintMissed(it.link, SS._ml.currentMob)
                end
                PlayInventoryFullCue()
                return -- consume; no default duplicate
              else
                return -- nothing new; still consume to avoid default spam
              end
            end
          end
        end
      end
      return UIErrorsFrame._SwiftSki_OrigOnEvent(frame, event, ...)
    end)

    SS._ml._hookedUIErrors = true
  end

  function SS:MissedLoot_Init()
    if self._mlEvt then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("LOOT_OPENED")
    f:RegisterEvent("LOOT_SLOT_CLEARED")
    f:RegisterEvent("LOOT_CLOSED")
    f:RegisterEvent("CHAT_MSG_LOOT")
    f:RegisterEvent("UI_ERROR_MESSAGE")

    f:SetScript("OnEvent", function(_, event, ...)
      if not SS._ml.enabled then return end

      if event == "LOOT_OPENED" then
        local now = GetTime()
        SS._ml.lastLootOpenTime = now
        SS._ml.lootActive = true

        local name = nil
        if UnitExists("target") and UnitIsDead("target") then name = UnitName("target") end
        if (not name) and UnitExists("mouseover") and UnitIsDead("mouseover") then name = UnitName("mouseover") end
        SS._ml.currentMob  = name

        wipe(SS._ml.slotLinks)
        wipe(SS._ml.linkQuality)
        wipe(SS._ml.reported)
        SS._ml.totalSlots   = GetNumLootItems() or 0
        SS._ml.clearedSlots = 0
        SS._ml.lastWon.t, SS._ml.lastWon.link, SS._ml.lastWon.mob, SS._ml.lastWon.reported, SS._ml.lastWon.quality
          = 0, nil, nil, false, nil

        for i=1,(SS._ml.totalSlots or 0) do
          local link = GetLootSlotLink(i)
          local _, _, _, quality = GetLootSlotInfo(i)
          if link then
            SS._ml.slotLinks[i]   = link
            SS._ml.linkQuality[link] = quality or 0
          end
        end

      elseif event == "LOOT_SLOT_CLEARED" then
        local slot = ...
        SS._ml.clearedSlots = (SS._ml.clearedSlots or 0) + 1

      elseif event == "LOOT_CLOSED" then
        SS._ml.totalSlots, SS._ml.clearedSlots = 0, 0
        wipe(SS._ml.slotLinks)
        SS._ml.currentMob = nil
        SS._ml.lootActive = false

      elseif event == "CHAT_MSG_LOOT" then
        local msg = ...
        local link = msg:match("|Hitem:.-|h%[.-%]|h")
        if link and (msg:find("You won") or (LOOT_ROLL_WON and msg:find(LOOT_ROLL_WON))) then
          SS._ml.lastWon.t = GetTime()
          SS._ml.lastWon.link = link
          SS._ml.lastWon.mob  = SS._ml.currentMob
          local _, _, q = GetItemInfo(link)
          SS._ml.lastWon.quality = q or 0
          SS._ml.lastWon.reported = false
        end

      elseif event == "UI_ERROR_MESSAGE" then
        -- Fallback: print any still-unreported items to chat
        local a1, a2 = ...
        local err = a2 or a1
        if type(err) == "number" then return end
        if NonMonsterUIsOpen() or not InMonsterLootContext() then return end

        local invFull = (err == ERR_INV_FULL)
          or (type(err) == "string" and string.find(err, ERR_INV_FULL or "Inventory is full", 1, true))
          or (err == "Inventory is full.")
        if invFull then
          local mob = SS._ml.currentMob
          local toShow = CollectUnreportedTop(99)
          for _, it in ipairs(toShow) do
            if not SS._ml.reported[it.link] then
              PrintMissed(it.link, mob)
              SS._ml.reported[it.link] = true
            end
          end
          if SS._ml.lastWon.link and not SS._ml.lastWon.reported
             and (GetTime() - (SS._ml.lastWon.t or 0) < 10) then
            PrintMissed(SS._ml.lastWon.link, (SS._ml.lastWon.mob or mob))
            SS._ml.lastWon.reported = true
          end
        end
      end
    end)

    self._mlEvt = f
    HookUIErrorsAugment()
  end

  function SS:MissedLoot_Dispose()
    if self._mlEvt then
      local f = self._mlEvt
      f:Hide()
      f:UnregisterAllEvents()
      f:SetScript("OnEvent", nil)
      self._mlEvt = nil
    end
  end

  function SS:MissedLoot_SetEnabled(on)
    SS._ml.enabled = on and true or false
    if on then SS:MissedLoot_Init() else SS:MissedLoot_Dispose() end
  end
end
