-- SwiftSki_About.lua
-- Populates the About/Credits tab (container is created in Core).

local SS = _G.SwiftSki
if not SS then return end

-- Colors (fallbacks if Core hasn't set them yet)
local COL_LIME  = (SS and SS.COL_LIME) or "32CD32"
local COL_WHITE = "FFFFFF"
local COL_PINK  = "FF66CC"   -- cats note

-- Text width for left column (full width since we removed the right panel)
local TEXT_W = 640

-- ---------- UI helpers ----------
local function addRule(parent, x, y, w)
  local t = parent:CreateTexture(nil, "ARTWORK")
  -- 3.3.5a: SetColorTexture doesn't exist; SetTexture(r,g,b,a) is supported
  t:SetTexture(1, 1, 1, 0.08)
  t:SetPoint("TOPLEFT", x, y)
  t:SetSize(w, 1)
  return t
end

local function addSubTitle(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  fs:SetText("|cff" .. COL_LIME .. text .. "|r")
  return fs
end

local function addText(parent, text, x, y, width, template)
  local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  fs:SetWidth(width or TEXT_W)
  fs:SetWordWrap(true)
  fs:SetText("|cff" .. COL_WHITE .. text .. "|r")
  return fs
end

-- Bullet that returns the next Y based on text height (prevents overlap)
local function addPawBullet(parent, text, x, y, width)
  local paw = parent:CreateTexture(nil, "ARTWORK")
  paw:SetPoint("TOPLEFT", x, y - 2)
  paw:SetSize(14, 14)
  paw:SetTexture("Interface\\Icons\\Ability_Druid_Maul")
  paw:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  paw:SetVertexColor(0.20, 0.92, 0.20) -- lime tint

  local fs = addText(parent, text, x + 22, y, width or TEXT_W, "GameFontHighlight")
  -- Space next line by the actual wrapped height + small padding
  local h = math.ceil(fs:GetStringHeight() or 16)
  local nextY = y - h - 6
  return paw, fs, nextY
end
-- --------------------------------

function SS:BuildAboutPanel(container)
  if not container or container._built then return end
  container._built = true

  local box = self:AddSeparator(container, 8, -18, -8)

  -- Header: logo + title/version + byline + cats note
  local logo = box:CreateTexture(nil, "OVERLAY")
  logo:SetSize(64, 64)
  logo:SetPoint("TOPLEFT", 14, -8)
  logo:SetTexture("Interface\\AddOns\\SwiftSki\\img\\DevSki.tga")

  local title = box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("LEFT", logo, "RIGHT", 12, 14)
  title:SetJustifyH("LEFT")
  local ver = (GetAddOnMetadata and (GetAddOnMetadata("SwiftSki", "Version") or "1.0")) or "1.0"
  title:SetText("|cff" .. COL_LIME .. "SwiftSki|r  |cffffffffv" .. ver .. "|r")

  local by = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  by:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  by:SetJustifyH("LEFT")
  by:SetText("|cffffffffA DevSki project by ShaunSki|r")

  local foot = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  foot:SetPoint("TOPLEFT", by, "BOTTOMLEFT", 0, -2)
  foot:SetJustifyH("LEFT")
  foot:SetText("|cff" .. COL_PINK .. "Cats supervised all commits. =^.^=|r")

  -- Divider under header
  addRule(box, 12, -96, 680)

  -- Tagline & short description
  addText(box, "Gaming Tools, Faster Worlds", 14, -110, TEXT_W, "GameFontNormalLarge")
  addText(box,
    "SwiftSki delivers fast, intuitive QoL tools to make gameplay smoother, smarter, and more fun.",
    14, -130, TEXT_W
  )

  -- Discord (read-only style input + Select button)
  addSubTitle(box, "Discord (bugs/feedback):", 14, -156)
  local URL = "https://discord.gg/mSyBB2jYZ2"

  local eb = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
  eb:SetPoint("TOPLEFT", 16, -178)
  eb:SetSize(420, 22)
  eb:SetAutoFocus(false)
  eb:SetText(URL)
  eb:HighlightText(0, 0)
  eb:SetCursorPosition(0)
  eb:SetScript("OnEditFocusGained", function(self)
    self:HighlightText(0, self:GetNumLetters())
  end)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(self, user)
    if user and self:GetText() ~= URL then
      self:SetText(URL)                       -- keep it effectively read-only
      self:HighlightText(0, self:GetNumLetters())
    end
  end)
  eb:SetScript("OnKeyDown", function(self, key)
    if IsControlKeyDown() and (key == "C" or key == "A") then return end -- allow copy/select
    self:HighlightText(0, self:GetNumLetters())
  end)

  local selectBtn = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
  selectBtn:SetSize(70, 22)
  selectBtn:SetPoint("LEFT", eb, "RIGHT", 8, 0)
  selectBtn:SetText("Select")
  selectBtn:SetScript("OnClick", function()
    eb:SetFocus()
    eb:HighlightText(0, eb:GetNumLetters())
    if UIErrorsFrame then
      UIErrorsFrame:AddMessage("Link selected — press Ctrl+C to copy.", 0.2, 1.0, 0.2, 1.0)
    else
      SS:Chat("|cff" .. COL_LIME .. "[SwiftSki]|r Link selected — press Ctrl+C to copy.")
    end
  end)

  addText(box, "Tip: Ctrl+A then Ctrl+C to copy.", 16, -202, TEXT_W, "GameFontHighlightSmall")

  -- Divider above highlights
  addRule(box, 12, -218, 680)

  -- Highlights (concise, auto-spaced)
  addSubTitle(box, "Highlights", 14, -234)
  local y = -256

  _, _, y = addPawBullet(box,
    "Questing: Bulk quest accept and bulk turn-in (appearance first -> vendor value).",
    18, y, TEXT_W)

  _, _, y = addPawBullet(box,
    "Vendor: Smart auto-sell with rarity filters & material protection. Works with Item Lock.",
    18, y, TEXT_W)

  _, _, y = addPawBullet(box,
    "Item Lock: ALT+Left-Click to lock/unlock. Searchable list with quality filters.",
    18, y, TEXT_W)

  _, _, y = addPawBullet(box,
    "Ascension: Manastorm buff button, fast roulette (Elune), auto-equip heirlooms on prestige, automatic appearance collection.",
    18, y, TEXT_W)
end
