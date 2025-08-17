-- SwiftSki_Questing.lua — Questing tab
-- Auto-accept / Auto-complete with robust bulk-accept (no re-open calls).
-- Accepts ALL available quests from the currently open Gossip/Greeting list,
-- one after another, by staying within the same UI session (no InteractUnit/retarget).
-- Suppresses duplicate "already on that quest" spam in chat and UI error text.

local SS = _G.SwiftSki

-- Fallback: tiny After helper if not provided elsewhere
if SS and not SS.After then
  function SS:After(delay, fn)
    local f, t = CreateFrame("Frame"), 0
    f:SetScript("OnUpdate", function(self, e)
      t = t + e
      if t >= (delay or 0) then self:SetScript("OnUpdate", nil); self:Hide(); pcall(fn) end
    end)
  end
end

------------------------------------------------------------
-- Saved options
------------------------------------------------------------
local function QOpt()
  _G.SwiftSkiDB = _G.SwiftSkiDB or { options = {} }
  local o = SwiftSkiDB.options
  if o.autoAccept        == nil then o.autoAccept        = true  end
  if o.autoTurnIn        == nil then o.autoTurnIn        = true  end   -- now “Auto-Complete Quests”
  if o.showAbandonAllBtn == nil then o.showAbandonAllBtn = true  end

  -- Reward preferences
  o.qReward = o.qReward or {}
  if o.qReward.autoChoose == nil then o.qReward.autoChoose = false end
  o.qReward.attr     = o.qReward.attr     or "ANY"        -- Strength/Agility/Stamina/Intellect/Spirit/ANY
  o.qReward.armor    = o.qReward.armor    or "ANY"        -- Cloth/Leather/Mail/Plate/ANY
  o.qReward.strategy = o.qReward.strategy or "ATTRIBUTE"  -- ATTRIBUTE or VENDOR
  return o
end

------------------------------------------------------------
-- Chat / colors / UI helpers
------------------------------------------------------------
local function Yellow(s) return "|cffffd100"..(s or "").."|r" end
local function Tag() return "["..SS:lime("SwiftSki").."–"..Yellow("Questing").."] " end
local function QPrint(msg) SS:Chat(Tag()..msg) end

local GOLD, RED, END = "|cffffd100", "|cffff5555", "|r"

local function SetQuestLabel(cb, baseText, isOn)
  local fs = cb and (_G[cb:GetName().."Text"] or cb.Text or cb.text)
  if fs then fs:SetText((isOn and GOLD or RED)..baseText..END) end
end

local function WireGoldRedTooltip(cb, titleText, descText)
  if not cb then return end
  cb._tipTitle, cb._tipDesc = titleText, descText
  local function refresh(self)
    if not GameTooltip:IsOwned(self) then GameTooltip:SetOwner(self,"ANCHOR_RIGHT") else GameTooltip:ClearLines() end
    GameTooltip:AddLine((self:GetChecked() and GOLD or RED)..(self._tipTitle or "")..END)
    if self._tipDesc and self._tipDesc ~= "" then GameTooltip:AddLine(self._tipDesc, .8,.8,.8, true) end
    GameTooltip:Show()
  end
  cb._refreshTooltip = refresh
  cb:EnableMouse(true)
  cb:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); self:_refreshTooltip() end)
  cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  cb:HookScript("OnClick", function(self) if self._refreshTooltip then self:_refreshTooltip() end end)
end

------------------------------------------------------------
-- Command Board detector
------------------------------------------------------------
local function IsCommandBoard()
  local name = UnitName("npc"); if not name then return false end
  local s = name:lower()
  return (s:find("warchief") and s:find("board"))
      or (s:find("hero") and s:find("call") and s:find("board"))
      or false
end

------------------------------------------------------------
-- Reward chooser helpers (attribute + armor filters)
------------------------------------------------------------
local ARMOR_CLASS = _G.ARMOR or "Armor"
local ATTR_INFO = {
  ANY       = { patt = nil, keys = {} },
  Strength  = { patt = "[+%-]?%d+%s+[Ss]trength",  keys = { "ITEM_MOD_STRENGTH",  "ITEM_MOD_STRENGTH_SHORT"  } },
  Agility   = { patt = "[+%-]?%d+%s+[Aa]gility",   keys = { "ITEM_MOD_AGILITY",   "ITEM_MOD_AGILITY_SHORT"   } },
  Stamina   = { patt = "[+%-]?%d+%s+[Ss]tamina",   keys = { "ITEM_MOD_STAMINA",   "ITEM_MOD_STAMINA_SHORT"   } },
  Intellect = { patt = "[+%-]?%d+%s+[Ii]ntellect", keys = { "ITEM_MOD_INTELLECT", "ITEM_MOD_INTELLECT_SHORT" } },
  Spirit    = { patt = "[+%-]?%d+%s+[Ss]pirit",    keys = { "ITEM_MOD_SPIRIT",    "ITEM_MOD_SPIRIT_SHORT"    } },
}

local function GetItemIDFromLink(link) return link and tonumber(link:match("item:(%d+)") or 0) or 0 end
local function GetVendorPriceByLink(link)
  local id = GetItemIDFromLink(link); if id == 0 then return 0 end
  local _,_,_,_,_,_,_,_,_,_, sell = GetItemInfo(id); return sell or 0
end

-- Try to read the attribute amount from GetItemStats; fallback to tooltip parse.
local _tip = nil
local function EnsureTip()
  if _tip then return _tip end
  _tip = CreateFrame("GameTooltip", "SwiftSki_QRewardTip", nil, "GameTooltipTemplate")
  _G.SwiftSki_QRewardTipTextLeft1  = _G.SwiftSki_QRewardTipTextLeft1  or _G["SwiftSki_QRewardTipTextLeft1"]
  return _tip
end

local function ParseAttrFromTooltip(link, info)
  local tip = EnsureTip()
  tip:SetOwner(UIParent, "ANCHOR_NONE")
  tip:ClearLines()
  tip:SetHyperlink(link)
  local patt = info.patt
  if not patt then return 0 end
  local sum = 0
  for i = 1, 15 do
    local line = _G["SwiftSki_QRewardTipTextLeft"..i]
    if line then
      local t = line:GetText()
      if t and t ~= "" then
        local v = string.match(t, patt)
        if v then
          local num = tonumber((v:gsub("[^%-%d]", "")) or 0) or 0
          sum = sum + num
        end
      end
    end
  end
  return sum
end

local function GetAttrScore(link, attrName)
  if not link or attrName == "ANY" then return 0 end
  local info = ATTR_INFO[attrName]; if not info then return 0 end

  local score = 0
  local stats = GetItemStats(link)
  if type(stats) == "table" then
    for _, key in ipairs(info.keys or {}) do
      local v = stats[key]
      if v and type(v) == "number" then score = score + v end
    end
  end
  if score > 0 then return score end

  -- Fallback: tooltip parse (covers older clients)
  return ParseAttrFromTooltip(link, info) or 0
end

local function ArmorMatches(link, wanted)
  if not wanted or wanted == "ANY" then return true end
  local name, _, _, _, _, itemClass, itemSubClass = GetItemInfo(link or "")
  if not name then return false end
  if (itemClass == ARMOR_CLASS) and (itemSubClass == wanted) then return true end
  return false
end

-- Choose with filters: first restrict by Armor, then maximize chosen Attribute; ties by vendor value.
local function ChooseRewardIndex_ByFilters(attrName, armorType)
  local n = GetNumQuestChoices() or 0
  if n <= 0 then return 1 end

  -- Pass 1: find candidates that match armor filter (if any)
  local candidates = {}
  if armorType and armorType ~= "ANY" then
    for i = 1, n do
      local link = GetQuestItemLink("choice", i)
      if ArmorMatches(link, armorType) then table.insert(candidates, i) end
    end
  end
  -- If none matched, consider all
  if #candidates == 0 then for i = 1, n do table.insert(candidates, i) end end

  -- If attr = ANY, fall back to vendor value (within candidate set)
  if attrName == "ANY" then
    local bestI, bestV = candidates[1], -1
    for _, i in ipairs(candidates) do
      local link = GetQuestItemLink("choice", i)
      local v = GetVendorPriceByLink(link)
      if v > bestV then bestV, bestI = v, i end
    end
    return bestI or 1
  end

  -- Otherwise, maximize the attribute; break ties with vendor value
  local bestI, bestScore, bestV = candidates[1], -math.huge, -1
  for _, i in ipairs(candidates) do
    local link = GetQuestItemLink("choice", i)
    local score = GetAttrScore(link, attrName) or 0
    local v = GetVendorPriceByLink(link) or 0
    if (score > bestScore) or (score == bestScore and v > bestV) then
      bestScore, bestV, bestI = score, v, i
    end
  end

  -- If everything scored 0 (no stat present), fallback to vendor value among candidates
  if bestScore <= 0 then
    local altI, altV = candidates[1], -1
    for _, i in ipairs(candidates) do
      local link = GetQuestItemLink("choice", i)
      local v = GetVendorPriceByLink(link)
      if v > altV then altV, altI = v, i end
    end
    return altI or 1
  end

  return bestI or 1
end

------------------------------------------------------------
-- Abandon All
------------------------------------------------------------
local Abandon = { running=false, total=0, done=0 }
local function CountAbandonable()
  local n = GetNumQuestLogEntries() or 0; local q=0
  for i=1,n do local _,_,_,_,hdr=GetQuestLogTitle(i); if not hdr then q=q+1 end end
  return q
end
local function AbandonNext()
  local n = GetNumQuestLogEntries() or 0
  for i=n,1,-1 do local _,_,_,_,hdr=GetQuestLogTitle(i); if not hdr then
    SelectQuestLogEntry(i); if SetAbandonQuest then SetAbandonQuest() end
    if StaticPopup_Hide then StaticPopup_Hide("ABANDON_QUEST") end
    AbandonQuest(); Abandon.done = Abandon.done + 1; return true end end
  return false
end
local function AbandonAll_Start()
  if Abandon.running then return end
  local t = CountAbandonable(); if t<=0 then QPrint(SS:teal("No quests to abandon.")); return end
  Abandon.running, Abandon.total, Abandon.done = true, t, 0
  QPrint(SS:red("Abandon ALL").." started ("..t.." quests).")
  AbandonNext()
end
local function AbandonAll_Stop()
  if Abandon.running then QPrint(SS:lime("Abandon ALL complete.").." ("..Abandon.done.." removed)") end
  Abandon.running = false
end
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["SSOL_ABANDON_ALL"] = {
  text="Abandon ALL quests?\n\nThis will remove every quest in your log.",
  button1=YES, button2=NO, OnAccept=function() AbandonAll_Start() end,
  timeout=0, whileDead=1, hideOnEscape=1, preferredIndex=3,
}
local AbandonBtn
local function EnsureAbandonAllButton()
  local show = QOpt().showAbandonAllBtn
  if not show then if AbandonBtn then AbandonBtn:Hide() end; return end
  if not QuestLogFrame then return end
  if not AbandonBtn then
    AbandonBtn = CreateFrame("Button","SwiftSki_AbandonAllButton",QuestLogFrame,"UIPanelButtonTemplate")
    AbandonBtn:SetSize(120,22)
    local track=_G.QuestLogFrameTrackButton
    if track then AbandonBtn:SetPoint("LEFT",track,"RIGHT",6,0)
    else AbandonBtn:SetPoint("BOTTOMRIGHT",QuestLogFrame,"BOTTOMRIGHT",-38,44) end
    AbandonBtn:SetText("Abandon All")
    AbandonBtn:SetScript("OnClick", function()
      local c=CountAbandonable(); if c<=0 then QPrint(SS:teal("No quests to abandon.")); return end
      StaticPopupDialogs["SSOL_ABANDON_ALL"].text = ("Abandon ALL quests?\n\nThis will remove |cffff5555%d|r quests from your log."):format(c)
      StaticPopup_Show("SSOL_ABANDON_ALL")
    end)
    if SS.AttachTip then SS:AttachTip(AbandonBtn,"Abandon All","Remove every quest in your log. Shows a confirmation first.") end
  end
  AbandonBtn:Show()
end

------------------------------------------------------------
-- Completed-first detection (turn-ins)
------------------------------------------------------------
local function TitleLooksCompleted(title)
  if not title then return false end
  local t = title:lower()
  if t:find("%(complete%)",1,true) then return true end
  if _G.COMPLETE then local c=tostring(_G.COMPLETE):lower(); if c~="" and t:find(c,1,true) then return true end end
  return false
end
local function Gossip_ClickCompleted_Robust()
  local cnt = (GetNumGossipActiveQuests and GetNumGossipActiveQuests()) or 0
  if cnt<=0 then return false end
  local data={GetGossipActiveQuests()}; if #data==0 then return false end
  local stride=6; if (#data%6)~=0 and (#data%5)==0 then stride=5 end
  for i=1,cnt do
    local base=(i-1)*stride; local title=data[base+1]; local isComp=(stride==6) and data[base+6] or nil
    if (isComp==true) or (type(isComp)=="number" and isComp~=0) or TitleLooksCompleted(title) then
      SelectGossipActiveQuest(i); return true
    end
  end
  if cnt==1 then SelectGossipActiveQuest(1); return true end
  return false
end
local function Greeting_ClickNextCompleted()
  local total=GetNumActiveQuests() or 0
  for i=1,total do local title,done=GetActiveTitle(i); if done or TitleLooksCompleted(title) then SelectActiveQuest(i); return true end end
  if total==1 then SelectActiveQuest(1); return true end
  return false
end

------------------------------------------------------------
-- Bulk accept (in-session, no re-open)
------------------------------------------------------------
local QState = {
  blockTurnInUntil = 0,
  recentAccepted   = {},   -- [title]=expire
  lastAutoAcceptAt = 0,    -- for suppression window
  bulk = { active=false, tried=nil, deadline=0, cycles=0 },
}

local function TurnInBlocked() return GetTime() < (QState.blockTurnInUntil or 0) end

local function RememberAcceptedTitle(title)
  if title and title ~= "" then QState.recentAccepted[title] = GetTime() + 8.0 end
end
local function WasJustAccepted(title)
  local t = title and QState.recentAccepted[title]
  return t and (GetTime() < t)
end

local function IsQuestInLogByTitle(title)
  if not title or title=="" then return false end
  local n = GetNumQuestLogEntries() or 0
  for i=1,n do local t,_,_,_,hdr=GetQuestLogTitle(i); if not hdr and t==title then return true end end
  return false
end

-- Duplicate text suppression (sound unaffected)
local function ShouldSuppressAlreadyMsg(msg)
  if not msg then return false end
  local m = tostring(msg)
  if m == ERR_QUEST_ALREADY_ON or m:lower():find("already on that quest",1,true) then
    return (GetTime() - (QState.lastAutoAcceptAt or 0)) < 5.0
  end
  return false
end

local function CountGossipAvailable()
  local n = (GetNumGossipAvailableQuests and GetNumGossipAvailableQuests()) or 0
  if n<=0 then return 0 end
  local data = { GetGossipAvailableQuests() }
  if #data==0 then return 0 end
  local stride = math.max(1, math.floor(#data / n))
  local count = 0
  for i=1,n do
    local title = data[(i-1)*stride + 1]
    if title and title~="" and not IsQuestInLogByTitle(title) and not WasJustAccepted(title)
       and not (QState.bulk.tried and QState.bulk.tried[title]) then
      count = count + 1
    end
  end
  return count
end
local function CountGreetingAvailable()
  local n = GetNumAvailableQuests() or 0
  if n<=0 then return 0 end
  local count = 0
  for i=1,n do
    local title = GetAvailableTitle(i)
    if title and title~="" and not IsQuestInLogByTitle(title) and not WasJustAccepted(title)
       and not (QState.bulk.tried and QState.bulk.tried[title]) then
      count = count + 1
    end
  end
  return count
end

-- Select next one from the currently visible list (Gossip/Greeting)
local function SelectNextFromGossip()
  local n = (GetNumGossipAvailableQuests and GetNumGossipAvailableQuests()) or 0
  if n<=0 then return false end
  local data = { GetGossipAvailableQuests() }
  if #data==0 then return false end
  local stride = math.max(1, math.floor(#data / n))
  for i=1,n do
    local title = data[(i-1)*stride + 1]
    if title and title~=""
       and not IsQuestInLogByTitle(title)
       and not WasJustAccepted(title)
       and not (QState.bulk.tried and QState.bulk.tried[title]) then
      QState.bulk.tried[title] = true
      QState.lastAutoAcceptAt = GetTime()
      SelectGossipAvailableQuest(i) -- opens QUEST_DETAIL
      return true
    end
  end
  return false
end

local function SelectNextFromGreeting()
  local n = GetNumAvailableQuests() or 0
  if n<=0 then return false end
  for i=1,n do
    local title = GetAvailableTitle(i)
    if title and title~=""
       and not IsQuestInLogByTitle(title)
       and not WasJustAccepted(title)
       and not (QState.bulk.tried and QState.bulk.tried[title]) then
      QState.bulk.tried[title] = true
      QState.lastAutoAcceptAt = GetTime()
      SelectAvailableQuest(i) -- opens QUEST_DETAIL
      return true
    end
  end
  return false
end

-- Bulk pump: runs entirely within the currently-open panels (no re-open)
local function BulkPump()
  if not QState.bulk.active then return end
  if GetTime() > (QState.bulk.deadline or 0) then QState.bulk.active=false; return end
  QState.bulk.cycles = (QState.bulk.cycles or 0) + 1

  -- If detail is shown, accept it (guard double-accept)
  if QuestFrame and QuestFrame:IsShown()
     and QuestFrameDetailPanel and QuestFrameDetailPanel:IsShown() then
    local title = (GetTitleText and GetTitleText()) or (QuestInfoTitleText and QuestInfoTitleText:GetText())
    if title and not IsQuestInLogByTitle(title) then
      AcceptQuest()
      RememberAcceptedTitle(title)
    end
    -- Let UI bounce back to list, then continue
    SS:After(0.06, BulkPump)
    return
  end

  -- If a list is visible, pick the next one; else stop
  local progressed = false
  if GossipFrame and GossipFrame:IsShown() then
    if CountGossipAvailable() > 0 then
      progressed = SelectNextFromGossip()
    end
  elseif QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown() then
    if CountGreetingAvailable() > 0 then
      progressed = SelectNextFromGreeting()
    end
  else
    QState.bulk.active = false
    return
  end

  if progressed then
    SS:After(0.06, BulkPump)
  else
    -- No more selectable quests in the current list, stop.
    QState.bulk.active = false
  end
end

local function StartBulkAccept()
  QState.bulk.active   = true
  QState.bulk.tried    = {}
  QState.bulk.deadline = GetTime() + 6.0
  QState.bulk.cycles   = 0
  BulkPump()
end

------------------------------------------------------------
-- Retry pump (completed-first)
------------------------------------------------------------
local _pumpActive, _pumpDeadline = false, 0
local function TryAutoTurnInOnce()
  if TurnInBlocked() then return end
  if GossipFrame and GossipFrame:IsShown() then if Gossip_ClickCompleted_Robust() then return end end
  if QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown() then if Greeting_ClickNextCompleted() then return end end
end
local function StartTurnInPump()
  if _pumpActive then return end
  _pumpActive, _pumpDeadline = true, GetTime()+2.0
  local function step()
    if not _pumpActive then return end
    TryAutoTurnInOnce()
    if GetTime() < _pumpDeadline then SS:After(0.15, step) else _pumpActive=false end
  end
  SS:After(0.05, step)
end

------------------------------------------------------------
-- Events & filters
------------------------------------------------------------
function SS:Quest_WireEvents()
  if self._questEvt then return end
  local f = CreateFrame("Frame")
  f:RegisterEvent("GOSSIP_SHOW")
  f:RegisterEvent("GOSSIP_CLOSED")
  f:RegisterEvent("QUEST_GREETING")
  f:RegisterEvent("QUEST_DETAIL")
  f:RegisterEvent("QUEST_PROGRESS")
  f:RegisterEvent("QUEST_COMPLETE")
  f:RegisterEvent("QUEST_FINISHED")
  f:RegisterEvent("QUEST_LOG_UPDATE")
  f:RegisterEvent("QUEST_ACCEPTED")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("UI_ERROR_MESSAGE")

  if not SS._SwiftSkiQuestFiltersInstalled then
    SS._SwiftSkiQuestFiltersInstalled = true
    -- Hide the chat system line during our window
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
      if ShouldSuppressAlreadyMsg(msg) then return true end
      return false
    end)
    -- Swallow red UI error text (do not alter sound)
    if UIErrorsFrame and not UIErrorsFrame._SwiftSkiOnEventHooked then
      UIErrorsFrame._SwiftSkiOnEventHooked = true
      local _origOnEvent = UIErrorsFrame:GetScript("OnEvent")
      UIErrorsFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "UI_ERROR_MESSAGE" then
          local a1,a2 = ...; local msg = a2 or a1
          if ShouldSuppressAlreadyMsg(msg) then return end
        end
        if _origOnEvent then return _origOnEvent(self, event, ...) end
      end)
    end
    -- Redundancy: block AddMessage if something slips
    local origAdd = UIErrorsFrame and UIErrorsFrame.AddMessage
    if origAdd and not UIErrorsFrame._SwiftSkiAddHooked then
      UIErrorsFrame._SwiftSkiAddHooked = true
      UIErrorsFrame.AddMessage = function(self, msg, r,g,b, id, holdTime)
        if ShouldSuppressAlreadyMsg(msg) then return end
        return origAdd(self, msg, r,g,b, id, holdTime)
      end
    end
  end

  f:SetScript("OnEvent", function(_, event, ...)
    local o = QOpt()

    if event == "PLAYER_ENTERING_WORLD" then
      EnsureAbandonAllButton()

    elseif event == "GOSSIP_CLOSED" then
      -- Stop bulk when the player intentionally closes the window
      QState.bulk.active = false

    elseif event == "UI_ERROR_MESSAGE" then
      local a1,a2 = ...; local msg = a2 or a1
      local invFull = (msg == ERR_INV_FULL) or (type(msg)=="string" and msg:find(ERR_INV_FULL or "Inventory is full",1,true))
      if invFull and QuestFrame and QuestFrame:IsShown() then
        QState.blockTurnInUntil = GetTime() + 8
      end
      local already = (msg == ERR_QUEST_ALREADY_ON) or (type(msg)=="string" and msg:lower():find("already on that quest",1,true))
      if already then
        QState.lastAutoAcceptAt = GetTime()
      end

    elseif event == "QUEST_ACCEPTED" then
      local questIndex = ...
      if questIndex then
        local t, _, _, _, isHeader = GetQuestLogTitle(questIndex)
        if t and not isHeader then RememberAcceptedTitle(t) end
      end
      QState.lastAutoAcceptAt = GetTime()
      if QState.bulk.active then SS:After(0.06, BulkPump) end

    elseif event == "QUEST_LOG_UPDATE" then
      if Abandon.running then if not AbandonNext() then AbandonAll_Stop() end end

    elseif event == "GOSSIP_SHOW" then
      if IsCommandBoard() then return end
      if o.autoTurnIn and not TurnInBlocked() then
        local didTurn = Gossip_ClickCompleted_Robust()
        if not didTurn then StartTurnInPump() end
      end
      if o.autoAccept then
        if not QState.bulk.active then StartBulkAccept() else SS:After(0.06, BulkPump) end
      end

    elseif event == "QUEST_GREETING" then
      if IsCommandBoard() then return end
      if o.autoTurnIn and not TurnInBlocked() then
        local didTurn = Greeting_ClickNextCompleted()
        if not didTurn then StartTurnInPump() end
      end
      if o.autoAccept then
        if not QState.bulk.active then StartBulkAccept() else SS:After(0.06, BulkPump) end
      end

    elseif event == "QUEST_DETAIL" then
      if IsCommandBoard() then return end
      if o.autoAccept then
        local title = (GetTitleText and GetTitleText()) or (QuestInfoTitleText and QuestInfoTitleText:GetText())
        if not IsQuestInLogByTitle(title) then
          AcceptQuest()
        end
      end
      if QState.bulk.active then SS:After(0.06, BulkPump) end

    elseif event == "QUEST_PROGRESS" then
      if IsCommandBoard() then return end
      -- Take you to the rewards screen only.
      if o.autoTurnIn and not TurnInBlocked() and IsQuestCompletable() then CompleteQuest() end

    elseif event == "QUEST_COMPLETE" then
      if IsCommandBoard() then return end
      -- Only auto-select if user enabled Auto-choose Reward
      if o.autoTurnIn and not TurnInBlocked() then
        if o.qReward and o.qReward.autoChoose then
          local idx
          if (o.qReward.strategy == "VENDOR") then
            -- Highest vendor price (respect armor filter first; fallback to all)
            idx = ChooseRewardIndex_ByFilters("ANY", o.qReward.armor or "ANY")
          else
            -- Attribute strategy
            idx = ChooseRewardIndex_ByFilters(o.qReward.attr or "ANY", o.qReward.armor or "ANY")
          end
          GetQuestReward(idx)
        else
          -- leave rewards screen open for manual selection
        end
      end

    elseif event == "QUEST_FINISHED" then
      if IsCommandBoard() then return end
      if o.autoTurnIn and not TurnInBlocked() then
        if GossipFrame and GossipFrame:IsShown() then if Gossip_ClickCompleted_Robust() then return end end
        if QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsShown() then
          if Greeting_ClickNextCompleted() then return end
        end
      end
      if QState.bulk.active then SS:After(0.06, BulkPump) end
    end
  end)

  self._questEvt = f
end

------------------------------------------------------------
-- Login prints
------------------------------------------------------------
local _login = CreateFrame("Frame")
_login:RegisterEvent("PLAYER_LOGIN")
_login:SetScript("OnEvent", function()
  if SS and type(SS.Quest_WireEvents)=="function" then SS:Quest_WireEvents() end
  local o=QOpt(); EnsureAbandonAllButton()
  QPrint("Auto-accept quests: "..(o.autoAccept and SS:lime("ON") or SS:red("OFF")))
  QPrint("Auto-Complete Quests: "..(o.autoTurnIn and SS:lime("ON") or SS:red("OFF")))
  local ac = (o.qReward and o.qReward.autoChoose) and (o.qReward.strategy or "ATTRIBUTE") or "OFF"
  QPrint("Auto-choose Reward: "..SS:teal(tostring(ac)))
  QPrint("Quest Log 'Abandon All' button: "..(o.showAbandonAllBtn and SS:lime("ON") or SS:red("OFF")))
end)

------------------------------------------------------------
-- UI: Questing tab
------------------------------------------------------------
function SS:BuildQuestingPanel(container)
  local o = QOpt()
  local box = (self.AddSeparator and self:AddSeparator(container, 8, -18, -8)) or container
  local function NewCheck(name, baseText, tip, y)
    local cb = CreateFrame("CheckButton", name, container, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", box, "TOPLEFT", 14, y)
    local lbl=_G[name.."Text"]; if lbl then lbl:SetText(baseText) end
    return cb, baseText, tip
  end

  local y=-18
  self.chkQAccept, self._qAcceptText, self._qAcceptDesc =
    NewCheck("SwiftSki_AutoAccept","Auto-accept quests","Accepts all available quests automatically (stays in the current window; no re-open).",y)
  self.chkQAccept:SetChecked(o.autoAccept); SetQuestLabel(self.chkQAccept,self._qAcceptText,o.autoAccept)

  y=y-38
  -- RENAMED: Auto-Complete Quests (no auto-pick on rewards unless Auto-choose is ON)
  self.chkQTurnIn, self._qTurnInText, self._qTurnInDesc =
    NewCheck("SwiftSki_AutoTurnIn","Auto-Complete Quests","When quests are ready to turn in, moves straight to the reward screen. Does not choose a reward unless 'Auto-choose Reward' is enabled below.",y)
  self.chkQTurnIn:SetChecked(o.autoTurnIn); SetQuestLabel(self.chkQTurnIn,self._qTurnInText,o.autoTurnIn)

  y=y-38
  self.chkQAbAll, self._qAbAllText, self._qAbAllDesc =
    NewCheck("SwiftSki_AbandonAllBtn","Abandon All button (Quest Log)","Adds an 'Abandon All' button to the Blizzard Quest Log next to the 'Track' button.",y)
  self.chkQAbAll:SetChecked(o.showAbandonAllBtn); SetQuestLabel(self.chkQAbAll,self._qAbAllText,o.showAbandonAllBtn)

  -- Auto-choose Reward + filters
  y = y - 42
  local chkAuto = CreateFrame("CheckButton", "SwiftSki_QReward_Auto", container, "InterfaceOptionsCheckButtonTemplate")
  chkAuto:SetPoint("TOPLEFT", box, "TOPLEFT", 14, y)
  _G[chkAuto:GetName().."Text"]:SetText("Auto-choose Reward")
  chkAuto:SetChecked(o.qReward.autoChoose)
  SetQuestLabel(chkAuto, "Auto-choose Reward", o.qReward.autoChoose)
  WireGoldRedTooltip(chkAuto, "Auto-choose Reward", "If enabled, SwiftSki selects a reward using the filters below:\n• Strategy = Attribute: pick the item with the highest amount of the chosen stat (ties by vendor value).\n• Strategy = Highest Vendor Price: pick the most valuable item.\n• Armor type: prefer this armor class; if none match, falls back to Any.")

  -- Strategy dropdown
  local stratLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  stratLbl:SetPoint("TOPLEFT", chkAuto, "BOTTOMLEFT", 6, -6)
  stratLbl:SetText("Strategy:")
  local ddStrat = CreateFrame("Frame", "SwiftSki_QReward_StratDD", container, "UIDropDownMenuTemplate")
  ddStrat:SetPoint("LEFT", stratLbl, "RIGHT", 6, 0)

  local STRAT_OPTS = {
    { code="ATTRIBUTE", text="Attribute" },
    { code="VENDOR",    text="Highest Vendor Price" },
  }
  UIDropDownMenu_Initialize(ddStrat, function(self, level)
    for _, opt in ipairs(STRAT_OPTS) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.text
      info.func = function()
        SwiftSkiDB.options.qReward.strategy = opt.code
        UIDropDownMenu_SetText(ddStrat, opt.text)
        QPrint("Auto-choose strategy: "..SS:teal(opt.text))
        -- Toggle attribute control availability
        if opt.code == "VENDOR" then
          UIDropDownMenu_DisableDropDown(ddAttr); attrLbl:SetAlpha(0.35)
        else
          UIDropDownMenu_EnableDropDown(ddAttr); attrLbl:SetAlpha(1.0)
        end
      end
      info.checked = (o.qReward.strategy == opt.code)
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetWidth(ddStrat, 180)
  local function StratText(code) for _,o2 in ipairs(STRAT_OPTS) do if o2.code==code then return o2.text end end return "Attribute" end
  UIDropDownMenu_SetText(ddStrat, StratText(o.qReward.strategy))

  -- Attribute
  local attrLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  attrLbl:SetPoint("TOPLEFT", stratLbl, "BOTTOMLEFT", 0, -18)
  attrLbl:SetText("Attribute:")
  local ddAttr = CreateFrame("Frame", "SwiftSki_QReward_AttrDD", container, "UIDropDownMenuTemplate")
  ddAttr:SetPoint("LEFT", attrLbl, "RIGHT", 6, 0)

  local ATTR_OPTS = { "ANY","Strength","Agility","Stamina","Intellect","Spirit" }
  UIDropDownMenu_Initialize(ddAttr, function(self, level)
    for _, opt in ipairs(ATTR_OPTS) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt
      info.func = function()
        SwiftSkiDB.options.qReward.attr = opt
        UIDropDownMenu_SetText(ddAttr, opt)
        QPrint("Auto-choose attribute: "..SS:teal(opt))
      end
      info.checked = (o.qReward.attr == opt)
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetWidth(ddAttr, 130)
  UIDropDownMenu_SetText(ddAttr, o.qReward.attr)

  -- Armor type
  local armorLbl = container:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  armorLbl:SetPoint("LEFT", ddAttr, "RIGHT", 20, 0)
  armorLbl:SetText("Armor type:")
  local ddArmor = CreateFrame("Frame", "SwiftSki_QReward_ArmorDD", container, "UIDropDownMenuTemplate")
  ddArmor:SetPoint("LEFT", armorLbl, "RIGHT", 6, 0)

  local ARMOR_OPTS = { "ANY","Cloth","Leather","Mail","Plate" }
  UIDropDownMenu_Initialize(ddArmor, function(self, level)
    for _, opt in ipairs(ARMOR_OPTS) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt
      info.func = function()
        SwiftSkiDB.options.qReward.armor = opt
        UIDropDownMenu_SetText(ddArmor, opt)
        QPrint("Auto-choose armor: "..SS:teal(opt))
      end
      info.checked = (o.qReward.armor == opt)
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  UIDropDownMenu_SetWidth(ddArmor, 110)
  UIDropDownMenu_SetText(ddArmor, o.qReward.armor)

  -- Enable/disable filters when master checkbox changes
  local function SetFilterEnabled(on, strategy)
    local a = on and 1.0 or 0.35
    stratLbl:SetAlpha(a); attrLbl:SetAlpha(a); armorLbl:SetAlpha(a)
    UIDropDownMenu_EnableDropDown(ddStrat)
    UIDropDownMenu_EnableDropDown(ddAttr)
    UIDropDownMenu_EnableDropDown(ddArmor)
    if not on then
      UIDropDownMenu_DisableDropDown(ddStrat)
      UIDropDownMenu_DisableDropDown(ddAttr)
      UIDropDownMenu_DisableDropDown(ddArmor)
    else
      if strategy == "VENDOR" then
        UIDropDownMenu_DisableDropDown(ddAttr); attrLbl:SetAlpha(0.35)
      end
    end
  end
  SetFilterEnabled(o.qReward.autoChoose, o.qReward.strategy)

  SS:WireCheckSound(chkAuto, function(btn)
    local on = btn:GetChecked() and true or false
    SwiftSkiDB.options.qReward.autoChoose = on
    SetQuestLabel(chkAuto, "Auto-choose Reward", on)
    if chkAuto._refreshTooltip then chkAuto:_refreshTooltip() end
    SetFilterEnabled(on, SwiftSkiDB.options.qReward.strategy)
    QPrint("Auto-choose Reward: "..(on and SS:lime("ON") or SS:red("OFF")))
  end, "Auto-choose Reward")

  -- Wire the other three checkboxes
  SS:WireCheckSound(self.chkQAccept, function(btn)
    local on = btn:GetChecked() and true or false
    SwiftSkiDB.options.autoAccept = on; SetQuestLabel(self.chkQAccept,self._qAcceptText,on)
    if self.chkQAccept._refreshTooltip then self.chkQAccept:_refreshTooltip() end
    QPrint("Auto-accept quests: "..(on and SS:lime("ON") or SS:red("OFF")))
  end, "Auto-accept quests")

  SS:WireCheckSound(self.chkQTurnIn, function(btn)
    local on = btn:GetChecked() and true or false
    SwiftSkiDB.options.autoTurnIn = on; SetQuestLabel(self.chkQTurnIn,self._qTurnInText,on)
    if self.chkQTurnIn._refreshTooltip then self.chkQTurnIn:_refreshTooltip() end
    QPrint("Auto-Complete Quests: "..(on and SS:lime("ON")or SS:red("OFF")))
  end, "Auto-Complete Quests")

  SS:WireCheckSound(self.chkQAbAll, function(btn)
    local on = btn:GetChecked() and true or false
    SwiftSkiDB.options.showAbandonAllBtn = on; EnsureAbandonAllButton()
    SetQuestLabel(self.chkQAbAll,self._qAbAllText,on)
    if self.chkQAbAll._refreshTooltip then self.chkQAbAll:_refreshTooltip() end
    QPrint("Quest Log 'Abandon All' button: "..(on and SS:lime("ON") or SS:red("OFF")))
  end, "Abandon All button")

  WireGoldRedTooltip(self.chkQAccept, self._qAcceptText, self._qAcceptDesc)
  WireGoldRedTooltip(self.chkQTurnIn, self._qTurnInText, self._qTurnInDesc)
  WireGoldRedTooltip(self.chkQAbAll,  self._qAbAllText,  self._qAbAllDesc)

  self:Quest_WireEvents()
end
