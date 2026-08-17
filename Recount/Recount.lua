-- Recount v1.1.0
-- Recount-style meter rebuilt for WoW 1.12.1.
-- Vanilla combat-log parser + fight segments + reports + configuration UI.

Recount = {}
local RV = Recount

RV.version = "2.0.2"
RV.rows = {}
RV.petOwners = {}
RV.petNamesByOwner = {}
RV.maxRows = 10
RV.updateTimer = 0
RV.inCombat = false
RV.currentFightStart = nil
RV.currentFightEnd = nil
RV.fights = {}
RV.maxSavedFights = 10
RV.segmentType = "overall" -- overall/current/fight
RV.segmentIndex = nil

RV.modes = {
  { key = "damage",       label = "Damage Done" },
  { key = "dps",          label = "DPS" },
  { key = "taken",        label = "Damage Taken" },
  { key = "healing",      label = "Healing Done" },
  { key = "healingTaken", label = "Healing Taken" },
  { key = "deaths",       label = "Deaths" }
}
RV.modeIndex = 1
RV.mode = "damage"

RV.overallData = {}
RV.currentData = {}
RV.data = RV.overallData

RV.settings = {
  locked = false,
  showPetsMerged = true,
  showBackground = true,
  windowAlpha = .90,
  scale = 1.0,
  classColors = true,
  autoDeleteOnNewGroup = false,
  confirmReset = true,
  classFilter = {
    WARRIOR = true,
    ROGUE = true,
    PRIEST = true,
    HUNTER = true,
    DRUID = true,
    MAGE = true,
    WARLOCK = true,
    PALADIN = true,
    SHAMAN = true
  }
}

RV.layout = {
  point = "CENTER",
  relativePoint = "CENTER",
  x = 300,
  y = 0,
  width = 320,
  height = 238
}

function RV:LoadSavedSettings()
  if not RecountDB then
    RecountDB = {}
  end

  if RecountDB.settings then
    local k,v
    for k,v in pairs(RecountDB.settings) do
      if k ~= "classFilter" then
        self.settings[k] = v
      end
    end

    if RecountDB.settings.classFilter then
      local classToken, enabled
      for classToken, enabled in pairs(RecountDB.settings.classFilter) do
        self.settings.classFilter[classToken] = enabled
      end
    end
  end

  if RecountDB.layout then
    local k,v
    for k,v in pairs(RecountDB.layout) do
      self.layout[k] = v
    end
  end
end

function RV:SaveSettings()
  if not RecountDB then
    RecountDB = {}
  end

  RecountDB.settings = {}
  local k,v
  for k,v in pairs(self.settings) do
    RecountDB.settings[k] = v
  end

  RecountDB.layout = {}
  for k,v in pairs(self.layout) do
    RecountDB.layout[k] = v
  end
end

function RV:SaveCombatData()
  if not RecountDB then
    RecountDB = {}
  end

  RecountDB.overallData = self.overallData
  RecountDB.currentData = self.currentData
  RecountDB.segmentType = self.segmentType
  RecountDB.modeIndex = self.modeIndex
end

function RV:LoadCombatData()
  if not RecountDB then
    RecountDB = {}
  end

  if RecountDB.overallData then
    self.overallData = RecountDB.overallData
  end

  if RecountDB.currentData then
    self.currentData = RecountDB.currentData
  end

  if RecountDB.segmentType == "overall" or RecountDB.segmentType == "current" then
    self.segmentType = RecountDB.segmentType
  end

  if RecountDB.modeIndex and self.modes[RecountDB.modeIndex] then
    self.modeIndex = RecountDB.modeIndex
    self.mode = self.modes[self.modeIndex].key
  end

  self.segmentIndex = nil
  self.inCombat = false
  self.data = self:GetSelectedData()
end

function RV:SaveMainLayout()
  if not self.frame then return end

  local point, relativeTo, relativePoint, x, y = self.frame:GetPoint()
  self.layout.point = point or "CENTER"
  self.layout.relativePoint = relativePoint or "CENTER"
  self.layout.x = x or 0
  self.layout.y = y or 0
  self.layout.width = self.frame:GetWidth()
  self.layout.height = self.frame:GetHeight()
  self:SaveSettings()
end

function RV:RestoreMainLayout()
  if not self.frame then return end

  self.frame:ClearAllPoints()
  self.frame:SetPoint(
    self.layout.point or "CENTER",
    UIParent,
    self.layout.relativePoint or "CENTER",
    self.layout.x or 0,
    self.layout.y or 0
  )
  self.frame:SetWidth(self.layout.width or 320)
  self.frame:SetHeight(self.layout.height or 238)
end

function RV:MakeWindowDraggable(frame, bar)
  bar = bar or frame
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")

  bar:SetScript("OnDragStart", function()
    if frame == RV.frame and RV.settings.locked then
      return
    end
    frame:StartMoving()
  end)

  bar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    if frame == RV.frame then
      RV:SaveMainLayout()
    end
  end)
end

function RV:MakeCloseButton(frame)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetWidth(26)
  close:SetHeight(26)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -4)
  close:SetFrameLevel(frame:GetFrameLevel() + 30)
  close:EnableMouse(true)

  if close.SetHitRectInsets then
    close:SetHitRectInsets(-4, -4, -4, -4)
  end

  return close
end

function RV:CreateTitleBar(frame, text, height)
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
  bar:SetHeight(height or 22)
  bar:SetFrameLevel(frame:GetFrameLevel() + 8)

  local redFill = bar:CreateTexture(nil, "BACKGROUND")
  redFill:SetAllPoints(bar)
  redFill:SetTexture(1.00, .02, .02, 1)
  bar.redFill = redFill

  local topLine = bar:CreateTexture(nil, "BORDER")
  topLine:SetHeight(1)
  topLine:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  topLine:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
  topLine:SetTexture(1, .20, .20, 1)

  local bottomLine = bar:CreateTexture(nil, "BORDER")
  bottomLine:SetHeight(1)
  bottomLine:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  bottomLine:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  bottomLine:SetTexture(.35, 0, 0, 1)

  local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", bar, "LEFT", 6, 0)
  label:SetText(text or "")
  label:SetTextColor(1, .82, 0)

  self:MakeWindowDraggable(frame, bar)
  return bar, label
end

local floor = math.floor
local lower = string.lower
local gsub = string.gsub
local format = string.format

local CLASS_COLORS = {
  WARRIOR = { .78, .61, .43 }, MAGE = { .41, .80, .94 },
  ROGUE = { 1.00, .96, .41 }, DRUID = { 1.00, .49, .04 },
  HUNTER = { .67, .83, .45 }, SHAMAN = { .00, .44, .87 },
  PRIEST = { 1.00, 1.00, 1.00 }, WARLOCK = { .58, .51, .79 },
  PALADIN = { .96, .55, .73 }
}

local function trim(s)
  if not s then return "" end
  s = gsub(s, "^%s+", "")
  s = gsub(s, "%s+$", "")
  return s
end

local function stripPunctuation(s)
  if not s then return s end
  s = gsub(s, "%.$", "")
  s = gsub(s, "!$", "")
  return s
end

local function normalizeYou(name)
  if not name then return nil end
  if name == "you" or name == "You" or name == "YOU" then
    return UnitName("player")
  end
  return name
end

local function capture(s, pattern)
  if not s or not pattern then return nil end
  local results = { string.find(s, pattern) }
  if table.getn(results) < 3 then return nil end
  table.remove(results, 1)
  table.remove(results, 1)
  return unpack(results)
end

local function formatNumber(n)
  n = n or 0
  if n >= 1000000 then return format("%.2fm", n / 1000000)
  elseif n >= 1000 then return format("%.1fk", n / 1000)
  else return tostring(floor(n + .5)) end
end

local function createBackdrop(frame, alpha)
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  frame:SetBackdropColor(.03, .03, .03, alpha or .92)
  frame:SetBackdropBorderColor(.32, .32, .32, 1)
end

local function newActor(name, r, g, b)
  return {
    name = name, damage = 0, healing = 0, taken = 0, healingTaken = 0,
    deaths = 0, petDamage = 0, hits = 0, first = nil, last = nil,
    r = r, g = g, b = b, pets = {}, spells = {},
    spellCounts = {}, spellStats = {}, damageEvents = {},
    healingSpells = {}, healingSpellCounts = {}, healingStats = {}, healingEvents = {},
    takenSources = {}, takenSourceCounts = {}, takenStats = {}, takenEvents = {},
    healingTakenSources = {}, healingTakenSourceCounts = {}, healingTakenStats = {}, healingTakenEvents = {}
  }
end

local function copyActor(a)
  local n = newActor(a.name, a.r, a.g, a.b)
  n.damage = a.damage or 0
  n.healing = a.healing or 0
  n.taken = a.taken or 0
  n.healingTaken = a.healingTaken or 0
  n.deaths = a.deaths or 0
  n.petDamage = a.petDamage or 0
  n.hits = a.hits or 0
  n.first = a.first
  n.last = a.last
  local k,v
  for k,v in pairs(a.pets or {}) do n.pets[k] = v end
  for k,v in pairs(a.spells or {}) do n.spells[k] = v end
  for k,v in pairs(a.spellCounts or {}) do n.spellCounts[k] = v end
  for k,v in pairs(a.spellStats or {}) do
    n.spellStats[k] = { count=v.count, amount=v.amount, min=v.min, max=v.max, crit=v.crit or 0, hit=v.hit or 0 }
  end
  local i
  for i=1,table.getn(a.damageEvents or {}) do
    local e=a.damageEvents[i]
    table.insert(n.damageEvents,{ time=e.time, amount=e.amount, spell=e.spell })
  end

  for k,v in pairs(a.healingSpells or {}) do n.healingSpells[k] = v end
  for k,v in pairs(a.healingSpellCounts or {}) do n.healingSpellCounts[k] = v end
  for k,v in pairs(a.healingStats or {}) do
    n.healingStats[k] = { count=v.count, amount=v.amount, min=v.min, max=v.max }
  end
  for i=1,table.getn(a.healingEvents or {}) do
    local e=a.healingEvents[i]
    table.insert(n.healingEvents,{ time=e.time, amount=e.amount, spell=e.spell })
  end

  for k,v in pairs(a.takenSources or {}) do n.takenSources[k] = v end
  for k,v in pairs(a.takenSourceCounts or {}) do n.takenSourceCounts[k] = v end
  for k,v in pairs(a.takenStats or {}) do
    n.takenStats[k] = { count=v.count, amount=v.amount, min=v.min, max=v.max }
  end
  for i=1,table.getn(a.takenEvents or {}) do
    local e=a.takenEvents[i]
    table.insert(n.takenEvents,{ time=e.time, amount=e.amount, spell=e.spell })
  end

  for k,v in pairs(a.healingTakenSources or {}) do n.healingTakenSources[k] = v end
  for k,v in pairs(a.healingTakenSourceCounts or {}) do n.healingTakenSourceCounts[k] = v end
  for k,v in pairs(a.healingTakenStats or {}) do
    n.healingTakenStats[k] = { count=v.count, amount=v.amount, min=v.min, max=v.max }
  end
  for i=1,table.getn(a.healingTakenEvents or {}) do
    local e=a.healingTakenEvents[i]
    table.insert(n.healingTakenEvents,{ time=e.time, amount=e.amount, spell=e.spell })
  end
  return n
end

local function copyDataset(data)
  local out = {}
  local k,v
  for k,v in pairs(data) do out[k] = copyActor(v) end
  return out
end

function RV:IsKnownGroupMember(name)
  if not name or name == "" then return false end

  if UnitName("player") == name then
    return true
  end

  local i
  for i = 1, 4 do
    if UnitName("party"..i) == name then
      return true
    end
  end

  for i = 1, 40 do
    if UnitName("raid"..i) == name then
      return true
    end
  end

  return false
end

function RV:IsTrackableSource(name)
  if not name or name == "" then return false end

  name = normalizeYou(stripPunctuation(trim(name)))

  if self:IsKnownGroupMember(name) then
    return true
  end

  if self.petOwners[name] then
    return true
  end

  return false
end
function RV:GetUnitClassToken(name)
  if not name or name == "" then return nil end

  local unit = nil
  local i

  if UnitName("player") == name then
    unit = "player"
  elseif UnitName("pet") == name then
    -- Pets inherit owner's class for display-filter purposes.
    return select(2, UnitClass("player"))
  else
    for i = 1, 4 do
      if UnitName("party"..i) == name then
        unit = "party"..i
        break
      end

      if UnitName("partypet"..i) == name or UnitName("party"..i.."pet") == name then
        return select(2, UnitClass("party"..i))
      end
    end

    if not unit then
      for i = 1, 40 do
        if UnitName("raid"..i) == name then
          unit = "raid"..i
          break
        end

        if UnitName("raidpet"..i) == name or UnitName("raid"..i.."pet") == name then
          return select(2, UnitClass("raid"..i))
        end
      end
    end
  end

  if unit then
    local _, class = UnitClass(unit)
    return class
  end

  return nil
end

function RV:IsActorVisibleByFilter(actor)
  if not actor or not actor.name then return false end

  local class = self:GetUnitClassToken(actor.name)

  -- If a class cannot be resolved (rare edge case), keep it visible.
  if not class then
    return true
  end

  if not self.settings.classFilter then
    return true
  end

  if self.settings.classFilter[class] == nil then
    return true
  end

  return self.settings.classFilter[class] and true or false
end

function RV:GetUnitClassColor(name)
  local unit, i

  if UnitName("player") == name then
    unit = "player"
  elseif UnitName("pet") == name then
    unit = "pet"
  else
    for i = 1, 4 do
      if UnitName("party"..i) == name then
        unit = "party"..i
        break
      end
    end

    if not unit then
      for i = 1, 40 do
        if UnitName("raid"..i) == name then
          unit = "raid"..i
          break
        end
      end
    end
  end

  if unit then
    local _, class = UnitClass(unit)
    if class and CLASS_COLORS[class] then
      return CLASS_COLORS[class][1], CLASS_COLORS[class][2], CLASS_COLORS[class][3]
    end
  end

  return .75, .25, .25
end


function RV:GetActorIn(data, name)
  name = normalizeYou(stripPunctuation(trim(name)))
  if not name or name == "" then return nil end
  if not self:IsTrackableSource(name) then return nil end

  local owner = self.petOwners[name]
  local actorName = owner or name

  if not data[actorName] then
    local r,g,b = self:GetUnitClassColor(actorName)
    data[actorName] = newActor(actorName, r,g,b)
  end

  return data[actorName], owner ~= nil, name
end

local function RV_UpdateStats(tbl, key, amount)
  if not key or key == "" then key = "Unknown" end
  local s = tbl[key]
  if not s then
    s = { count=0, amount=0, min=nil, max=nil, hit=0, crit=0 }
    tbl[key] = s
  end
  s.count = s.count + 1
  s.amount = s.amount + amount
  if not s.min or amount < s.min then s.min = amount end
  if not s.max or amount > s.max then s.max = amount end
  return s
end

function RV:AddDamageTo(data, source, amount, target, spell)
  amount = tonumber(amount)
  if not source or not amount or amount <= 0 then return end

  local actor, isPet, actualSource = self:GetActorIn(data, source)
  if not actor then return end

  local now = GetTime()
  actor.damage = actor.damage + amount
  actor.hits = actor.hits + 1
  actor.first = actor.first or now
  actor.last = now

  if spell and spell ~= "" then
    actor.spells[spell] = (actor.spells[spell] or 0) + amount
    actor.spellCounts[spell] = (actor.spellCounts[spell] or 0) + 1
    RV_UpdateStats(actor.spellStats, spell, amount)
    table.insert(actor.damageEvents, { time=now, amount=amount, spell=spell })
  end

  if isPet then
    actor.petDamage = actor.petDamage + amount
    actor.pets[actualSource] = (actor.pets[actualSource] or 0) + amount
  end

  if target then
    local t = normalizeYou(stripPunctuation(trim(target)))
    if self:IsKnownGroupMember(t) then
      local targetActor = self:GetActorIn(data, t)
      if targetActor then targetActor.taken = (targetActor.taken or 0) + amount end
    end
  end
end

function RV:AddDamage(source, amount, target, spell)
  if not self.inCombat then self:StartFight() end
  self:AddDamageTo(self.overallData, source, amount, target, spell)
  self:AddDamageTo(self.currentData, source, amount, target, spell)
end

function RV:AddDamageTakenTo(data, target, amount, source, spell)
  amount = tonumber(amount)
  if not target or not amount or amount <= 0 then return end

  target = normalizeYou(stripPunctuation(trim(target)))
  if not self:IsKnownGroupMember(target) then return end

  local actor = self:GetActorIn(data, target)
  if actor then
    actor.taken = (actor.taken or 0) + amount

    local key = source or "Unknown"
    if spell and spell ~= "" then
      key = key .. " - " .. spell
    end
    actor.takenSources[key] = (actor.takenSources[key] or 0) + amount
    actor.takenSourceCounts[key] = (actor.takenSourceCounts[key] or 0) + 1
    RV_UpdateStats(actor.takenStats, key, amount)
    table.insert(actor.takenEvents, { time=GetTime(), amount=amount, spell=key })
  end
end

function RV:AddDamageTaken(target, amount, source, spell)
  self:AddDamageTakenTo(self.overallData, target, amount, source, spell)
  self:AddDamageTakenTo(self.currentData, target, amount, source, spell)
end

function RV:GetKnownSources()
  local sources = {}
  local seen = {}

  local function add(name)
    if name and name ~= "" and not seen[name] then
      seen[name] = true
      table.insert(sources, name)
    end
  end

  add(UnitName("player"))
  add(UnitName("pet"))

  local i
  for i = 1, 4 do
    add(UnitName("party"..i))
    add(UnitName("partypet"..i))
    add(UnitName("party"..i.."pet"))
  end

  for i = 1, 40 do
    add(UnitName("raid"..i))
    add(UnitName("raidpet"..i))
    add(UnitName("raid"..i.."pet"))
  end

  return sources
end

function RV:ParseKnownSourceSpell(msg, verb)
  local sources = self:GetKnownSources()
  local i

  for i = 1, table.getn(sources) do
    local source = sources[i]
    local prefix = source .. "'s "
    local plen = string.len(prefix)

    if string.sub(msg, 1, plen) == prefix then
      local rest = string.sub(msg, plen + 1)
      local needle = " " .. verb .. " "
      local a, b = string.find(rest, needle, 1, true)

      if a then
        return source, string.sub(rest, 1, a - 1), string.sub(rest, b + 1)
      end
    end
  end

  return nil
end

function RV:ParseKnownSourceAfterFrom(text)
  local sources = self:GetKnownSources()
  local i

  for i = 1, table.getn(sources) do
    local source = sources[i]
    local prefix = source .. "'s "
    local plen = string.len(prefix)

    if string.sub(text, 1, plen) == prefix then
      return source, string.sub(text, plen + 1)
    end
  end

  return nil
end

function RV:AddHealingTo(data, source, amount, target, spell)
  amount = tonumber(amount)
  if not source or not amount or amount <= 0 then return end
  local actor = self:GetActorIn(data, source)
  if not actor then return end

  local now = GetTime()
  actor.healing = actor.healing + amount
  actor.first = actor.first or now
  actor.last = now

  if spell and spell ~= "" then
    actor.healingSpells[spell] = (actor.healingSpells[spell] or 0) + amount
    actor.healingSpellCounts[spell] = (actor.healingSpellCounts[spell] or 0) + 1
    RV_UpdateStats(actor.healingStats, spell, amount)
    table.insert(actor.healingEvents, { time=now, amount=amount, spell=spell })
  end

  if target then
    local t = normalizeYou(stripPunctuation(trim(target)))
    if self:IsKnownGroupMember(t) then
      local targetActor = self:GetActorIn(data, t)
      if targetActor then
        targetActor.healingTaken = (targetActor.healingTaken or 0) + amount

        local key = source or "Unknown"
        if spell and spell ~= "" then
          key = key .. " - " .. spell
        end
        targetActor.healingTakenSources[key] = (targetActor.healingTakenSources[key] or 0) + amount
        targetActor.healingTakenSourceCounts[key] = (targetActor.healingTakenSourceCounts[key] or 0) + 1
        RV_UpdateStats(targetActor.healingTakenStats, key, amount)
        table.insert(targetActor.healingTakenEvents, { time=now, amount=amount, spell=key })
      end
    end
  end
end

function RV:AddHealing(source, amount, target, spell)
  if not self.inCombat then self:StartFight() end
  self:AddHealingTo(self.overallData, source, amount, target, spell)
  self:AddHealingTo(self.currentData, source, amount, target, spell)
end

function RV:MarkDeathIn(data, name)
  name = normalizeYou(stripPunctuation(trim(name)))
  if not name or name == "" or not self:IsKnownGroupMember(name) then return end
  local actor = self:GetActorIn(data, name)
  if actor then actor.deaths = (actor.deaths or 0) + 1 end
end

function RV:MarkDeath(name)
  self:MarkDeathIn(self.overallData, name)
  self:MarkDeathIn(self.currentData, name)
end

function RV:RefreshPetOwners()
  self.petOwners = {}
  self.petNamesByOwner = {}

  local function mapPet(ownerUnit, petUnit)
    if not UnitExists(ownerUnit) or not UnitExists(petUnit) then return end
    local owner = UnitName(ownerUnit)
    local pet = UnitName(petUnit)
    if owner and pet and pet ~= UNKNOWNOBJECT then
      RV.petOwners[pet] = owner
      RV.petNamesByOwner[owner] = pet
    end
  end

  mapPet("player", "pet")

  local i
  for i = 1, 4 do
    -- Different 1.12 derivatives have exposed both conventions.
    mapPet("party"..i, "partypet"..i)
    mapPet("party"..i, "party"..i.."pet")
  end

  for i = 1, 40 do
    mapPet("raid"..i, "raidpet"..i)
    mapPet("raid"..i, "raid"..i.."pet")
  end
end

function RV:ParseCombatMessage(eventName, msg)
  if not msg or msg == "" then return end

  local source, target, amount, spell, rest, a, b

  -- Direct healing: self.
  spell, amount = capture(msg, "^Your (.+) critically heals you for (%d+)")
  if spell then self:AddHealing(UnitName("player"), amount, UnitName("player"), spell); return end

  spell, amount = capture(msg, "^Your (.+) heals you for (%d+)")
  if spell then self:AddHealing(UnitName("player"), amount, UnitName("player"), spell); return end

  spell, target, amount = capture(msg, "^Your (.+) critically heals (.+) for (%d+)")
  if spell then self:AddHealing(UnitName("player"), amount, target, spell); return end

  spell, target, amount = capture(msg, "^Your (.+) heals (.+) for (%d+)")
  if spell then self:AddHealing(UnitName("player"), amount, target, spell); return end

  -- Direct healing: another known player/pet.
  source, spell, rest = self:ParseKnownSourceSpell(msg, "critically heals")
  if source then
    amount = capture(rest, "^you for (%d+)")
    if amount then self:AddHealing(source, amount, UnitName("player"), spell); return end

    target, amount = capture(rest, "^(.+) for (%d+)")
    if target then self:AddHealing(source, amount, target, spell); return end
  end

  source, spell, rest = self:ParseKnownSourceSpell(msg, "heals")
  if source then
    amount = capture(rest, "^you for (%d+)")
    if amount then self:AddHealing(source, amount, UnitName("player"), spell); return end

    target, amount = capture(rest, "^(.+) for (%d+)")
    if target then self:AddHealing(source, amount, target, spell); return end
  end

  -- HoTs.
  amount, rest = capture(msg, "^You gain (%d+) health from (.+)%.$")
  if amount then
    source, spell = self:ParseKnownSourceAfterFrom(rest)
    if source then
      self:AddHealing(source, amount, UnitName("player"), spell)
    else
      self:AddHealing(UnitName("player"), amount, UnitName("player"), rest)
    end
    return
  end

  target, amount, spell = capture(msg, "^(.+) gains (%d+) health from your (.+)%.$")
  if target then self:AddHealing(UnitName("player"), amount, target, spell); return end

  target, amount, rest = capture(msg, "^(.+) gains (%d+) health from (.+)%.$")
  if target then
    source, spell = self:ParseKnownSourceAfterFrom(rest)
    if source then self:AddHealing(source, amount, target, spell); return end
  end

  -- Your direct spell damage.
  spell, target, amount = capture(msg, "^Your (.+) hits (.+) for (%d+)")
  if spell then self:AddDamage(UnitName("player"), amount, target, spell); return end

  spell, target, amount = capture(msg, "^Your (.+) crits (.+) for (%d+)")
  if spell then self:AddDamage(UnitName("player"), amount, target, spell); return end

  -- Other group member / pet direct spell damage.
  source, spell, rest = self:ParseKnownSourceSpell(msg, "hits")
  if source then
    target, amount = capture(rest, "^(.+) for (%d+)")
    if target then self:AddDamage(source, amount, target, spell); return end
  end

  source, spell, rest = self:ParseKnownSourceSpell(msg, "crits")
  if source then
    target, amount = capture(rest, "^(.+) for (%d+)")
    if target then self:AddDamage(source, amount, target, spell); return end
  end

  -- Melee damage.
  target, amount = capture(msg, "^You hit (.+) for (%d+)")
  if target then self:AddDamage(UnitName("player"), amount, target, "Melee"); return end

  target, amount = capture(msg, "^You crit (.+) for (%d+)")
  if target then self:AddDamage(UnitName("player"), amount, target, "Melee"); return end

  source, target, amount = capture(msg, "^(.+) hits (.+) for (%d+)")
  if source and self:IsTrackableSource(source) then
    self:AddDamage(source, amount, target, "Melee")
    return
  end

  source, target, amount = capture(msg, "^(.+) crits (.+) for (%d+)")
  if source and self:IsTrackableSource(source) then
    self:AddDamage(source, amount, target, "Melee")
    return
  end

  -- DoTs.
  -- Periodic damage. Do not anchor to end-of-line because Vanilla may append
  -- partial resist/absorb text after the terminating period.
  target, amount, spell = capture(msg, "^(.+) suffers (%d+) .+ damage from your (.-)%.")
  if target then
    self:AddDamage(UnitName("player"), amount, target, spell .. " [DOT]")
    return
  end

  target, amount, rest = capture(msg, "^(.+) suffers (%d+) .+ damage from (.-)%.")
  if target then
    source, spell = self:ParseKnownSourceAfterFrom(rest)
    if source then
      self:AddDamage(source, amount, target, spell .. " [DOT]")
      return
    end
  end

  -- Damage shields / reflected damage.
  amount, target = capture(msg, "^You reflect (%d+) .+ damage to (.+)%.$")
  if amount then self:AddDamage(UnitName("player"), amount, target, "Reflection"); return end

  source, amount, target = capture(msg, "^(.+) reflects (%d+) .+ damage to (.+)%.$")
  if source and self:IsTrackableSource(source) then
    self:AddDamage(source, amount, target, "Reflection")
    return
  end

  -- Incoming melee against the player.
  source, amount = capture(msg, "^(.+) hits you for (%d+)")
  if source then self:AddDamageTaken(UnitName("player"), amount, source, "Melee"); return end

  source, amount = capture(msg, "^(.+) crits you for (%d+)")
  if source then self:AddDamageTaken(UnitName("player"), amount, source, "Melee"); return end

  -- Incoming spell against player.
  source, spell, amount = capture(msg, "^(.+)'s (.+) hits you for (%d+)")
  if source then self:AddDamageTaken(UnitName("player"), amount, source, spell); return end

  source, spell, amount = capture(msg, "^(.+)'s (.+) crits you for (%d+)")
  if source then self:AddDamageTaken(UnitName("player"), amount, source, spell); return end

  -- Incoming damage against another group member.
  source, target, amount = capture(msg, "^(.+) hits (.+) for (%d+)")
  if source and target and self:IsKnownGroupMember(normalizeYou(target)) then
    self:AddDamageTaken(target, amount, source, "Melee")
    return
  end

  source, target, amount = capture(msg, "^(.+) crits (.+) for (%d+)")
  if source and target and self:IsKnownGroupMember(normalizeYou(target)) then
    self:AddDamageTaken(target, amount, source, "Melee")
    return
  end

  source, spell, target, amount = capture(msg, "^(.+)'s (.+) hits (.+) for (%d+)")
  if source and target and self:IsKnownGroupMember(normalizeYou(target)) then
    self:AddDamageTaken(target, amount, source, spell)
    return
  end

  source, spell, target, amount = capture(msg, "^(.+)'s (.+) crits (.+) for (%d+)")
  if source and target and self:IsKnownGroupMember(normalizeYou(target)) then
    self:AddDamageTaken(target, amount, source, spell)
    return
  end

  -- Periodic incoming damage.
  amount, rest = capture(msg, "^You suffer (%d+) .+ damage from (.-)%.")
  if amount then
    a, b = string.find(rest, "'s ", 1, true)
    if a then
      source = string.sub(rest, 1, a - 1)
      spell = string.sub(rest, b + 1) .. " [DOT]"
    else
      source = rest
      spell = "Periodic [DOT]"
    end
    self:AddDamageTaken(UnitName("player"), amount, source, spell)
    return
  end

  target, amount, rest = capture(msg, "^(.+) suffers (%d+) .+ damage from (.-)%.")
  if target and self:IsKnownGroupMember(normalizeYou(target)) then
    a, b = string.find(rest, "'s ", 1, true)
    if a then
      source = string.sub(rest, 1, a - 1)
      spell = string.sub(rest, b + 1) .. " [DOT]"
    else
      source = rest
      spell = "Periodic [DOT]"
    end
    self:AddDamageTaken(target, amount, source, spell)
    return
  end

  target = capture(msg, "^(.+) dies%.$")
  if target then self:MarkDeath(target); return end
end

function RV:StartFight()
  if self.inCombat then return end
  self.inCombat = true
  self.currentData = {}
  self.currentFightStart = GetTime()
  self.currentFightEnd = nil
  if self.segmentType == "current" then self.data = self.currentData end
end

function RV:EndFight()
  if not self.inCombat then return end
  self.inCombat = false
  self.currentFightEnd = GetTime()

  local hasData = false
  local _,a
  for _,a in pairs(self.currentData) do
    if (a.damage or 0) > 0 or (a.healing or 0) > 0 then hasData = true break end
  end

  if hasData then
    table.insert(self.fights, 1, {
      label = "Fight " .. tostring(table.getn(self.fights) + 1),
      startTime = self.currentFightStart,
      endTime = self.currentFightEnd,
      data = copyDataset(self.currentData)
    })
    while table.getn(self.fights) > self.maxSavedFights do
      table.remove(self.fights)
    end
  end
  self:Refresh()
end

function RV:GetSelectedData()
  if self.segmentType == "current" then
    return self.currentData
  end
  return self.overallData
end

function RV:GetSegmentLabel()
  if self.segmentType == "current" then
    return "Current Fight"
  end
  return "Overall Data"
end

function RV:SetSegment(kind, index)
  if kind ~= "overall" and kind ~= "current" then
    kind = "overall"
  end

  self.segmentType = kind
  self.segmentIndex = nil
  self.data = self:GetSelectedData()

  if self.segmentMenu then
    self:RefreshSegmentMenu()
    self.segmentMenu:Hide()
  end

  self:Refresh()
end

function RV:GetDuration(actor)
  if not actor or not actor.first then return 0 end
  local ending = actor.last or GetTime()
  local d = ending - actor.first
  if d < 1 then d = 1 end
  return d
end

function RV:GetMetric(actor)
  if self.mode == "damage" then return actor.damage or 0
  elseif self.mode == "dps" then return (actor.damage or 0) / self:GetDuration(actor)
  elseif self.mode == "taken" then return actor.taken or 0
  elseif self.mode == "healing" then return actor.healing or 0
  elseif self.mode == "healingTaken" then return actor.healingTaken or 0
  elseif self.mode == "deaths" then return actor.deaths or 0 end
  return 0
end

function RV:GetMetricText(actor)
  if self.mode == "damage" then
    if self.settings.showPetsMerged and (actor.petDamage or 0) > 0 then
      return tostring(floor((actor.damage or 0) + .5)) .. " (" .. tostring(floor((actor.petDamage or 0) + .5)) .. " pet)"
    end
    return tostring(floor((actor.damage or 0) + .5))
  elseif self.mode == "dps" then
    return format("%.1f", self:GetMetric(actor))
  elseif self.mode == "taken" then
    return tostring(floor((actor.taken or 0) + .5))
  elseif self.mode == "healing" then
    return tostring(floor((actor.healing or 0) + .5))
  elseif self.mode == "healingTaken" then
    return tostring(floor((actor.healingTaken or 0) + .5))
  elseif self.mode == "deaths" then
    return tostring(actor.deaths or 0)
  end
  return ""
end

function RV:GetModeLabel()
  return self.modes[self.modeIndex].label
end

function RV:SetModeIndex(i)
  if i < 1 then i = table.getn(self.modes) end
  if i > table.getn(self.modes) then i = 1 end
  self.modeIndex = i
  self.mode = self.modes[i].key
  self:Refresh()
end

function RV:NextMode() self:SetModeIndex(self.modeIndex + 1) end
function RV:PrevMode() self:SetModeIndex(self.modeIndex - 1) end

function RV:DoReset()
  self.overallData = {}
  self.currentData = {}
  self.data = self.overallData
  self.fights = {}
  self.currentFightStart = nil
  self.currentFightEnd = nil
  self.segmentType = "overall"
  self.segmentIndex = nil
  if self.resetFrame then self.resetFrame:Hide() end
  self:SaveCombatData()
  self:Refresh()
end

function RV:ShowReset()
  if not self.settings.confirmReset then self:DoReset(); return end
  self:CreateResetWindow()
  self.resetFrame:Show()
end

function RV:GetBreakdownForActor(actor)
  local data = actor.spells
  local counts = actor.spellCounts
  local title = "Damage Done"

  if self.mode == "healing" then
    data = actor.healingSpells
    counts = actor.healingSpellCounts
    title = "Healing Done"
  elseif self.mode == "taken" then
    data = actor.takenSources
    counts = actor.takenSourceCounts
    title = "Damage Taken"
  elseif self.mode == "healingTaken" then
    data = actor.healingTakenSources
    counts = actor.healingTakenSourceCounts
    title = "Healing Taken"
  elseif self.mode == "dps" then
    data = actor.spells
    counts = actor.spellCounts
    title = "Damage Done"
  elseif self.mode == "deaths" then
    data = nil
    counts = nil
    title = "Deaths"
  end

  local stats = actor.spellStats
  local events = actor.damageEvents

  if self.mode == "healing" then
    stats = actor.healingStats
    events = actor.healingEvents
  elseif self.mode == "taken" then
    stats = actor.takenStats
    events = actor.takenEvents
  elseif self.mode == "healingTaken" then
    stats = actor.healingTakenStats
    events = actor.healingTakenEvents
  end

  return data, counts, stats, events, title
end

function RV:CreateDetailWindow()
  if self.detailFrame then return end

  local f = CreateFrame("Frame", "RVDetailFrame", UIParent)
  self.detailFrame = f
  f:SetWidth(620)
  f:SetHeight(430)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:SetResizable(true)
  f:SetMinResize(470,320)
  f:SetMaxResize(1000,800)
  createBackdrop(f, .97)
  f:Hide()

  self:CreateTitleBar(f, "Details", 22)
  self:MakeCloseButton(f)

  local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  self.detailHeader = header
  header:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
  header:SetWidth(380)
  header:SetJustifyH("LEFT")
  header:SetTextColor(1,1,1)

  local total = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  self.detailTotal = total
  total:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -38)
  total:SetJustifyH("RIGHT")
  total:SetTextColor(1,.82,0)

  -- Summary table region.
  local tableFrame = CreateFrame("Frame", nil, f)
  self.detailTableFrame = tableFrame
  tableFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -62)
  tableFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -62)
  tableFrame:SetHeight(165)
  createBackdrop(tableFrame, .35)
  tableFrame:EnableMouse(true)
  tableFrame:EnableMouseWheel(true)
  tableFrame:SetScript("OnMouseWheel",function()
    RV:ScrollDetail(arg1)
  end)

  local scrollText = tableFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  self.detailScrollText = scrollText
  scrollText:SetPoint("BOTTOMRIGHT",tableFrame,"BOTTOMRIGHT",-7,5)
  scrollText:SetTextColor(.55,.55,.55)
  scrollText:SetText("")

  local headers = {
    {"Ability / Source", 5, 225, "LEFT"},
    {"Hits", 235, 45, "RIGHT"},
    {"Amount", 285, 65, "RIGHT"},
    {"%", 355, 45, "RIGHT"},
    {"Avg", 405, 55, "RIGHT"},
    {"Min", 465, 55, "RIGHT"},
    {"Max", 525, 55, "RIGHT"},
  }
  self.detailHeaderColumns = {}

  local i
  for i=1,table.getn(headers) do
    local h = tableFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    self.detailHeaderColumns[i]=h
    h:SetPoint("TOPLEFT",tableFrame,"TOPLEFT",headers[i][2],-6)
    h:SetWidth(headers[i][3])
    h:SetJustifyH(headers[i][4])
    h:SetText(headers[i][1])
    h:SetTextColor(1,.82,0)
  end

  self.detailRows = {}
  self.detailScrollOffset = 0
  self.detailVisibleRows = 7

  for i=1,self.detailVisibleRows do
    local row = CreateFrame("Button", nil, tableFrame)
    self.detailRows[i]=row
    row:SetHeight(18)
    row:SetPoint("TOPLEFT",tableFrame,"TOPLEFT",4,-25-((i-1)*19))
    row:SetPoint("TOPRIGHT",tableFrame,"TOPRIGHT",-4,-25-((i-1)*19))

    if math.mod(i,2)==0 then
      local bg=row:CreateTexture(nil,"BACKGROUND")
      bg:SetAllPoints(row)
      bg:SetTexture(.08,.08,.08,.40)
    end

    row.cols={}
    local widths={225,45,65,45,55,55,55}
    local offsets={0,230,280,350,400,460,520}
    local aligns={"LEFT","RIGHT","RIGHT","RIGHT","RIGHT","RIGHT","RIGHT"}
    local c
    for c=1,7 do
      local fs=row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
      row.cols[c]=fs
      fs:SetPoint("LEFT",row,"LEFT",offsets[c],0)
      fs:SetWidth(widths[c])
      fs:SetJustifyH(aligns[c])
      fs:SetTextColor(.95,.95,.95)
    end

    row:SetScript("OnClick",function()
      if this.detailKey then
        RV.detailSelectedKey=this.detailKey
        RV:RefreshDetailSelection()
      end
    end)
  end

  -- Bottom split region: graph left, selected ability stats right.
  local graph = CreateFrame("Frame", nil, f)
  self.detailGraph = graph
  graph:SetPoint("TOPLEFT", tableFrame, "BOTTOMLEFT", 0, -8)
  graph:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
  graph:SetWidth(290)
  createBackdrop(graph, .35)

  local graphTitle = graph:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  graphTitle:SetPoint("TOPLEFT",graph,"TOPLEFT",8,-6)
  graphTitle:SetText("Activity Over Time")
  graphTitle:SetTextColor(1,.82,0)

  self.graphBars={}
  for i=1,24 do
    local bar=graph:CreateTexture(nil,"ARTWORK")
    self.graphBars[i]=bar
    bar:SetTexture(.85,.08,.08,1)
    bar:SetWidth(8)
    bar:SetHeight(1)
    bar:SetPoint("BOTTOMLEFT",graph,"BOTTOMLEFT",12+((i-1)*11),24)
  end

  self.graphScaleText=graph:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  self.graphScaleText:SetPoint("BOTTOMLEFT",graph,"BOTTOMLEFT",8,6)
  self.graphScaleText:SetTextColor(.65,.65,.65)

  local statsFrame = CreateFrame("Frame", nil, f)
  self.detailStatsFrame = statsFrame
  statsFrame:SetPoint("TOPLEFT", graph, "TOPRIGHT", 8, 0)
  statsFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -235)
  statsFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
  createBackdrop(statsFrame, .35)

  self.detailSelectedTitle=statsFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
  self.detailSelectedTitle:SetPoint("TOPLEFT",statsFrame,"TOPLEFT",8,-8)
  self.detailSelectedTitle:SetWidth(280)
  self.detailSelectedTitle:SetJustifyH("LEFT")
  self.detailSelectedTitle:SetTextColor(1,.82,0)

  self.detailStatLines={}
  for i=1,7 do
    local fs=statsFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    self.detailStatLines[i]=fs
    fs:SetPoint("TOPLEFT",statsFrame,"TOPLEFT",10,-35-((i-1)*20))
    fs:SetWidth(280)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(.92,.92,.92)
  end

  -- Bottom-right resize grip.
  local rightGrip=CreateFrame("Button",nil,f)
  self.detailResizeRight=rightGrip
  rightGrip:SetWidth(20)
  rightGrip:SetHeight(20)
  rightGrip:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-3,3)
  rightGrip:SetFrameLevel(f:GetFrameLevel()+25)
  rightGrip:EnableMouse(true)

  local rightTex=rightGrip:CreateTexture(nil,"OVERLAY")
  rightTex:SetAllPoints(rightGrip)
  rightTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  rightTex:SetVertexColor(.85,.85,.85,1)
  rightGrip.texture=rightTex

  rightGrip:SetScript("OnEnter",function()
    if this.texture then this.texture:SetVertexColor(1,1,1,1) end
  end)
  rightGrip:SetScript("OnLeave",function()
    if this.texture then this.texture:SetVertexColor(.85,.85,.85,1) end
  end)
  rightGrip:SetScript("OnMouseDown",function()
    if arg1=="LeftButton" then
      RV.detailFrame:StartSizing("BOTTOMRIGHT")
    end
  end)
  rightGrip:SetScript("OnMouseUp",function()
    RV.detailFrame:StopMovingOrSizing()
    RV:LayoutDetailWindow()
  end)

  -- Bottom-left resize grip, mirrored like the main window.
  local leftGrip=CreateFrame("Button",nil,f)
  self.detailResizeLeft=leftGrip
  leftGrip:SetWidth(20)
  leftGrip:SetHeight(20)
  leftGrip:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",3,3)
  leftGrip:SetFrameLevel(f:GetFrameLevel()+25)
  leftGrip:EnableMouse(true)

  local leftTex=leftGrip:CreateTexture(nil,"OVERLAY")
  leftTex:SetAllPoints(leftGrip)
  leftTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  leftTex:SetTexCoord(1,0,0,1)
  leftTex:SetVertexColor(.85,.85,.85,1)
  leftGrip.texture=leftTex

  leftGrip:SetScript("OnEnter",function()
    if this.texture then this.texture:SetVertexColor(1,1,1,1) end
  end)
  leftGrip:SetScript("OnLeave",function()
    if this.texture then this.texture:SetVertexColor(.85,.85,.85,1) end
  end)
  leftGrip:SetScript("OnMouseDown",function()
    if arg1=="LeftButton" then
      RV.detailFrame:StartSizing("BOTTOMLEFT")
    end
  end)
  leftGrip:SetScript("OnMouseUp",function()
    RV.detailFrame:StopMovingOrSizing()
    RV:LayoutDetailWindow()
  end)

  f:SetScript("OnSizeChanged",function()
    RV:LayoutDetailWindow()
  end)
end


function RV:LayoutDetailWindow()
  local f=self.detailFrame
  if not f then return end

  local w=f:GetWidth()
  local h=f:GetHeight()

  -- Summary table expands horizontally with the window.
  -- Keep the lower half split roughly 48/52 between graph and selected stats.
  local graphW=floor((w-36)*.48)
  if graphW<210 then graphW=210 end

  self.detailGraph:SetWidth(graphW)

  -- Lower panels grow/shrink vertically with the dashboard.
  local lowerTop = 235
  local lowerHeight = h - lowerTop - 10
  if lowerHeight < 95 then lowerHeight = 95 end

  self.detailGraph:ClearAllPoints()
  self.detailGraph:SetPoint("TOPLEFT", self.detailTableFrame, "BOTTOMLEFT", 0, -8)
  self.detailGraph:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
  self.detailGraph:SetWidth(graphW)

  self.detailStatsFrame:ClearAllPoints()
  self.detailStatsFrame:SetPoint("TOPLEFT", self.detailGraph, "TOPRIGHT", 8, 0)
  self.detailStatsFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -235)
  self.detailStatsFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)

  -- Stretch graph bars across available graph width.
  local usable=graphW-24
  local barW=floor(usable/24)-2
  if barW<2 then barW=2 end

  local i
  for i=1,24 do
    local b=self.graphBars[i]
    b:ClearAllPoints()
    b:SetWidth(barW)
    b:SetPoint("BOTTOMLEFT",self.detailGraph,"BOTTOMLEFT",12+((i-1)*(barW+2)),24)
  end

  -- Refresh bar heights because graph height may have changed.
  if self.detailActor then
    local breakdown, counts, stats, events = self:GetBreakdownForActor(self.detailActor)
    self:RefreshDetailGraph(events)
  end
end

function RV:RefreshDetailGraph(events)
  local bars=self.graphBars
  local i
  for i=1,24 do bars[i]:SetHeight(1) end

  if not events or table.getn(events)==0 then
    self.graphScaleText:SetText("No activity")
    return
  end

  local first=events[1].time
  local last=events[table.getn(events)].time
  local span=last-first
  if span<1 then span=1 end

  local bins={}
  for i=1,24 do bins[i]=0 end

  local e
  for i=1,table.getn(events) do
    e=events[i]
    local pos=(e.time-first)/span
    local idx=floor(pos*23)+1
    if idx<1 then idx=1 end
    if idx>24 then idx=24 end
    bins[idx]=bins[idx]+(e.amount or 0)
  end

  local max=1
  for i=1,24 do if bins[i]>max then max=bins[i] end end

  local maxH=self.detailGraph:GetHeight()-55
  if maxH<20 then maxH=20 end
  for i=1,24 do
    self.graphBars[i]:SetHeight(math.max(1,(bins[i]/max)*maxH))
  end

  self.graphScaleText:SetText(format("%.1fs activity",span))
end

function RV:RefreshDetailSelection()
  if not self.detailActor then return end

  local breakdown, counts, stats, events, breakdownTitle=self:GetBreakdownForActor(self.detailActor)
  local key=self.detailSelectedKey
  if not key and self.detailSorted and self.detailSorted[1] then
    key=self.detailSorted[1].name
    self.detailSelectedKey=key
  end

  self.detailSelectedTitle:SetText(key or "No ability selected")

  local s = stats and key and stats[key] or nil
  local lines=self.detailStatLines
  local i
  for i=1,7 do lines[i]:SetText("") end

  if s then
    local avg=0
    if (s.count or 0)>0 then avg=(s.amount or 0)/(s.count or 1) end
    lines[1]:SetText("Count: "..tostring(s.count or 0))
    lines[2]:SetText("Amount: "..tostring(floor((s.amount or 0)+.5)))
    lines[3]:SetText("Average: "..format("%.1f",avg))
    lines[4]:SetText("Minimum: "..tostring(floor((s.min or 0)+.5)))
    lines[5]:SetText("Maximum: "..tostring(floor((s.max or 0)+.5)))
  end

  self:RefreshDetailGraph(events)
end

function RV:RefreshDetailRows()
  if not self.detailActor or not self.detailSorted then return end

  local actor = self.detailActor
  local sorted = self.detailSorted
  local denom = 0

  if self.mode=="healing" then
    denom=actor.healing or 0
  elseif self.mode=="taken" then
    denom=actor.taken or 0
  elseif self.mode=="healingTaken" then
    denom=actor.healingTaken or 0
  else
    denom=actor.damage or 0
  end

  local i
  for i=1,self.detailVisibleRows do
    local row=self.detailRows[i]
    local idx=(self.detailScrollOffset or 0)+i
    local item=sorted[idx]

    if item then
      local pct=0
      if denom>0 then pct=(item.value/denom)*100 end
      local avg=0
      if item.count>0 then avg=item.value/item.count end

      row.detailKey=item.name
      row:Show()
      row.cols[1]:SetText(idx..". "..item.name)
      row.cols[2]:SetText(tostring(item.count))
      row.cols[3]:SetText(tostring(floor(item.value+.5)))
      row.cols[4]:SetText(format("%.1f",pct))
      row.cols[5]:SetText(format("%.1f",avg))
      row.cols[6]:SetText(tostring(floor((item.min or 0)+.5)))
      row.cols[7]:SetText(tostring(floor((item.max or 0)+.5)))
    else
      row.detailKey=nil
      local c
      for c=1,7 do row.cols[c]:SetText("") end
    end
  end

  if self.detailScrollText then
    local total=table.getn(sorted)
    if total > self.detailVisibleRows then
      self.detailScrollText:SetText(
        tostring((self.detailScrollOffset or 0)+1) .. "-" ..
        tostring(math.min((self.detailScrollOffset or 0)+self.detailVisibleRows,total)) ..
        " / " .. tostring(total)
      )
    else
      self.detailScrollText:SetText("")
    end
  end
end

function RV:ScrollDetail(delta)
  if not self.detailSorted then return end

  local maxOffset=table.getn(self.detailSorted)-(self.detailVisibleRows or 7)
  if maxOffset<0 then maxOffset=0 end

  self.detailScrollOffset=(self.detailScrollOffset or 0)-(delta or 0)
  if self.detailScrollOffset<0 then self.detailScrollOffset=0 end
  if self.detailScrollOffset>maxOffset then self.detailScrollOffset=maxOffset end

  self:RefreshDetailRows()
end

function RV:ShowActorDetails(actor)
  if not actor then return end
  self:CreateDetailWindow()

  self.detailActor=actor
  self.detailSelectedKey=nil
  self.detailScrollOffset=0

  local breakdown, counts, stats, events, breakdownTitle = self:GetBreakdownForActor(actor)

  self.detailHeader:SetText(actor.name .. " - " .. breakdownTitle)

  local totalValue = self:GetMetric(actor)
  local totalText
  if self.mode == "dps" then
    totalText = format("%.1f", totalValue)
  else
    totalText = tostring(floor((totalValue or 0) + .5))
  end
  self.detailTotal:SetText("Total: " .. totalText)

  local sorted={}
  if breakdown then
    local name,value
    for name,value in pairs(breakdown) do
      local s=stats and stats[name] or nil
      table.insert(sorted,{
        name=name,
        value=value,
        count=(counts and counts[name]) or 0,
        min=s and s.min or 0,
        max=s and s.max or 0
      })
    end
    table.sort(sorted,function(a,b) return a.value>b.value end)
  end
  self.detailSorted=sorted

  local denom=0
  if self.mode=="healing" then denom=actor.healing or 0
  elseif self.mode=="taken" then denom=actor.taken or 0
  elseif self.mode=="healingTaken" then denom=actor.healingTaken or 0
  else denom=actor.damage or 0 end

  self:RefreshDetailRows()

  if sorted[1] then self.detailSelectedKey=sorted[1].name end
  self:RefreshDetailSelection()
  self:LayoutDetailWindow()
  self.detailFrame:Show()
end

function RV:GetSortedActors()
  local data = self:GetSelectedData()
  local list = {}
  local _,actor
  for _,actor in pairs(data) do
    if self:GetMetric(actor) > 0 and self:IsActorVisibleByFilter(actor) then
      table.insert(list, actor)
    end
  end
  table.sort(list, function(a,b) return RV:GetMetric(a) > RV:GetMetric(b) end)
  return list
end

function RV:Refresh()
  if not self.frame then return end
  self.data = self:GetSelectedData()

  local list = self:GetSortedActors()
  local maxValue = 1
  if list[1] then maxValue = self:GetMetric(list[1]) end
  if maxValue <= 0 then maxValue = 1 end

  self.title:SetText(self:GetModeLabel())
  if self.segmentText then self.segmentText:SetText(self:GetSegmentLabel()) end

  local i
  for i = 1, self.maxRows do
    local row = self.rows[i]
    local actor = list[i]
    if actor then
      local value = self:GetMetric(actor)
      row.actor = actor
      row:Show()
      row.bar:SetMinMaxValues(0, maxValue)
      row.bar:SetValue(value)
      row.bar:SetStatusBarColor(actor.r or .75, actor.g or .25, actor.b or .25)
      row.name:SetText(i .. ". " .. actor.name)
      if self.settings.showPetsMerged and (actor.petDamage or 0) > 0 then
        row.name:SetText(i .. ". " .. actor.name .. " |cffaaaaaa+pet|r")
      end
      row.value:SetText(self:GetMetricText(actor))
    else
      row.actor = nil
      row:Hide()
    end
  end
end

local function RowEnter()
  local actor = this.actor
  if not actor then return end
  GameTooltip:SetOwner(this, "ANCHOR_LEFT")
  GameTooltip:SetText(actor.name, 1,.82,0)
  GameTooltip:AddDoubleLine("Damage", formatNumber(actor.damage), 1,1,1,.9,.9,.9)
  if (actor.petDamage or 0) > 0 then
    GameTooltip:AddDoubleLine("Pet Damage", formatNumber(actor.petDamage), 1,1,1,.4,1,.4)
    local pet,amount
    for pet,amount in pairs(actor.pets) do
      GameTooltip:AddDoubleLine("  "..pet, formatNumber(amount), .7,.7,.7,.7,.7,.7)
    end
  end
  GameTooltip:AddDoubleLine("DPS", format("%.1f", actor.damage / RV:GetDuration(actor)),1,1,1,.9,.9,.9)
  GameTooltip:AddDoubleLine("Healing",formatNumber(actor.healing),1,1,1,.9,.9,.9)
  GameTooltip:AddDoubleLine("Healing Taken",formatNumber(actor.healingTaken),1,1,1,.9,.9,.9)
  GameTooltip:AddDoubleLine("Damage Taken",formatNumber(actor.taken),1,1,1,.9,.9,.9)
  GameTooltip:AddDoubleLine("Deaths",tostring(actor.deaths or 0),1,1,1,.9,.9,.9)
  GameTooltip:Show()
end
local function RowLeave() GameTooltip:Hide() end

function RV:ClassFilterDropDown_Initialize()
  local classes = {
    {"WARRIOR","Warrior"},
    {"ROGUE","Rogue"},
    {"PRIEST","Priest"},
    {"HUNTER","Hunter"},
    {"DRUID","Druid"},
    {"MAGE","Mage"},
    {"WARLOCK","Warlock"},
    {"PALADIN","Paladin"},
    {"SHAMAN","Shaman"}
  }

  local function toggle_class()
    local token = this.value
    RV.settings.classFilter[token] = not RV.settings.classFilter[token]
    RV:SaveSettings()
    RV:Refresh()

    -- Keep the menu open while toggling multiple classes.
    ToggleDropDownMenu(1, nil, RV.classFilterDropDown, nil, nil, nil)
  end

  local i
  for i = 1, table.getn(classes) do
    local token = classes[i][1]
    local label = classes[i][2]

    UIDropDownMenu_AddButton({
      text = label,
      value = token,
      checked = RV.settings.classFilter[token] and true or false,
      keepShownOnClick = true,
      func = toggle_class
    })
  end

  UIDropDownMenu_AddButton({
    text = "All",
    value = "__ALL__",
    checked = false,
    func = function()
      local j
      for j = 1, table.getn(classes) do
        RV.settings.classFilter[classes[j][1]] = true
      end
      RV:SaveSettings()
      RV:Refresh()
    end
  })

  UIDropDownMenu_AddButton({
    text = "None",
    value = "__NONE__",
    checked = false,
    func = function()
      local j
      for j = 1, table.getn(classes) do
        RV.settings.classFilter[classes[j][1]] = false
      end
      RV:SaveSettings()
      RV:Refresh()
    end
  })
end

function RV:GetClassFilterSummary()
  local classes = {
    "WARRIOR","ROGUE","PRIEST","HUNTER","DRUID",
    "MAGE","WARLOCK","PALADIN","SHAMAN"
  }

  local enabled = 0
  local i
  for i = 1, table.getn(classes) do
    if self.settings.classFilter[classes[i]] then
      enabled = enabled + 1
    end
  end

  if enabled == 9 then
    return "All Classes"
  elseif enabled == 0 then
    return "No Classes"
  else
    return tostring(enabled) .. " / 9 Classes"
  end
end

function RV:CreateFilterMenu()
  if self.filterMenu then return end

  local f = CreateFrame("Frame", "RVFilterMenu", UIParent)
  self.filterMenu = f
  f:SetWidth(215)
  f:SetHeight(100)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  createBackdrop(f,.98)
  f:Hide()

  self:CreateTitleBar(f, "Class Filters", 22)
  self:MakeCloseButton(f)

  local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -38)
  label:SetText("Classes")

  local dropdown = CreateFrame(
    "Frame",
    "RVClassFilterDropDown",
    f,
    "UIDropDownMenuTemplate"
  )
  self.classFilterDropDown = dropdown
  dropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -50)

  UIDropDownMenu_Initialize(
    dropdown,
    function()
      RV:ClassFilterDropDown_Initialize()
    end
  )
  UIDropDownMenu_SetWidth(160, dropdown)
  UIDropDownMenu_SetText(self:GetClassFilterSummary(), dropdown)
end

function RV:RefreshFilterMenu()
  if self.classFilterDropDown then
    UIDropDownMenu_SetText(
      self:GetClassFilterSummary(),
      self.classFilterDropDown
    )
  end
end

function RV:ToggleFilterMenu()
  self:CreateFilterMenu()
  self:RefreshFilterMenu()

  if self.filterMenu:IsShown() then
    self.filterMenu:Hide()
  else
    self.filterMenu:ClearAllPoints()
    self.filterMenu:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -35, -24)
    self.filterMenu:Show()
  end
end


function RV:GetSegmentDisplayLabel()
  if self.segmentType == "current" then
    return "Current Fight"
  end
  return "Overall Data"
end

function RV:SegmentDropDown_Initialize()
  local function select_segment()
    local value = this.value

    if value == "Current Fight" then
      RV:SetSegment("current")
    else
      RV:SetSegment("overall")
    end

    UIDropDownMenu_SetSelectedValue(
      RV.segmentDropDown,
      RV:GetSegmentDisplayLabel()
    )
  end

  UIDropDownMenu_AddButton({
    text = "Overall Data",
    value = "Overall Data",
    checked = (RV.segmentType ~= "current"),
    func = select_segment
  })

  UIDropDownMenu_AddButton({
    text = "Current Fight",
    value = "Current Fight",
    checked = (RV.segmentType == "current"),
    func = select_segment
  })

  UIDropDownMenu_SetSelectedValue(
    RV.segmentDropDown,
    RV:GetSegmentDisplayLabel()
  )
end

function RV:CreateSegmentMenu()
  if self.segmentMenu then return end

  local f = CreateFrame("Frame", "RVSegmentMenu", UIParent)
  self.segmentMenu = f
  f:SetWidth(215)
  f:SetHeight(100)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  createBackdrop(f,.98)
  f:Hide()

  self:CreateTitleBar(f, "Segment", 22)
  self:MakeCloseButton(f)

  local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -38)
  label:SetText("Segment")

  local dropdown = CreateFrame(
    "Frame",
    "RVSegmentDropDown",
    f,
    "UIDropDownMenuTemplate"
  )
  self.segmentDropDown = dropdown
  dropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -50)

  UIDropDownMenu_Initialize(
    dropdown,
    function()
      RV:SegmentDropDown_Initialize()
    end
  )
  UIDropDownMenu_SetWidth(160, dropdown)
  UIDropDownMenu_SetSelectedValue(
    dropdown,
    self:GetSegmentDisplayLabel()
  )
end

function RV:RefreshSegmentMenu()
  if self.segmentDropDown then
    UIDropDownMenu_SetSelectedValue(
      self.segmentDropDown,
      self:GetSegmentDisplayLabel()
    )
  end
end

function RV:ToggleSegmentMenu()
  self:CreateSegmentMenu()
  self:RefreshSegmentMenu()

  if self.segmentMenu:IsShown() then
    self.segmentMenu:Hide()
  else
    self.segmentMenu:ClearAllPoints()
    self.segmentMenu:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -55, -24)
    self.segmentMenu:Show()
  end
end


function RV:BuildReportChannelOptions()
  self.reportChannelOptions = {}

  local function add(label, channel, chatNumber)
    self.reportChannelOptions[label] = {
      channel = channel,
      chatNumber = chatNumber
    }
  end

  add("Say", "SAY", nil)
  add("Whisper", "WHISPER", nil)
  add("Party", "PARTY", nil)
  add("Raid", "RAID", nil)
  add("Officer", "OFFICER", nil)
  add("Guild", "GUILD", nil)

  local i
  for i = 1, 25 do
    local id, name = GetChannelName(i)
    if id and id > 0 and name and name ~= "" then
      add(tostring(i) .. ". " .. name, "CHANNEL", id)
    end
  end
end

function RV:ReportChannelDropDown_Initialize()
  RV:BuildReportChannelOptions()

  local order = {
    "Say",
    "Whisper",
    "Party",
    "Raid",
    "Officer",
    "Guild"
  }

  local function select_channel()
    local label = this.value
    local opt = RV.reportChannelOptions[label]
    if not opt then return end

    RV.reportChannelLabel = label
    RV.reportChannel = opt.channel
    RV.reportChatNumber = opt.chatNumber

    UIDropDownMenu_SetSelectedValue(RV.reportChannelDropDown, label)
    RV:RefreshReportChannel()
  end

  local i
  for i = 1, table.getn(order) do
    local label = order[i]
    UIDropDownMenu_AddButton({
      text = label,
      value = label,
      func = select_channel
    })
  end

  -- Add currently joined numbered chat channels after the standard choices.
  for i = 1, 25 do
    local id, name = GetChannelName(i)
    if id and id > 0 and name and name ~= "" then
      local label = tostring(i) .. ". " .. name
      UIDropDownMenu_AddButton({
        text = label,
        value = label,
        func = select_channel
      })
    end
  end

  UIDropDownMenu_SetSelectedValue(
    RV.reportChannelDropDown,
    RV.reportChannelLabel or "Party"
  )
end

function RV:RefreshReportChannel()
  if not self.reportChannelLabel then
    self.reportChannelLabel = "Party"
  end

  if self.reportChannelDropDown then
    UIDropDownMenu_SetSelectedValue(
      self.reportChannelDropDown,
      self.reportChannelLabel
    )
  end

  if self.reportWhisper then
    -- Keep the target box usable at all times. It is only read when
    -- Whisper is the selected report channel, but users can pre-fill it.
    self.reportWhisper:EnableMouse(true)
    self.reportWhisper:SetTextColor(1,1,1)
  end
end

function RV:CreateReportWindow()
  if self.reportFrame then return end

  local f=CreateFrame("Frame","RVReportFrame",UIParent)
  self.reportFrame=f
  f:SetWidth(260)
  f:SetHeight(270)
  f:SetPoint("CENTER",UIParent,"CENTER",-250,0)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  createBackdrop(f,.96)
  f:Hide()

  self:CreateTitleBar(f, "Report Data", 22)
  self:MakeCloseButton(f)

  self.reportChannel = "PARTY"
  self.reportChannelLabel = "Party"
  self.reportChatNumber = nil
  self.reportDelay = false

  local channelLabel=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
  channelLabel:SetPoint("TOPLEFT",f,"TOPLEFT",17,-38)
  channelLabel:SetText("Channel")

  -- This is the exact built-in Vanilla dropdown mechanism DPSMate uses.
  local dropdown=CreateFrame(
    "Frame",
    "RVReportChannelDropDown",
    f,
    "UIDropDownMenuTemplate"
  )
  self.reportChannelDropDown=dropdown
  dropdown:SetPoint("TOPLEFT",f,"TOPLEFT",0,-50)

  UIDropDownMenu_Initialize(
    dropdown,
    function()
      RV:ReportChannelDropDown_Initialize()
    end
  )
  UIDropDownMenu_SetWidth(145, dropdown)
  UIDropDownMenu_SetSelectedValue(dropdown, "Party")

  local delay=CreateFrame("CheckButton",nil,f,"UICheckButtonTemplate")
  self.reportDelayCheck=delay
  delay:SetWidth(22)
  delay:SetHeight(22)
  delay:SetPoint("TOPRIGHT",f,"TOPRIGHT",-54,-58)
  delay:SetScript("OnClick",function()
    RV.reportDelay=this:GetChecked() and true or false
  end)

  local delayText=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  delayText:SetPoint("LEFT",delay,"RIGHT",0,0)
  delayText:SetText("Delay")

  local topLabel=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  topLabel:SetPoint("TOPLEFT",f,"TOPLEFT",17,-101)
  topLabel:SetText("Report Top:")

  local edit=CreateFrame("EditBox",nil,f,"InputBoxTemplate")
  self.reportTop=edit
  edit:SetWidth(42)
  edit:SetHeight(20)
  edit:SetPoint("LEFT",topLabel,"RIGHT",8,0)
  edit:SetText("10")
  edit:SetAutoFocus(false)

  local whisperLabel=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  whisperLabel:SetPoint("TOPLEFT",f,"TOPLEFT",17,-136)
  whisperLabel:SetText("Whisper Target  (player name)")

  local whisper=CreateFrame("EditBox",nil,f,"InputBoxTemplate")
  self.reportWhisper=whisper
  whisper:SetWidth(215)
  whisper:SetHeight(24)
  whisper:SetPoint("TOPLEFT",f,"TOPLEFT",17,-154)
  whisper:SetAutoFocus(false)
  whisper:EnableMouse(true)
  whisper:SetTextColor(1,1,1)
  whisper:SetTextInsets(6,6,0,0)

  -- Slight dark fill so the text-entry area is easy to see against the world.
  local whisperBG=whisper:CreateTexture(nil,"BACKGROUND")
  whisperBG:SetPoint("TOPLEFT",whisper,"TOPLEFT",-3,2)
  whisperBG:SetPoint("BOTTOMRIGHT",whisper,"BOTTOMRIGHT",3,-2)
  whisperBG:SetTexture(.03,.03,.03,.85)
  whisper.whisperBG=whisperBG

  local help=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  help:SetPoint("TOPLEFT",f,"TOPLEFT",17,-188)
  help:SetWidth(220)
  help:SetJustifyH("LEFT")
  help:SetText("Choose a channel, number of lines, then Report.")
  help:SetTextColor(.65,.65,.65)

  local send=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
  send:SetWidth(155)
  send:SetHeight(24)
  send:SetPoint("BOTTOM",f,"BOTTOM",0,13)
  send:SetText("Report")
  send:SetScript("OnClick",function() RV:SendReport() end)

  self:RefreshReportChannel()
end

function RV:SendReportLine(text, channel, target, chatNumber)
  if channel=="CHANNEL" then
    SendChatMessage(text, "CHANNEL", nil, chatNumber)
  else
    SendChatMessage(text, channel, nil, target)
  end
end

function RV:SendReport()
  local list=self:GetSortedActors()
  local top=tonumber(self.reportTop:GetText()) or 10
  if top<1 then top=1 end
  if top>25 then top=25 end
  if top>table.getn(list) then top=table.getn(list) end

  local channel=self.reportChannel or "PARTY"
  local target=nil
  local chatNumber=self.reportChatNumber

  if channel=="WHISPER" then
    target=trim(self.reportWhisper:GetText() or "")
    if target=="" then
      DEFAULT_CHAT_FRAME:AddMessage(
        "|cffffcc00Recount:|r enter a Whisper Target first."
      )
      return
    end
  end

  if channel=="CHANNEL" and not chatNumber then
    DEFAULT_CHAT_FRAME:AddMessage(
      "|cffffcc00Recount:|r select a valid chat channel."
    )
    return
  end

  self.reportQueue={}
  table.insert(
    self.reportQueue,
    "Recount - "..self:GetModeLabel().." - "..self:GetSegmentLabel()
  )

  local i
  for i=1,top do
    local a=list[i]
    table.insert(
      self.reportQueue,
      i..". "..a.name.." - "..self:GetMetricText(a)
    )
  end

  self.reportQueueChannel=channel
  self.reportQueueTarget=target
  self.reportQueueChatNumber=chatNumber

  if self.reportDelay then
    self.reportQueueTimer=0
    self.reportQueueActive=true
  else
    for i=1,table.getn(self.reportQueue) do
      self:SendReportLine(
        self.reportQueue[i],
        channel,
        target,
        chatNumber
      )
    end
    self.reportQueue={}
    self.reportQueueActive=false
  end
end


function RV:CreateResetWindow()
  if self.resetFrame then return end
  local f=CreateFrame("Frame","RVResetFrame",UIParent)
  self.resetFrame=f
  f:SetWidth(190); f:SetHeight(85); f:SetPoint("CENTER",UIParent,"CENTER",0,80)
  f:SetFrameStrata("FULLSCREEN_DIALOG"); createBackdrop(f,.98); f:Hide()
  local bar = self:CreateTitleBar(f, "Reset Recount?", 22)
  local q=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  q:SetPoint("TOP",f,"TOP",0,-38); q:SetText("Do you wish to reset the data?")
  local yes=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
  yes:SetWidth(70); yes:SetHeight(22); yes:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",18,10)
  yes:SetText("Yes"); yes:SetScript("OnClick",function() RV:DoReset() end)
  local no=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
  no:SetWidth(70); no:SetHeight(22); no:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-18,10)
  no:SetText("No"); no:SetScript("OnClick",function() RV.resetFrame:Hide() end)
end

function RV:CreateConfigWindow()
  if self.configFrame then return end
  local f=CreateFrame("Frame","RVConfigFrame",UIParent)
  self.configFrame=f
  f:SetWidth(510); f:SetHeight(330); f:SetPoint("CENTER",UIParent,"CENTER",0,20)
  f:SetFrameStrata("DIALOG"); createBackdrop(f,.97); f:Hide()

  local bar = self:CreateTitleBar(f, "Config Recount", 22)
  local close=self:MakeCloseButton(f)

  self.configPages={}
  local tabs={"Data","Window","Appearance","Color"}
  local i
  for i=1,4 do
    local idx=i
    local b=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    b:SetWidth(110); b:SetHeight(22); b:SetPoint("TOPLEFT",f,"TOPLEFT",12+((i-1)*120),-35)
    b:SetText(tabs[i]); b:SetScript("OnClick",function() RV:ShowConfigPage(idx) end)

    local p=CreateFrame("Frame",nil,f); self.configPages[i]=p
    p:SetPoint("TOPLEFT",f,"TOPLEFT",15,-68); p:SetWidth(475); p:SetHeight(240); p:Hide()
  end

  local function checkbox(parent,text,y,checked,func)
    local c=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate")
    c:SetPoint("TOPLEFT",parent,"TOPLEFT",0,y); c:SetWidth(24); c:SetHeight(24)
    c:SetChecked(checked and 1 or nil)
    local l=parent:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    l:SetPoint("LEFT",c,"RIGHT",2,0); l:SetText(text)
    c:SetScript("OnClick",func); return c
  end

  checkbox(self.configPages[1],"Merge Pets with Owners",-5,self.settings.showPetsMerged,
    function() RV.settings.showPetsMerged=this:GetChecked() and true or false; RV:SaveSettings(); RV:Refresh() end)
  checkbox(self.configPages[1],"Confirm Reset",-35,self.settings.confirmReset,
    function() RV.settings.confirmReset=this:GetChecked() and true or false; RV:SaveSettings() end)
  checkbox(self.configPages[1],"Auto Delete on New Group",-65,self.settings.autoDeleteOnNewGroup,
    function() RV.settings.autoDeleteOnNewGroup=this:GetChecked() and true or false; RV:SaveSettings() end)

  checkbox(self.configPages[2],"Lock Window",-5,self.settings.locked,
    function() RV.settings.locked=this:GetChecked() and true or false; RV:SaveSettings(); RV:ApplyWindowSettings() end)
  checkbox(self.configPages[2],"Show Background",-35,self.settings.showBackground,
    function() RV.settings.showBackground=this:GetChecked() and true or false; RV:SaveSettings(); RV:ApplyWindowSettings() end)

  local scaleLabel=self.configPages[2]:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  scaleLabel:SetPoint("TOPLEFT",self.configPages[2],"TOPLEFT",5,-75); scaleLabel:SetText("Scale")
  local scale=CreateFrame("Slider",nil,self.configPages[2],"OptionsSliderTemplate")
  scale:SetWidth(180); scale:SetPoint("LEFT",scaleLabel,"RIGHT",20,0)
  scale:SetMinMaxValues(.7,1.5); scale:SetValueStep(.1); scale:SetValue(self.settings.scale)
  scale:SetScript("OnValueChanged",function() RV.settings.scale=this:GetValue(); RV:SaveSettings(); RV:ApplyWindowSettings() end)

  local a=self.configPages[3]:CreateFontString(nil,"OVERLAY","GameFontNormal")
  a:SetPoint("TOPLEFT",self.configPages[3],"TOPLEFT",0,-5)
  a:SetText("Appearance")
  local a2=self.configPages[3]:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  a2:SetPoint("TOPLEFT",a,"BOTTOMLEFT",0,-12)
  a2:SetText("Recount-style bars, compact title bar, and class-colored rows.")

  checkbox(self.configPages[4],"Use Class Colors",-5,self.settings.classColors,
    function() RV.settings.classColors=this:GetChecked() and true or false; RV:SaveSettings(); RV:Refresh() end)

  self:ShowConfigPage(1)
end

function RV:ShowConfigPage(index)
  local i
  for i=1,table.getn(self.configPages) do
    if i==index then self.configPages[i]:Show() else self.configPages[i]:Hide() end
  end
end

function RV:ApplyWindowSettings()
  if not self.frame then return end
  self.frame:SetScale(self.settings.scale or 1)
  if self.settings.locked then
    self.frame:SetMovable(false)
    if self.resizeGrip then self.resizeGrip:Hide() end
    if self.resizeGripLeft then self.resizeGripLeft:Hide() end
  else
    self.frame:SetMovable(true)
    if self.resizeGrip then self.resizeGrip:Show() end
    if self.resizeGripLeft then self.resizeGripLeft:Show() end
  end
  if self.settings.showBackground then
    self.frame:SetBackdropColor(.015,.015,.015,.97)
  else
    self.frame:SetBackdropColor(0,0,0,0)
  end
end

function RV:CreateUI()
  if self.frame then return end

  local f=CreateFrame("Frame","RecountFrame",UIParent)
  self.frame=f
  f:SetWidth(self.layout.width or 320)
  f:SetHeight(self.layout.height or 238)
  f:SetPoint("CENTER",UIParent,"CENTER",300,0)
  f:SetMovable(true)
  f:SetResizable(true)
  f:SetMinResize(220,140)
  f:SetMaxResize(700,700)
  f:EnableMouse(true)
  createBackdrop(f,.97)

  -- Recount-style red title bar. Drag ONLY the title bar to move the window.
  local titleBar = self:CreateTitleBar(f, "", 22)
  self.titleBar = titleBar

  local title=titleBar:CreateFontString(nil,"OVERLAY","GameFontNormal")
  self.title=title
  title:SetPoint("LEFT",titleBar,"LEFT",7,0)
  title:SetWidth(135)
  title:SetJustifyH("LEFT")
  title:SetText("Damage Done")
  title:SetTextColor(1,1,1,1)
  title:SetShadowColor(0,0,0,1)
  title:SetShadowOffset(1,-1)

  -- Small icon buttons packed together like original Recount.
  local function iconButton(texture, pushedTexture, anchor, x, func, tip)
    local b=CreateFrame("Button",nil,titleBar)
    b:SetWidth(16)
    b:SetHeight(16)

    if anchor then
      b:SetPoint("RIGHT",anchor,"LEFT",-2,0)
    else
      b:SetPoint("RIGHT",titleBar,"RIGHT",x or -18,0)
    end

    b:SetNormalTexture(texture)
    if pushedTexture then
      b:SetPushedTexture(pushedTexture)
    end
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight.blp")
    b:SetFrameLevel(titleBar:GetFrameLevel()+10)
    b:EnableMouse(true)
    b:SetScript("OnClick",func)

    if tip then
      b:SetScript("OnEnter",function()
        GameTooltip:SetOwner(this,"ANCHOR_TOP")
        GameTooltip:SetText(tip)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    end

    return b
  end

  local close=CreateFrame("Button",nil,titleBar,"UIPanelCloseButton")
  close:SetWidth(24)
  close:SetHeight(24)
  close:SetPoint("RIGHT",titleBar,"RIGHT",-7,0)
  close:SetFrameLevel(titleBar:GetFrameLevel()+25)
  close:EnableMouse(true)
  if close.SetHitRectInsets then
    close:SetHitRectInsets(-3,-3,-3,-3)
  end

  local nextBtn = iconButton(
    "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
    "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
    close,nil,function() RV:NextMode() end,"Next Data View")

  local prevBtn = iconButton(
    "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
    "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down",
    nextBtn,nil,function() RV:PrevMode() end,"Previous Data View")

  local resetBtn = iconButton(
    "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
    "Interface\\Buttons\\UI-GuildButton-PublicNote-Down",
    prevBtn,nil,function() RV:ShowReset() end,"Reset Data")

  -- Recount-style reset marker: same family of icon with a small red X overlay.
  local resetX = resetBtn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  resetX:SetPoint("CENTER",resetBtn,"CENTER",3,-2)
  resetX:SetText("x")
  resetX:SetTextColor(1,.15,.05)

  local configBtn = iconButton(
    "Interface\\Buttons\\UI-GuildButton-OfficerNote-Up",
    "Interface\\Buttons\\UI-GuildButton-OfficerNote-Down",
    resetBtn,nil,function() RV:CreateConfigWindow(); RV.configFrame:Show() end,"Configuration")

  local fightBtn = iconButton(
    "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
    "Interface\\Buttons\\UI-GuildButton-PublicNote-Down",
    configBtn,nil,function() RV:ToggleSegmentMenu() end,"Segment")

  local filterBtn = iconButton(
    "Interface\\Buttons\\UI-GuildButton-OfficerNote-Up",
    "Interface\\Buttons\\UI-GuildButton-OfficerNote-Down",
    fightBtn,nil,function() RV:ToggleFilterMenu() end,"Class Filters")

  local reportBtn = iconButton(
    "Interface\\Buttons\\UI-GuildButton-MOTD-Up",
    "Interface\\Buttons\\UI-GuildButton-MOTD-Down",
    filterBtn,nil,function() RV:CreateReportWindow(); RV.reportFrame:Show() end,"Report Data")

  -- Fight/segment selection is handled by the title-bar Fight icon.
  -- Do not consume vertical space with a permanent "Overall Data" label.
  self.segmentButton = nil
  self.segmentText = nil

  local listArea = CreateFrame("Frame", nil, f)
  self.listArea = listArea
  listArea:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -29)
  listArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 20)

  local i
  for i=1,self.maxRows do
    local row=CreateFrame("Button",nil,listArea)
    self.rows[i]=row
    row:SetHeight(18)
    row:SetPoint("TOPLEFT",listArea,"TOPLEFT",0,-((i-1)*19))
    row:SetPoint("TOPRIGHT",listArea,"TOPRIGHT",0,-((i-1)*19))
    row:SetScript("OnEnter",RowEnter)
    row:SetScript("OnLeave",RowLeave)
    row:SetScript("OnClick",function()
      if this.actor then
        RV:ShowActorDetails(this.actor)
      end
    end)

    local bar=CreateFrame("StatusBar",nil,row)
    row.bar=bar
    bar:SetAllPoints(row)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0,1)
    bar:SetValue(0)

    local bg=bar:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture(.08,.08,.08,.82)

    local name=bar:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    row.name=name
    name:SetPoint("LEFT",bar,"LEFT",4,0)
    name:SetWidth(190)
    name:SetJustifyH("LEFT")
    name:SetTextColor(1,1,1)

    local value=bar:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    row.value=value
    value:SetPoint("RIGHT",bar,"RIGHT",-4,0)
    value:SetWidth(105)
    value:SetJustifyH("RIGHT")
    value:SetTextColor(1,1,1)
    row:Hide()
  end

  local footer=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
  self.footer=footer
  footer:SetPoint("BOTTOM",f,"BOTTOM",0,5)
  footer:SetText("RV 2.0.2")
  footer:SetTextColor(.40,.40,.40)

  -- Clean Recount-style bottom-right resize grip: three parallel diagonals.
  local rightGrip=CreateFrame("Button","RecountResizeGripRight",f)
  self.resizeGrip=rightGrip
  rightGrip:SetFrameLevel(f:GetFrameLevel()+30)
  rightGrip:SetWidth(22)
  rightGrip:SetHeight(22)
  rightGrip:SetPoint("BOTTOMRIGHT",f,"BOTTOMRIGHT",-4,4)
  rightGrip:EnableMouse(true)

  local function rightDot(x,y,shade)
    local p=rightGrip:CreateTexture(nil,"OVERLAY")
    p:SetWidth(2)
    p:SetHeight(2)
    p:SetTexture(shade,shade,shade,1)
    p:SetPoint("BOTTOMLEFT",rightGrip,"BOTTOMLEFT",x,y)
  end

  -- three clean parallel / lines
  local i
  for i=0,8 do rightDot(10+i,2+i,.88) end
  for i=0,6 do rightDot(13+i,2+i,.68) end
  for i=0,4 do rightDot(16+i,2+i,.48) end

  rightGrip:SetAlpha(.92)
  rightGrip:SetScript("OnEnter",function() this:SetAlpha(1) end)
  rightGrip:SetScript("OnLeave",function() this:SetAlpha(.92) end)
  rightGrip:SetScript("OnMouseDown",function()
    if not RV.settings.locked and arg1=="LeftButton" then
      RV.frame:StartSizing("BOTTOMRIGHT")
    end
  end)
  rightGrip:SetScript("OnMouseUp",function()
    RV.frame:StopMovingOrSizing()
    RV:SaveMainLayout()
  end)

  -- Clean Recount-style bottom-left resize grip: mirrored three-line mark.
  local leftGrip=CreateFrame("Button","RecountResizeGripLeft",f)
  self.resizeGripLeft=leftGrip
  leftGrip:SetFrameLevel(f:GetFrameLevel()+30)
  leftGrip:SetWidth(22)
  leftGrip:SetHeight(22)
  leftGrip:SetPoint("BOTTOMLEFT",f,"BOTTOMLEFT",4,4)
  leftGrip:EnableMouse(true)

  local function leftDot(x,y,shade)
    local p=leftGrip:CreateTexture(nil,"OVERLAY")
    p:SetWidth(2)
    p:SetHeight(2)
    p:SetTexture(shade,shade,shade,1)
    p:SetPoint("BOTTOMLEFT",leftGrip,"BOTTOMLEFT",x,y)
  end

  -- mirror of the right grip
  local i
  for i=0,8 do leftDot(2+i,10-i,.88) end
  for i=0,6 do leftDot(2+i,7-i,.68) end
  for i=0,4 do leftDot(2+i,4-i,.48) end

  leftGrip:SetAlpha(.92)
  leftGrip:SetScript("OnEnter",function() this:SetAlpha(1) end)
  leftGrip:SetScript("OnLeave",function() this:SetAlpha(.92) end)
  leftGrip:SetScript("OnMouseDown",function()
    if not RV.settings.locked and arg1=="LeftButton" then
      RV.frame:StartSizing("BOTTOMLEFT")
    end
  end)
  leftGrip:SetScript("OnMouseUp",function()
    RV.frame:StopMovingOrSizing()
    RV:SaveMainLayout()
  end)

  self:RestoreMainLayout()
  self:ApplyWindowSettings()
  self:Refresh()
end

function RV:Toggle()
  if not self.frame then self:CreateUI() end
  if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

function RV:SetCombatLogRange200()
  local ranges={"Party","PartyPet","FriendlyPlayers","FriendlyPlayersPets","HostilePlayers","HostilePlayersPets","Creature"}
  local i
  for i=1,table.getn(ranges) do SetCVar("CombatLogRange"..ranges[i],200) end
  DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Recount:|r combat log ranges set to 200.")
end

local events={
  "PLAYER_LOGIN","PLAYER_LOGOUT","PLAYER_ENTERING_WORLD","PARTY_MEMBERS_CHANGED","RAID_ROSTER_UPDATE",
  "PLAYER_PET_CHANGED","UNIT_PET","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED",
  "CHAT_MSG_COMBAT_SELF_HITS","CHAT_MSG_COMBAT_PARTY_HITS","CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS",
  "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS","CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS",
  "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS","CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS",
  "CHAT_MSG_COMBAT_PET_HITS",
  "CHAT_MSG_SPELL_SELF_DAMAGE","CHAT_MSG_SPELL_PARTY_DAMAGE","CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE","CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
  "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE","CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
  "CHAT_MSG_SPELL_PET_DAMAGE","CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF",
  "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS",
  "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE","CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE","CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE","CHAT_MSG_SPELL_SELF_BUFF","CHAT_MSG_SPELL_PARTY_BUFF",
  "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF","CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
  "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS","CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS",
  "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS","CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
  "CHAT_MSG_COMBAT_HOSTILE_DEATH","CHAT_MSG_COMBAT_FRIENDLY_DEATH"
}

local ef=CreateFrame("Frame","RecountEventFrame")
local i
for i=1,table.getn(events) do ef:RegisterEvent(events[i]) end

ef:SetScript("OnEvent",function()
  if event=="PLAYER_LOGIN" then
    RV:LoadSavedSettings()
    RV:LoadCombatData()
    RV:CreateUI()
    RV:RefreshPetOwners()
    RV:Refresh()
  elseif event=="PLAYER_LOGOUT" then
    RV:SaveCombatData()
    RV:SaveMainLayout()
    RV:SaveSettings()
  elseif event=="PLAYER_REGEN_DISABLED" then
    RV:StartFight()
  elseif event=="PLAYER_REGEN_ENABLED" then
    RV:EndFight()
  elseif event=="PLAYER_ENTERING_WORLD" or event=="PARTY_MEMBERS_CHANGED" or event=="RAID_ROSTER_UPDATE"
      or event=="PLAYER_PET_CHANGED" or event=="UNIT_PET" then
    RV:RefreshPetOwners()
  elseif event=="CHAT_MSG_COMBAT_HOSTILE_DEATH" or event=="CHAT_MSG_COMBAT_FRIENDLY_DEATH" then
    RV:ParseCombatMessage(event,arg1)
  elseif string.find(event,"^CHAT_MSG_") then
    RV:RefreshPetOwners(); RV:ParseCombatMessage(event,arg1)
  end
end)

ef:SetScript("OnUpdate",function()
  RV.updateTimer=RV.updateTimer+arg1

  if RV.reportQueueActive and RV.reportQueue and table.getn(RV.reportQueue)>0 then
    RV.reportQueueTimer=(RV.reportQueueTimer or 0)+arg1
    if RV.reportQueueTimer>=1.0 then
      RV.reportQueueTimer=0
      local text=table.remove(RV.reportQueue,1)
      RV:SendReportLine(
        text,
        RV.reportQueueChannel,
        RV.reportQueueTarget,
        RV.reportQueueChatNumber
      )
      if table.getn(RV.reportQueue)==0 then
        RV.reportQueueActive=false
      end
    end
  end

  if RV.updateTimer>=.5 then
    RV.updateTimer=0
    RV:Refresh()
  end
end)

SLASH_RECOUNTVANILLA1="/rv"
SLASH_RECOUNTVANILLA2="/recountvanilla"
SlashCmdList["RECOUNTVANILLA"]=function(msg)
  msg=lower(trim(msg or ""))
  if msg=="" or msg=="toggle" then RV:Toggle()
  elseif msg=="reset" then RV:ShowReset()
  elseif msg=="damage" then RV:SetModeIndex(1)
  elseif msg=="dps" then RV:SetModeIndex(2)
  elseif msg=="taken" then RV:SetModeIndex(3)
  elseif msg=="healing" or msg=="heal" then RV:SetModeIndex(4)
  elseif msg=="healingtaken" then RV:SetModeIndex(5)
  elseif msg=="deaths" then RV:SetModeIndex(6)
  elseif msg=="overall" then RV:SetSegment("overall")
  elseif msg=="current" then RV:SetSegment("current")
  elseif msg=="config" then RV:CreateConfigWindow(); RV.configFrame:Show()
  elseif msg=="report" then RV:CreateReportWindow(); RV.reportFrame:Show()
  elseif msg=="range200" then RV:SetCombatLogRange200()
  elseif msg=="pets" then
    RV:RefreshPetOwners()
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Recount pet map:|r")
    local pet,owner
    for pet,owner in pairs(RV.petOwners) do DEFAULT_CHAT_FRAME:AddMessage("  "..pet.." -> "..owner) end
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Recount commands:|r /rv reset, config, report, overall, current, damage, dps, taken, healing, healingtaken, deaths, pets, range200")
  end
end
