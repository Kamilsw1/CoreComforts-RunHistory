-- Core Comforts
-- Full target health, kill / gold / cache, guardian timers,
-- and minimap pins plus arrows for waiting bosses and caches.
-- Spell tooltips can show the cooldown with more decimal places.
-- WoW 1.12 / Lua 5.0. Drag the list to move it. /cc or the minimap button opens options. /cc reset parks it.

if not CoreComfortsDB and ClassicComfortsDB then
	CoreComfortsDB = ClassicComfortsDB
end
CoreComfortsDB = CoreComfortsDB or {}

local ROWS = 16
local PIN_LIMIT = 48

local outdoorYards = { 466.67, 400, 333.33, 266.67, 200, 133.33 }
local indoorYards = { 300, 240, 180, 120, 80, 50 }

local TEX_CACHE = "Interface\\AddOns\\CoreComforts\\bag"
local TEX_BOSS_ALIVE = "Interface\\AddOns\\CoreComforts\\skull-alive"
local TEX_BOSS_COMBAT = "Interface\\AddOns\\CoreComforts\\skull-combat"
local TEX_BOSS_WAIT = "Interface\\AddOns\\CoreComforts\\skull-dead"
local TEX_MINIMAP = "Interface\\Icons\\INV_Misc_Rune_01"

local pins = {}
local pinUsed = 0
local guides = {}
local rows = {}
local stockTallyHidden = false
local stockClockHidden = false
local facingModel
local told = false
local listElapsed = 0
local mapElapsed = 0
local statsElapsed = 0

local function Num(value)
	if type(value) == "number" and value == value then return value end
end

local function Whole(value)
	local n = Num(value)
	if not n then return "0" end
	return string.format("%.0f", n)
end

local function Clock(seconds)
	local s = math.floor(seconds)
	if s < 0 then s = 0 end
	local m = math.floor(s / 60)
	s = math.mod(s, 60)
	return string.format("%d:%02d", m, s)
end

local function InRun()
	if not AZS_GetPhase then return end
	local phase = AZS_GetPhase()
	if phase == "playing" or phase == "choosing" or phase == "paused" then
		return phase
	end
end

local function Staging()
	if not AZS_GetPhase then return end
	return AZS_GetPhase() == "ready"
end

local function Say(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Core Comforts|r: " .. msg)
	end
end

local function On(key)
	if key == "dotestimate" or key == "nameplates" or key == "luckodds" then
		local picked = CoreComfortsDB[key]
		return picked == true or picked == 1
	end
	if key == "list" and CoreComfortsDB.hidden then return false end
	if key == "counter" and CoreComfortsDB.stock then return false end
	local value = CoreComfortsDB[key]
	if value == nil then
		if key == "guardpins" or key == "cachepins" then value = CoreComfortsDB.pins end
		if key == "guardarrow" or key == "cachearrow" then value = CoreComfortsDB.arrows end
	end
	if value == false or value == 0 then return false end
	return true
end

local function Locked()
	return CoreComfortsDB.locked == true or CoreComfortsDB.locked == 1
end

local function Count(list)
	if type(list) ~= "table" then return 0 end
	return table.getn(list)
end

local function Lairs()
	if AZS_GetLairs then
		local list = AZS_GetLairs()
		if type(list) == "table" then return list end
	end
	if type(AZS_LAIRS) == "table" then return AZS_LAIRS end
end

local function Chests()
	if type(AZS_CHESTS) == "table" then return AZS_CHESTS end
end

local function Living(lair)
	if lair.active == true or lair.active == 1 then return true end
	return lair.state == "asleep" or lair.state == "awake"
end

----------------------------------------------------------------
-- Target health, written in full (170000 / 200000)
----------------------------------------------------------------

local healthText
local playerHealthText
local playerPowerText
local playerHealthState = {}
local playerPowerState = {}

local function EnsureBarText(bar, text, globalName)
	if text or not bar then return text end
	text = bar:CreateFontString(globalName, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER", bar, "CENTER", 0, 0)
	text:SetTextColor(1, 1, 1)
	text:SetShadowColor(0, 0, 0)
	text:SetShadowOffset(1, -1)
	return text
end

local function PaintHealth(bar, text, key, unit, globalName)
	if not On(key) then
		if text then text:SetText("") end
		return text
	end
	text = EnsureBarText(bar, text, globalName)
	if not text then return text end
	if not UnitExists(unit) then
		text:SetText("")
		return text
	end
	local current = UnitHealth(unit)
	local maximum = UnitHealthMax(unit)
	if not Num(current) or not Num(maximum) or maximum <= 0 then
		text:SetText("")
		return text
	end
	text:SetText(Whole(current) .. " / " .. Whole(maximum))
	text:Show()
	return text
end

local function Settled(state, dt, current, maximum, force, quietNeed, ageNeed)
	if force or state.shownCurrent == nil then
		state.seenCurrent = current
		state.seenMax = maximum
		state.shownCurrent = current
		state.shownMax = maximum
		state.quiet = 0
		state.age = 0
		return true
	end
	if state.seenCurrent ~= current or state.seenMax ~= maximum then
		state.seenCurrent = current
		state.seenMax = maximum
		state.quiet = 0
	else
		state.quiet = state.quiet + dt
	end
	state.age = state.age + dt
	if state.shownCurrent == current and state.shownMax == maximum then
		state.age = 0
		return false
	end
	if state.quiet >= quietNeed or state.age >= ageNeed then
		state.shownCurrent = current
		state.shownMax = maximum
		state.age = 0
		return true
	end
	return false
end

local function PaintSettled(bar, text, key, state, globalName, current, maximum, dt, force, quietNeed, ageNeed)
	if not On(key) then
		if text then text:SetText("") end
		state.shownCurrent = nil
		return text
	end
	text = EnsureBarText(bar, text, globalName)
	if not text then return text end
	if not Num(current) or not Num(maximum) or maximum <= 0 then
		text:SetText("")
		state.shownCurrent = nil
		return text
	end
	if Settled(state, dt or 0, current, maximum, force, quietNeed, ageNeed) then
		text:SetText(Whole(current) .. " / " .. Whole(maximum))
		text:Show()
	end
	return text
end

local function HealthSeconds(value)
	local n = Num(value)
	if not n then n = 0.05 end
	if n >= 1 then
		n = math.floor(n + 0.5)
		if n == 7 then return 0.05 end
		if n < 1 then n = 1 end
		if n > 10 then n = 10 end
		n = 0.62 - (n - 1) * 0.06
	end
	n = math.floor(n * 100 + 0.5) / 100
	if n < 0.01 then n = 0.01 end
	if n > 0.50 then n = 0.50 end
	return n
end

local function HealthPace()
	local age = HealthSeconds(CoreComfortsDB.healthrate)
	return age * 0.5, age
end

local function HealthPaceText(value)
	return string.format("every %.2f s", HealthSeconds(value))
end

local function UpdateHealth()
	healthText = PaintHealth(TargetFrameHealthBar, healthText, "health", "target", "CoreComfortsHealthText")
end

local function UpdatePlayerBars(dt, force)
	local current, maximum
	if UnitExists("player") then
		current = UnitHealth("player")
		maximum = UnitHealthMax("player")
	end
	local quiet, age = HealthPace()
	playerHealthText = PaintSettled(PlayerFrameHealthBar, playerHealthText, "playerhealth", playerHealthState, "CoreComfortsPlayerHealthText", current, maximum, dt, force, quiet, age)
	current, maximum = nil, nil
	if UnitExists("player") and UnitMana and UnitManaMax then
		current = UnitMana("player")
		maximum = UnitManaMax("player")
	end
	playerPowerText = PaintSettled(PlayerFrameManaBar, playerPowerText, "power", playerPowerState, "CoreComfortsPlayerPowerText", current, maximum, dt, force, 0.15, 0.35)
end

----------------------------------------------------------------
-- List: Kill / Gold / Cache, then each guardian lair
----------------------------------------------------------------

local list = CreateFrame("Frame", "CoreComfortsFrame", UIParent)
list:SetWidth(220)
list:SetHeight(36)
list:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -260)
list:SetMovable(true)
list:EnableMouse(true)
list:RegisterForDrag("LeftButton")
list:SetClampedToScreen(true)
list:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
list:SetBackdropColor(0, 0, 0, 0.55)
list:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.85)

local tally = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
tally:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -8)
tally:SetWidth(200)
tally:SetJustifyH("LEFT")
tally:SetText("Kill 0   Gold 0   Cache 0")

local i
for i = 1, ROWS do
	local name = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetWidth(120)
	name:SetHeight(12)
	name:SetJustifyH("LEFT")
	name:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -8 - (i - 1) * 13)
	name:Hide()
	local status = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetWidth(72)
	status:SetHeight(12)
	status:SetJustifyH("RIGHT")
	status:SetPoint("TOPRIGHT", list, "TOPRIGHT", -10, -8 - (i - 1) * 13)
	status:Hide()
	rows[i] = { name = name, status = status }
end

local function PlaceUnderMap(frame, extra)
	frame:ClearAllPoints()
	if MinimapZoomOut then
		frame:SetPoint("TOPRIGHT", MinimapZoomOut, "BOTTOMRIGHT", 0, -8 - extra)
	elseif Minimap then
		frame:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -52 - extra)
	else
		frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -228 - extra)
	end
end

local function PlaceList()
	PlaceUnderMap(list, 98)
end

local function RestoreList()
	if CoreComfortsDB.left and CoreComfortsDB.top then
		list:ClearAllPoints()
		list:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", CoreComfortsDB.left, CoreComfortsDB.top)
	else
		PlaceList()
	end
end

list:SetScript("OnDragStart", function()
	if Locked() then return end
	this:StartMoving()
end)
list:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	CoreComfortsDB.left = this:GetLeft()
	CoreComfortsDB.top = this:GetTop()
end)

local function HideRows()
	local n
	for n = 1, ROWS do
		rows[n].name:Hide()
		rows[n].status:Hide()
	end
end

local counter = CreateFrame("Frame", "CoreComfortsCounter", UIParent)
counter:SetWidth(196)
counter:SetHeight(18)
counter:SetMovable(true)
counter:EnableMouse(true)
counter:RegisterForDrag("LeftButton")
counter:SetClampedToScreen(true)
counter:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 10,
	insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
counter:SetBackdropColor(0.02, 0.015, 0.01, 0.78)
counter:SetBackdropBorderColor(0.12, 0.09, 0.05, 0.85)
local counterParts = {}
local pi
for pi = 1, 7 do
	local fs = counter:CreateFontString(nil, "OVERLAY")
	fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	fs:SetTextColor(0.93, 0.78, 0.38)
	counterParts[pi] = fs
end
tally:Hide()

local function PlaceCounter()
	counter:ClearAllPoints()
	local exp = MainMenuExpBar
	if exp and exp.IsShown and exp:IsShown() then
		counter:SetPoint("BOTTOM", exp, "TOP", 0, 5)
	else
		counter:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 55)
	end
end

local function RestoreCounter()
	if CoreComfortsDB.c2left and CoreComfortsDB.c2top then
		counter:ClearAllPoints()
		counter:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", CoreComfortsDB.c2left, CoreComfortsDB.c2top)
	else
		PlaceCounter()
	end
end

counter:SetScript("OnDragStart", function()
	if Locked() then return end
	this:StartMoving()
end)
counter:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	CoreComfortsDB.c2left = this:GetLeft()
	CoreComfortsDB.c2top = this:GetTop()
end)

local function HideStockTally()
	if stockTallyHidden or not AZS_SetHudShown then return end
	AZS_SetHudShown("tally", false)
	stockTallyHidden = true
end

local function ShowStockTally()
	if not stockTallyHidden or not AZS_SetHudShown then return end
	AZS_SetHudShown("tally", true)
	stockTallyHidden = false
end

local function CachesAffordable(gold, cost)
	if cost <= 0 then return 0 end
	local n = 0
	while gold >= cost and n < 200 do
		gold = gold - cost
		n = n + 1
		local nextCost = math.floor(cost * 1.3 + 5)
		if nextCost <= cost then break end
		cost = nextCost
	end
	return n
end

local function UpdateCounter()
	if not On("counter") or not (InRun() or Staging()) then
		if not On("counter") then ShowStockTally() end
		counter:Hide()
		return
	end
	if InRun() then HideStockTally() else ShowStockTally() end
	local run = AZS_RUN
	local kills, gold, cost = 0, 0, 0
	if type(run) == "table" then
		kills = Num(run.kills) or 0
		gold = Num(run.gold) or 0
		cost = Num(run.chest) or 0
	end
	local wordR, wordG, wordB = 0.78, 0.28, 0.22
	local numR, numG, numB = 1, 0.42, 0.32
	if gold >= cost then
		wordR, wordG, wordB = 0.38, 0.72, 0.32
		numR, numG, numB = 0.5, 0.92, 0.4
	end
	local bits = {
		{ "Kills", 10, 0.93, 0.78, 0.38, 1 },
		{ string.format("%.0f", kills), 12, 0.93, 0.78, 0.38, 0 },
		{ "Gold", 10, 0.93, 0.78, 0.38, 1 },
		{ string.format("%.0f", gold), 12, 0.93, 0.78, 0.38, 0 },
		{ "Cache", 10, wordR, wordG, wordB, 1 },
		{ string.format("%.0f", cost), 12, numR, numG, numB, 0 }
	}
	local gaps = { 3, 9, 3, 9, 3 }
	if On("cachecount") then
		local affordable = CachesAffordable(gold, cost)
		tinsert(bits, { string.format("(%.0f)", affordable), 12, numR, numG, numB, 0 })
		tinsert(gaps, 4)
	end
	local count = table.getn(bits)
	local widths = {}
	local total = 0
	local b
	for b = 1, count do
		local bit = bits[b]
		local fs = counterParts[b]
		fs:SetFont("Fonts\\FRIZQT__.TTF", bit[2], "")
		fs:SetText(bit[1])
		fs:SetTextColor(bit[3], bit[4], bit[5])
		local w = fs:GetStringWidth()
		if not w or w < 1 then w = 8 end
		widths[b] = w
		total = total + w
		if b < count then total = total + gaps[b] end
	end
	local x = -total / 2
	for b = 1, count do
		local fs = counterParts[b]
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", counter, "CENTER", x, bits[b][6])
		x = x + widths[b]
		if b < count then x = x + gaps[b] end
		fs:Show()
	end
	for b = count + 1, 7 do
		counterParts[b]:Hide()
	end
	counter:SetWidth(total + 18)
	counter:SetHeight(18)
	if not CoreComfortsDB.c2left then PlaceCounter() end
	counter:Show()
end

local stats = CreateFrame("Frame", "CoreComfortsStats", UIParent)
stats:SetWidth(280)
stats:SetHeight(18)
stats:SetMovable(true)
stats:EnableMouse(true)
stats:RegisterForDrag("LeftButton")
stats:SetClampedToScreen(true)
stats:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 10,
	insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
stats:SetBackdropColor(0.02, 0.015, 0.01, 0.78)
stats:SetBackdropBorderColor(0.12, 0.09, 0.05, 0.85)
local statsParts = {}
local si
for si = 1, 6 do
	local fs = stats:CreateFontString(nil, "OVERLAY")
	fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	fs:SetTextColor(0.93, 0.78, 0.38)
	statsParts[si] = fs
end
stats:Hide()

local xpWatch = { gained = 0 }
local pace = {}
local paceSamples = {}

local function PlaceStats()
	PlaceUnderMap(stats, 0)
end

local function RestoreStats()
	if CoreComfortsDB.sleft and CoreComfortsDB.stop then
		stats:ClearAllPoints()
		stats:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", CoreComfortsDB.sleft, CoreComfortsDB.stop)
	else
		PlaceStats()
	end
end

stats:SetScript("OnDragStart", function()
	if Locked() then return end
	this:StartMoving()
end)
stats:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	CoreComfortsDB.sleft = this:GetLeft()
	CoreComfortsDB.stop = this:GetTop()
end)

local function PerMinute(amount, seconds)
	if not amount or amount < 0 then amount = 0 end
	if not seconds or seconds < 5 then return 0 end
	return amount * 60 / seconds
end

local function RateText(n)
	if n >= 100 then return string.format("%.0f", n) end
	return string.format("%.1f", n)
end

local function RunKey()
	if type(AZS_ZONE) == "table" and AZS_ZONE.run ~= nil and tostring(AZS_ZONE.run) ~= "" then
		return tostring(AZS_ZONE.run)
	end
	if AZS_GetMeterContext then
		local ok, ctx = pcall(AZS_GetMeterContext)
		if ok and type(ctx) == "table" and ctx.runId ~= nil then return tostring(ctx.runId) end
	end
end

-- The run clock already stops for pauses and card picks, so it is the active time.
local function AdvancePace(run)
	local clock = 0
	if AZS_GetRunTime then clock = Num(AZS_GetRunTime()) or 0 end
	if pace.clock and clock + 1 < pace.clock then
		paceSamples = {}
		xpWatch.gained = 0
		xpWatch.lvl = nil
		CoreComfortsDB.xpGained = 0
	end
	pace.clock = clock
	pace.active = clock
end

local function NoteXp(run)
	local lvl = Num(run.lvl)
	local xp = Num(run.xp) or 0
	local xpn = Num(run.xpn)
	if xpWatch.lvl == nil then
		xpWatch.lvl = lvl
		xpWatch.xp = xp
		xpWatch.xpn = xpn
		local key = RunKey()
		if key and CoreComfortsDB.xpRun == key then
			xpWatch.gained = Num(CoreComfortsDB.xpGained) or 0
		else
			xpWatch.gained = 0
			CoreComfortsDB.xpRun = key
			CoreComfortsDB.xpGained = 0
		end
		return
	end
	if lvl == xpWatch.lvl then
		if xp > (xpWatch.xp or 0) then
			xpWatch.gained = xpWatch.gained + (xp - xpWatch.xp)
		end
	elseif lvl and xpWatch.lvl and lvl > xpWatch.lvl then
		local add = xp
		if xpWatch.xpn and xpWatch.xp and xpWatch.xpn > xpWatch.xp then
			add = add + (xpWatch.xpn - xpWatch.xp)
		end
		xpWatch.gained = xpWatch.gained + add
	end
	xpWatch.lvl = lvl
	xpWatch.xp = xp
	xpWatch.xpn = xpn
	CoreComfortsDB.xpGained = xpWatch.gained
end

local function RememberPace(kills, gold)
	local t = pace.active or 0
	local n = table.getn(paceSamples)
	if n > 0 and paceSamples[n].t == t then
		paceSamples[n].k = kills
		paceSamples[n].x = xpWatch.gained
		paceSamples[n].g = gold
	else
		table.insert(paceSamples, { t = t, k = kills, x = xpWatch.gained, g = gold })
	end
	while table.getn(paceSamples) > 1 and (t - paceSamples[1].t) > 60 do
		table.remove(paceSamples, 1)
	end
end

local function RecentRate(field)
	local n = table.getn(paceSamples)
	if n < 1 then return end
	local newest = paceSamples[n]
	local oldest = paceSamples[1]
	local span = newest.t - oldest.t
	if span < 5 then return end
	local delta = newest[field] - oldest[field]
	if delta < 0 then delta = 0 end
	return delta * 60 / span
end

local function PaceText(recent, average)
	if not recent then recent = average end
	return RateText(recent or 0) .. " (average " .. RateText(average or 0) .. ")"
end

local function UpdateStats(dt)
	local run = AZS_RUN
	local kills, earned = 0, 0
	if InRun() and type(run) == "table" then
		AdvancePace(run)
		NoteXp(run)
		kills = Num(run.kills) or 0
		earned = Num(run.ge) or 0
		RememberPace(kills, earned)
	end
	if not On("stats") or not (InRun() or Staging()) then
		stats:Hide()
		return
	end
	local lines = {
		{ "Kill/min", PaceText(RecentRate("k"), PerMinute(kills, pace.active)), 1, 0.62, 0.45 },
		{ "XP/min", PaceText(RecentRate("x"), PerMinute(xpWatch.gained, pace.active)), 0.55, 0.75, 1 },
		{ "Gold/min", PaceText(RecentRate("g"), PerMinute(earned, pace.active)), 0.93, 0.78, 0.38 }
	}
	local labelW, valueW = 0, 0
	local r
	for r = 1, 3 do
		local line = lines[r]
		local label = statsParts[r]
		local value = statsParts[r + 3]
		label:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
		label:SetText(line[1])
		label:SetTextColor(line[3], line[4], line[5])
		value:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
		value:SetText(line[2])
		value:SetTextColor(line[3], line[4], line[5])
		local lw = label:GetStringWidth()
		local vw = value:GetStringWidth()
		if not lw or lw < 1 then lw = 8 end
		if not vw or vw < 1 then vw = 8 end
		if lw > labelW then labelW = lw end
		if vw > valueW then valueW = vw end
	end
	stats:SetWidth(labelW + valueW + 26)
	stats:SetHeight(48)
	for r = 1, 3 do
		local y = -6 - (r - 1) * 14
		local label = statsParts[r]
		local value = statsParts[r + 3]
		label:ClearAllPoints()
		label:SetPoint("TOPLEFT", stats, "TOPLEFT", 8, y)
		value:ClearAllPoints()
		value:SetPoint("TOPRIGHT", stats, "TOPRIGHT", -8, y)
		label:Show()
		value:Show()
	end
	if not CoreComfortsDB.sleft then PlaceStats() end
	stats:Show()
end

local aliveFrame = CreateFrame("Frame", "CoreComfortsAlive", UIParent)
aliveFrame:SetWidth(150)
aliveFrame:SetHeight(18)
aliveFrame:SetMovable(true)
aliveFrame:EnableMouse(true)
aliveFrame:RegisterForDrag("LeftButton")
aliveFrame:SetClampedToScreen(true)
aliveFrame:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 10,
	insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
aliveFrame:SetBackdropColor(0.02, 0.015, 0.01, 0.78)
aliveFrame:SetBackdropBorderColor(0.12, 0.09, 0.05, 0.85)
local aliveLabel = aliveFrame:CreateFontString(nil, "OVERLAY")
aliveLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
aliveLabel:SetShadowColor(0, 0, 0, 1)
aliveLabel:SetShadowOffset(1, -1)
aliveLabel:SetTextColor(0.9, 0.9, 0.9)
aliveLabel:SetText("Alive Enemies")
local aliveValue = aliveFrame:CreateFontString(nil, "OVERLAY")
aliveValue:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
aliveValue:SetShadowColor(0, 0, 0, 1)
aliveValue:SetShadowOffset(1, -1)
aliveValue:SetTextColor(1, 1, 1)
aliveFrame:Hide()

local function PlaceAlive()
	PlaceUnderMap(aliveFrame, 56)
end

local function RestoreAlive()
	if CoreComfortsDB.aleft and CoreComfortsDB.atop then
		aliveFrame:ClearAllPoints()
		aliveFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", CoreComfortsDB.aleft, CoreComfortsDB.atop)
	else
		PlaceAlive()
	end
end

aliveFrame:SetScript("OnDragStart", function()
	if Locked() then return end
	this:StartMoving()
end)
aliveFrame:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	CoreComfortsDB.aleft = this:GetLeft()
	CoreComfortsDB.atop = this:GetTop()
end)

local function UpdateAlive()
	if not On("alive") or not (InRun() or Staging()) then
		aliveFrame:Hide()
		return
	end
	local count = 0
	if type(AZS_RUN) == "table" then count = Num(AZS_RUN.en) or 0 end
	aliveLabel:SetText("Alive Enemies")
	aliveValue:SetText(string.format("%.0f", count))
	local lw = aliveLabel:GetStringWidth()
	local vw = aliveValue:GetStringWidth()
	if not lw or lw < 1 then lw = 8 end
	if not vw or vw < 1 then vw = 8 end
	aliveFrame:SetWidth(lw + vw + 26)
	aliveFrame:SetHeight(18)
	aliveLabel:ClearAllPoints()
	aliveLabel:SetPoint("LEFT", aliveFrame, "LEFT", 8, 1)
	aliveValue:ClearAllPoints()
	aliveValue:SetPoint("RIGHT", aliveFrame, "RIGHT", -8, 0)
	aliveLabel:Show()
	aliveValue:Show()
	if not CoreComfortsDB.aleft then PlaceAlive() end
	aliveFrame:Show()
end

----------------------------------------------------------------
-- Boss timer: run clock + progress bar (no bar in endless)
-- Boss list: upcoming countdown rows; alive bosses become health
----------------------------------------------------------------

local BOSS_TIMER_CAP = 40
local BOSS_TIMER_ROW = 16
local BOSS_TIMER_GAP = 6
local BOSS_LIST_PAD = 8
local BOSS_PROGRESS_W = 247
local bossTimerRows = {}
local bossMarks = {}
local bossTimerEndlessSpan = nil
local bossTimerLastNb = nil

local bossTimers = CreateFrame("Frame", "CoreComfortsBossTimers", UIParent)
bossTimers:SetWidth(263)
bossTimers:SetHeight(34)
bossTimers:EnableMouse(false)
bossTimers:Hide()

local progressText = bossTimers:CreateFontString(nil, "OVERLAY")
progressText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
progressText:SetPoint("TOP", bossTimers, "TOP", 0, 0)
progressText:SetTextColor(1, 0.9, 0.55)
progressText:SetShadowColor(0, 0, 0, 1)
progressText:SetShadowOffset(1, -1)
progressText:SetText("0:00/0:00")

local progressBg = bossTimers:CreateTexture(nil, "ARTWORK")
progressBg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
progressBg:SetVertexColor(0.15, 0.1, 0.06, 0.95)
progressBg:SetPoint("TOP", bossTimers, "TOP", 0, -20)
progressBg:SetWidth(BOSS_PROGRESS_W)
progressBg:SetHeight(8)

local progressBar = CreateFrame("StatusBar", nil, bossTimers)
progressBar:SetPoint("TOPLEFT", progressBg, "TOPLEFT", 0, 0)
progressBar:SetPoint("BOTTOMRIGHT", progressBg, "BOTTOMRIGHT", 0, 0)
progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
progressBar:SetStatusBarColor(0.93, 0.62, 0.2)
progressBar:SetMinMaxValues(0, 1)
progressBar:SetValue(0)

local bossList = CreateFrame("Frame", "CoreComfortsBossList", UIParent)
bossList:SetWidth(263)
bossList:SetHeight(28)
bossList:SetMovable(true)
bossList:EnableMouse(true)
bossList:RegisterForDrag("LeftButton")
bossList:SetClampedToScreen(true)
bossList:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
bossList:SetBackdropColor(0, 0, 0, 0.55)
bossList:SetBackdropBorderColor(0.8, 0.7, 0.4, 0.85)
bossList:Hide()

local function BossTimerRow(index)
	local row = bossTimerRows[index]
	if row then return row end
	if index > BOSS_TIMER_CAP then return end
	local holder = CreateFrame("Frame", nil, bossList)
	holder:SetWidth(224)
	holder:SetHeight(BOSS_TIMER_ROW)
	holder:Hide()
	local bg = holder:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(holder)
	bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bg:SetVertexColor(0.25, 0.05, 0.05, 0.9)
	local bar = CreateFrame("StatusBar", nil, holder)
	bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	local label = bar:CreateFontString(nil, "OVERLAY")
	label:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
	label:SetPoint("LEFT", bar, "LEFT", 6, 0)
	label:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
	label:SetJustifyH("CENTER")
	label:SetTextColor(1, 0.95, 0.85)
	label:SetShadowColor(0, 0, 0, 1)
	label:SetShadowOffset(1, -1)
	row = { holder = holder, bar = bar, label = label }
	bossTimerRows[index] = row
	return row
end

local function PlaceBossTimers()
	bossTimers:ClearAllPoints()
	bossTimers:SetPoint("TOP", UIParent, "TOP", 0, -10)
end

local function RestoreBossTimers()
	PlaceBossTimers()
end

local function PlaceBossList()
	bossList:ClearAllPoints()
	bossList:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -160)
end

local function HideStockClock()
	if stockClockHidden or not AZS_SetHudShown then return end
	AZS_SetHudShown("clock", false)
	stockClockHidden = true
end

local function ShowStockClock()
	if not stockClockHidden or not AZS_SetHudShown then return end
	AZS_SetHudShown("clock", true)
	stockClockHidden = false
end

local function RestoreBossList()
	if CoreComfortsDB.blleft and CoreComfortsDB.bltop then
		bossList:ClearAllPoints()
		bossList:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", CoreComfortsDB.blleft, CoreComfortsDB.bltop)
	else
		PlaceBossList()
	end
end

bossList:SetScript("OnDragStart", function()
	if Locked() then return end
	this:StartMoving()
end)
bossList:SetScript("OnDragStop", function()
	this:StopMovingOrSizing()
	CoreComfortsDB.blleft = this:GetLeft()
	CoreComfortsDB.bltop = this:GetTop()
end)

local function HideBossTimerRows(from)
	local n = table.getn(bossTimerRows)
	local i
	for i = from, n do
		bossTimerRows[i].holder:Hide()
	end
end

local function BossTimerColor(left, isFinal)
	if left and left <= 15 then return 1, 0.35, 0.3 end
	if isFinal then return 1, 0.82, 0.25 end
	return 0.93, 0.62, 0.2
end

local function PreviousBossAt(boss)
	if type(AZS_SCHEDULE) ~= "table" or not boss or not boss.index then return 0 end
	local n = table.getn(AZS_SCHEDULE)
	local s
	for s = 1, n do
		local entry = AZS_SCHEDULE[s]
		if type(entry) == "table" and entry.index == boss.index and s > 1 then
			local prev = AZS_SCHEDULE[s - 1]
			if type(prev) == "table" then return Num(prev.at) or 0 end
			return 0
		end
	end
	return 0
end

local DROP_COLOR = {
	common = { 1, 1, 1 },
	uncommon = { 0.12, 1, 0 },
	rare = { 0, 0.44, 0.87 },
	epic = { 0.64, 0.21, 0.93 },
	legendary = { 1, 0.5, 0 },
	pvp = { 0.45, 0.82, 0.28 }
}
local bossDropCache = {}

local function BossClassKey()
	if AZS_ZONE and type(AZS_ZONE) == "table" and AZS_ZONE.class and AZS_ZONE.class ~= "" then
		return AZS_ZONE.class
	end
	local token
	if UnitClass then
		local _
		_, token = UnitClass("player")
	end
	if token and token ~= "" then return string.lower(token) end
end

local function BossDropMap()
	local key = BossClassKey()
	if bossDropCache.key == key and bossDropCache.map then return bossDropCache.map end
	local map = {}
	bossDropCache.key = key
	bossDropCache.map = map
	if not key or not CoreComfortsGear then return map end
	local gear = CoreComfortsGear[key]
	if not gear then return map end
	local i
	for i = 1, table.getn(gear) do
		local item = gear[i]
		local rest = item.drop
		while rest and rest ~= "" do
			local part
			local splitAt = string.find(rest, " | ", 1, true)
			if splitAt then
				part = string.sub(rest, 1, splitAt - 1)
				rest = string.sub(rest, splitAt + 3)
			else
				part = rest
				rest = nil
			end
			local comma = string.find(part, ", ", 1, true)
			local bossName = part
			if comma then bossName = string.sub(part, 1, comma - 1) end
			if bossName ~= "" then
				local lookup = string.lower(bossName)
				local list = map[lookup]
				if not list then
					list = {}
					map[lookup] = list
				end
				local n = table.getn(list)
				if n < 2 then list[n + 1] = item end
			end
		end
	end
	return map
end

local function DropOwned(item)
	if not item or not item.id then return end
	local key = BossClassKey()
	if not key or type(CoreComfortsDB.collection) ~= "table" then return end
	local bag = CoreComfortsDB.collection[key]
	if type(bag) ~= "table" then return end
	return bag[tostring(item.id)] ~= nil
end

local function DropButton(row, which)
	local hit = row["drop" .. which]
	if hit then return hit end
	hit = CreateFrame("Button", nil, row.holder)
	hit:SetWidth(20)
	hit:SetHeight(20)
	hit:SetFrameLevel(row.bar:GetFrameLevel() + 3)
	local icon = hit:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(hit)
	hit.icon = icon
	local mark = CreateFrame("Frame", nil, hit)
	mark:SetWidth(11)
	mark:SetHeight(11)
	mark:SetPoint("BOTTOMRIGHT", hit, "BOTTOMRIGHT", -1, 1)
	mark:SetFrameLevel(hit:GetFrameLevel() + 2)
	local markBg = mark:CreateTexture(nil, "BACKGROUND")
	markBg:SetAllPoints(mark)
	markBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	markBg:SetVertexColor(0, 0, 0, 0.85)
	local function BoxLine()
		local line = mark:CreateTexture(nil, "BORDER")
		line:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
		line:SetVertexColor(0.95, 0.9, 0.7, 1)
		return line
	end
	local boxTop = BoxLine()
	boxTop:SetHeight(1)
	boxTop:SetPoint("TOPLEFT", mark, "TOPLEFT", 0, 0)
	boxTop:SetPoint("TOPRIGHT", mark, "TOPRIGHT", 0, 0)
	local boxBottom = BoxLine()
	boxBottom:SetHeight(1)
	boxBottom:SetPoint("BOTTOMLEFT", mark, "BOTTOMLEFT", 0, 0)
	boxBottom:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 0, 0)
	local boxLeft = BoxLine()
	boxLeft:SetWidth(1)
	boxLeft:SetPoint("TOPLEFT", mark, "TOPLEFT", 0, 0)
	boxLeft:SetPoint("BOTTOMLEFT", mark, "BOTTOMLEFT", 0, 0)
	local boxRight = BoxLine()
	boxRight:SetWidth(1)
	boxRight:SetPoint("TOPRIGHT", mark, "TOPRIGHT", 0, 0)
	boxRight:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 0, 0)
	local tick = mark:CreateTexture(nil, "ARTWORK")
	tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	tick:SetVertexColor(0.15, 0.95, 0.25)
	tick:SetWidth(11)
	tick:SetHeight(11)
	tick:SetPoint("CENTER", mark, "CENTER", 0, 0)
	mark:Hide()
	hit.mark = mark
	hit:SetScript("OnEnter", function()
		if not On("itemtips") or not this.item or not GameTooltip then return end
		local item = this.item
		local color = DROP_COLOR[item.rarity]
		if not color then color = { 1, 1, 1 } end
		local title = item.name
		if item.alt and item.alt ~= "" then title = title .. " / " .. item.alt end
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, color[1], color[2], color[3])
		if item.slot and item.slot ~= "" then
			GameTooltip:AddLine(item.slot, 1, 0.82, 0)
		end
		local stats = item.stats
		local rest = stats
		while rest and rest ~= "" do
			local piece
			local at = string.find(rest, ", ", 1, true)
			if at then
				piece = string.sub(rest, 1, at - 1)
				rest = string.sub(rest, at + 2)
			else
				piece = rest
				rest = nil
			end
			if string.find(piece, "health", 1, true) then
				GameTooltip:AddLine(piece, 1, 1, 1)
			else
				GameTooltip:AddLine(piece, 0, 1, 0)
			end
		end
		GameTooltip:Show()
	end)
	hit:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	hit:Hide()
	row["drop" .. which] = hit
	return hit
end

local function BossListWidth()
	local classKey = BossClassKey()
	if classKey == "rogue" or classKey == "shaman" then return 286 end
	return 263
end

local function PaintBossTimer(index, name, left, span, r, g, b, bossName)
	local row = BossTimerRow(index)
	if not row then return end
	if not span or span < 1 then span = 1 end
	if not left or left < 0 then left = 0 end
	if left > span then left = span end
	bossList:SetWidth(BossListWidth())
	row.holder:ClearAllPoints()
	row.holder:SetPoint("TOPLEFT", bossList, "TOPLEFT", 8, -(BOSS_LIST_PAD + (index - 1) * (BOSS_TIMER_ROW + BOSS_TIMER_GAP)))
	row.bar:SetMinMaxValues(0, span)
	row.bar:SetValue(left)
	row.bar:SetStatusBarColor(r, g, b)
	row.label:SetText(name)
	local drops = nil
	if bossName and bossName ~= "" then
		local map = BossDropMap()
		drops = map[string.lower(bossName)]
	end
	local shown = 0
	if type(drops) == "table" then
		local d
		for d = 1, table.getn(drops) do
			local item = drops[d]
			if item and item.icon and item.icon ~= "" and shown < 2 then
				shown = shown + 1
				local hit = DropButton(row, shown)
				hit.item = item
				hit.icon:SetTexture(item.icon)
				hit:ClearAllPoints()
				hit:SetPoint("LEFT", row.holder, "RIGHT", 3 + (shown - 1) * 22, 0)
				if hit.mark then
					if DropOwned(item) then hit.mark:Show() else hit.mark:Hide() end
				end
				hit:Show()
			end
		end
	end
	if shown < 1 and row.drop1 then row.drop1:Hide() end
	if shown < 2 and row.drop2 then row.drop2:Hide() end
	row.label:ClearAllPoints()
	row.label:SetPoint("LEFT", row.bar, "LEFT", 6, 0)
	row.label:SetPoint("RIGHT", row.bar, "RIGHT", -6, 0)
	row.label:SetJustifyH("CENTER")
	row.holder:Show()
end

local function BossMark(index)
	local mark = bossMarks[index]
	if mark then return mark end
	if index > BOSS_TIMER_CAP then return end
	mark = CreateFrame("Frame", nil, bossTimers)
	mark:SetWidth(14)
	mark:SetHeight(14)
	mark:SetFrameLevel(bossTimers:GetFrameLevel() + 4)
	mark:EnableMouse(true)
	local tex = mark:CreateTexture(nil, "OVERLAY")
	tex:SetTexture(TEX_BOSS_ALIVE)
	tex:SetAllPoints(mark)
	mark.tex = tex
	mark:SetScript("OnEnter", function()
		if not GameTooltip then return end
		GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
		GameTooltip:SetText(this.bossName or "Boss", 1, 0.82, 0)
		if this.bossAt then GameTooltip:AddLine(Clock(this.bossAt), 1, 1, 1) end
		if this.bossState == "dead" then GameTooltip:AddLine("Dead", 0.7, 0.7, 0.7) end
		if this.bossState == "up" then GameTooltip:AddLine("Alive", 1, 0.35, 0.3) end
		GameTooltip:Show()
	end)
	mark:SetScript("OnLeave", function() GameTooltip:Hide() end)
	mark:Hide()
	bossMarks[index] = mark
	return mark
end

local function HideBossMarks(from)
	local n = table.getn(bossMarks)
	local i
	for i = from, n do
		bossMarks[i]:Hide()
	end
end

local function RunSpan()
	local length
	if AZS_GetRunLength then length = Num(AZS_GetRunLength()) end
	if (not length or length < 1) and type(AZS_RUN) == "table" then
		length = Num(AZS_RUN.fin)
	end
	if not length or length < 1 then return end
	return length
end

local function IsEndless()
	return type(AZS_RUN) == "table" and (AZS_RUN.endl == 1 or AZS_RUN.endl == true)
end

local function NextBossLeft()
	if type(AZS_RUN) == "table" then
		local nb = Num(AZS_RUN.nb)
		if nb and nb >= 0 then return nb end
	end
	if AZS_GetUpcomingBosses then
		local upcoming = AZS_GetUpcomingBosses()
		if type(upcoming) == "table" and table.getn(upcoming) > 0 then
			local first = upcoming[1]
			if type(first) == "table" then return Num(first.left) end
		end
	end
end

local function AliveBossMap()
	local map = {}
	local bosses = AZS_GetBosses and AZS_GetBosses()
	local n = Count(bosses)
	local i
	for i = 1, n do
		local boss = bosses[i]
		if type(boss) == "table" and type(boss.name) == "string" and boss.name ~= "" then
			map[string.lower(boss.name)] = boss
		end
	end
	return map
end

local function PaintBossProgress(length, now, endless)
	if endless or not length then
		progressBg:Hide()
		progressBar:Hide()
		HideBossMarks(1)
		return
	end
	progressBg:Show()
	progressBar:Show()
	local filled = now
	if filled < 0 then filled = 0 end
	if filled > length then filled = length end
	progressBar:SetMinMaxValues(0, length)
	progressBar:SetValue(filled)
	local schedule = AZS_SCHEDULE
	local n = 0
	if type(schedule) == "table" then n = table.getn(schedule) end
	if n > BOSS_TIMER_CAP then n = BOSS_TIMER_CAP end
	local shown = 0
	local i
	for i = 1, n do
		local entry = schedule[i]
		if type(entry) == "table" then
			shown = shown + 1
			local mark = BossMark(shown)
			if mark then
				local at = Num(entry.at) or 0
				local x = (at / length) * BOSS_PROGRESS_W
				if x < 0 then x = 0 end
				if x > BOSS_PROGRESS_W then x = BOSS_PROGRESS_W end
				mark:ClearAllPoints()
				mark:SetPoint("CENTER", progressBg, "LEFT", x, 0)
				local state = entry.state
				mark.tex:SetVertexColor(1, 1, 1)
				mark.tex:SetAlpha(1)
				if state == "up" then
					mark.tex:SetTexture(TEX_BOSS_ALIVE)
					mark:SetWidth(16)
					mark:SetHeight(16)
				else
					mark.tex:SetTexture(TEX_BOSS_WAIT)
					mark:SetWidth(state == "dead" and 12 or 14)
					mark:SetHeight(state == "dead" and 12 or 14)
				end
				local name = entry.name
				if type(name) ~= "string" or name == "" then name = "Boss" end
				mark.bossName = name
				mark.bossAt = at
				mark.bossState = state
				mark:Show()
			end
		end
	end
	HideBossMarks(shown + 1)
end

local function UpdateBossTimers()
	if not On("bosstimer") or not (InRun() or Staging()) then
		if not On("bosstimer") then ShowStockClock() end
		if not (InRun() or Staging()) then ShowStockClock() end
		bossTimers:Hide()
		return
	end
	HideStockClock()
	local now = 0
	if AZS_GetRunTime then now = Num(AZS_GetRunTime()) or 0 end
	if now < 0 then now = 0 end
	local endless = IsEndless()
	local length = RunSpan()
	local nextLeft = NextBossLeft()
	local text = Clock(now)
	if not endless and length then
		text = text .. "/" .. Clock(length)
	end
	if nextLeft then
		text = text .. " | " .. Clock(nextLeft)
	end
	progressText:SetText(text)
	progressText:ClearAllPoints()
	if endless or not length then
		progressText:SetPoint("TOP", bossTimers, "TOP", 0, 0)
		bossTimers:SetHeight(20)
	else
		progressText:SetPoint("TOP", bossTimers, "TOP", 0, 0)
		bossTimers:SetHeight(34)
	end
	PaintBossProgress(length, now, endless)
	PlaceBossTimers()
	bossTimers:Show()
end

local function FinishBossList(count)
	HideBossTimerRows(count + 1)
	if count < 1 then
		bossList:Hide()
		return
	end
	bossList:SetHeight(BOSS_LIST_PAD * 2 + count * (BOSS_TIMER_ROW + BOSS_TIMER_GAP) - BOSS_TIMER_GAP)
	if not CoreComfortsDB.blleft then PlaceBossList() end
	bossList:Show()
end

local function PaintDueBoss(index, boss, prevAt)
	local startAt = 0
	if prevAt then
		startAt = prevAt
	else
		startAt = PreviousBossAt(boss)
	end
	local at = Num(boss.at)
	local span = 1
	if at then span = at - startAt end
	local left = Num(boss.left)
	if not left and at then
		local now = 0
		if AZS_GetRunTime then now = Num(AZS_GetRunTime()) or 0 end
		left = at - now
	end
	if not left or left < 0 then left = 0 end
	if span < 1 then
		if left > 1 then span = left else span = 1 end
	end
	local name = boss.name
	if type(name) ~= "string" or name == "" then name = "Boss" end
	local rawName = name
	local isFinal = boss.final == true or boss.final == 1
	if isFinal then name = name .. " (final)" end
	name = name .. "  " .. Clock(left)
	local r, g, b = BossTimerColor(left, isFinal)
	PaintBossTimer(index, name, left, span, r, g, b, rawName)
	return at
end

local function PaintAliveBoss(index, unit, isFinal)
	local name = unit.name
	if type(name) ~= "string" or name == "" then name = "Boss" end
	local rawName = name
	if isFinal then name = name .. " (final)" end
	local hp = Num(unit.hp) or 0
	local hpm = Num(unit.hpm) or 0
	if hpm < 1 then hpm = 1 end
	if hp < 0 then hp = 0 end
	if hp > hpm then hp = hpm end
	local pct = math.floor((hp * 100) / hpm + 0.5)
	name = name .. "  " .. pct .. "%"
	local r, g, b = 0.9, 0.12, 0.08
	if unit.enraged == true or unit.enraged == 1 then
		r, g, b = 1, 0.35, 0.1
	end
	PaintBossTimer(index, name, hp, hpm, r, g, b, rawName)
end

local function ShowBossListFromSchedule()
	local schedule = AZS_SCHEDULE
	if type(schedule) ~= "table" or table.getn(schedule) < 1 then return end
	local alive = AliveBossMap()
	local upcomingLeft = {}
	local upcoming = AZS_GetUpcomingBosses and AZS_GetUpcomingBosses()
	if type(upcoming) == "table" then
		local u
		for u = 1, table.getn(upcoming) do
			local boss = upcoming[u]
			if type(boss) == "table" and type(boss.name) == "string" then
				upcomingLeft[string.lower(boss.name)] = boss
			end
		end
	end
	local shown = 0
	local prevAt = nil
	local n = table.getn(schedule)
	local i
	for i = 1, n do
		if shown >= BOSS_TIMER_CAP then break end
		local entry = schedule[i]
		if type(entry) == "table" then
			local state = entry.state
			local name = entry.name
			if type(name) ~= "string" or name == "" then name = "Boss" end
			local isFinal = entry.final == true or entry.final == 1
			if state == "up" then
				local unit = alive[string.lower(name)]
				if unit then
					shown = shown + 1
					PaintAliveBoss(shown, unit, isFinal)
				end
				prevAt = Num(entry.at)
			elseif state ~= "dead" then
				shown = shown + 1
				local due = upcomingLeft[string.lower(name)]
				if not due then
					due = {
						name = name,
						at = entry.at,
						left = nil,
						final = entry.final,
						index = entry.index
					}
				end
				prevAt = PaintDueBoss(shown, due, prevAt)
			else
				prevAt = Num(entry.at)
			end
		end
	end
	FinishBossList(shown)
	if shown < 1 and IsEndless() then return end
	return true
end

local function ShowEndlessBossList()
	local aliveList = AZS_GetBosses and AZS_GetBosses()
	local shown = 0
	local n = Count(aliveList)
	local i
	for i = 1, n do
		if shown >= BOSS_TIMER_CAP then break end
		local unit = aliveList[i]
		if type(unit) == "table" then
			shown = shown + 1
			PaintAliveBoss(shown, unit, unit.final == true or unit.final == 1)
		end
	end
	local run = AZS_RUN
	local nb = nil
	if type(run) == "table" then nb = Num(run.nb) end
	if nb and nb >= 0 and shown < BOSS_TIMER_CAP then
		if bossTimerLastNb and nb > bossTimerLastNb + 0.5 then
			bossTimerEndlessSpan = nb
		end
		if not bossTimerEndlessSpan or nb > bossTimerEndlessSpan then
			bossTimerEndlessSpan = nb
		end
		bossTimerLastNb = nb
		local name = nil
		if type(run) == "table" then name = run.nbn end
		local rawName = name
		if type(name) ~= "string" or name == "" then
			name = "Next boss"
			rawName = nil
		end
		shown = shown + 1
		local r, g, b = BossTimerColor(nb, false)
		PaintBossTimer(shown, name .. "  " .. Clock(nb), nb, bossTimerEndlessSpan, r, g, b, rawName)
	else
		bossTimerEndlessSpan = nil
		bossTimerLastNb = nil
	end
	FinishBossList(shown)
end

local function UpdateBossList()
	if not On("bosslist") or not (InRun() or Staging()) then
		bossList:Hide()
		if not InRun() then
			bossTimerEndlessSpan = nil
			bossTimerLastNb = nil
		end
		return
	end
	if ShowBossListFromSchedule() then
		if not IsEndless() then
			bossTimerEndlessSpan = nil
			bossTimerLastNb = nil
		end
		return
	end
	if IsEndless() then
		ShowEndlessBossList()
		return
	end
	local upcoming = AZS_GetUpcomingBosses and AZS_GetUpcomingBosses()
	if type(upcoming) == "table" and table.getn(upcoming) > 0 then
		local shown = 0
		local prevAt = nil
		local n
		for n = 1, table.getn(upcoming) do
			if shown >= BOSS_TIMER_CAP then break end
			local boss = upcoming[n]
			if type(boss) == "table" then
				shown = shown + 1
				prevAt = PaintDueBoss(shown, boss, prevAt)
			end
		end
		local alive = AZS_GetBosses and AZS_GetBosses()
		local a = Count(alive)
		local i
		for i = 1, a do
			if shown >= BOSS_TIMER_CAP then break end
			local unit = alive[i]
			if type(unit) == "table" then
				shown = shown + 1
				PaintAliveBoss(shown, unit, unit.final == true or unit.final == 1)
			end
		end
		FinishBossList(shown)
		return
	end
	if Staging() then
		local r, g, b = BossTimerColor(60, false)
		PaintBossTimer(1, "Boss  0:00", 60, 60, r, g, b)
		FinishBossList(1)
		return
	end
	bossList:Hide()
end

local function UpdateList()
	if not On("list") or not (InRun() or Staging()) then
		list:Hide()
		return
	end
	local lairs = Lairs()
	local n = Count(lairs)
	local shown = 0
	local r
	for r = 1, n do
		if shown >= ROWS then break end
		local lair = lairs[r]
		if type(lair) == "table" then
			shown = shown + 1
			local row = rows[shown]
			local label = lair.name
			if type(label) ~= "string" or label == "" then label = "Guardian" end
			row.name:SetText(label)
			row.name:Show()
			if Living(lair) then
				if lair.state == "awake" then
					row.status:SetText("In combat")
					row.status:SetTextColor(1, 0.35, 0.3)
				else
					row.status:SetText("Alive")
					row.status:SetTextColor(1, 0.82, 0.25)
				end
			else
				local left = Num(lair.left)
				if not left or left < 0 then
					row.status:SetText("--")
					row.status:SetTextColor(0.8, 0.8, 0.8)
				else
					row.status:SetText(Clock(left))
					if left <= 15 then
						row.status:SetTextColor(1, 0.85, 0.3)
					else
						row.status:SetTextColor(0.9, 0.9, 0.9)
					end
				end
			end
			row.status:Show()
		end
	end
	local extra
	for extra = shown + 1, ROWS do
		rows[extra].name:Hide()
		rows[extra].status:Hide()
	end
	if shown < 1 then
		if Staging() and rows[1] then
			rows[1].name:SetText("Guardian")
			rows[1].name:Show()
			rows[1].status:SetText("--")
			rows[1].status:SetTextColor(0.8, 0.8, 0.8)
			rows[1].status:Show()
			for extra = 2, ROWS do
				rows[extra].name:Hide()
				rows[extra].status:Hide()
			end
			list:Show()
			list:SetHeight(29)
			return
		end
		list:Hide()
		return
	end
	list:Show()
	list:SetHeight(16 + shown * 13)
end

----------------------------------------------------------------
-- Minimap: yards from the player to a lair or cache
----------------------------------------------------------------

local function Diameter()
	local zoom = 2
	if Minimap and Minimap.GetZoom then
		local z = Minimap:GetZoom()
		if Num(z) and z >= 0 and z <= 5 then zoom = z end
	end
	local idx = zoom + 1
	local outside, inside
	if GetCVar then
		outside = tonumber(GetCVar("minimapZoom"))
		inside = tonumber(GetCVar("minimapInsideZoom"))
	end
	if Num(inside) and zoom == inside and zoom ~= outside then
		return indoorYards[idx]
	end
	return outdoorYards[idx]
end

local heroSample = { frame = -1 }

local function HeroAt()
	local now = GetTime()
	if heroSample.frame == now then
		if heroSample.ok then return heroSample end
		return
	end
	heroSample.frame = now
	heroSample.ok = nil
	heroSample.x, heroSample.y, heroSample.facing = nil, nil, nil
	heroSample.spaceId, heroSample.mapId, heroSample.runId = nil, nil, nil
	if AZS_GetPlayerPosition then
		local pos = AZS_GetPlayerPosition()
		if type(pos) == "table" and Num(pos.x) and Num(pos.y) then
			heroSample.x = pos.x
			heroSample.y = pos.y
			heroSample.facing = pos.facing
			heroSample.spaceId = pos.spaceId
			heroSample.mapId = pos.mapId
			heroSample.runId = pos.runId
			heroSample.ok = true
			return heroSample
		end
	end
	local run = AZS_RUN
	if type(run) == "table" and Num(run.px) and Num(run.py) then
		heroSample.x = run.px
		heroSample.y = run.py
		heroSample.facing = run.pf
		heroSample.ok = true
		return heroSample
	end
end

local function SamePlace(target, hero)
	if hero.spaceId ~= nil and target.spaceId ~= nil and hero.spaceId ~= target.spaceId then return end
	if hero.mapId ~= nil and target.mapId ~= nil and hero.mapId ~= target.mapId then return end
	if hero.runId ~= nil and target.runId ~= nil and hero.runId ~= target.runId then return end
	return true
end

local function Delta(target)
	if type(target) ~= "table" then return end
	local hero = HeroAt()
	if hero and Num(target.x) and Num(target.y) then
		if not SamePlace(target, hero) then return end
		local east = hero.y - target.y
		local north = target.x - hero.x
		return east, north, math.sqrt(east * east + north * north)
	end
	if not GetPlayerMapPosition then return end
	if not Num(target.mx) or not Num(target.my) then return end
	if target.mx < 0 or target.my < 0 or target.mx > 1 or target.my > 1 then return end
	local px, py = GetPlayerMapPosition("player")
	if not Num(px) or not Num(py) then return end
	if px == 0 and py == 0 then return end
	-- Map fractions, stretched by a zone-sized yard guess, only when neither
	-- the live position nor the run packet has world coordinates.
	local east = (target.mx - px) * 3000
	local north = (py - target.my) * 3000
	return east, north, math.sqrt(east * east + north * north)
end

local function AcquirePin()
	pinUsed = pinUsed + 1
	local pin = pins[pinUsed]
	if pin then return pin end
	if not Minimap or pinUsed > PIN_LIMIT then
		pinUsed = pinUsed - 1
		return
	end
	pin = CreateFrame("Frame", nil, Minimap)
	pin:SetWidth(10)
	pin:SetHeight(10)
	pin:EnableMouse(false)
	pin:SetFrameLevel(Minimap:GetFrameLevel() + 4)
	local tex = pin:CreateTexture(nil, "OVERLAY")
	tex:SetAllPoints(pin)
	tex:SetTexture(TEX_BOSS_ALIVE)
	pin.tex = tex
	pins[pinUsed] = pin
	return pin
end

local function PinSize()
	local zoom = 0
	if Minimap and Minimap.GetZoom then
		local z = Minimap:GetZoom()
		if Num(z) and z > 0 then zoom = z end
	end
	if zoom > 5 then zoom = 5 end
	return 7 + zoom * 1.3
end

local function PlacePin(pin, texture, x, y, size, r, g, b, timer)
	pin:SetWidth(size)
	pin:SetHeight(size)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
	pin.tex:SetTexture(texture)
	pin.tex:SetTexCoord(0, 1, 0, 1)
	pin.tex:SetVertexColor(r or 1, g or 1, b or 1, 1)
	if not pin.time then
		local label = pin:CreateFontString(nil, "OVERLAY")
		label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		label:SetPoint("CENTER", pin, "CENTER", 0, -1)
		label:SetTextColor(1, 0.95, 0.45)
		pin.time = label
	end
	if timer then
		pin.time:SetText(timer)
		pin.time:Show()
	else
		pin.time:Hide()
	end
	pin:Show()
end

local function HidePins()
	local n
	for n = 1, pinUsed do
		pins[n]:Hide()
	end
	pinUsed = 0
end

local function Rotate(tex, angle)
	local c = math.cos(angle) / 2
	local s = math.sin(angle) / 2
	tex:SetTexCoord(
		0.5 - c - s, 0.5 + s - c,
		0.5 - c + s, 0.5 + s + c,
		0.5 + c - s, 0.5 - s - c,
		0.5 + c + s, 0.5 - s + c
	)
end

local function Heading()
	local hero = HeroAt()
	if hero and Num(hero.facing) then return hero.facing end
	if not facingModel and Minimap and Minimap.GetChildren then
		local children = { Minimap:GetChildren() }
		local n = table.getn(children)
		local i
		for i = 1, n do
			local child = children[i]
			if child and child.GetModel and child.GetFacing then
				local ok, path = pcall(child.GetModel, child)
				if ok and type(path) == "string" then
					local lower = string.lower(path)
					if string.find(lower, "minimaparrow") and not string.find(lower, "rotating") then
						facingModel = child
					end
				end
			end
		end
	end
	if facingModel and facingModel.GetFacing then
		local ok, facing = pcall(facingModel.GetFacing, facingModel)
		if ok and Num(facing) then return facing end
		facingModel = nil
	end
	local run = AZS_RUN
	if type(run) == "table" and Num(run.pf) then return run.pf end
end

local function MakeGuide(name, iconPath, x, leftKey, topKey, title, texCoord)
	local named = type(title) == "string"
	local guide = CreateFrame("Frame", name, UIParent)
	guide:SetWidth(named and 128 or 80)
	guide:SetHeight(named and 40 or 52)
	guide:SetMovable(true)
	guide:EnableMouse(true)
	guide:RegisterForDrag("LeftButton")
	guide:SetClampedToScreen(true)
	guide:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	})
	guide:SetBackdropColor(0, 0, 0, 0.45)
	guide:SetBackdropBorderColor(0.85, 0.75, 0.4, 0.55)
	guide:SetPoint("BOTTOM", UIParent, "BOTTOM", x, 108)
	guide:Hide()
	guide.homeX = x
	guide.leftKey = leftKey
	guide.topKey = topKey
	guide.named = named
	local icon = guide:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(iconPath)
	if texCoord then icon:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4]) end
	icon:SetWidth(named and 22 or 22)
	icon:SetHeight(named and 22 or 22)
	icon:SetPoint("LEFT", guide, "LEFT", 6, named and 0 or 6)
	local arrow = guide:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
	arrow:SetWidth(28)
	arrow:SetHeight(28)
	if named then
		arrow:SetPoint("RIGHT", guide, "RIGHT", -4, 0)
	else
		arrow:SetPoint("LEFT", icon, "RIGHT", 2, 0)
	end
	local dist = guide:CreateFontString(nil, "OVERLAY")
	dist:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
	dist:SetShadowColor(0, 0, 0, 1)
	dist:SetShadowOffset(1, -1)
	if named then
		local caption = guide:CreateFontString(nil, "OVERLAY")
		caption:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
		caption:SetPoint("TOPLEFT", icon, "TOPRIGHT", 4, 1)
		caption:SetText(title)
		caption:SetTextColor(0.93, 0.8, 0.53)
		caption:SetShadowColor(0, 0, 0, 1)
		caption:SetShadowOffset(1, -1)
		local textW = caption:GetStringWidth()
		local guess = string.len(title) * 6
		if not textW or textW < guess then textW = guess end
		if textW < 40 then textW = 40 end
		guide:SetWidth(6 + 22 + 4 + textW + 6 + 28 + 6)
		arrow:ClearAllPoints()
		arrow:SetPoint("LEFT", guide, "LEFT", 6 + 22 + 4 + textW + 6, 0)
		dist:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -1)
		dist:SetTextColor(1, 0.96, 0.85)
	else
		dist:SetPoint("BOTTOM", guide, "BOTTOM", 6, 6)
		dist:SetTextColor(1, 0.9, 0.6)
	end
	guide.icon = icon
	guide.arrow = arrow
	guide.dist = dist
	guide:SetScript("OnDragStart", function()
		if Locked() then return end
		this:StartMoving()
	end)
	guide:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		local left = this:GetLeft()
		local top = this:GetTop()
		if left and top then
			CoreComfortsDB[this.leftKey] = left
			CoreComfortsDB[this.topKey] = top
		end
	end)
	return guide
end

local function PlaceGuide(guide)
	if not guide then return end
	guide:ClearAllPoints()
	guide:SetPoint("BOTTOM", UIParent, "BOTTOM", guide.homeX, 108)
end

local function RestoreGuide(guide)
	if not guide then return end
	local left = CoreComfortsDB[guide.leftKey]
	local top = CoreComfortsDB[guide.topKey]
	if left and top then
		guide:ClearAllPoints()
		guide:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	else
		PlaceGuide(guide)
	end
end

local function EnsureGuides()
	if guides.guardian then return end
	guides.guardian = MakeGuide(
		"CoreComfortsGuardGuide",
		TEX_BOSS_ALIVE,
		210,
		"agleft",
		"agtop",
		"Guardian"
	)
	guides.cache = MakeGuide(
		"CoreComfortsCacheGuide",
		TEX_CACHE,
		-210,
		"acleft",
		"actop",
		"Cache"
	)
	RestoreGuide(guides.guardian)
	RestoreGuide(guides.cache)
end

local function PointGuide(guide, best)
	if not guide then return end
	if not best then
		guide:Hide()
		return
	end
	local bearing = math.atan2(best.east, best.north)
	local facing = Heading()
	local angle = bearing
	if facing then angle = bearing + facing end
	Rotate(guide.arrow, angle)
	if best.texture and guide.icon then
		guide.icon:SetTexture(best.texture)
		guide.icon:SetTexCoord(0, 1, 0, 1)
	end
	if guide.named then
		guide.dist:SetText(string.format("%.0f yd", best.yards))
	else
		guide.dist:SetText(string.format("%.0f", best.yards))
	end
	guide:Show()
end

local function Consider(best, east, north, yards, name, texture)
	if not yards then return best end
	if not best or yards < best.yards then
		return { east = east, north = north, yards = yards, name = name, texture = texture }
	end
	return best
end

local function UpdateMap()
	HidePins()
	if not InRun() or not Minimap or not Minimap:IsShown() then
		if Staging() and (On("guardarrow") or On("cachearrow")) then
			EnsureGuides()
			if On("guardarrow") and guides.guardian then
				PointGuide(guides.guardian, { east = 0, north = 1, yards = 0 })
			elseif guides.guardian then
				guides.guardian:Hide()
			end
			if On("cachearrow") and guides.cache then
				PointGuide(guides.cache, { east = 0, north = 1, yards = 0 })
			elseif guides.cache then
				guides.cache:Hide()
			end
			return
		end
		if guides.guardian then guides.guardian:Hide() end
		if guides.cache then guides.cache:Hide() end
		return
	end

	local width = Minimap:GetWidth()
	local yardsAcross = Diameter()
	if not Num(width) or width <= 16 or not Num(yardsAcross) or yardsAcross <= 0 then return end
	local scale = width / yardsAcross
	local pinSize = PinSize()
	local limit = width / 2 - pinSize / 2 - 1

	local nearestGuard
	local nearestCache
	local lairs = Lairs()
	local n = Count(lairs)
	local r
	for r = 1, n do
		local lair = lairs[r]
		if type(lair) == "table" then
			local east, north, yards = Delta(lair)
			local label = lair.name
			if type(label) ~= "string" or label == "" then label = "Guardian" end
			local texture = TEX_BOSS_WAIT
			if lair.state == "awake" then
				texture = TEX_BOSS_COMBAT
			elseif Living(lair) then
				texture = TEX_BOSS_ALIVE
			end
			if lair.state == "asleep" then
				nearestGuard = Consider(nearestGuard, east, north, yards, label, TEX_BOSS_ALIVE)
			end
			if On("guardpins") and east then
				local timer
				if lair.state ~= "awake" and not Living(lair) then
					local left = Num(lair.left)
					local limit = Num(CoreComfortsDB.pintimer)
					if not limit then limit = 30 end
					limit = math.floor(limit + 0.5)
					if limit < 0 then limit = 0 end
					if limit > 180 then limit = 180 end
					if left and limit > 0 and left >= 0 and left <= limit then
						timer = string.format("%.0f", math.floor(left))
					end
				end
				local x = east * scale
				local y = north * scale
				local px = math.sqrt(x * x + y * y)
				if px > limit and px > 0 then
					x = x / px * limit
					y = y / px * limit
				end
				local pin = AcquirePin()
				if pin then PlacePin(pin, texture, x, y, pinSize, 1, 1, 1, timer) end
			end
		end
	end

	local chests = Chests()
	n = Count(chests)
	for r = 1, n do
		local chest = chests[r]
		if type(chest) == "table" then
			local east, north, yards = Delta(chest)
			nearestCache = Consider(nearestCache, east, north, yards, "Cache", TEX_CACHE)
			if On("cachepins") and east then
				local x = east * scale
				local y = north * scale
				local px = math.sqrt(x * x + y * y)
				if px <= limit then
					local pin = AcquirePin()
					if pin then PlacePin(pin, TEX_CACHE, x, y, pinSize, 1, 1, 1) end
				end
			end
		end
	end

	if On("guardarrow") or On("cachearrow") then EnsureGuides() end
	if guides.guardian then
		if On("guardarrow") then PointGuide(guides.guardian, nearestGuard) else guides.guardian:Hide() end
	end
	if guides.cache then
		if On("cachearrow") then PointGuide(guides.cache, nearestCache) else guides.cache:Hide() end
	end
end

----------------------------------------------------------------
-- Our own boss and guardian bars. Debuff icons sit under each
-- bar. The stock bars stay hidden while this is on, so the
-- addon never walks the whole interface looking for them.
----------------------------------------------------------------

local BAR_UNITS = 8
local BAR_ICONS = 8
local BAR_ICON = 12
local BAR_W = 240
local bossGroup
local bossRows = {}
local stockBossesHidden = false

local function PlaceBosses()
	if not bossGroup then return end
	bossGroup:ClearAllPoints()
	bossGroup:SetPoint("TOP", UIParent, "TOP", 0, -48)
end

local function RestoreBosses()
	if not bossGroup then return end
	if CoreComfortsDB.bleft and CoreComfortsDB.btop then
		bossGroup:ClearAllPoints()
		bossGroup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", CoreComfortsDB.bleft, CoreComfortsDB.btop)
	else
		PlaceBosses()
	end
end

local function HideStockBosses()
	if stockBossesHidden or not AZS_SetHudShown then return end
	AZS_SetHudShown("bosses", false)
	stockBossesHidden = true
end

local function ShowStockBosses()
	if not stockBossesHidden or not AZS_SetHudShown then return end
	AZS_SetHudShown("bosses", true)
	stockBossesHidden = false
end

local function BossRow(index)
	local row = bossRows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, bossGroup)
	row:SetWidth(BAR_W)
	row:SetHeight(24)
	local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("TOP", row, "TOP", 0, 0)
	name:SetJustifyH("CENTER")
	name:SetTextColor(1, 0.9, 0.75)
	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bg:SetVertexColor(0.25, 0.05, 0.05, 0.9)
	bg:SetWidth(BAR_W - 10)
	bg:SetHeight(8)
	bg:SetPoint("TOP", row, "TOP", 0, -13)
	local bar = CreateFrame("StatusBar", nil, row)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0.9, 0.12, 0.08)
	bar:SetMinMaxValues(0, 1)
	bar:SetAllPoints(bg)
	bar:SetFrameLevel(row:GetFrameLevel() + 3)
	local orange = CreateFrame("StatusBar", nil, row)
	orange:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	orange:SetStatusBarColor(1, 0.5, 0.05)
	orange:SetMinMaxValues(0, 1)
	orange:SetAllPoints(bg)
	orange:SetFrameLevel(row:GetFrameLevel() + 2)
	row.name = name
	row.bar = bar
	row.orange = orange
	row.icons = {}
	local n
	for n = 1, BAR_ICONS do
		local icon = CreateFrame("Frame", nil, row)
		icon:SetWidth(BAR_ICON)
		icon:SetHeight(BAR_ICON)
		icon:EnableMouse(true)
		local tex = icon:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints(icon)
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local stacks = icon:CreateFontString(nil, "OVERLAY")
		stacks:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
		stacks:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 1, 1)
		stacks:SetTextColor(0.25, 1, 0.35)
		local time = icon:CreateFontString(nil, "OVERLAY")
		time:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
		time:SetPoint("BOTTOM", icon, "BOTTOM", 0, 0)
		time:SetTextColor(1, 0.95, 0.7)
		icon.tex = tex
		icon.stacks = stacks
		icon.time = time
		icon:SetScript("OnEnter", function()
			if not this.tip or not GameTooltip then return end
			GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
			GameTooltip:SetText(this.tip)
			if this.extra then GameTooltip:AddLine(this.extra, 1, 0.82, 0.4) end
			GameTooltip:Show()
		end)
		icon:SetScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
		icon:Hide()
		row.icons[n] = icon
	end
	bossRows[index] = row
	return row
end

local function EnsureBosses()
	if bossGroup then return end
	bossGroup = CreateFrame("Frame", "CoreComfortsBosses", UIParent)
	bossGroup:SetWidth(BAR_W)
	bossGroup:SetHeight(24)
	bossGroup:SetMovable(true)
	bossGroup:EnableMouse(true)
	bossGroup:RegisterForDrag("LeftButton")
	bossGroup:SetClampedToScreen(true)
	bossGroup:SetScript("OnDragStart", function()
		if Locked() then return end
		this:StartMoving()
	end)
	bossGroup:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		local left = this:GetLeft()
		local top = this:GetTop()
		if left and top then
			CoreComfortsDB.bleft = left
			CoreComfortsDB.btop = top
		end
	end)
	PlaceBosses()
	RestoreBosses()
end

local function CollectEffects(unit, into)
	if not AZS_GetDebuffs or type(unit) ~= "table" or not Num(unit.id) then return end
	local list = AZS_GetDebuffs(unit.id)
	local n = Count(list)
	local i
	for i = 1, n do
		if table.getn(into) >= BAR_ICONS then return end
		local effect = list[i]
		if type(effect) == "table" and type(effect.icon) == "string" and effect.icon ~= "" then
			tinsert(into, effect)
		end
	end
end

----------------------------------------------------------------
-- DoT estimate. Per boss or guardian and per DoT, the periodic
-- hits of the last few seconds give a damage rate. The estimate
-- is that rate from the last hit to when the DoT runs out, so it
-- drops when a tick lands instead of on a clock of its own.
-- Everything is timed on the run clock, which stops in pauses.
----------------------------------------------------------------

local LearnDots, EffectEstimate, DotDebug
do
	local DOT_WINDOW = 6
	local DOT_BREAK = 4
	local DOT_MIN_SPAN = 0.5
	local DEBUG_EVERY = 3
	local dotUnits = {}
	local dotSpells = {}
	local dotFeed = {}
	local dotDebug = { on = false, clock = 0, counts = {}, sampled = {}, meter = {} }
	local DebugReport

	local function DebugNote(event, outcome)
		if not dotDebug.on then return end
		local label = event.meterSource
		if type(label) ~= "string" or label == "" then label = event.abilityName end
		if type(label) ~= "string" or label == "" then label = "?" end
		local c = dotDebug.counts[label]
		if not c then
			c = { hit = 0, sum = 0, crit = 0, noUnit = 0, noDebuff = 0, direct = 0, directSum = 0, proc = 0, procSum = 0 }
			dotDebug.counts[label] = c
		end
		c[outcome] = c[outcome] + 1
		if outcome == "hit" then
			c.sum = c.sum + (Num(event.amount) or 0)
			if event.critical == true or event.critical == 1 then c.crit = c.crit + 1 end
		elseif outcome == "direct" then
			c.directSum = c.directSum + (Num(event.amount) or 0)
		elseif outcome == "proc" then
			c.procSum = c.procSum + (Num(event.amount) or 0)
		end
		local sampleKey = label .. " " .. outcome
		if dotDebug.sampled[sampleKey] then return end
		dotDebug.sampled[sampleKey] = true
		local keys = {}
		local k, v
		for k, v in pairs(event) do
			if type(v) ~= "table" and type(v) ~= "function" then
				tinsert(keys, tostring(k) .. "=" .. tostring(v))
			end
		end
		table.sort(keys)
		Say("DoT event " .. label .. " (" .. outcome .. "): " .. table.concat(keys, " ") .. string.format(" (GetTime %.2f)", GetTime()))
	end

	local function DotNow()
		local t = AZS_GetRunTime and Num(AZS_GetRunTime())
		return t or GetTime()
	end

	local function ClearDots()
		dotUnits = {}
		dotSpells = {}
	end

	local function EventTime(event, now)
		local at = Num(event.presentedAt)
		local real = GetTime()
		if at and at <= real + 0.5 and at >= real - DOT_WINDOW then
			return now - (real - at)
		end
		return now
	end

	local function DotRate(rec)
		local hits = rec.hits
		local n = table.getn(hits)
		if n < 2 then return end
		local span = hits[n].t - hits[1].t
		if span < DOT_MIN_SPAN then return end
		local sum = 0
		local i
		for i = 2, n do sum = sum + hits[i].amount end
		return sum / span, span
	end

	local function ProcRate(rec, now)
		local total = 0
		if not rec.procs then return total end
		local label, proc
		for label, proc in pairs(rec.procs) do
			local hits = proc.hits
			local n = table.getn(hits)
			if n > 0 and now - hits[n].t < DOT_BREAK then
				local r = DotRate(proc)
				if r then total = total + r end
			end
		end
		return total
	end

	local function UnitRate(unit, name, now)
		local rec = dotUnits[unit.id] and dotUnits[unit.id][name]
		local feed = rec and DotRate(rec)
		local procs = 0
		if rec then procs = ProcRate(rec, now) end
		local tick = feed or dotSpells[name]
		if not tick and procs > 0 then tick = 0 end
		if not tick then return nil, rec, feed, procs end
		return tick + procs, rec, feed, procs
	end

	local function DotTarget(event, bosses, guardians)
		local target = event.targetName
		local named = type(target) == "string" and target ~= ""
		local id = Num(event.targetId)
		local i
		if id then
			for i = 1, Count(bosses) do
				local u = bosses[i]
				if type(u) == "table" and u.id == id and (not named or u.name == target) then return u end
			end
			for i = 1, Count(guardians) do
				local u = guardians[i]
				if type(u) == "table" and u.id == id and (not named or u.name == target) then return u end
			end
		end
		if not named then return end
		for i = 1, Count(bosses) do
			local u = bosses[i]
			if type(u) == "table" and u.name == target then return u end
		end
		if type(AZS_UNITS) == "table" then
			local same = 0
			for i = 1, Count(AZS_UNITS) do
				local entry = AZS_UNITS[i]
				if type(entry) == "table" and entry.name == target then same = same + 1 end
			end
			if same ~= 1 then return end
		end
		for i = 1, Count(guardians) do
			local u = guardians[i]
			if type(u) == "table" and u.name == target then return u end
		end
	end

	local function NoteCombat(event, bosses, guardians, now)
		if type(event) ~= "table" or event.kind ~= "damage" then return end
		if event.reflected == true or event.reflected == 1 then return end
		local amount = Num(event.amount)
		if not amount or amount <= 0 then return end
		local periodic = event.periodic == true or event.periodic == 1
		local ability = event.abilityName
		if type(ability) ~= "string" or ability == "" then ability = nil end
		local source = event.meterSource
		if type(source) ~= "string" or source == "" then source = ability end
		local borrowed = ability and source and source ~= ability
		local unit = DotTarget(event, bosses, guardians)
		if type(unit) ~= "table" or not Num(unit.id) then
			if periodic then DebugNote(event, "noUnit") end
			return
		end
		if not periodic and not borrowed then
			DebugNote(event, "direct")
			return
		end
		local list = AZS_GetDebuffs(unit.id)
		local effect
		local i
		for i = 1, Count(list) do
			local candidate = list[i]
			if type(candidate) == "table" and candidate.permanent ~= true and candidate.permanent ~= 1 then
				local label = candidate.name
				if type(label) == "string" and label ~= "" then
					local match
					if borrowed then
						match = label == ability
					else
						match = label == source or (Num(event.spellId) and Num(candidate.spell) and event.spellId == candidate.spell)
					end
					if match then
						effect = candidate
						break
					end
				end
			end
		end
		local byUnit = dotUnits[unit.id]
		local key = source
		if borrowed then key = ability end
		local name
		if effect then
			name = effect.name
		elseif byUnit and key and byUnit[key] then
			name = key
		else
			DebugNote(event, "noDebuff")
			return
		end
		if not byUnit then
			byUnit = {}
			dotUnits[unit.id] = byUnit
		end
		local rec = byUnit[name]
		if not rec then
			rec = { hits = {} }
			byUnit[name] = rec
		end
		local at = EventTime(event, now)
		if borrowed then
			DebugNote(event, "proc")
			if not rec.procs then rec.procs = {} end
			local proc = rec.procs[source]
			if not proc then
				proc = { hits = {} }
				rec.procs[source] = proc
			end
			local ph = proc.hits
			local pn = table.getn(ph)
			if pn > 0 and at - ph[pn].t > DOT_BREAK then
				proc.hits = {}
				ph = proc.hits
			end
			tinsert(ph, { t = at, amount = amount })
			while table.getn(ph) > 1 and at - ph[1].t > DOT_WINDOW do
				table.remove(ph, 1)
			end
			if not rec.last or at > rec.last then rec.last = at end
			return
		end
		DebugNote(event, "hit")
		local hits = rec.hits
		local n = table.getn(hits)
		if n > 0 and at - hits[n].t > DOT_BREAK then
			rec.hits = {}
			hits = rec.hits
		end
		tinsert(hits, { t = at, amount = amount })
		while table.getn(hits) > 1 and at - hits[1].t > DOT_WINDOW do
			table.remove(hits, 1)
		end
		if not rec.last or at > rec.last then rec.last = at end
		if effect then
			local stacks = Num(effect.stacks) or 1
			if stacks < 1 then stacks = 1 end
			rec.stacks = stacks
		end
		local rate = DotRate(rec)
		if rate then
			local old = dotSpells[name]
			if old then dotSpells[name] = old * 0.7 + rate * 0.3 else dotSpells[name] = rate end
		end
	end

	local function ReadCombatTicks(bosses, guardians, now)
		if not AZS_GetCombatTextEvents then return end
		local guard = 0
		while guard < 5 do
			guard = guard + 1
			local batch, err = AZS_GetCombatTextEvents(dotFeed.cursor, 256)
			if not batch then
				if type(err) == "table" and err.code == "STREAM_CHANGED" then
					ClearDots()
					dotFeed.cursor = nil
					dotFeed.stream = nil
				elseif type(err) == "table" and (err.code == "NOT_READY" or err.code == "NOT_IN_WORLD") then
					dotFeed.cursor = nil
				end
				return
			end
			if type(dotFeed.stream) == "string" and type(batch.streamId) == "string" and dotFeed.stream ~= batch.streamId then
				ClearDots()
			end
			dotFeed.stream = batch.streamId
			if batch.cursor ~= nil then dotFeed.cursor = batch.cursor end
			local events = batch.events
			local i
			for i = 1, Count(events) do
				NoteCombat(events[i], bosses, guardians, now)
			end
			if batch.hasMore ~= true and batch.hasMore ~= 1 then return end
		end
	end

	LearnDots = function()
		if not On("dotestimate") or not AZS_GetDebuffs then return end
		local bosses = AZS_GetBosses and AZS_GetBosses()
		local guardians = AZS_GetGuardians and AZS_GetGuardians()
		ReadCombatTicks(bosses, guardians, DotNow())
		local alive = {}
		local i
		for i = 1, Count(bosses) do
			if type(bosses[i]) == "table" and bosses[i].id then alive[bosses[i].id] = true end
		end
		for i = 1, Count(guardians) do
			if type(guardians[i]) == "table" and guardians[i].id then alive[guardians[i].id] = true end
		end
		local id
		for id in pairs(dotUnits) do
			if not alive[id] then dotUnits[id] = nil end
		end
		if DebugReport then DebugReport(bosses, guardians) end
	end

	EffectEstimate = function(unit, effect, copies)
		if not On("dotestimate") or type(unit) ~= "table" or type(effect) ~= "table" or type(effect.name) ~= "string" then return end
		if effect.permanent == true or effect.permanent == 1 then return end
		local left = Num(effect.remaining)
		if not left or left <= 0 then return end
		local now = DotNow()
		local rate, rec = UnitRate(unit, effect.name, now)
		if not rate or rate <= 0 then return end
		local stacks = Num(effect.stacks) or 1
		if stacks < 1 then stacks = 1 end
		if rec and rec.stacks and rec.stacks > 0 and stacks ~= rec.stacks then
			rate = rate * stacks / rec.stacks
		end
		if not copies or copies < 1 then copies = 1 end
		rate = rate / copies
		local from = now
		if rec and rec.last and rec.last <= now and now - rec.last < DOT_BREAK then from = rec.last end
		local duration = Num(effect.duration)
		if duration and duration > 0 and from < now + left - duration then from = now + left - duration end
		local span = now + left - from
		if span <= 0 then return end
		return rate * span
	end

	DebugReport = function(bosses, guardians)
		if not dotDebug.on then return end
		local real = GetTime()
		local span = real - dotDebug.clock
		if span < DEBUG_EVERY then return end
		dotDebug.clock = real
		local label, c
		for label, c in pairs(dotDebug.counts) do
			if c.hit + c.proc + c.noUnit + c.noDebuff > 0 then
				Say(string.format("feed %s: %d ticks (%d crits) %.0f dmg, %d borrowed hits %.0f dmg, %d direct %.0f dmg; skipped %d no target, %d no debuff",
					label, c.hit, c.crit, c.sum, c.proc, c.procSum, c.direct, c.directSum, c.noUnit, c.noDebuff))
			end
		end
		dotDebug.counts = {}
		local meter = {}
		local lines = AZS_GetBossMeter and AZS_GetBossMeter()
		local i
		for i = 1, Count(lines) do
			local line = lines[i]
			if type(line) == "table" and type(line.name) == "string" and Num(line.dmg) then meter[line.name] = line.dmg end
		end
		local units = {}
		for i = 1, Count(bosses) do tinsert(units, bosses[i]) end
		for i = 1, Count(guardians) do
			local g = guardians[i]
			if type(g) == "table" and (g.awake == true or g.awake == 1) then tinsert(units, g) end
		end
		local u
		for u = 1, table.getn(units) do
			local unit = units[u]
			if u <= 3 and type(unit) == "table" and Num(unit.id) and AZS_GetDebuffs then
				local list = AZS_GetDebuffs(unit.id)
				local groups, order = {}, {}
				for i = 1, Count(list) do
					local effect = list[i]
					if type(effect) == "table" and type(effect.name) == "string" and effect.permanent ~= true and effect.permanent ~= 1 then
						local g = groups[effect.name]
						if not g then
							g = { n = 0, stacks = 0, effects = {} }
							groups[effect.name] = g
							tinsert(order, effect.name)
						end
						g.n = g.n + 1
						g.stacks = g.stacks + (Num(effect.stacks) or 1)
						tinsert(g.effects, effect)
						local left = Num(effect.remaining)
						if left and (not g.left or left > g.left) then g.left = left end
						if Num(effect.duration) then g.dur = effect.duration end
					end
				end
				local o
				for o = 1, table.getn(order) do
					local name = order[o]
					local g = groups[name]
					local est = 0
					local e
					for e = 1, table.getn(g.effects) do
						est = est + (EffectEstimate(unit, g.effects[e], g.n) or 0)
					end
					local rec = dotUnits[unit.id] and dotUnits[unit.id][name]
					local kept = 0
					local feed
					if rec then
						kept = table.getn(rec.hits)
						feed = DotRate(rec)
					end
					local used, _, _, procs = UnitRate(unit, name, DotNow())
					local meterRate
					if meter[name] and dotDebug.meter[name] and meter[name] >= dotDebug.meter[name] then
						meterRate = (meter[name] - dotDebug.meter[name]) / span
					end
					Say(string.format("%s / %s: %d entries, %d stacks, %.1fs left of %s, %d ticks kept, ticks %s/s + borrowed %.0f/s = %s/s, boss meter %s/s, estimate %.0f",
						tostring(unit.name), name, g.n, g.stacks, g.left or -1, g.dur and string.format("%.1fs", g.dur) or "?",
						kept, feed and string.format("%.0f", feed) or "-",
						procs or 0, used and string.format("%.0f", used) or "-", meterRate and string.format("%.0f", meterRate) or "-", est))
				end
			end
		end
		dotDebug.meter = meter
	end

	DotDebug = function()
		dotDebug.on = not dotDebug.on
		dotDebug.clock = GetTime()
		dotDebug.counts = {}
		dotDebug.sampled = {}
		dotDebug.meter = {}
		if dotDebug.on then
			Say("DoT debug on. Every 3 seconds it prints the DoT ticks it read and the boss meter. /cc dotdebug again stops it.")
			if not On("dotestimate") then Say("Turn on DoT damage on boss bars in the Experimental tab first, or nothing is read.") end
		else
			Say("DoT debug off.")
		end
	end
end

local function PaintIcon(icon, effect, est)
	icon.tex:SetTexture(effect.icon)
	local stacks = Num(effect.stacks)
	if stacks and stacks > 1 then
		icon.stacks:SetText(string.format("%.0f", stacks))
	else
		icon.stacks:SetText("")
	end
	local label = effect.name
	if type(label) ~= "string" or label == "" then label = "Debuff" end
	icon.tip = label
	if effect.permanent == true or effect.permanent == 1 then
		icon.time:SetText("")
		icon.extra = "No expiration"
	else
		local left = Num(effect.remaining)
		if left and left >= 0 then
			local text
			if left < 60 then
				text = string.format("%.0f", math.floor(left))
			else
				text = Clock(left)
			end
			icon.time:SetText(text)
			icon.extra = text .. " left"
		else
			icon.time:SetText("")
			icon.extra = nil
		end
	end
	if On("dotestimate") and effect.permanent ~= true and effect.permanent ~= 1 then
		if est and est > 0 then
			est = math.floor(est + 0.5)
			if icon.extra then
				icon.extra = icon.extra .. ", about " .. est
			else
				icon.extra = "about " .. est
			end
		end
	end
	icon:Show()
end

local function UpdateDebuffs(dt)
	EnsureBosses()
	if not On("debuffs") or not (InRun() or Staging()) then
		if not On("debuffs") then ShowStockBosses() end
		bossGroup:Hide()
		return
	end
	if InRun() then HideStockBosses() else ShowStockBosses() end
	LearnDots()
	local units = {}
	local seenId = {}
	local function AddUnit(unit)
		if type(unit) ~= "table" or not Num(unit.id) or seenId[unit.id] then return end
		if table.getn(units) >= BAR_UNITS then return end
		seenId[unit.id] = true
		tinsert(units, unit)
	end
	local bosses = AZS_GetBosses and AZS_GetBosses()
	local n = Count(bosses)
	local i
	for i = 1, n do AddUnit(bosses[i]) end
	local guardians = AZS_GetGuardians and AZS_GetGuardians()
	n = Count(guardians)
	for i = 1, n do
		local guardian = guardians[i]
		if type(guardian) == "table" and (guardian.awake == true or guardian.awake == 1) then
			AddUnit(guardian)
		end
	end
	local shown = 0
	local y = 0
	for i = 1, table.getn(units) do
		local unit = units[i]
		local hp = Num(unit.hp) or 0
		local hpm = Num(unit.hpm) or 0
		if hpm > 0 then
			shown = shown + 1
			local row = BossRow(shown)
			local label = unit.name
			if type(label) ~= "string" or label == "" then label = "Guardian" end
			row.name:SetText(label)
			if unit.enraged == true or unit.enraged == 1 then
				row.bar:SetStatusBarColor(1, 0.35, 0.05)
			else
				row.bar:SetStatusBarColor(0.9, 0.12, 0.08)
			end
			local effects = {}
			CollectEffects(unit, effects)
			local count = table.getn(effects)
			local dot = 0
			local copies = {}
			local ests = {}
			local e
			for e = 1, count do
				local label = effects[e].name
				if type(label) == "string" then copies[label] = (copies[label] or 0) + 1 end
			end
			for e = 1, count do
				local est = EffectEstimate(unit, effects[e], copies[effects[e].name])
				ests[e] = est
				if est and est > 0 then dot = dot + est end
			end
			if dot > hp then dot = hp end
			row.orange:SetMinMaxValues(0, hpm)
			row.orange:SetValue(hp)
			row.bar:SetMinMaxValues(0, hpm)
			row.bar:SetValue(hp - dot)
			local span = 0
			if count > 0 then span = count * BAR_ICON + (count - 1) end
			local start = (BAR_W - span) / 2
			for e = 1, count do
				local icon = row.icons[e]
				icon:ClearAllPoints()
				icon:SetPoint("TOPLEFT", row, "TOPLEFT", start + (e - 1) * (BAR_ICON + 1), -23)
				PaintIcon(icon, effects[e], ests[e])
			end
			for e = count + 1, BAR_ICONS do
				row.icons[e]:Hide()
			end
			local height = 22
			if count > 0 then height = 23 + BAR_ICON end
			row:SetHeight(height)
			row:ClearAllPoints()
			row:SetPoint("TOP", bossGroup, "TOP", 0, -y)
			row:Show()
			y = y + height + 6
		end
	end
	for i = shown + 1, table.getn(bossRows) do
		bossRows[i]:Hide()
	end
	if shown < 1 then
		if Staging() then
			local row = BossRow(1)
			row.name:SetText("Boss")
			row.bar:SetStatusBarColor(0.9, 0.12, 0.08)
			row.orange:SetMinMaxValues(0, 1)
			row.orange:SetValue(0)
			row.bar:SetMinMaxValues(0, 1)
			row.bar:SetValue(1)
			local e
			for e = 1, BAR_ICONS do
				row.icons[e]:Hide()
			end
			row:SetHeight(22)
			row:ClearAllPoints()
			row:SetPoint("TOP", bossGroup, "TOP", 0, 0)
			row:Show()
			for i = 2, table.getn(bossRows) do
				bossRows[i]:Hide()
			end
			bossGroup:SetHeight(28)
			bossGroup:Show()
			return
		end
		bossGroup:Hide()
		return
	end
	bossGroup:SetHeight(y)
	bossGroup:Show()
end

----------------------------------------------------------------
-- Jewelry row. The game's build HUD is one piece, so hiding the
-- ability icons also hides its jewelry squares. This row replaces them.
-- Built inside a function so its locals stay under Lua's 200 limit.
----------------------------------------------------------------

local PlaceJewelry, UpdateJewelry, ShowStockBuild

local function BuildJewelry()
local JEWEL_SLOTS = {
	{ "Finger0Slot", 11, "Interface\\Paperdoll\\UI-PaperDoll-Slot-Finger" },
	{ "Finger1Slot", 12, "Interface\\Paperdoll\\UI-PaperDoll-Slot-Finger" },
	{ "NeckSlot", 2, "Interface\\Paperdoll\\UI-PaperDoll-Slot-Neck" },
	{ "Trinket0Slot", 13, "Interface\\Paperdoll\\UI-PaperDoll-Slot-Trinket" },
	{ "Trinket1Slot", 14, "Interface\\Paperdoll\\UI-PaperDoll-Slot-Trinket" }
}
local JEWEL_SIZE = 28
local JEWEL_PITCH = 46
local JEWEL_PAD = 16
local stockBuildHidden = false
local jewelSlots = {}
local jewelryTold = false
local jewelStrips = {}
local jewelRadius = JEWEL_SIZE / 2
local jewelRow = 0
while jewelRow < JEWEL_SIZE do
	local mid = jewelRow + 0.5 - jewelRadius
	local inside = jewelRadius * jewelRadius - mid * mid
	if inside > 0 then
		local half = math.sqrt(inside)
		local left = jewelRadius - half
		table.insert(jewelStrips, {
			left = left,
			top = jewelRow,
			width = half * 2,
			height = 1
		})
	end
	jewelRow = jewelRow + 1
end

local jewelry = CreateFrame("Frame", "CoreComfortsJewelry", UIParent)
jewelry:SetWidth(JEWEL_PAD * 2 + JEWEL_SIZE + JEWEL_PITCH * 4)
jewelry:SetHeight(JEWEL_SIZE)
jewelry:SetMovable(true)
jewelry:EnableMouse(true)
jewelry:RegisterForDrag("LeftButton")
jewelry:SetClampedToScreen(true)
jewelry:SetPoint("BOTTOM", counter, "TOP", 0, 6)
jewelry:Hide()

local function DragJewelry()
	if Locked() then return end
	jewelry:StartMoving()
end

local function StopJewelry()
	jewelry:StopMovingOrSizing()
	CoreComfortsDB.jleft = jewelry:GetLeft()
	CoreComfortsDB.jtop = jewelry:GetTop()
end

jewelry:SetScript("OnDragStart", DragJewelry)
jewelry:SetScript("OnDragStop", StopJewelry)

local ji
for ji = 1, 5 do
	local spec = JEWEL_SLOTS[ji]
	local button = CreateFrame("Button", "CoreComfortsJewel" .. ji, jewelry)
	button:SetWidth(JEWEL_SIZE)
	button:SetHeight(JEWEL_SIZE)
	button:SetPoint("LEFT", jewelry, "LEFT", JEWEL_PAD + (ji - 1) * JEWEL_PITCH, 0)
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", DragJewelry)
	button:SetScript("OnDragStop", StopJewelry)
	button.slotName = spec[1]
	button.slotFallback = spec[2]
	button.emptyTexture = spec[3]
	button.strips = {}
	local stripIndex
	for stripIndex = 1, table.getn(jewelStrips) do
		local specStrip = jewelStrips[stripIndex]
		local strip = button:CreateTexture(nil, "ARTWORK")
		strip:SetPoint("TOPLEFT", button, "TOPLEFT", specStrip.left, -specStrip.top)
		strip:SetWidth(specStrip.width)
		strip:SetHeight(specStrip.height)
		button.strips[stripIndex] = strip
	end
	local cd = button:CreateFontString(nil, "OVERLAY")
	cd:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	cd:SetPoint("CENTER", button, "CENTER", 0, 0)
	cd:SetTextColor(1, 0.9, 0.4)
	button.cd = cd
	button:SetScript("OnEnter", function()
		local id = this.slotId
		if not id or not this.filled or not GameTooltip or not GameTooltip.SetInventoryItem then return end
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetInventoryItem("player", id)
	end)
	button:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	jewelSlots[ji] = button
end

PlaceJewelry = function()
	jewelry:ClearAllPoints()
	if CoreComfortsDB.jleft and CoreComfortsDB.jtop then
		jewelry:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", CoreComfortsDB.jleft, CoreComfortsDB.jtop)
	else
		jewelry:SetPoint("BOTTOM", counter, "TOP", 0, 6)
	end
end

local function DragonForcesBuild()
	if type(DFRL) ~= "table" then return false end
	local display = DFRL.display
	if type(display) ~= "table" or type(display.Get) ~= "function" then return false end
	local hide = display.Get("hideNativeBuild")
	if hide == true or hide == 1 then return false end
	return true
end

local function HideStockBuild()
	if stockBuildHidden or not AZS_SetHudShown then return end
	if DragonForcesBuild() then return end
	AZS_SetHudShown("build", false)
	stockBuildHidden = true
end

ShowStockBuild = function()
	if not stockBuildHidden or not AZS_SetHudShown then return end
	AZS_SetHudShown("build", true)
	stockBuildHidden = false
end

local function JewelSlotId(button)
	if button.slotId then return button.slotId end
	if GetInventorySlotInfo then
		local ok, id = pcall(GetInventorySlotInfo, button.slotName)
		if ok and Num(id) and id > 0 then
			button.slotId = id
			return id
		end
	end
	button.slotId = button.slotFallback
	return button.slotId
end

local function PaintJewelCircle(button, texture, zoom, r, g, b)
	local span = 1 - zoom * 2
	local i
	for i = 1, table.getn(button.strips) do
		local spec = jewelStrips[i]
		local strip = button.strips[i]
		strip:SetTexture(texture)
		strip:SetVertexColor(r, g, b)
		strip:SetTexCoord(
			zoom + (spec.left / JEWEL_SIZE) * span,
			zoom + ((spec.left + spec.width) / JEWEL_SIZE) * span,
			zoom + (spec.top / JEWEL_SIZE) * span,
			zoom + ((spec.top + spec.height) / JEWEL_SIZE) * span
		)
	end
end

UpdateJewelry = function()
	if not On("jewelry") or not GetInventoryItemTexture or not (InRun() or Staging()) then
		if not On("jewelry") then ShowStockBuild() end
		jewelry:Hide()
		return
	end
	if InRun() then
		HideStockBuild()
		if DragonForcesBuild() and not jewelryTold then
			jewelryTold = true
			Say("DragonUI is keeping the ability icons on. In DragonUI, turn on Hide default jewelry / abilities and turn off Equipped jewelry.")
		end
	else
		ShowStockBuild()
	end
	local n
	for n = 1, 5 do
		local button = jewelSlots[n]
		local id = JewelSlotId(button)
		local texture
		if id then
			local ok, path = pcall(GetInventoryItemTexture, "player", id)
			if ok and type(path) == "string" and path ~= "" then texture = path end
		end
		if texture then
			button.filled = true
			PaintJewelCircle(button, texture, 0.08, 1, 1, 1)
			local remain
			if GetInventoryItemCooldown then
				local ok, start, duration, enabled = pcall(GetInventoryItemCooldown, "player", id)
				if ok and Num(start) and Num(duration) and Num(enabled) and enabled > 0 and start > 0 and duration > 1.5 then
					remain = duration - (GetTime() - start)
					if remain < 0 then remain = nil end
				end
			end
			if remain then
				button.cd:SetText(string.format("%.0f", math.ceil(remain)))
			else
				button.cd:SetText("")
			end
		else
			button.filled = nil
			PaintJewelCircle(button, button.emptyTexture, 0, 1, 1, 1)
			button.cd:SetText("")
		end
		button:Show()
	end
	jewelry:Show()
end

end
BuildJewelry()

----------------------------------------------------------------
-- Luck: the same card-chance guide LuckyOdds draws, without its map pins
----------------------------------------------------------------

local function BuildLuck()
	local frame = CreateFrame("Frame", "CoreComfortsLuck", UIParent)
	frame:SetWidth(248)
	frame:SetHeight(112)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 10,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	})
	frame:SetBackdropColor(0.02, 0.015, 0.01, 0.78)
	frame:SetBackdropBorderColor(0.12, 0.09, 0.05, 0.85)
	frame:Hide()

	local function Face(parent, size, r, g, b, justify)
		local text = parent:CreateFontString(nil, "OVERLAY")
		text:SetFont("Fonts\\FRIZQT__.TTF", size, "")
		text:SetShadowColor(0, 0, 0, 1)
		text:SetShadowOffset(1, -1)
		text:SetTextColor(r, g, b)
		text:SetJustifyH(justify or "LEFT")
		return text
	end

	local luckLabel = Face(frame, 12, 1, 0.82, 0)
	luckLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
	luckLabel:SetText("Luck")
	local luckValue = Face(frame, 12, 1, 1, 1)
	luckValue:SetPoint("LEFT", luckLabel, "RIGHT", 6, 0)
	local levelNote = Face(frame, 10, 0.7, 0.7, 0.7, "RIGHT")
	levelNote:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)

	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	rule:SetVertexColor(0.85, 0.7, 0.3, 0.55)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -26)
	rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -26)

	local spellHead = Face(frame, 10, 0.93, 0.78, 0.38, "RIGHT")
	spellHead:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -78, -30)
	spellHead:SetWidth(64)
	spellHead:SetText("Spells")
	local amuletHead = Face(frame, 10, 0.93, 0.78, 0.38, "RIGHT")
	amuletHead:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -30)
	amuletHead:SetWidth(64)
	amuletHead:SetText("Amulets")

	local names = { "Rare", "Epic", "Legendary" }
	local colors = {
		{ 0, 0.44, 0.87 },
		{ 0.64, 0.21, 0.93 },
		{ 1, 0.5, 0 }
	}
	local spellText = {}
	local amuletText = {}
	local row
	for row = 1, 3 do
		local y = -44 - (row - 1) * 14
		local color = colors[row]
		local name = Face(frame, 10, color[1], color[2], color[3])
		name:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, y)
		name:SetText(names[row])
		local spell = Face(frame, 10, color[1], color[2], color[3], "RIGHT")
		spell:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -78, y)
		spell:SetWidth(58)
		local amulet = Face(frame, 10, color[1], color[2], color[3], "RIGHT")
		amulet:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, y)
		amulet:SetWidth(58)
		spellText[row] = spell
		amuletText[row] = amulet
	end

	local note = Face(frame, 10, 0.65, 0.6, 0.45, "CENTER")
	note:SetPoint("BOTTOM", frame, "BOTTOM", 0, 6)
	note:SetWidth(228)
	note:SetText("Rings and trinkets match Spells.")

	local function Odds(k)
		if k < 0 then k = 0 end
		local square = k * k
		local cube = square * k
		local fourth = cube * k
		local rare = 10 * square
		local epic = 4 * cube
		local legend = fourth
		local total = 60 + (25 * k) + rare + epic + legend
		if total <= 0 then return 0, 0, 0 end
		return rare * 100 / total, epic * 100 / total, legend * 100 / total
	end

	local function Pct(n)
		return string.format("%.1f%%", n or 0)
	end

	local function Lift(shown)
		if not AZS_SetOnTopOfScreens then return end
		pcall(AZS_SetOnTopOfScreens, frame, shown and true or false)
	end

	frame.Place = function()
		frame:ClearAllPoints()
		if CoreComfortsDB.luckleft and CoreComfortsDB.lucktop then
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", CoreComfortsDB.luckleft, CoreComfortsDB.lucktop)
		elseif bossList:IsShown() then
			frame:SetPoint("TOPLEFT", bossList, "BOTTOMLEFT", 0, -4)
		else
			frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -220)
		end
	end

	frame:SetScript("OnDragStart", function()
		if Locked() then return end
		this:StartMoving()
	end)
	frame:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		CoreComfortsDB.luckleft = this:GetLeft()
		CoreComfortsDB.lucktop = this:GetTop()
	end)
	frame:SetScript("OnEnter", function()
		if not GameTooltip then return end
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText("Luck", 1, 0.82, 0)
		GameTooltip:AddLine("Spells, rings, and trinkets share the first column.", 1, 1, 1)
		GameTooltip:AddLine("Amulets are figured with more luck.", 1, 1, 1)
		GameTooltip:AddLine("One percent is added for each level, up to 30%.", 1, 1, 1)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)

	local raised = false
	frame.Update = function()
		if not On("luckodds") then
			if frame:IsShown() then
				raised = false
				Lift(false)
				frame:Hide()
			end
			return
		end
		local luck = 0
		local lvl = 0
		if InRun() then
			if type(AZS_STATS) == "table" then
				local n = tonumber(AZS_STATS.luck)
				if n then luck = n end
			end
			if type(AZS_RUN) == "table" and tonumber(AZS_RUN.lvl) then
				lvl = tonumber(AZS_RUN.lvl)
			elseif UnitLevel then
				lvl = UnitLevel("player") or 0
			end
		end
		if lvl < 0 then lvl = 0 end
		local bonus = lvl * 0.01
		if bonus > 0.30 then bonus = 0.30 end
		luckValue:SetText(math.floor(luck * 100 + 0.5) .. "%")
		levelNote:SetText("+" .. math.floor(bonus * 100 + 0.5) .. "% from level")
		local k = 1 + luck + bonus
		local rare, epic, legend = Odds(k)
		local amuletRare, amuletEpic, amuletLegend = Odds(k + 0.5)
		spellText[1]:SetText(Pct(rare))
		spellText[2]:SetText(Pct(epic))
		spellText[3]:SetText(Pct(legend))
		amuletText[1]:SetText(Pct(amuletRare))
		amuletText[2]:SetText(Pct(amuletEpic))
		amuletText[3]:SetText(Pct(amuletLegend))
		local wantLift = InRun() and true or false
		if wantLift ~= raised then
			raised = wantLift
			Lift(raised)
		end
		if frame:IsShown() then return end
		frame.Place()
		frame:Show()
	end

	frame.Place()
end
BuildLuck()

----------------------------------------------------------------
-- Driver
----------------------------------------------------------------

local ToggleOptions
local BuildMinimap
local PlaceMinimap

local driver = CreateFrame("Frame", "CoreComfortsDriver")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("UNIT_HEALTH")
driver:RegisterEvent("UNIT_MAXHEALTH")
driver:RegisterEvent("VARIABLES_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_LOGOUT")
driver:RegisterEvent("UNIT_INVENTORY_CHANGED")
driver:SetScript("OnEvent", function()
	if event == "PLAYER_LOGOUT" then
		ShowStockBuild()
		ShowStockClock()
		ShowStockTally()
		ShowStockBosses()
		return
	end
	if event == "VARIABLES_LOADED" then
		if not CoreComfortsDB.rightside then
			CoreComfortsDB.left = nil
			CoreComfortsDB.top = nil
			CoreComfortsDB.sleft = nil
			CoreComfortsDB.stop = nil
			CoreComfortsDB.rightside = true
		end
		if not CoreComfortsDB.jewelrow then
			CoreComfortsDB.jleft = nil
			CoreComfortsDB.jtop = nil
			CoreComfortsDB.jewelrow = true
		end
		if not CoreComfortsDB.clockcenter then
			CoreComfortsDB.btleft = nil
			CoreComfortsDB.bttop = nil
			CoreComfortsDB.clockcenter = true
		end
		xpWatch.lvl = nil
		RestoreList()
		RestoreCounter()
		RestoreStats()
		RestoreAlive()
		RestoreBossTimers()
		RestoreBossList()
		RestoreBosses()
		PlaceJewelry()
		local luckFrame = getglobal("CoreComfortsLuck")
		if luckFrame and luckFrame.Place then luckFrame.Place() end
		if CoreComfortsDB.hidden then list:Hide() end
		if BuildMinimap then BuildMinimap() end
	elseif event == "PLAYER_LOGIN" then
		if BuildMinimap then BuildMinimap() end
		if not told then
			told = true
			Say("loaded. /cc opens options. The minimap button opens it too.")
		end
	end
	UpdateHealth()
	if event ~= "UNIT_HEALTH" and event ~= "UNIT_MAXHEALTH" then
		UpdatePlayerBars(0, true)
	end
end)
driver:SetScript("OnUpdate", function()
	local dt = arg1 or 0
	listElapsed = listElapsed + dt
	mapElapsed = mapElapsed + dt
	statsElapsed = statsElapsed + dt
	UpdatePlayerBars(dt)
	if listElapsed >= 0.2 then
		local step = listElapsed
		listElapsed = 0
		UpdateCounter()
		UpdateAlive()
		UpdateList()
		UpdateBossTimers()
		UpdateBossList()
		UpdateHealth()
		UpdateDebuffs(step)
		UpdateJewelry()
	end
	if statsElapsed >= 0.5 then
		statsElapsed = 0
		UpdateStats(0.5)
		local luckFrame = getglobal("CoreComfortsLuck")
		if luckFrame and luckFrame.Update then luckFrame.Update() end
	end
	if mapElapsed >= 0.05 then
		mapElapsed = 0
		UpdateMap()
	end
end)

----------------------------------------------------------------
-- Nameplates: guardians and bosses only, while the option is on
----------------------------------------------------------------

local UpdateNameplates
local function SetupNameplates()
	local PLATE_BORDER = "Interface\\Tooltips\\Nameplate-Border"
	local platesActive = false

	local function KeepName(set, unit)
		if type(unit) ~= "table" then return end
		local name = unit.name
		if type(name) == "string" and name ~= "" then set[name] = true end
	end

	local function KeepNames()
		local set = {}
		local bosses = AZS_GetBosses and AZS_GetBosses()
		local i
		local n = Count(bosses)
		for i = 1, n do KeepName(set, bosses[i]) end
		local guardians = AZS_GetGuardians and AZS_GetGuardians()
		n = Count(guardians)
		for i = 1, n do KeepName(set, guardians[i]) end
		if type(AZS_UNITS) == "table" then
			n = Count(AZS_UNITS)
			for i = 1, n do
				local unit = AZS_UNITS[i]
				if type(unit) == "table" and (unit.kind == "boss" or unit.kind == "final" or unit.kind == "guardian") then
					KeepName(set, unit)
				end
			end
		end
		return set
	end

	local function PlateName(plate)
		if not plate or not plate.GetRegions or not plate.GetChildren then return end
		if plate.GetName and plate:GetName() then return end
		local regions = { plate:GetRegions() }
		local count = table.getn(regions)
		if count < 1 then return end
		local hasBorder = false
		local nameText
		local i
		for i = 1, count do
			local region = regions[i]
			if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.GetTexture and region:GetTexture() == PLATE_BORDER then
				hasBorder = true
			end
		end
		if not hasBorder then return end
		local nameRegion = regions[3]
		if nameRegion and nameRegion.GetObjectType and nameRegion:GetObjectType() == "FontString" then
			local value = nameRegion:GetText()
			if type(value) == "string" and value ~= "" and value ~= "??" and not string.find(value, "^%d+$") then
				nameText = value
			end
		end
		if not nameText then
			for i = 1, count do
				local region = regions[i]
				if region and region.GetObjectType and region:GetObjectType() == "FontString" then
					local value = region:GetText()
					if type(value) == "string" and value ~= "" and value ~= "??" and not string.find(value, "^%d+$") then
						nameText = value
						break
					end
				end
			end
		end
		local children = { plate:GetChildren() }
		local bar = false
		for i = 1, table.getn(children) do
			local child = children[i]
			if child and child.GetObjectType and child:GetObjectType() == "StatusBar" then
				bar = true
				break
			end
		end
		if not bar then return end
		return nameText or ""
	end

	local function RestoreNameplates()
		platesActive = false
		if not WorldFrame or not WorldFrame.GetChildren then return end
		local children = { WorldFrame:GetChildren() }
		local i
		for i = 1, table.getn(children) do
			local plate = children[i]
			if plate and plate.ccHidden then
				plate.ccHidden = nil
				if plate.Show then plate:Show() end
			end
		end
	end

	UpdateNameplates = function()
		if not On("nameplates") or not InRun() or not WorldFrame or not WorldFrame.GetChildren then
			if platesActive then RestoreNameplates() end
			return
		end
		local keep = KeepNames()
		local children = { WorldFrame:GetChildren() }
		local i
		for i = 1, table.getn(children) do
			local plate = children[i]
			local name = PlateName(plate)
			if name then
				platesActive = true
				if name ~= "" and keep[name] then
					if plate.ccHidden then
						plate.ccHidden = nil
						plate:Show()
					end
				else
					plate.ccHidden = true
					if plate.IsShown and plate:IsShown() then plate:Hide() end
				end
			end
		end
	end

	local plateDriver = CreateFrame("Frame", "CoreComfortsNameplates")
	local plateElapsed = 0
	plateDriver:SetScript("OnUpdate", function()
		plateElapsed = plateElapsed + (arg1 or 0)
		if plateElapsed < 0.05 then return end
		plateElapsed = 0
		UpdateNameplates()
	end)
end
SetupNameplates()

----------------------------------------------------------------
-- Spell tooltip: show cdmax to the chosen number of decimal places
----------------------------------------------------------------

local function SetupCooldownDecimals()
	local cooldownSlot
	local cooldownFixer

	local function CooldownPlaces()
		local n = Num(CoreComfortsDB.decimals)
		if not n then n = 0 end
		n = math.floor(n + 0.5)
		if n < 0 then n = 0 end
		if n > 4 then n = 4 end
		return n
	end

	local function SpellAtSlot(slot)
		slot = Num(slot)
		if not slot or type(AZS_SPELLS) ~= "table" then return end
		slot = math.floor(slot + 0.5)
		local n = table.getn(AZS_SPELLS)
		if n < 1 then return end
		if slot == 12 then return AZS_SPELLS[n] end
		if slot >= 1 and slot <= n - 1 then return AZS_SPELLS[slot] end
	end

	local function SlotFromTooltip()
		if cooldownSlot then return cooldownSlot end
		if not GameTooltip or not GameTooltip.GetOwner then return end
		local owner = GameTooltip:GetOwner()
		if not owner or not owner.GetID then return end
		return owner:GetID()
	end

	local function CooldownLine(text, formatted)
		if type(text) ~= "string" then return end
		local first = string.find(text, "%d+%.?%d* sec cooldown")
		if not first then return end
		local rest = string.find(text, "sec cooldown", first)
		if not rest then return end
		return string.sub(text, 1, first - 1) .. formatted .. " " .. string.sub(text, rest)
	end

	local function PaintCooldownLine(line, formatted)
		if not line or not line.GetText or not line.SetText then return end
		local nextText = CooldownLine(line:GetText(), formatted)
		if not nextText or nextText == line:GetText() then return end
		line:SetText(nextText)
		return true
	end

	local function FixCooldownTooltip()
		local places = CooldownPlaces()
		if places < 1 then return end
		if not GameTooltip or not GameTooltip.IsShown or not GameTooltip:IsShown() then return end
		local spell = SpellAtSlot(SlotFromTooltip())
		if not spell then return end
		local cd = Num(spell.cdmax)
		if not cd then return end
		local formatted = string.format("%." .. places .. "f", cd)
		local lines = 0
		if GameTooltip.NumLines then lines = GameTooltip:NumLines() or 0 end
		local i
		for i = 1, lines do
			PaintCooldownLine(getglobal("GameTooltipTextLeft" .. i), formatted)
			PaintCooldownLine(getglobal("GameTooltipTextRight" .. i), formatted)
		end
	end

	cooldownFixer = CreateFrame("Frame", "CoreComfortsCooldownFixer")
	cooldownFixer:Hide()
	cooldownFixer:SetScript("OnShow", function() this.wait = 0 end)
	cooldownFixer:SetScript("OnUpdate", function()
		this.wait = (this.wait or 0) + 1
		if this.wait < 2 then return end
		this:Hide()
		FixCooldownTooltip()
	end)

	if GameTooltip and GameTooltip.SetAction then
		local origSetAction = GameTooltip.SetAction
		GameTooltip.SetAction = function(frame, slot)
			if type(frame) == "number" then
				slot = frame
				frame = GameTooltip
			end
			cooldownSlot = slot
			origSetAction(frame, slot)
			if CooldownPlaces() >= 1 then
				cooldownFixer.wait = 0
				cooldownFixer:Show()
			end
		end
		local origOnHide = GameTooltip:GetScript("OnHide")
		GameTooltip:SetScript("OnHide", function()
			cooldownSlot = nil
			cooldownFixer:Hide()
			if origOnHide then origOnHide() end
		end)
	end
end
SetupCooldownDecimals()

local function BuildOptions()
local options = CreateFrame("Frame", "CoreComfortsOptions", UIParent)
options:SetWidth(580)
options:SetHeight(420)
options:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
options:SetFrameStrata("DIALOG")
options:SetMovable(true)
options:EnableMouse(true)
options:RegisterForDrag("LeftButton")
options:SetClampedToScreen(true)
options:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
options:Hide()
options:SetScript("OnDragStart", function() this:StartMoving() end)
options:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
if UISpecialFrames then
	local listed
	local frameIndex
	for frameIndex = 1, table.getn(UISpecialFrames) do
		if UISpecialFrames[frameIndex] == "CoreComfortsOptions" then listed = true end
	end
	if not listed then tinsert(UISpecialFrames, "CoreComfortsOptions") end
end

local optionsTitle = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
optionsTitle:SetPoint("TOP", options, "TOP", 0, -16)
optionsTitle:SetText("Core Comforts")

local optionBoxes = {}
local optionKeys = {
	{ header = "Health numbers", col = 1, tab = 1 },
	{ key = "health", label = "Target health numbers" },
	{ key = "playerhealth", label = "Your health numbers" },
	{ slider = "healthrate", label = "Update speed", min = 0.01, max = 0.50, default = 0.05, step = 0.01, low = "0.01", high = "0.50", tip = "How often your health number refreshes.|0.01 updates on the next frame.|0.50 is twice a second." },
	{ key = "power", label = "Your mana, rage, or energy" },
	{ key = "debuffs", label = "Boss bars and debuffs" },
	{ key = "bosstimer", label = "Boss timer", tip = "Replaces the stock run clock at the top of the screen.|Shows the run clock and next-boss countdown.|A progress bar fills for the full run.|Endless hides the bar and shows only the clock and next boss." },
	{ header = "Minimap icons", col = 1 },
	{ key = "guardpins", label = "Boss icons" },
	{ edit = "pintimer", label = "Boss countdown", min = 0, max = 180, default = 30, tip = "A waiting boss icon shows the seconds left once it is inside this number.|0 hides the countdown.|180 is three minutes." },
	{ key = "cachepins", label = "Cache icons" },
	{ header = "Direction arrows", col = 1 },
	{ key = "guardarrow", label = "Boss arrow", tip = "Points at the closest boss that is still waiting.|A boss already in combat is left off, since it leaves its spawn." },
	{ key = "cachearrow", label = "Cache arrow" },
	{ header = "UI", col = 2, tab = 1 },
	{ key = "counter", label = "Kills, gold, and cache" },
	{ key = "cachecount", label = "Caches you can buy", tip = "Adds (3) after the cache price.|That number is how many caches your gold can pay for right now.|Each one costs more than the last, so 100 gold at 20 buys 3.|While this is off, the bar shows the price only." },
	{ key = "jewelry", label = "Jewelry bar" },
	{ header = "Statistics", col = 2 },
	{ key = "stats", label = "Kill, XP, and gold per minute", tip = "The first number is the last 60 seconds.|Average is the pace for the whole run.|Pauses, level-up picks, and cache picks are left out." },
	{ key = "alive", label = "Alive enemies" },
	{ key = "list", label = "Guardian timers" },
	{ key = "bosslist", label = "Boss list", tip = "Upcoming bosses as countdown bars.|When a boss spawns, its row becomes a health bar instead of vanishing." },
	{ header = "Core Comfort Tooltips", col = 2 },
	{ key = "itemtips", label = "Enable item tooltips", tip = "Tooltip on the item icons beside the boss list.|Turn this off to hide those.|The armory always keeps its tooltips.|Tips in this options window always stay." },
	{ header = "Positions", col = 2 },
	{ key = "locked", label = "Lock positions" },
	{ header = "Experimental", col = 1, tab = 2 },
	{ key = "dotestimate", label = "DoT damage on boss bars", tip = "The orange length is the damage your damage-over-time effects should still deal before they run out.|It comes from each DoT's periodic hits on that boss over the last 6 seconds, crits and haste included.|Talent hits a tick sets off, like Shadowy Weaving, are added to that DoT.|The estimate drops when a tick lands, so the red part holds still between ticks.|A DoT first used this run shows after its first ticks. Later enemies start from what it learned." },
	{ key = "nameplates", label = "Guardian and boss nameplates", tip = "Shows nameplates for guardians and bosses only.|Turn on enemy nameplates in the game options, or no plates are shown.|Other enemies are hidden while this is on.|A normal enemy with the same name as one of them still shows." },
	{ key = "luckodds", label = "Luck and card chances", tip = "Shows your luck and the estimated chance of a Rare, Epic, or Legendary card.|It stays up before a run too, at 0% until the run begins.|Spells, rings, and trinkets share one column. Amulets are higher.|One percent is added for each level, up to 30%.|Drag the panel to move it." },
	{ header = "Cooldown decimals", col = 1 },
	{ slider = "decimals", label = "Decimal places", min = 0, max = 4, default = 0, tip = "Shows a spell's cooldown with more decimal places.|The number is the cooldown the game already reports." }
}

local optionSliders = {}
local optionEdits = {}

local function SliderValue(key, low, high, fallback)
	if key == "healthrate" then return HealthSeconds(CoreComfortsDB[key]) end
	local value = Num(CoreComfortsDB[key])
	if not value then value = fallback end
	value = math.floor(value + 0.5)
	if value < low then value = low end
	if value > high then value = high end
	return value
end

local function SliderCaption(key, value)
	if key == "healthrate" then return HealthPaceText(value) end
	if value < 1 then return "Off" end
	if value == 1 then return "1 place" end
	return value .. " places"
end

local function RefreshOptions()
	local n
	for n = 1, table.getn(optionBoxes) do
		local box = optionBoxes[n]
		local checked = On(box.key)
		if box.key == "locked" then checked = Locked() end
		if checked then box:SetChecked(1) else box:SetChecked(nil) end
	end
	for n = 1, table.getn(optionSliders) do
		local slider = optionSliders[n]
		slider:SetValue(SliderValue(slider.optKey, slider.optMin, slider.optMax, slider.optDefault))
	end
	for n = 1, table.getn(optionEdits) do
		local edit = optionEdits[n]
		edit:SetText(string.format("%.0f", SliderValue(edit.optKey, edit.optMin, edit.optMax, edit.optDefault)))
	end
end

local oi
local boxCount = 0
local optionCols = { 18, 304 }
local optionTab = 1
local tabYs = { { -74, -74 }, { -74, -74 }, { -74, -74 } }
local optionParts = {}
local optionTabButtons = {}
local optionTabShown = 1
local RefreshArmory
local AskArmoryClose
local ArmoryHide

local function NoteOption(frame, tab)
	tinsert(optionParts, { frame = frame, tab = tab })
end

local function HookTip(frame, title, body, anchor)
	if not body or body == "" then return end
	frame.tipTitle = title
	frame.tipAnchor = anchor
	frame.tipLines = {}
	local rest = body
	while rest and rest ~= "" do
		local splitAt = string.find(rest, "|", 1, true)
		if splitAt then
			tinsert(frame.tipLines, string.sub(rest, 1, splitAt - 1))
			rest = string.sub(rest, splitAt + 1)
		else
			tinsert(frame.tipLines, rest)
			rest = nil
		end
	end
	frame:SetScript("OnEnter", function()
		if not GameTooltip then return end
		if this.tipAnchor then
			GameTooltip:SetOwner(this, "ANCHOR_NONE")
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("BOTTOMLEFT", this.tipAnchor, "TOPLEFT", 0, 6)
		else
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		end
		GameTooltip:SetText(this.tipTitle or "", 1, 0.82, 0)
		local n
		for n = 1, table.getn(this.tipLines) do
			GameTooltip:AddLine(this.tipLines[n], 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
end

local function ShowOptionTab(tab)
	optionTabShown = tab
	local n
	for n = 1, table.getn(optionParts) do
		local part = optionParts[n]
		if part.tab == tab then part.frame:Show() else part.frame:Hide() end
	end
	for n = 1, table.getn(optionTabButtons) do
		local button = optionTabButtons[n]
		local label = button:GetFontString()
		if label then
			if n == tab then
				label:SetTextColor(1, 0.82, 0)
			else
				label:SetTextColor(0.55, 0.48, 0.32)
			end
		end
		if button.underline then
			if n == tab then button.underline:Show() else button.underline:Hide() end
		end
	end
	if tab == 3 then
		options:SetWidth(700)
		options:SetHeight(536)
		if RefreshArmory then RefreshArmory() end
	else
		options:SetWidth(580)
		local ys = tabYs[tab]
		local bottom = ys[1]
		if ys[2] < bottom then bottom = ys[2] end
		options:SetHeight(-bottom + 52)
	end
end

local tabNames = { "Options", "Experimental", "Armory" }
local tabIndex
local tabAnchor = nil
for tabIndex = 1, 3 do
	local tabButton = CreateFrame("Button", "CoreComfortsOptTab" .. tabIndex, options)
	tabButton:SetHeight(18)
	if tabAnchor then
		tabButton:SetPoint("LEFT", tabAnchor, "RIGHT", 18, 0)
	else
		tabButton:SetPoint("TOPLEFT", options, "TOPLEFT", 22, -38)
	end
	tabButton:SetText(tabNames[tabIndex])
	tabButton:SetTextFontObject(GameFontNormal)
	local tabText = tabButton:GetFontString()
	if tabText then
		tabText:ClearAllPoints()
		tabText:SetPoint("LEFT", tabButton, "LEFT", 0, 0)
	end
	local textW = tabText and tabText:GetStringWidth() or 0
	if not textW or textW < 24 then textW = 24 end
	tabButton:SetWidth(textW + 2)
	local underline = tabButton:CreateTexture(nil, "OVERLAY")
	underline:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	underline:SetVertexColor(1, 0.82, 0, 0.95)
	underline:SetHeight(2)
	underline:SetPoint("TOPLEFT", tabButton, "BOTTOMLEFT", 0, -1)
	underline:SetPoint("TOPRIGHT", tabButton, "BOTTOMRIGHT", 0, -1)
	underline:Hide()
	tabButton.underline = underline
	tabButton.tabIndex = tabIndex
	tabButton:SetScript("OnClick", function()
		local tab = this.tabIndex
		if tab == optionTabShown then return end
		if AskArmoryClose then
			AskArmoryClose(function() ShowOptionTab(tab) end)
		else
			ShowOptionTab(tab)
		end
	end)
	tabButton:SetScript("OnEnter", function()
		local label = this:GetFontString()
		if label and this.tabIndex ~= optionTabShown then
			label:SetTextColor(1, 0.9, 0.55)
		end
	end)
	tabButton:SetScript("OnLeave", function()
		local label = this:GetFontString()
		if not label then return end
		if this.tabIndex == optionTabShown then
			label:SetTextColor(1, 0.82, 0)
		else
			label:SetTextColor(0.55, 0.48, 0.32)
		end
	end)
	optionTabButtons[tabIndex] = tabButton
	tabAnchor = tabButton
end
local tabRule = options:CreateTexture(nil, "ARTWORK")
tabRule:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
tabRule:SetVertexColor(0.85, 0.7, 0.3, 0.35)
tabRule:SetHeight(1)
tabRule:SetPoint("TOPLEFT", options, "TOPLEFT", 16, -58)
tabRule:SetPoint("TOPRIGHT", options, "TOPRIGHT", -16, -58)

local optionCol = 1
for oi = 1, table.getn(optionKeys) do
	local entry = optionKeys[oi]
	if entry.header then
		if entry.tab then optionTab = entry.tab end
		if entry.col then optionCol = entry.col end
		local ys = tabYs[optionTab]
		local x = optionCols[optionCol]
		local y = ys[optionCol]
		local header = options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		header:SetPoint("TOPLEFT", options, "TOPLEFT", x, y)
		header:SetText(entry.header)
		local line = options:CreateTexture(nil, "ARTWORK")
		line:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
		line:SetVertexColor(0.85, 0.7, 0.3, 0.8)
		line:SetWidth(250)
		line:SetHeight(1)
		line:SetPoint("TOPLEFT", options, "TOPLEFT", x, y - 14)
		ys[optionCol] = y - 22
		NoteOption(header, optionTab)
		NoteOption(line, optionTab)
	elseif entry.slider then
		local ys = tabYs[optionTab]
		local x = optionCols[optionCol]
		local y = ys[optionCol]
		local caption = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		caption:SetPoint("TOPLEFT", options, "TOPLEFT", x + 18, y)
		caption:SetText(entry.label)
		local valueText = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		valueText:SetPoint("TOPRIGHT", options, "TOPLEFT", x + 250, y)
		valueText:SetTextColor(1, 0.82, 0)
		local sliderName = "CoreComfortsHealthRate"
		if entry.slider == "decimals" then sliderName = "CoreComfortsDecimals" end
		local slider = CreateFrame("Slider", sliderName, options)
		slider:SetOrientation("HORIZONTAL")
		slider:SetWidth(190)
		slider:SetHeight(17)
		slider:SetPoint("TOPLEFT", options, "TOPLEFT", x + 28, y - 16)
		slider:SetMinMaxValues(entry.min, entry.max)
		slider.optKey = entry.slider
		slider.optMin = entry.min
		slider.optMax = entry.max
		slider.optDefault = entry.default
		slider.optStep = entry.step or 1
		slider.caption = valueText
		slider:SetValueStep(slider.optStep)
		slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
		local thumb = slider:GetThumbTexture()
		if thumb then
			thumb:SetWidth(32)
			thumb:SetHeight(32)
		end
		local track = slider:CreateTexture(nil, "BACKGROUND")
		track:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
		track:SetHeight(8)
		track:SetPoint("LEFT", slider, "LEFT", 0, 0)
		track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
		local slow = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		slow:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, 2)
		if entry.low then slow:SetText(entry.low)
		elseif entry.slider == "decimals" then slow:SetText("Off")
		else slow:SetText("Slower") end
		slow:SetTextColor(0.7, 0.7, 0.7)
		local fast = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fast:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 4, 2)
		if entry.high then fast:SetText(entry.high)
		elseif entry.slider == "decimals" then fast:SetText("4")
		else fast:SetText("Faster") end
		fast:SetTextColor(0.7, 0.7, 0.7)
		slider:SetScript("OnValueChanged", function()
			local size = this.optStep or 1
			local step = math.floor(this:GetValue() / size + 0.5) * size
			step = math.floor(step * 100 + 0.5) / 100
			if step < this.optMin then step = this.optMin end
			if step > this.optMax then step = this.optMax end
			if math.abs(this:GetValue() - step) > 0.001 then
				this:SetValue(step)
				return
			end
			CoreComfortsDB[this.optKey] = step
			if this.caption then this.caption:SetText(SliderCaption(this.optKey, step)) end
		end)
		slider:EnableMouseWheel(true)
		slider:SetScript("OnMouseWheel", function()
			local step = this:GetValue()
			local size = this.optStep or 1
			if arg1 and arg1 > 0 then step = step + size else step = step - size end
			this:SetValue(step)
		end)
		tinsert(optionSliders, slider)
		slider:SetValue(SliderValue(entry.slider, entry.min, entry.max, entry.default))
		HookTip(slider, entry.label, entry.tip, caption)
		if entry.tip then
			local hit = CreateFrame("Button", nil, options)
			hit:SetPoint("TOPLEFT", options, "TOPLEFT", x + 18, y + 2)
			hit:SetWidth(160)
			hit:SetHeight(16)
			HookTip(hit, entry.label, entry.tip, caption)
			NoteOption(hit, optionTab)
		end
		NoteOption(caption, optionTab)
		NoteOption(valueText, optionTab)
		NoteOption(slider, optionTab)
		NoteOption(slow, optionTab)
		NoteOption(fast, optionTab)
		ys[optionCol] = y - 48
	elseif entry.edit then
		local ys = tabYs[optionTab]
		local x = optionCols[optionCol]
		local y = ys[optionCol]
		local caption = options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		caption:SetPoint("TOPLEFT", options, "TOPLEFT", x + 36, y - 4)
		caption:SetText(entry.label)
		local edit = CreateFrame("EditBox", "CoreComfortsOpt" .. entry.edit, options)
		edit:SetWidth(46)
		edit:SetHeight(20)
		edit:SetPoint("TOPRIGHT", options, "TOPLEFT", x + 250, y + 2)
		edit:SetFontObject(GameFontHighlight)
		edit:SetJustifyH("CENTER")
		edit:SetTextInsets(2, 2, 0, 0)
		edit:SetNumeric(true)
		edit:SetMaxLetters(3)
		edit:SetAutoFocus(false)
		edit:SetTextColor(1, 0.82, 0)
		edit:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 8,
			insets = { left = 2, right = 2, top = 2, bottom = 2 }
		})
		edit:SetBackdropColor(0, 0, 0, 0.55)
		edit:SetBackdropBorderColor(0.62, 0.52, 0.32, 0.9)
		edit.optKey = entry.edit
		edit.optMin = entry.min
		edit.optMax = entry.max
		edit.optDefault = entry.default
		local function ApplyEdit(box, keep)
			local n = tonumber(box:GetText())
			if not n then n = box.optDefault end
			n = math.floor(n + 0.5)
			if n < box.optMin then n = box.optMin end
			if n > box.optMax then n = box.optMax end
			CoreComfortsDB[box.optKey] = n
			box:SetText(string.format("%.0f", n))
			if not keep then box:ClearFocus() end
		end
		edit:SetScript("OnEnterPressed", function() ApplyEdit(this) end)
		edit:SetScript("OnEscapePressed", function()
			this:SetText(string.format("%.0f", SliderValue(this.optKey, this.optMin, this.optMax, this.optDefault)))
			this:ClearFocus()
		end)
		edit:SetScript("OnEditFocusLost", function() ApplyEdit(this, true) end)
		edit:SetScript("OnEditFocusGained", function() this:HighlightText() end)
		edit:EnableMouseWheel(true)
		edit:SetScript("OnMouseWheel", function()
			local n = SliderValue(this.optKey, this.optMin, this.optMax, this.optDefault)
			if arg1 and arg1 > 0 then n = n + 1 else n = n - 1 end
			if n < this.optMin then n = this.optMin end
			if n > this.optMax then n = this.optMax end
			CoreComfortsDB[this.optKey] = n
			this:SetText(string.format("%.0f", n))
		end)
		edit:SetText(string.format("%.0f", SliderValue(entry.edit, entry.min, entry.max, entry.default)))
		tinsert(optionEdits, edit)
		HookTip(edit, entry.label, entry.tip)
		if entry.tip then
			local hit = CreateFrame("Button", nil, options)
			hit:SetPoint("TOPLEFT", options, "TOPLEFT", x + 32, y + 2)
			hit:SetWidth(160)
			hit:SetHeight(20)
			HookTip(hit, entry.label, entry.tip)
			NoteOption(hit, optionTab)
		end
		NoteOption(caption, optionTab)
		NoteOption(edit, optionTab)
		ys[optionCol] = y - 28
	else
		local ys = tabYs[optionTab]
		local x = optionCols[optionCol]
		local y = ys[optionCol]
		boxCount = boxCount + 1
		local box = CreateFrame("CheckButton", "CoreComfortsOpt" .. entry.key, options)
		box:SetWidth(26)
		box:SetHeight(26)
		box:SetPoint("TOPLEFT", options, "TOPLEFT", x + 6, y)
		box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
		box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
		box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
		box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
		box.key = entry.key
		local caption = options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		caption:SetPoint("LEFT", box, "RIGHT", 6, 0)
		caption:SetText(entry.label)
		box:SetScript("OnClick", function()
			local key = this.key
			if key == "locked" then
				if this:GetChecked() then CoreComfortsDB.locked = true else CoreComfortsDB.locked = false end
				return
			end
			if this:GetChecked() then
				CoreComfortsDB[key] = true
				if key == "list" then CoreComfortsDB.hidden = nil end
				if key == "counter" then CoreComfortsDB.stock = nil end
			else
				CoreComfortsDB[key] = false
				if key == "list" then CoreComfortsDB.hidden = true end
				if key == "counter" then CoreComfortsDB.stock = true end
			end
			UpdateCounter()
			UpdateStats(0)
			UpdateAlive()
			UpdateList()
			UpdateBossTimers()
			UpdateBossList()
			UpdateHealth()
			UpdatePlayerBars(0, true)
			UpdateDebuffs()
			UpdateMap()
			UpdateJewelry()
			UpdateNameplates()
			local luckFrame = getglobal("CoreComfortsLuck")
			if luckFrame and luckFrame.Update then luckFrame.Update() end
		end)
		if entry.tip then
			local hit = CreateFrame("Button", nil, options)
			hit:SetPoint("LEFT", box, "RIGHT", 2, 0)
			hit:SetWidth(220)
			hit:SetHeight(22)
			HookTip(hit, entry.label, entry.tip)
			NoteOption(hit, optionTab)
		end
		HookTip(box, entry.label, entry.tip)
		NoteOption(box, optionTab)
		NoteOption(caption, optionTab)
		optionBoxes[boxCount] = box
		ys[optionCol] = y - 28
	end
end

local function BuildArmoryPanel()
	local COLOR = {
		common = { 1, 1, 1 },
		uncommon = { 0.12, 1, 0 },
		rare = { 0, 0.44, 0.87 },
		epic = { 0.64, 0.21, 0.93 },
		pvp = { 0.45, 0.82, 0.28 },
		legendary = { 1, 0.5, 0 }
	}
	local RARITY_NAME = {
		common = "Common",
		uncommon = "Uncommon",
		rare = "Rare",
		epic = "Epic",
		pvp = "PvP",
		legendary = "Legendary"
	}
	local RARITIES = {
		{ key = "common", zones = "Elwynn Forest\nDuskwood" },
		{ key = "uncommon", zones = "Warsong Gulch\nUn'Goro Crater" },
		{ key = "rare", zones = "Arathi Basin\nFeralas" },
		{ key = "epic", zones = "Gurubashi Arena\nScarlet Monastery" },
		{ key = "pvp", zones = "Alterac Valley\nBlackrock Mountain" },
		{ key = "legendary", zones = "Gates of Ahn'Qiraj\nNaxxramas" }
	}
	local SLOTS = {
		{ key = "Head", label = "HEAD" },
		{ key = "Shoulder", label = "SHOULDER" },
		{ key = "Chest", label = "CHEST" },
		{ key = "Waist", label = "WAIST" },
		{ key = "Legs", label = "LEGS" },
		{ key = "Feet", label = "FEET" },
		{ key = "Wrist", label = "WRIST" },
		{ key = "Hands", label = "HANDS" },
		{ key = "Main Hand", label = "MAIN\nHAND" },
		{ key = "Off Hand", label = "OFF\nHAND" }
	}
	local cells = {}
	local headers = {}
	local collect = {}
	local editButton
	local ToggleOwned

	local armoryRoot = CreateFrame("Frame", nil, options)
	armoryRoot:SetPoint("TOPLEFT", options, "TOPLEFT", 16, -64)
	armoryRoot:SetPoint("BOTTOMRIGHT", options, "BOTTOMRIGHT", -14, 40)
	armoryRoot:Hide()
	NoteOption(armoryRoot, 3)

	local classTitle = armoryRoot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	classTitle:SetPoint("TOP", armoryRoot, "TOP", 50, 0)
	classTitle:SetText("Armory")
	local titleRule = armoryRoot:CreateTexture(nil, "ARTWORK")
	titleRule:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	titleRule:SetVertexColor(0.85, 0.7, 0.3, 0.65)
	titleRule:SetHeight(1)
	titleRule:SetPoint("TOPLEFT", armoryRoot, "TOPLEFT", 128, -16)
	titleRule:SetPoint("TOPRIGHT", armoryRoot, "TOPRIGHT", -4, -16)

	local howNote = armoryRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	howNote:SetPoint("BOTTOM", armoryRoot, "BOTTOM", 0, 28)
	howNote:SetWidth(640)
	howNote:SetJustifyH("CENTER")
	howNote:SetText("The addon cannot read your collection. Tick pieces yourself, or a drop marks them, new or already owned.")
	howNote:SetTextColor(0.75, 0.68, 0.45)

	local sourceNote = armoryRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sourceNote:SetPoint("CENTER", armoryRoot, "BOTTOM", 0, 10)
	sourceNote:SetText("Data pulled from https://azerothsurvivors.app/items on 01/11/2026")
	sourceNote:SetTextColor(0.55, 0.48, 0.32)

	local function AddPieces(text, sep, r, g, b)
		if not text or text == "" or not GameTooltip then return end
		local rest = text
		while rest and rest ~= "" do
			local splitAt = string.find(rest, sep, 1, true)
			if splitAt then
				GameTooltip:AddLine(string.sub(rest, 1, splitAt - 1), r, g, b)
				rest = string.sub(rest, splitAt + string.len(sep))
			else
				GameTooltip:AddLine(rest, r, g, b)
				rest = nil
			end
		end
	end

	local function AddStats(text)
		if not text or text == "" or not GameTooltip then return end
		local health = ""
		local effects = ""
		local rest = text
		while rest and rest ~= "" do
			local piece
			local splitAt = string.find(rest, ", ", 1, true)
			if splitAt then
				piece = string.sub(rest, 1, splitAt - 1)
				rest = string.sub(rest, splitAt + 2)
			else
				piece = rest
				rest = nil
			end
			if string.find(piece, "health", 1, true) then
				if health ~= "" then health = health .. ", " end
				health = health .. piece
			else
				if effects ~= "" then effects = effects .. ", " end
				effects = effects .. piece
			end
		end
		if health ~= "" then GameTooltip:AddLine(health, 1, 1, 1) end
		local green = effects
		while green and green ~= "" do
			if string.len(green) <= 48 then
				GameTooltip:AddLine(green, 0, 1, 0)
				green = nil
			else
				local at = string.find(green, ", ", 1, true)
				local last = nil
				while at and at <= 48 do
					last = at
					at = string.find(green, ", ", at + 2, true)
				end
				if not last then last = 48 end
				GameTooltip:AddLine(string.sub(green, 1, last - 1), 0, 1, 0)
				if string.sub(green, last, last + 1) == ", " then
					green = string.sub(green, last + 2)
				else
					green = string.sub(green, last)
				end
			end
		end
	end

	local function AddWrapped(text, r, g, b)
		if not text or text == "" or not GameTooltip then return end
		local rest = text
		while rest and rest ~= "" do
			if string.len(rest) <= 52 then
				GameTooltip:AddLine(rest, r, g, b)
				return
			end
			local at = 52
			while at > 24 and string.sub(rest, at, at) ~= " " do
				at = at - 1
			end
			if string.sub(rest, at, at) ~= " " then at = 52 end
			GameTooltip:AddLine(string.sub(rest, 1, at - 1), r, g, b)
			rest = string.sub(rest, at + 1)
		end
	end

	local function FitTooltip(owner)
		GameTooltip:Show()
		local screen = GetScreenHeight()
		if not screen then return end
		local bottom = GameTooltip:GetBottom()
		if bottom and bottom < 8 then
			local left = GameTooltip:GetLeft()
			if not left then left = 20 end
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, 8)
		end
		local top = GameTooltip:GetTop()
		local height = GameTooltip:GetHeight()
		if top and height and height < screen - 16 and top > screen - 4 then
			local left = GameTooltip:GetLeft()
			if not left then left = 20 end
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, screen - 4)
		end
	end

	local function TintEdges(button, r, g, b, a)
		local n
		for n = 1, 4 do
			button.edges[n]:SetVertexColor(r, g, b, a)
		end
	end

	local function PaintCell(button, filled)
		if filled then
			button:SetBackdropColor(0, 0, 0, 0.94)
			TintEdges(button, 0.72, 0.58, 0.28, 0.95)
		else
			button:SetBackdropColor(0.03, 0.03, 0.03, 0.55)
			TintEdges(button, 0.22, 0.18, 0.12, 0.8)
		end
	end

	local ri
	local si
	for ri = 1, table.getn(RARITIES) do
		local info = RARITIES[ri]
		local color = COLOR[info.key]
		local rowY = -42 - (ri - 1) * 54
		local rarityText = armoryRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		rarityText:SetPoint("TOPLEFT", armoryRoot, "TOPLEFT", 2, rowY + 2)
		rarityText:SetText(RARITY_NAME[info.key])
		rarityText:SetTextColor(color[1], color[2], color[3])
		local zoneText = armoryRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		zoneText:SetPoint("TOPLEFT", rarityText, "BOTTOMLEFT", 0, -1)
		zoneText:SetWidth(122)
		zoneText:SetJustifyH("LEFT")
		zoneText:SetText(info.zones)
		zoneText:SetTextColor(0.55, 0.55, 0.55)
		for si = 1, table.getn(SLOTS) do
			local slotInfo = SLOTS[si]
			local x = 128 + (si - 1) * 54
			if ri == 1 then
				local header = armoryRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				header:SetPoint("TOPLEFT", armoryRoot, "TOPLEFT", x - 2, -18)
				header:SetWidth(52)
				header:SetHeight(22)
				header:SetJustifyH("CENTER")
				header:SetJustifyV("BOTTOM")
				header:SetText(slotInfo.label)
				header:SetTextColor(0.9, 0.78, 0.4)
				headers[slotInfo.key] = header
			end
			local button = CreateFrame("Button", nil, armoryRoot)
			button:SetWidth(48)
			button:SetHeight(48)
			button:SetPoint("TOPLEFT", armoryRoot, "TOPLEFT", x, rowY)
			button:SetBackdrop({
				bgFile = "Interface\\ChatFrame\\ChatFrameBackground"
			})
			local icon = button:CreateTexture(nil, "ARTWORK")
			icon:SetAllPoints(button)
			icon:Hide()
			button.icon = icon
			local function Edge()
				local line = button:CreateTexture(nil, "OVERLAY")
				line:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
				return line
			end
			local top = Edge()
			top:SetHeight(1)
			top:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
			top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
			local bottom = Edge()
			bottom:SetHeight(1)
			bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
			bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
			local left = Edge()
			left:SetWidth(1)
			left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
			left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
			local right = Edge()
			right:SetWidth(1)
			right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
			right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
			button.edges = { top, bottom, left, right }
			local mark = CreateFrame("Frame", nil, button)
			mark:SetWidth(16)
			mark:SetHeight(16)
			mark:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
			mark:SetFrameLevel(button:GetFrameLevel() + 3)
			local markBg = mark:CreateTexture(nil, "BACKGROUND")
			markBg:SetAllPoints(mark)
			markBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
			markBg:SetVertexColor(0, 0, 0, 0.82)
			local function BoxLine()
				local line = mark:CreateTexture(nil, "BORDER")
				line:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
				line:SetVertexColor(0.95, 0.9, 0.7, 1)
				return line
			end
			local boxTop = BoxLine()
			boxTop:SetHeight(1)
			boxTop:SetPoint("TOPLEFT", mark, "TOPLEFT", 0, 0)
			boxTop:SetPoint("TOPRIGHT", mark, "TOPRIGHT", 0, 0)
			local boxBottom = BoxLine()
			boxBottom:SetHeight(1)
			boxBottom:SetPoint("BOTTOMLEFT", mark, "BOTTOMLEFT", 0, 0)
			boxBottom:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 0, 0)
			local boxLeft = BoxLine()
			boxLeft:SetWidth(1)
			boxLeft:SetPoint("TOPLEFT", mark, "TOPLEFT", 0, 0)
			boxLeft:SetPoint("BOTTOMLEFT", mark, "BOTTOMLEFT", 0, 0)
			local boxRight = BoxLine()
			boxRight:SetWidth(1)
			boxRight:SetPoint("TOPRIGHT", mark, "TOPRIGHT", 0, 0)
			boxRight:SetPoint("BOTTOMRIGHT", mark, "BOTTOMRIGHT", 0, 0)
			local tick = mark:CreateTexture(nil, "ARTWORK")
			tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
			tick:SetVertexColor(0.15, 0.95, 0.25)
			tick:SetWidth(16)
			tick:SetHeight(16)
			tick:SetPoint("CENTER", mark, "CENTER", 0, 0)
			tick:Hide()
			mark:Hide()
			button.mark = mark
			button.tick = tick
			PaintCell(button, false)
			button:SetScript("OnClick", function()
				if ToggleOwned then ToggleOwned(this) end
			end)
			button:SetScript("OnEnter", function()
				if not this.item or not GameTooltip then return end
				local item = this.item
				PaintCell(this, true)
				TintEdges(this, 1, 0.86, 0.45, 1)
				local tint = COLOR[item.rarity]
				if not tint then tint = { 1, 1, 1 } end
				local title = item.name
				if item.alt and item.alt ~= "" then title = title .. " / " .. item.alt end
				local cx = this:GetCenter()
				local sx = UIParent:GetCenter()
				if cx and sx and cx > sx then
					GameTooltip:SetOwner(this, "ANCHOR_LEFT")
				else
					GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
				end
				GameTooltip:SetText(title, tint[1], tint[2], tint[3])
				local rarityName = RARITY_NAME[item.rarity]
				if not rarityName then rarityName = item.rarity end
				GameTooltip:AddLine(item.slot .. ", " .. rarityName, 1, 0.82, 0)
				local star
				for star = 0, 5 do
					local line = item["s" .. star]
					if line and line ~= "" then
						GameTooltip:AddLine(star .. " star", 0.85, 0.7, 0.3)
						AddStats(line)
					end
				end
				if item.drop and item.drop ~= "" then
					AddPieces(item.drop, " | ", 0.7, 0.7, 0.7)
				end
				FitTooltip(this)
			end)
			button:SetScript("OnLeave", function()
				PaintCell(this, this.item ~= nil)
				if GameTooltip then GameTooltip:Hide() end
			end)
			cells[info.key .. "|" .. slotInfo.key] = button
		end
	end

	local setButtons = {}
	local setHeader = armoryRoot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	setHeader:SetWidth(52)
	setHeader:SetHeight(22)
	setHeader:SetJustifyH("CENTER")
	setHeader:SetJustifyV("BOTTOM")
	setHeader:SetText("SET")
	setHeader:SetTextColor(0.9, 0.78, 0.4)
	setHeader:Hide()
	for ri = 1, table.getn(RARITIES) do
		local info = RARITIES[ri]
		local button = CreateFrame("Button", nil, armoryRoot)
		button:SetWidth(48)
		button:SetHeight(48)
		button:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground"
		})
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints(button)
		icon:Hide()
		button.icon = icon
		local function Edge()
			local line = button:CreateTexture(nil, "OVERLAY")
			line:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
			return line
		end
		local top = Edge()
		top:SetHeight(1)
		top:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
		top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
		local bottom = Edge()
		bottom:SetHeight(1)
		bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
		bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
		local left = Edge()
		left:SetWidth(1)
		left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
		left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
		local right = Edge()
		right:SetWidth(1)
		right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
		right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
		button.edges = { top, bottom, left, right }
		button.rowIndex = ri
		PaintCell(button, false)
		button:SetScript("OnEnter", function()
			if not this.setBonus or not GameTooltip then return end
			local bonus = this.setBonus
			PaintCell(this, true)
			TintEdges(this, 1, 0.86, 0.45, 1)
			local tint = COLOR[bonus.rarity]
			if not tint then tint = { 1, 1, 1 } end
			local cx = this:GetCenter()
			local sx = UIParent:GetCenter()
			if cx and sx and cx > sx then
				GameTooltip:SetOwner(this, "ANCHOR_LEFT")
			else
				GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			end
			GameTooltip:SetText(bonus.skill, tint[1], tint[2], tint[3])
			local rarityName = RARITY_NAME[bonus.rarity]
			if not rarityName then rarityName = bonus.rarity end
			GameTooltip:AddLine(rarityName .. " set", 1, 0.82, 0)
			GameTooltip:AddLine("4 pieces at 1 star", 0.85, 0.7, 0.3)
			AddStats(bonus.four)
			GameTooltip:AddLine("8 pieces at 3 stars", 0.85, 0.7, 0.3)
			AddWrapped(bonus.eight, 0, 1, 0)
			GameTooltip:AddLine("8 pieces at 5 stars", 0.85, 0.7, 0.3)
			AddWrapped(bonus.five, 0, 1, 0)
			GameTooltip:AddLine("Weapons are not part of the set.", 0.7, 0.7, 0.7)
			FitTooltip(this)
		end)
		button:SetScript("OnLeave", function()
			PaintCell(this, this.setBonus ~= nil)
			if GameTooltip then GameTooltip:Hide() end
		end)
		button:Hide()
		setButtons[info.key] = button
	end

	local function CurrentClass()
		local key = BossClassKey()
		local label
		if key and AZS_ZONE and type(AZS_ZONE) == "table" and AZS_ZONE.class == key and AZS_ZONE.cname and AZS_ZONE.cname ~= "" then
			label = AZS_ZONE.cname
		end
		if (not label or label == "") and UnitClass then
			local unitLabel, token = UnitClass("player")
			if token and key and string.lower(token) == key then label = unitLabel end
		end
		if (not label or label == "") and key and key ~= "" then
			label = string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
		end
		return key, label
	end

	local function PaintOwned(button, owned)
		if not button.mark then return end
		if not button.item then
			button.mark:Hide()
			return
		end
		if collect.editing or owned then
			button.mark:Show()
			if owned then button.tick:Show() else button.tick:Hide() end
		else
			button.mark:Hide()
		end
	end

	RefreshArmory = function()
		local key, label = CurrentClass()
		if collect.editing and key ~= collect.classKey then
			collect.editing = false
			collect.draft = nil
			if editButton then editButton:SetText("Edit collection") end
		end
		collect.classKey = key
		if label and label ~= "" then
			classTitle:SetText(label)
		else
			classTitle:SetText("Armory")
		end
		local gear
		if key and CoreComfortsGear then gear = CoreComfortsGear[key] end
		local n = 0
		if gear then n = table.getn(gear) end
		local row
		local col
		for row = 1, table.getn(RARITIES) do
			for col = 1, table.getn(SLOTS) do
				local button = cells[RARITIES[row].key .. "|" .. SLOTS[col].key]
				button.item = nil
				button.icon:Hide()
				if button.mark then button.mark:Hide() end
				PaintCell(button, false)
				button:Show()
			end
		end
		local i
		for i = 1, n do
			local item = gear[i]
			local button = cells[item.rarity .. "|" .. item.slot]
			if button and item.icon and item.icon ~= "" then
				button.item = item
				button.icon:SetTexture(item.icon)
				button.icon:Show()
				PaintCell(button, true)
				local ownedBag
				if collect.editing and collect.draft then
					ownedBag = collect.draft
				elseif CoreComfortsDB.collection then
					ownedBag = CoreComfortsDB.collection[key]
				end
				local ownedId = item.id and tostring(item.id)
				local owned = ownedBag and ownedId and ownedBag[ownedId] ~= nil
				PaintOwned(button, owned)
			end
		end
		local showOff = (key == "rogue" or key == "shaman")
		local offHeader = headers["Off Hand"]
		if offHeader then
			if showOff then offHeader:Show() else offHeader:Hide() end
		end
		local rarity
		for rarity = 1, table.getn(RARITIES) do
			local offButton = cells[RARITIES[rarity].key .. "|Off Hand"]
			if offButton then
				if showOff then
					offButton:Show()
				else
					offButton.item = nil
					offButton.icon:Hide()
					if offButton.mark then offButton.mark:Hide() end
					offButton:Hide()
				end
			end
		end
		local setX = 614
		if showOff then setX = 668 end
		local classSets
		if key and CoreComfortsSets then classSets = CoreComfortsSets[key] end
		if setHeader then
			if classSets then
				setHeader:ClearAllPoints()
				setHeader:SetPoint("TOPLEFT", armoryRoot, "TOPLEFT", setX - 2, -18)
				setHeader:Show()
			else
				setHeader:Hide()
			end
		end
		for rarity = 1, table.getn(RARITIES) do
			local rarityKey = RARITIES[rarity].key
			local setButton = setButtons[rarityKey]
			local bonus = classSets and classSets[rarityKey]
			if setButton then
				if bonus then
					setButton.setBonus = bonus
					bonus.rarity = rarityKey
					setButton:ClearAllPoints()
					setButton:SetPoint("TOPLEFT", armoryRoot, "TOPLEFT", setX, -42 - (rarity - 1) * 54)
					if bonus.icon and bonus.icon ~= "" then
						setButton.icon:SetTexture(bonus.icon)
						setButton.icon:Show()
					else
						setButton.icon:Hide()
					end
					PaintCell(setButton, true)
					setButton:Show()
				else
					setButton.setBonus = nil
					setButton.icon:Hide()
					setButton:Hide()
				end
			end
		end
		if showOff then
			options:SetWidth(754)
		else
			options:SetWidth(700)
		end
	end

	local function OwnedSame(saved, draft)
		if type(saved) ~= "table" then saved = {} end
		if type(draft) ~= "table" then draft = {} end
		local id, value
		for id, value in pairs(draft) do
			if saved[id] == nil then return false end
		end
		for id, value in pairs(saved) do
			if value ~= nil and draft[id] == nil then return false end
		end
		return true
	end

	local function EditDirty()
		if not collect.editing then return end
		local saved
		if CoreComfortsDB.collection then saved = CoreComfortsDB.collection[collect.classKey] end
		return not OwnedSame(saved, collect.draft)
	end

	local function StopEditing(quiet)
		collect.editing = false
		collect.draft = nil
		if editButton then editButton:SetText("Edit collection") end
		if not quiet and RefreshArmory then RefreshArmory() end
	end

	local function CommitEditing()
		if not collect.classKey then
			StopEditing()
			return
		end
		if type(CoreComfortsDB.collection) ~= "table" then CoreComfortsDB.collection = {} end
		local clean = {}
		local any = false
		local id
		if collect.draft then
			for id in pairs(collect.draft) do
				clean[id] = 0
				any = true
			end
		end
		if any then
			CoreComfortsDB.collection[collect.classKey] = clean
		else
			CoreComfortsDB.collection[collect.classKey] = nil
		end
		StopEditing()
	end

	local function BeginEditing()
		if not collect.classKey or collect.classKey == "" then return end
		local draft = {}
		local saved
		if CoreComfortsDB.collection then saved = CoreComfortsDB.collection[collect.classKey] end
		if type(saved) == "table" then
			local id, value
			for id, value in pairs(saved) do
				if value ~= nil then draft[id] = 0 end
			end
		end
		collect.draft = draft
		collect.editing = true
		editButton:SetText("Confirm")
		if RefreshArmory then RefreshArmory() end
	end

	ToggleOwned = function(button)
		if not collect.editing or not collect.draft then return end
		if not button.item or not button.item.id then return end
		local id = tostring(button.item.id)
		if collect.draft[id] ~= nil then
			collect.draft[id] = nil
			if button.tick then button.tick:Hide() end
		else
			collect.draft[id] = 0
			if button.mark then button.mark:Show() end
			if button.tick then button.tick:Show() end
		end
	end

	local function PanelButton(parent, text, width)
		local button = CreateFrame("Button", nil, parent)
		button:SetWidth(width)
		button:SetHeight(24)
		button:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
		button:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
		button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
		button:SetText(text)
		button:SetTextFontObject(GameFontNormal)
		local normalTex = button:GetNormalTexture()
		local pushedTex = button:GetPushedTexture()
		local highlightTex = button:GetHighlightTexture()
		if normalTex then normalTex:SetTexCoord(0, 0.625, 0, 0.6875) end
		if pushedTex then pushedTex:SetTexCoord(0, 0.625, 0, 0.6875) end
		if highlightTex then highlightTex:SetTexCoord(0, 0.625, 0, 0.6875) end
		local label = button:GetFontString()
		if label then label:SetPoint("CENTER", button, "CENTER", 0, 1) end
		return button
	end

	editButton = PanelButton(options, "Edit collection", 160)
	editButton:SetPoint("BOTTOMLEFT", options, "BOTTOMLEFT", 22, 16)
	editButton:SetScript("OnClick", function()
		if collect.editing then
			CommitEditing()
		else
			BeginEditing()
		end
	end)
	HookTip(editButton, "Edit collection", "Click the items you already own.|A green tick marks an item you have.|Confirm saves that list for this class.|Owned items are kept as 0 star.|A drop marks the piece too, new or already owned.|Closing asks you to save, leave without saving, or cancel.")
	NoteOption(editButton, 3)

	local collectBlocker = CreateFrame("Frame", nil, options)
	collectBlocker:SetAllPoints(options)
	collectBlocker:SetFrameLevel(options:GetFrameLevel() + 20)
	collectBlocker:EnableMouse(true)
	collectBlocker:Hide()
	local prompt = CreateFrame("Frame", nil, collectBlocker)
	prompt:SetWidth(500)
	prompt:SetHeight(112)
	prompt:SetPoint("CENTER", collectBlocker, "CENTER", 0, 24)
	prompt:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 }
	})
	local promptText = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	promptText:SetPoint("TOP", prompt, "TOP", 0, -22)
	promptText:SetText("Save your collection changes?")
	local saveExit = PanelButton(prompt, "Save and exit", 130)
	saveExit:SetPoint("BOTTOMLEFT", prompt, "BOTTOMLEFT", 18, 16)
	local discardExit = PanelButton(prompt, "Exit without saving", 168)
	discardExit:SetPoint("BOTTOM", prompt, "BOTTOM", 0, 16)
	local cancelPrompt = PanelButton(prompt, "Cancel", 90)
	cancelPrompt:SetPoint("BOTTOMRIGHT", prompt, "BOTTOMRIGHT", -18, 16)

	local function FinishPrompt(save)
		local after = collect.after
		collect.after = nil
		if save then
			CommitEditing()
		else
			StopEditing()
			if RefreshArmory then RefreshArmory() end
		end
		collectBlocker:Hide()
		if after then after() end
	end
	local function CancelPrompt()
		collect.after = nil
		collectBlocker:Hide()
	end
	saveExit:SetScript("OnClick", function() FinishPrompt(true) end)
	discardExit:SetScript("OnClick", function() FinishPrompt(false) end)
	cancelPrompt:SetScript("OnClick", function() CancelPrompt() end)

	local allowHide
	local reopen
	local function RunMenu()
		local phase
		if AZS_GetPhase then phase = AZS_GetPhase() end
		return phase == "ready" or phase == "dead" or phase == "victory"
	end
	reopen = CreateFrame("Frame", nil, UIParent)
	reopen:Hide()
	reopen:SetScript("OnUpdate", function()
		this:Hide()
		if allowHide or RunMenu() then return end
		if not collect.editing or not EditDirty() then return end
		options:Show()
		collectBlocker:Show()
	end)
	ArmoryHide = function()
		allowHide = true
		reopen:Hide()
		collectBlocker:Hide()
		if options:IsShown() then options:Hide() else allowHide = nil end
	end
	AskArmoryClose = function(after)
		if not collect.editing or not EditDirty() then
			if collect.editing then StopEditing(true) end
			collectBlocker:Hide()
			reopen:Hide()
			if after then after() end
			return true
		end
		collect.after = after
		collectBlocker:Show()
		return false
	end
	options:SetScript("OnHide", function()
		if allowHide then
			allowHide = nil
			reopen:Hide()
			collectBlocker:Hide()
			return
		end
		if RunMenu() or not collect.editing or not EditDirty() then
			if collect.editing then StopEditing(true) end
			collect.after = nil
			collectBlocker:Hide()
			reopen:Hide()
			return
		end
		collect.after = ArmoryHide
		reopen:Show()
	end)

	local gearNames = {}
	local function GearId(classKey, name)
		if not classKey or not name or name == "" then return end
		local map = gearNames[classKey]
		if not map then
			map = {}
			gearNames[classKey] = map
			local gear = CoreComfortsGear and CoreComfortsGear[classKey]
			if type(gear) == "table" then
				local i
				for i = 1, table.getn(gear) do
					local item = gear[i]
					if type(item) == "table" and item.id then
						local id = tostring(item.id)
						if item.name and item.name ~= "" then map[string.lower(item.name)] = id end
						if item.alt and item.alt ~= "" then map[string.lower(item.alt)] = id end
					end
				end
			end
		end
		return map[string.lower(name)]
	end

	local function LootItemName(text)
		if type(text) ~= "string" then return end
		local markers = {}
		local global = getglobal("LOOT_ITEM_SELF")
		if type(global) == "string" then
			local cut = string.find(global, "%%s", 1, true)
			if cut and cut > 1 then
				local prefix = string.gsub(string.sub(global, 1, cut - 1), "%s+$", "")
				if prefix ~= "" then markers[1] = prefix end
			end
		end
		if markers[1] ~= "You receive loot:" then
			markers[table.getn(markers) + 1] = "You receive loot:"
		end
		local body
		local i
		for i = 1, table.getn(markers) do
			local marker = markers[i]
			local at = string.find(text, marker, 1, true)
			if at then
				local lead = string.sub(text, 1, at - 1)
				lead = string.gsub(lead, "|c%x%x%x%x%x%x%x%x", "")
				lead = string.gsub(lead, "|r", "")
				lead = string.gsub(lead, "%s", "")
				if lead == "" then
					body = string.sub(text, at + string.len(marker))
					break
				end
			end
		end
		if not body then return end
		body = string.gsub(body, "^%s+", "")
		while string.sub(body, 1, 2) == "|r" do
			body = string.gsub(string.sub(body, 3), "^%s+", "")
		end
		local _, _, name = string.find(body, "%[(.-)%]")
		if not name or name == "" then return end
		return name
	end

	local function MarkDropped(name)
		local key = CurrentClass()
		if not key or key == "" then return end
		local id = GearId(key, name)
		if not id then return end
		if type(CoreComfortsDB.collection) ~= "table" then CoreComfortsDB.collection = {} end
		local bag = CoreComfortsDB.collection[key]
		if type(bag) ~= "table" then
			bag = {}
			CoreComfortsDB.collection[key] = bag
		end
		local changed = bag[id] == nil
		bag[id] = 0
		if collect.editing and collect.classKey == key and collect.draft and collect.draft[id] == nil then
			collect.draft[id] = 0
			changed = true
		end
		if changed and optionTabShown == 3 and RefreshArmory then RefreshArmory() end
	end

	local lootWatch = CreateFrame("Frame", nil, UIParent)
	lootWatch:RegisterEvent("CHAT_MSG_LOOT")
	lootWatch:RegisterEvent("CHAT_MSG_SYSTEM")
	lootWatch:RegisterEvent("CHAT_MSG_ADDON")
	lootWatch:SetScript("OnEvent", function()
		if event == "CHAT_MSG_ADDON" then
			if arg1 == "AZSZONE" and optionTabShown == 3 and RefreshArmory then RefreshArmory() end
			return
		end
		local name = LootItemName(arg1)
		if name then MarkDropped(name) end
	end)
end
BuildArmoryPanel()
ShowOptionTab(1)

local close = CreateFrame("Button", "CoreComfortsOptionsClose", options)
close:SetWidth(96)
close:SetHeight(24)
close:SetPoint("BOTTOM", options, "BOTTOM", 0, 16)
close:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
close:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
close:SetText("Close")
close:SetTextFontObject(GameFontNormal)
local normalTex = close:GetNormalTexture()
local pushedTex = close:GetPushedTexture()
local highlightTex = close:GetHighlightTexture()
if normalTex then normalTex:SetTexCoord(0, 0.625, 0, 0.6875) end
if pushedTex then pushedTex:SetTexCoord(0, 0.625, 0, 0.6875) end
if highlightTex then highlightTex:SetTexCoord(0, 0.625, 0, 0.6875) end
local closeText = close:GetFontString()
if closeText then closeText:SetPoint("CENTER", close, "CENTER", 0, 1) end
close:SetScript("OnClick", function()
	if AskArmoryClose then
		AskArmoryClose(ArmoryHide)
	else
		options:Hide()
	end
end)

ToggleOptions = function()
	if options:IsShown() then
		options:Hide()
	else
		RefreshOptions()
		options:Show()
		if optionTabShown == 3 and RefreshArmory then RefreshArmory() end
	end
end
end
BuildOptions()

PlaceMinimap = function()
	local btn = getglobal("CoreComfortsMinimapButton")
	if not btn or not Minimap then return end
	local angle = CoreComfortsDB.mmAngle
	if not Num(angle) then angle = math.pi end
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
end

BuildMinimap = function()
	if not Minimap then return end
	if getglobal("CoreComfortsMinimapButton") then
		PlaceMinimap()
		return
	end
	local btn = CreateFrame("Button", "CoreComfortsMinimapButton", Minimap)
	btn:SetWidth(31)
	btn:SetHeight(31)
	btn:SetFrameStrata("MEDIUM")
	local icon = btn:CreateTexture(nil, "BACKGROUND")
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
	icon:SetTexture(TEX_MINIMAP)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	btn:RegisterForDrag("LeftButton")
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local dragged = false
	btn:SetScript("OnDragStart", function()
		dragged = false
		this:SetScript("OnUpdate", function()
			dragged = true
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local s = UIParent:GetScale()
			CoreComfortsDB.mmAngle = math.atan2(py / s - my, px / s - mx)
			PlaceMinimap()
		end)
	end)
	btn:SetScript("OnDragStop", function()
		this:SetScript("OnUpdate", nil)
	end)
	btn:SetScript("OnClick", function()
		if dragged then
			dragged = false
			return
		end
		ToggleOptions()
	end)
	btn:SetScript("OnEnter", function()
		if not GameTooltip then return end
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText("Core Comforts")
		GameTooltip:AddLine("Left-click: open options", 1, 1, 1)
		GameTooltip:AddLine("Drag: move", 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	PlaceMinimap()
end

SLASH_CORECOMFORTS1 = "/cc"
SLASH_CORECOMFORTS2 = "/core"
SLASH_CORECOMFORTS3 = "/classic"
SlashCmdList["CORECOMFORTS"] = function(msg)
	if msg == "reset" then
		CoreComfortsDB.left = nil
		CoreComfortsDB.top = nil
		CoreComfortsDB.c2left = nil
		CoreComfortsDB.c2top = nil
		CoreComfortsDB.sleft = nil
		CoreComfortsDB.stop = nil
		CoreComfortsDB.aleft = nil
		CoreComfortsDB.atop = nil
		CoreComfortsDB.bleft = nil
		CoreComfortsDB.btop = nil
		CoreComfortsDB.agleft = nil
		CoreComfortsDB.agtop = nil
		CoreComfortsDB.acleft = nil
		CoreComfortsDB.actop = nil
		CoreComfortsDB.btleft = nil
		CoreComfortsDB.bttop = nil
		CoreComfortsDB.blleft = nil
		CoreComfortsDB.bltop = nil
		CoreComfortsDB.jleft = nil
		CoreComfortsDB.jtop = nil
		CoreComfortsDB.luckleft = nil
		CoreComfortsDB.lucktop = nil
		CoreComfortsDB.mmAngle = nil
		PlaceList()
		PlaceCounter()
		PlaceStats()
		PlaceAlive()
		PlaceBossTimers()
		PlaceBossList()
		PlaceBosses()
		PlaceGuide(guides.guardian)
		PlaceGuide(guides.cache)
		PlaceJewelry()
		local luckFrame = getglobal("CoreComfortsLuck")
		if luckFrame and luckFrame.Place then luckFrame.Place() end
		PlaceMinimap()
		Say("positions restored")
	elseif msg == "dotdebug" then
		if DotDebug then DotDebug() end
	else
		ToggleOptions()
	end
end

if not CoreComfortsDB.rightside then
	CoreComfortsDB.left = nil
	CoreComfortsDB.top = nil
	CoreComfortsDB.sleft = nil
	CoreComfortsDB.stop = nil
	CoreComfortsDB.rightside = true
end
if not CoreComfortsDB.jewelrow then
	CoreComfortsDB.jleft = nil
	CoreComfortsDB.jtop = nil
	CoreComfortsDB.jewelrow = true
end
if not CoreComfortsDB.clockcenter then
	CoreComfortsDB.btleft = nil
	CoreComfortsDB.bttop = nil
	CoreComfortsDB.clockcenter = true
end

RestoreList()
RestoreCounter()
RestoreStats()
RestoreAlive()
RestoreBossTimers()
RestoreBossList()
getglobal("CoreComfortsLuck"):Place()
EnsureBosses()
RestoreBosses()
PlaceJewelry()
BuildMinimap()
if CoreComfortsDB.hidden then list:Hide() end
UpdateHealth()
