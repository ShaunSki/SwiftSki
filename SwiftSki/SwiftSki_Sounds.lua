-- SwiftSki_Sounds.lua — sound helpers + lazy hook of frame/tabs

local SS = _G.SwiftSki or {}
_G.SwiftSki = SS

function SS:PlayTab()   if PlaySound then PlaySound("igCharacterInfoTab") end end
function SS:PlayOpen()  if PlaySound then PlaySound("igMainMenuOpen")     end end
function SS:PlayClose() if PlaySound then PlaySound("igMainMenuClose")    end end
function SS:PlayCheck(checked)
  if not PlaySound then return end
  if checked then PlaySound("igMainMenuOptionCheckBoxOn")
  else PlaySound("igMainMenuOptionCheckBoxOff") end
end

function SS:WireCheckSound(cb, handler)
  if not cb then return end
  cb:SetScript("OnClick", function(self, ...)
    SS:PlayCheck(self:GetChecked())
    if handler then handler(self, ...) end
  end)
end

local function HookFrameAndTabs()
  local f = SS and SS.frame
  if not f then return false end

  if not f._ssSoundHooked then
    f:HookScript("OnShow", function() SS:PlayOpen() end)
    f:HookScript("OnHide", function() SS:PlayClose() end)
    f._ssSoundHooked = true
  end

  local found = false
  if SS.tabs and type(SS.tabs) == "table" then
    for _, t in ipairs(SS.tabs) do
      if t and not t._ssSoundHooked then
        t:HookScript("OnClick", function() SS:PlayTab() end)
        t._ssSoundHooked = true
      end
      found = true
    end
  end
  return f._ssSoundHooked and found
end

function SS:InitSounds() HookFrameAndTabs() end

local hooker = CreateFrame("Frame")
hooker._t = 0
hooker:SetScript("OnUpdate", function(self, elapsed)
  self._t = self._t + elapsed
  if self._t < 0.2 then return end
  self._t = 0
  if HookFrameAndTabs() then self:SetScript("OnUpdate", nil) end
end)