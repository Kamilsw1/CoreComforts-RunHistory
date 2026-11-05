-- Run History: one saved sheet when the final boss dies (Full run) and one at
-- the real end including endless (Endless). The list defaults to this class,
-- this map, and this difficulty. Kills per minute is the sort. /history toggles
-- the window.

-- One table so the file stays under Lua 5.0's 200 locals.
local CFG = {
	PAGE = 12,
	ROW_H = 24,
	MIN_TIME = 600,
	MARK = 1200,
	MIN_MAX = 16,
	FRAME_W = 880,
	ROMAN = { "I", "II", "III", "IV", "V" },
	CLASS_ORDER = { "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" },
	STAT_KEYS = {
		"crit", "cm", "dmg", "haste", "doth",
		"area", "echo", "cnt", "bp", "luck", "arm", "spd", "lch",
		"hp", "reg", "pick", "heal", "thn", "liv", "dots", "sxp", "sgold",
	},
	CLASS_COLOR = {
		warrior = { 0.78, 0.61, 0.43 },
		paladin = { 0.96, 0.55, 0.73 },
		hunter = { 0.67, 0.83, 0.45 },
		rogue = { 1.00, 0.96, 0.41 },
		priest = { 1.00, 1.00, 1.00 },
		shaman = { 0.00, 0.44, 0.87 },
		mage = { 0.41, 0.80, 0.94 },
		warlock = { 0.58, 0.51, 0.79 },
		druid = { 1.00, 0.49, 0.04 },
	},
	MAPS = {
		{ key = "elwynn", name = "Elwynn Forest" },
		{ key = "duskwood", name = "Duskwood" },
		{ key = "wsg", name = "Warsong Gulch" },
		{ key = "ungoro", name = "Un'Goro Crater" },
		{ key = "ab", name = "Arathi Basin" },
		{ key = "feralas", name = "Feralas" },
		{ key = "arena", name = "Gurubashi Arena" },
		{ key = "sm", name = "Scarlet Monastery" },
		{ key = "av", name = "Alterac Valley" },
		{ key = "brm", name = "Blackrock Mountain" },
		{ key = "aq", name = "Gates of Ahn'Qiraj" },
		{ key = "naxx", name = "Naxxramas" },
	},
}

local TREE_ORDER = {
	priest = { "discipline", "holy", "shadow" },
	warrior = { "arms", "fury", "protection" },
	paladin = { "holy", "protection", "retribution" },
	hunter = { "beast_mastery", "marksmanship", "survival" },
	rogue = { "assassination", "combat", "subtlety" },
	shaman = { "elemental", "enhancement", "restoration" },
	mage = { "arcane", "fire", "frost" },
	warlock = { "affliction", "demonology", "destruction" },
	druid = { "balance", "feral", "restoration" },
}

local TREE_NAME = {
	discipline = "Discipline", holy = "Holy", shadow = "Shadow",
	arms = "Arms", fury = "Fury", protection = "Protection", retribution = "Retribution",
	beast_mastery = "Beast Mastery", marksmanship = "Marksmanship", survival = "Survival",
	assassination = "Assassination", combat = "Combat", subtlety = "Subtlety",
	elemental = "Elemental", enhancement = "Enhancement", restoration = "Restoration",
	arcane = "Arcane", fire = "Fire", frost = "Frost",
	affliction = "Affliction", demonology = "Demonology", destruction = "Destruction",
	balance = "Balance", feral = "Feral",
}

local COLS = {
	{ key = "t", text = "Time", x = 8, w = 50 },
	{ key = "class", text = "Class", x = 60, w = 74 },
	{ key = "map", text = "Map", x = 136, w = 100 },
	{ key = "diff", text = "Diff", x = 240, w = 72 },
	{ key = "kpm", text = "K/min", x = 316, w = 50 },
	{ key = "xpm", text = "XP/min", x = 368, w = 54 },
	{ key = "gpm", text = "G/min", x = 424, w = 50 },
	{ key = "dps", text = "DPS", x = 476, w = 58 },
	{ key = "bosses", text = "Boss", x = 536, w = 40 },
	{ key = "guardians", text = "Guard", x = 578, w = 46 },
	{ key = "elites", text = "Elite", x = 626, w = 46 },
	{ key = "lvl", text = "Lvl", x = 674, w = 32 },
	{ key = "race", text = "Race", x = 708, w = 62 },
}

local ready = false
local told = false
local page = 1
local shown = {}
local anchorCache = nil
local anchorAt = 0

local frame, sub, headers, rows, foot, prevBtn, nextBtn, pageText
local mapBtn, diffBtn, windowBtn, classBtn, diffMenu
local pop, popTitle, popScroll, popChild, popSlider, statBtn
local PlaceDetails
local PlaceWindow
local PaintHeaders
local SavePlace
local popLines = {}
local popBars = {}
local popIcons = {}
local ask, askText
local pendingRec = nil
local liveBtn
local hitCursor = nil
local hitCursorRun = nil
local dropped = {}
local lastOwed = 0

local function Say(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00Run History|r: " .. msg)
	end
end

local function ResetRoundFilters()
	-- Only min length is kept between rounds; the rest follow the new run.
	RunStatsDB.classFilter = nil
	RunStatsDB.mapFilter = nil
	RunStatsDB.diff = nil
	RunStatsDB.full = 1
	RunStatsDB.lastMin = nil
	RunStatsDB.allClasses = nil
	RunStatsDB.allMaps = nil
end

local function InitDB()
	if not RunStatsDB then RunStatsDB = {} end
	if not RunStatsDB.runs then RunStatsDB.runs = {} end
	if not RunStatsDB.sort then RunStatsDB.sort = "kpm" end
	if RunStatsDB.minTime == nil then RunStatsDB.minTime = 0 end
	ResetRoundFilters()
	if RunStatsDB.mmCorner ~= 1 then
		RunStatsDB.mmAngle = -math.pi * 0.75
		RunStatsDB.mmCorner = 1
	end
end

local function Num(v)
	local n = tonumber(v)
	if not n then return 0 end
	return n
end

local function MinMins()
	if not RunStatsDB or RunStatsDB.minTime == nil then return 0 end
	local n = math.floor(Num(RunStatsDB.minTime) / 60)
	if n < 0 then n = 0 end
	if n > CFG.MIN_MAX then n = CFG.MIN_MAX end
	return n
end

local function MinSecs()
	return MinMins() * 60
end

local function MinLabel()
	return "Min " .. tostring(MinMins()) .. "m"
end

local function Flag(v)
	return v == true or v == 1
end

local function Clock(seconds)
	local s = math.floor(Num(seconds))
	if s < 0 then s = 0 end
	local m = math.floor(s / 60)
	s = math.mod(s, 60)
	return string.format("%d:%02d", m, s)
end

local function Rate(n)
	n = Num(n)
	if n >= 100 then return string.format("%.0f", n) end
	return string.format("%.1f", n)
end

local function Pct(n)
	n = Num(n) * 100
	local nearest = math.floor(n + 0.5)
	if math.abs(n - nearest) < 0.05 then
		return string.format("%d%%", nearest)
	end
	return string.format("%.1f%%", n)
end

local function PlusPct(n)
	local text = Pct(n)
	if Num(n) > 0 then return "+" .. text end
	return text
end

local function Count(n)
	n = Num(n)
	local nearest = math.floor(n + 0.5)
	if math.abs(n - nearest) < 0.05 then return string.format("%d", nearest) end
	return string.format("%.1f", n)
end

local function Comma(n)
	local s = string.format("%d", math.floor(Num(n) + 0.5))
	local out = ""
	local i = string.len(s)
	local group = 0
	while i >= 1 do
		if group == 3 then
			out = "," .. out
			group = 0
		end
		out = string.sub(s, i, i) .. out
		group = group + 1
		i = i - 1
	end
	if out == "" then return "0" end
	return out
end

local function Short(n)
	n = Num(n)
	if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
	if n >= 1000 then return string.format("%.1fk", n / 1000) end
	return string.format("%.0f", n)
end

local function Pretty(key)
	if type(key) ~= "string" or key == "" then return "" end
	local s = ""
	local up = true
	local i
	for i = 1, string.len(key) do
		local c = string.sub(key, i, i)
		if c == "_" or c == "-" then
			s = s .. " "
			up = true
		else
			if up then s = s .. string.upper(c) else s = s .. c end
			up = false
		end
	end
	return s
end

local function Each(list, fn)
	if type(list) ~= "table" then return end
	local n = table.getn(list)
	local i
	if n > 0 then
		for i = 1, n do fn(list[i]) end
		return
	end
	for _, row in pairs(list) do fn(row) end
end

local function MeterId()
	if AZS_GetMeterContext then
		local ok, ctx = pcall(AZS_GetMeterContext)
		if ok and type(ctx) == "table" then
			if type(ctx.runId) == "string" and ctx.runId ~= "" then return ctx.runId end
			if type(ctx.runId) == "number" then return tostring(ctx.runId) end
		end
	end
	if type(AZS_ZONE) == "table" then
		if type(AZS_ZONE.run) == "string" and AZS_ZONE.run ~= "" then return AZS_ZONE.run end
		if type(AZS_ZONE.run) == "number" then return tostring(AZS_ZONE.run) end
	end
end

local function NormKey(s)
	if type(s) ~= "string" or s == "" then return "" end
	local out = ""
	local i
	s = string.lower(s)
	for i = 1, string.len(s) do
		local c = string.sub(s, i, i)
		if c == " " or c == "-" then c = "_" end
		out = out .. c
	end
	if out == "beastmastery" or out == "beast_master" then return "beast_mastery" end
	if out == "feral_combat" or out == "feralcombat" then return "feral" end
	return out
end

local function NiceTree(key)
	if TREE_NAME[key] then return TREE_NAME[key] end
	if key == "" then return "?" end
	return string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
end

local function DiffName(h)
	h = math.floor(Num(h))
	if h < 0 then return "Any difficulty" end
	if h == 0 then return "Normal" end
	if h > 5 then h = 5 end
	return "Heroic " .. (CFG.ROMAN[h] or tostring(h))
end

local function DiffLevel(h)
	h = math.floor(Num(h))
	if h < 0 then h = 0 end
	if h > 5 then h = 5 end
	return h
end

-- Seconds until the zone's final boss (Elwynn 960, Naxx 1200, …).
local function ZoneLength(rec)
	if rec and Num(rec.len) > 0 then return Num(rec.len) end
	if AZS_GetRunLength then
		local n = Num(AZS_GetRunLength())
		if n > 0 then return n end
	end
	if type(AZS_ZONE) == "table" and Num(AZS_ZONE.len) > 0 then return Num(AZS_ZONE.len) end
	if type(AZS_RUN) == "table" and Num(AZS_RUN.fin) > 0 then return Num(AZS_RUN.fin) end
	return CFG.MARK
end

local function Phase()
	if AZS_GetPhase then
		local ph = AZS_GetPhase()
		if ph and ph ~= "" then return ph end
	end
	if type(AZS_RUN) == "table" and type(AZS_RUN.ph) == "string" then
		return AZS_RUN.ph
	end
end

local function InRun()
	local ph = Phase()
	if type(ph) ~= "string" or ph == "" then return false end
	ph = string.lower(ph)
	if ph == "ready" then return false end
	return true
end

local function RunTime()
	if AZS_GetRunTime then
		local t = AZS_GetRunTime()
		if t then return Num(t) end
	end
	if type(AZS_RUN) == "table" then return Num(AZS_RUN.t) end
	return 0
end

local fallbackId = nil

local function RunId()
	if not InRun() then
		fallbackId = nil
		return nil
	end
	local id = nil
	if type(AZS_ZONE) == "table" then
		if type(AZS_ZONE.run) == "string" and AZS_ZONE.run ~= "" then
			id = AZS_ZONE.run
		elseif type(AZS_ZONE.run) == "number" then
			id = tostring(AZS_ZONE.run)
		end
	end
	if not id and AZS_GetMeterContext then
		local ok, ctx = pcall(AZS_GetMeterContext)
		if ok and type(ctx) == "table" then
			if type(ctx.runId) == "string" and ctx.runId ~= "" then
				id = ctx.runId
			elseif type(ctx.runId) == "number" then
				id = tostring(ctx.runId)
			end
		end
	end
	if id then
		fallbackId = nil
		return id
	end
	if not fallbackId then
		local now = 0
		if GetTime then now = GetTime() end
		fallbackId = "run:" .. tostring(math.floor(now))
	end
	return fallbackId
end

local function FindRun(id)
	local runs = RunStatsDB.runs
	local i
	for i = 1, table.getn(runs) do
		if runs[i].id == id then return runs[i] end
	end
end

local function HasteOf(cd)
	cd = tonumber(cd)
	if not cd or cd <= 0 then return 0 end
	if cd <= 1 then
		local h = 1 - cd
		if h < 0 then h = 0 end
		return h
	end
	return 0
end

local function CopyList(src, field)
	local out = {}
	if type(src) ~= "table" then return out end
	local i
	for i = 1, table.getn(src) do
		local row = src[i]
		if type(row) == "table" then
			if field == "points" then
				tinsert(out, { key = row.key or "", name = row.name or "", points = Num(row.points), order = Num(row.order) })
			elseif field == "talents" then
				tinsert(out, { tree = row.tree or "", name = row.name or "", rank = Num(row.rank), key = row.key or "" })
			elseif field == "spells" then
				tinsert(out, { key = row.key or "", name = row.name or "", rank = Num(row.rank), icon = row.icon or "" })
			else
				tinsert(out, {
					category = row.category or "", name = row.name or "",
					key = row.key or "", rarity = row.rarity or "", icon = row.icon or "",
				})
			end
		end
	end
	return out
end

local function SpecOf(points)
	local list = {}
	local i
	if type(points) ~= "table" then return "No spec", "" end
	for i = 1, table.getn(points) do
		if Num(points[i].points) > 0 then tinsert(list, points[i]) end
	end
	if table.getn(list) == 0 then return "No spec", "" end
	table.sort(list, function(a, b)
		if Num(a.points) == Num(b.points) then return Num(a.order) < Num(b.order) end
		return Num(a.points) > Num(b.points)
	end)
	local name = list[1].name or NiceTree(list[1].key)
	for i = 2, table.getn(list) do
		name = name .. "/" .. (list[i].name or NiceTree(list[i].key))
	end
	return name, list[1].key or ""
end

local function SplitOf(points)
	if type(points) ~= "table" or table.getn(points) == 0 then return "0" end
	local s = ""
	local i
	for i = 1, table.getn(points) do
		if s ~= "" then s = s .. "/" end
		s = s .. tostring(math.floor(Num(points[i].points)))
	end
	return s
end

local function TreeKeyOf(raw, class)
	local key = NormKey(raw)
	if key == "" then return "" end
	local dot = 0
	local i
	for i = 1, string.len(key) do
		if string.sub(key, i, i) == "." then dot = i end
	end
	if dot > 0 then key = string.sub(key, dot + 1) end
	local order = nil
	if type(class) == "string" then order = TREE_ORDER[class] end
	if order then
		for i = 1, table.getn(order) do
			if key == order[i] then return order[i] end
		end
		for i = 1, table.getn(order) do
			if string.find(key, order[i], 1, true) then return order[i] end
		end
	end
	return key
end

local function ReadTalentFrame(class)
	if not GetNumTalentTabs or not GetTalentTabInfo or not GetNumTalents or not GetTalentInfo then
		return nil
	end
	local tabs = tonumber(GetNumTalentTabs())
	if not tabs or tabs < 1 then return nil end
	local order = nil
	if type(class) == "string" then order = TREE_ORDER[class] end
	local talents = {}
	local points = {}
	local any = false
	local tab
	for tab = 1, tabs do
		local tabName, _, spent = GetTalentTabInfo(tab)
		spent = Num(spent)
		local key = ""
		if order and order[tab] then key = order[tab] end
		if key == "" then key = TreeKeyOf(tabName, class) end
		if key == "" then key = "tree" .. tostring(tab) end
		local nice = NiceTree(key)
		if type(tabName) == "string" and tabName ~= "" then nice = tabName end
		local keep = tab <= 3 or spent > 0
		if keep then
			tinsert(points, { key = key, name = nice, points = spent, order = tab })
			if spent > 0 then any = true end
			local n = tonumber(GetNumTalents(tab)) or 0
			local i
			for i = 1, n do
				local tname, _, _, _, rank = GetTalentInfo(tab, i)
				rank = Num(rank)
				if rank > 0 then
					any = true
					if type(tname) ~= "string" or tname == "" then tname = "Talent" end
					tinsert(talents, { tree = key, name = tname, rank = rank, key = key .. ":" .. tostring(i) })
				end
			end
		end
	end
	if not any then return nil end
	return { points = points, talents = talents }
end

local function SourceName(sources, key)
	if type(sources) ~= "table" or type(key) ~= "string" then return nil end
	local src = sources[key]
	if type(src) == "table" and type(src.name) == "string" and src.name ~= "" then
		return src.name
	end
end

local function SourceIcon(sources, key)
	if type(sources) ~= "table" or type(key) ~= "string" then return "" end
	local src = sources[key]
	if type(src) ~= "table" then return "" end
	local icon = src.icon
	if type(icon) == "string" and icon ~= "" then return icon end
	if type(icon) == "table" and type(icon.path) == "string" and icon.path ~= "" then
		if icon.status == nil or icon.status == "ready" then return icon.path end
	end
	return ""
end

local function SpellBarIcon(key)
	if type(key) ~= "string" or key == "" or type(AZS_SPELLS) ~= "table" or not GetActionTexture then
		return ""
	end
	local total = table.getn(AZS_SPELLS)
	local i
	for i = 1, total do
		local row = AZS_SPELLS[i]
		if type(row) == "table" and row.key == key then
			local slot = i
			if i == total then slot = 12 end
			local ok, path = pcall(GetActionTexture, slot)
			if ok and type(path) == "string" and path ~= "" then return path end
			return ""
		end
	end
	return ""
end

local function RacialKey()
	if type(AZS_SPELLS) ~= "table" then return "" end
	local n = table.getn(AZS_SPELLS)
	if n < 1 then return "" end
	local row = AZS_SPELLS[n]
	if type(row) ~= "table" or type(row.key) ~= "string" then return "" end
	return row.key
end

local function IsRacial(key, name, slotId)
	if Num(slotId) == 12 then return true end
	local racial = RacialKey()
	if racial == "" then return false end
	if type(key) == "string" and key == racial then return true end
	if type(name) == "string" and name ~= "" and name == Pretty(racial) then return true end
	return false
end

local function JewelBase(name)
	if type(name) ~= "string" then return "" end
	local s = name
	local suffixes = { " VIII", " VII", " III", " II", " IX", " IV", " VI", " V", " X" }
	local i
	for i = 1, table.getn(suffixes) do
		local suf = suffixes[i]
		local n = string.len(s)
		local m = string.len(suf)
		if n > m and string.sub(s, n - m + 1, n) == suf then
			return string.sub(s, 1, n - m)
		end
	end
	return s
end

local function ShareJewelIcons(list, extra)
	if type(list) ~= "table" then return end
	local icons = {}
	local function Remember(row)
		if type(row) ~= "table" then return end
		if row.kind == "spell" or row.kind == "talent" then return end
		if type(row.icon) ~= "string" or row.icon == "" then return end
		if type(row.name) ~= "string" or row.name == "" then return end
		icons[row.name] = row.icon
		local base = JewelBase(row.name)
		if base ~= "" then icons[base] = row.icon end
	end
	local i
	for i = 1, table.getn(list) do
		Remember(list[i])
	end
	if type(extra) == "table" then
		for i = 1, table.getn(extra) do
			Remember(extra[i])
		end
	end
	for i = 1, table.getn(list) do
		local row = list[i]
		if type(row) == "table" and row.kind ~= "spell" and row.kind ~= "talent" then
			if (type(row.icon) ~= "string" or row.icon == "") and type(row.name) == "string" then
				local icon = icons[row.name]
				if not icon or icon == "" then icon = icons[JewelBase(row.name)] end
				if icon and icon ~= "" then row.icon = icon end
			end
		end
	end
end

local ReadWorn

local function ReadBuild(id, class)
	if type(class) ~= "string" or class == "" then
		if type(AZS_ZONE) == "table" and type(AZS_ZONE.class) == "string" then
			class = AZS_ZONE.class
		else
			class = ""
		end
	end
	local mid = MeterId()
	if not mid then mid = id end
	if type(mid) ~= "string" or mid == "" or not AZS_GetMeterLoadout then
		mid = nil
	elseif string.sub(mid, 1, 4) == "run:" then
		mid = nil
	end
	local sources = nil
	local talents = {}
	local spells = {}
	local jewelry = {}
	if mid then
		local ok, loadout = pcall(AZS_GetMeterLoadout, { apiVersion = 1, runId = mid })
		if ok and type(loadout) == "table" then
			sources = loadout.sources
			Each(loadout.talents, function(row)
				if type(row) == "table" then
					local rank = Num(row.rank)
					if rank > 0 then
						local key = TreeKeyOf(row.treeKey, class)
						if key == "" then key = TreeKeyOf(row.sourceKey, class) end
						local name = SourceName(sources, row.sourceKey) or Pretty(key)
						if name == "" then name = "?" end
						tinsert(talents, {
							tree = key,
							name = name,
							rank = rank,
							key = type(row.sourceKey) == "string" and row.sourceKey or "",
						})
					end
				end
			end)
			Each(loadout.abilities, function(row)
				if type(row) == "table" then
					local rank = Num(row.rank)
					local learned = Flag(row.learned) or Flag(row.selected) or rank > 0
					if learned and rank > 0 then
						local src = nil
						if type(sources) == "table" and type(row.sourceKey) == "string" then
							src = sources[row.sourceKey]
						end
						local name = SourceName(sources, row.sourceKey) or "?"
						local key = ""
						if type(src) == "table" and type(src.abilityKey) == "string" then key = src.abilityKey end
						local icon = SourceIcon(sources, row.sourceKey)
						if icon == "" then icon = SpellBarIcon(key) end
						if not IsRacial(key, name, row.slotId) then
							tinsert(spells, { key = key, name = name, rank = rank, icon = icon })
						end
					end
				end
			end)
			Each(loadout.runJewelry, function(row)
				if type(row) == "table" then
					local name = SourceName(sources, row.sourceKey) or ""
					local cat = type(row.category) == "string" and row.category or ""
					if name == "" and type(row.sourceKey) == "string" then
						local _, _, kind, body = string.find(row.sourceKey, "^(%a+):([^:]+)")
						if type(body) == "string" and body ~= "" then name = Pretty(body) end
						if cat == "" and kind == "amulet" then cat = "amulet" end
						if cat == "" and (kind == "jewel" or kind == "ring") then cat = "ring" end
						if cat == "" and kind == "trinket" then cat = "trinket" end
						if name == "" then name = row.sourceKey end
					end
					tinsert(jewelry, {
						category = cat,
						name = name,
						key = type(row.sourceKey) == "string" and row.sourceKey or "",
						rarity = "",
						icon = SourceIcon(sources, row.sourceKey),
					})
				end
			end)
		end
	end
	local frameBuild = ReadTalentFrame(class)
	local points = {}
	local armory = nil
	if frameBuild then
		points = frameBuild.points
		armory = 1
		if table.getn(frameBuild.talents) > 0 then talents = frameBuild.talents end
	end
	local worn = ReadWorn()
	local w
	for w = 1, table.getn(worn) do
		local piece = worn[w]
		local have = false
		local j
		for j = 1, table.getn(jewelry) do
			if jewelry[j].name == piece.name then
				have = true
				if (type(jewelry[j].icon) ~= "string" or jewelry[j].icon == "") and type(piece.icon) == "string" then
					jewelry[j].icon = piece.icon
				end
			end
		end
		if not have then tinsert(jewelry, piece) end
	end
	ShareJewelIcons(jewelry)
	return {
		points = points or {},
		armory = armory,
		talents = talents,
		spells = spells,
		jewelry = jewelry,
		jewelsRead = 1,
	}
end

ReadWorn = function()
	local out = {}
	if not GetInventoryItemLink then return out end
	local slots = {
		{ slot = 2, category = "amulet" },
		{ slot = 11, category = "ring" },
		{ slot = 12, category = "ring" },
		{ slot = 13, category = "trinket" },
		{ slot = 14, category = "trinket" },
	}
	local names = {
		[0] = "Poor", [1] = "Common", [2] = "Uncommon",
		[3] = "Rare", [4] = "Epic", [5] = "Legendary", [6] = "Artifact",
	}
	local i
	for i = 1, table.getn(slots) do
		local spec = slots[i]
		local link = GetInventoryItemLink("player", spec.slot)
		local name = nil
		if type(link) == "string" then
			local _, _, found = string.find(link, "%[(.-)%]")
			if type(found) == "string" and found ~= "" then name = found end
		end
		if name then
			local rarity = ""
			if GetInventoryItemQuality then
				local q = GetInventoryItemQuality("player", spec.slot)
				if names[q] then rarity = names[q] end
			end
			local icon = ""
			if GetInventoryItemTexture then
				local ok, path = pcall(GetInventoryItemTexture, "player", spec.slot)
				if ok and type(path) == "string" then icon = path end
			end
			tinsert(out, {
				category = spec.category,
				name = name,
				key = spec.category .. tostring(spec.slot) .. ":" .. name,
				rarity = rarity,
				icon = icon,
			})
		end
	end
	return out
end

local function StatsOf()
	local s = {}
	if type(AZS_STATS) == "table" then s = AZS_STATS end
	return {
		crit = Num(s.crit),
		cm = Num(s.cm),
		dmg = Num(s.dmg),
		haste = HasteOf(s.cd),
		doth = Num(s.doth),
		area = Num(s.area),
		echo = Num(s.echo),
		cnt = Num(s.cnt),
		bp = Num(s.bp),
		luck = Num(s.luck),
		arm = Num(s.arm),
		spd = Num(s.spd),
		lch = Num(s.lch),
		hp = Num(s.hp),
		reg = Num(s.reg),
		pick = Num(s.pick),
		heal = Num(s.heal),
		thn = Num(s.thn),
		liv = Num(s.liv),
		dots = Num(s.dots),
		sxp = Num(s.xp),
		sgold = Num(s.gold),
	}
end

local function WriteStats(dst, src)
	local i
	for i = 1, table.getn(CFG.STAT_KEYS) do
		local key = CFG.STAT_KEYS[i]
		dst[key] = Num(src[key])
	end
end

local function DamageOf()
	if type(AZS_RUN) == "table" then return Num(AZS_RUN.dealt) end
	return 0
end

local function MakeSheet(rec, id, t)
	local stats = StatsOf()
	local build = ReadBuild(id, rec.class)
	local looked = type(build) == "table" and build.jewelsRead == 1
	local useful = false
	if type(build) == "table" then
		if table.getn(build.talents) > 0 or table.getn(build.spells) > 0 or table.getn(build.jewelry) > 0 then
			useful = true
		end
		if not useful and type(build.points) == "table" then
			local i
			for i = 1, table.getn(build.points) do
				if Num(build.points[i].points) > 0 then useful = true end
			end
		end
	end
	if useful then
		rec.cache = build
	else
		build = rec.cache
	end
	local points, talents, spells, jewelry = {}, {}, {}, {}
	if type(build) == "table" then
		points = CopyList(build.points, "points")
		talents = CopyList(build.talents, "talents")
		spells = CopyList(build.spells, "spells")
		jewelry = CopyList(build.jewelry, "jewelry")
	end
	local kills, gold, lvl = 0, 0, 0
	local bosses, guardians, elites = 0, 0, 0
	local takenTotal, chests = 0, 0
	if type(AZS_RUN) == "table" then
		kills = Num(AZS_RUN.kills)
		gold = Num(AZS_RUN.ge)
		lvl = Num(AZS_RUN.lvl)
		bosses = Num(AZS_RUN.bk)
		guardians = Num(AZS_RUN.gk)
		elites = Num(AZS_RUN.ek)
		takenTotal = Num(AZS_RUN.taken)
		chests = Num(AZS_RUN.ck)
	end
	if type(rec.pending) == "table" then
		if kills <= 0 then kills = Num(rec.pending.kills) end
		if gold <= 0 then gold = Num(rec.pending.gold) end
		if lvl <= 0 then lvl = Num(rec.pending.lvl) end
		if bosses <= 0 then bosses = Num(rec.pending.bosses) end
		if guardians <= 0 then guardians = Num(rec.pending.guardians) end
		if elites <= 0 then elites = Num(rec.pending.elites) end
		if takenTotal <= 0 then takenTotal = Num(rec.pending.takenTotal) end
		if chests <= 0 then chests = Num(rec.pending.chests) end
	end
	if table.getn(spells) == 0 and type(rec.seenSpells) == "table" then
		local key, rank
		for key, rank in pairs(rec.seenSpells) do
			local name = Pretty(key)
			if type(rec.picks) == "table" then
				local i
				for i = 1, table.getn(rec.picks) do
					local pick = rec.picks[i]
					if type(pick) == "table" and pick.key == key and type(pick.name) == "string" and pick.name ~= "" then
						name = pick.name
					end
				end
			end
			if not IsRacial(key, name) then
				tinsert(spells, { key = key, name = name, rank = Num(rank), icon = "" })
			end
		end
	end
	local sheet = {
		t = Num(t),
		fight = Num(rec.fight),
		kills = kills,
		gold = gold,
		xp = Num(rec.xp),
		damage = DamageOf(),
		lvl = lvl,
		bosses = bosses,
		guardians = guardians,
		elites = elites,
		takenTotal = takenTotal,
		chests = chests,
		points = points,
		armory = (type(build) == "table" and build.armory == 1) and 1 or nil,
		talents = talents,
		spells = spells,
		jewelry = jewelry,
		picks = {},
		meter = {},
		jewelsRead = looked and 1 or nil,
		bestHit = Num(rec.bestHit),
		bestName = rec.bestName or "",
	}
	if type(rec.picks) == "table" then
		local i
		for i = 1, table.getn(rec.picks) do
			local row = rec.picks[i]
			if type(row) == "table" then
				tinsert(sheet.picks, {
					t = Num(row.t), kind = row.kind or "", name = row.name or "",
					rank = Num(row.rank), key = row.key or "", rarity = row.rarity or "",
					icon = row.icon or "",
				})
			end
		end
	end
	ShareJewelIcons(sheet.picks, jewelry)
	if Num(sheet.damage) <= 0 and type(rec.pending) == "table" then
		sheet.damage = Num(rec.pending.damage)
	end
	WriteStats(sheet, stats)
	if type(rec.pending) == "table" then
		local i
		for i = 1, table.getn(CFG.STAT_KEYS) do
			local key = CFG.STAT_KEYS[i]
			if Num(sheet[key]) == 0 and Num(rec.pending[key]) ~= 0 then
				sheet[key] = Num(rec.pending[key])
			end
		end
	end
	return sheet
end

local function FillIdentity(rec)
	if type(AZS_ZONE) == "table" then
	if type(AZS_ZONE.class) == "string" and AZS_ZONE.class ~= "" then rec.class = AZS_ZONE.class end
	if type(AZS_ZONE.cname) == "string" and AZS_ZONE.cname ~= "" then rec.cname = AZS_ZONE.cname end
	if type(AZS_ZONE.zone) == "string" and AZS_ZONE.zone ~= "" then rec.zone = AZS_ZONE.zone end
	if type(AZS_ZONE.zname) == "string" and AZS_ZONE.zname ~= "" then rec.zname = AZS_ZONE.zname end
	if type(AZS_ZONE.hero) == "string" and AZS_ZONE.hero ~= "" then rec.hero = AZS_ZONE.hero end
	if type(AZS_ZONE.race) == "string" and AZS_ZONE.race ~= "" then rec.race = AZS_ZONE.race end
	if type(AZS_ZONE.rname) == "string" and AZS_ZONE.rname ~= "" then rec.rname = AZS_ZONE.rname end
	if type(AZS_ZONE.affixes) == "string" then rec.affixes = AZS_ZONE.affixes end
	if AZS_ZONE.heroic ~= nil then rec.heroic = math.floor(Num(AZS_ZONE.heroic)) end
	if Num(AZS_ZONE.len) > 0 then rec.len = Num(AZS_ZONE.len) end
	end
	if (not rec.len or Num(rec.len) <= 0) and AZS_GetRunLength then
		local n = Num(AZS_GetRunLength())
		if n > 0 then rec.len = n end
	end
	if (not rec.len or Num(rec.len) <= 0) and type(AZS_RUN) == "table" and Num(AZS_RUN.fin) > 0 then
		rec.len = Num(AZS_RUN.fin)
	end
	if (not rec.class or rec.class == "") and UnitClass then
		local name = UnitClass("player")
		if type(name) == "string" and name ~= "" then
			rec.class = string.lower(name)
			if not rec.cname or rec.cname == "" then rec.cname = name end
		end
	end
	if (not rec.zname or rec.zname == "") and GetRealZoneText then
		local z = GetRealZoneText()
		if type(z) == "string" and z ~= "" then
			rec.zname = z
			if not rec.zone or rec.zone == "" then rec.zone = string.lower(z) end
		end
	end
	if (not rec.rname or rec.rname == "") and UnitRace then
		local name = UnitRace("player")
		if type(name) == "string" and name ~= "" then rec.rname = name end
	end
end

local function NoteParty(rec)
	if rec.party == 1 or not AZS_GetMeterContext then return end
	local ok, ctx = pcall(AZS_GetMeterContext)
	if ok and type(ctx) == "table" and type(ctx.partyState) == "string" and ctx.partyState ~= "solo" then
		rec.party = 1
	end
end

local function TrackXp(rec)
	if type(AZS_RUN) ~= "table" then return end
	local lvl = tonumber(AZS_RUN.lvl)
	local xp = tonumber(AZS_RUN.xp)
	local xpn = tonumber(AZS_RUN.xpn)
	if not lvl or not xp then return end
	if not rec.trackLvl then
		rec.trackLvl = lvl
		rec.trackXp = xp
		rec.trackXpn = xpn
		return
	end
	if lvl == rec.trackLvl then
		if xp > Num(rec.trackXp) then
			rec.xp = Num(rec.xp) + (xp - Num(rec.trackXp))
		end
	elseif lvl > rec.trackLvl then
		local add = 0
		if rec.trackXpn and Num(rec.trackXpn) > Num(rec.trackXp) then
			add = Num(rec.trackXpn) - Num(rec.trackXp)
		end
		rec.xp = Num(rec.xp) + add + xp
	end
	rec.trackLvl = lvl
	rec.trackXp = xp
	rec.trackXpn = xpn
end

local function StartRun(id)
	local rec = {
		id = id,
		open = 1,
		xp = 0,
		party = 0,
		heroic = 0,
		affixes = "",
		len = 0,
	}
	tinsert(RunStatsDB.runs, rec)
	FillIdentity(rec)
	return rec
end

local function BlankSheet(t, xp)
	local sheet = {
		t = Num(t), kills = 0, gold = 0, xp = Num(xp), damage = 0, lvl = 0,
		bosses = 0, guardians = 0, elites = 0,
		points = {}, talents = {}, spells = {}, jewelry = {}, picks = {}, meter = {},
	}
	WriteStats(sheet, {})
	return sheet
end

local function AttachCache(sheet, rec)
	if type(rec.cache) ~= "table" then return end
	if table.getn(sheet.talents) == 0 then
		sheet.points = CopyList(rec.cache.points, "points")
		sheet.talents = CopyList(rec.cache.talents, "talents")
		sheet.spells = CopyList(rec.cache.spells, "spells")
		sheet.jewelry = CopyList(rec.cache.jewelry, "jewelry")
	end
end

local function Remember(rec, t)
	local stats = StatsOf()
	local kills, gold, lvl = 0, 0, 0
	local dealt, bosses, guardians, elites = 0, 0, 0, 0
	local takenTotal, chests = 0, 0
	if type(AZS_RUN) == "table" then
		kills = Num(AZS_RUN.kills)
		gold = Num(AZS_RUN.ge)
		lvl = Num(AZS_RUN.lvl)
		dealt = Num(AZS_RUN.dealt)
		bosses = Num(AZS_RUN.bk)
		guardians = Num(AZS_RUN.gk)
		elites = Num(AZS_RUN.ek)
		takenTotal = Num(AZS_RUN.taken)
		chests = Num(AZS_RUN.ck)
	end
	rec.liveT = Num(t)
	rec.pending = {
		t = Num(t), kills = kills, gold = gold, xp = Num(rec.xp),
		damage = dealt, lvl = lvl,
		bosses = bosses, guardians = guardians, elites = elites,
		takenTotal = takenTotal, chests = chests,
		taken = {},
	}
	if type(AZS_TAKEN) == "table" then
		local i
		for i = 1, table.getn(AZS_TAKEN) do
			local row = AZS_TAKEN[i]
			if type(row) == "table" and Num(row.dmg) > 0 then
				tinsert(rec.pending.taken, { source = row.source or "?", dmg = Num(row.dmg) })
			end
		end
	end
	WriteStats(rec.pending, stats)
end

local function NotePace(rec, t)
	t = Num(t)
	if not rec or t <= 0 then return end
	local frozen = false
	local ph = Phase()
	if ph == "paused" or ph == "choosing" then frozen = true end
	if rec.fightClock == nil then
		rec.fightClock = t
		if rec.fight == nil then rec.fight = t end
	else
		local delta = t - Num(rec.fightClock)
		if delta < -1 then
			rec.fight = t
			rec.pace = {}
			rec.fightClock = t
		else
			if delta > 0 and not frozen then rec.fight = Num(rec.fight) + delta end
			if delta > 0 then rec.fightClock = t end
		end
	end
	if type(rec.pending) == "table" then rec.pending.fight = Num(rec.fight) end
	local kills, gold, dealt, taken = 0, 0, 0, 0
	if type(AZS_RUN) == "table" then
		kills = Num(AZS_RUN.kills)
		gold = Num(AZS_RUN.ge)
		dealt = Num(AZS_RUN.dealt)
		taken = Num(AZS_RUN.taken)
	end
	local takenRows = {}
	if type(AZS_TAKEN) == "table" then
		Each(AZS_TAKEN, function(row)
			if type(row) == "table" and Num(row.dmg) > 0 then
				tinsert(takenRows, { source = row.source or "?", dmg = Num(row.dmg) })
			end
		end)
	end
	if type(rec.pace) ~= "table" then rec.pace = {} end
	local pace = rec.pace
	local n = table.getn(pace)
	local last = pace[n]
	local fight = Num(rec.fight)
	if type(last) == "table" and (frozen or t - Num(last.t) < 1) then
		last.t = t
		last.fight = fight
		last.kills = kills
		last.xp = Num(rec.xp)
		last.gold = gold
		last.damage = dealt
		last.taken = taken
		last.takenRows = takenRows
		return
	end
	tinsert(pace, { t = t, fight = fight, kills = kills, xp = Num(rec.xp), gold = gold, damage = dealt, taken = taken, takenRows = takenRows })
	n = table.getn(pace)
	while n > 1 and fight - Num(pace[1].fight) > 90 do
		table.remove(pace, 1)
		n = n - 1
	end
end

local function NoteMeter(rec, t)
	t = Num(t)
	if not rec or t <= 0 or not AZS_GetMeter then return end
	if rec.meterTry and t - Num(rec.meterTry) < 15 then return end
	rec.meterTry = t
	local ok, lines = pcall(AZS_GetMeter)
	if not ok or type(lines) ~= "table" then return end
	local rows = {}
	local i
	for i = 1, table.getn(lines) do
		local row = lines[i]
		if type(row) == "table" and Num(row.dmg) > 0 then
			local proc = 0
			if row.proc == 1 or row.proc == true then proc = 1 end
			tinsert(rows, { name = row.name or "?", dmg = Num(row.dmg), proc = proc })
		end
	end
	if type(rec.meterPace) ~= "table" then rec.meterPace = {} end
	tinsert(rec.meterPace, { t = t, rows = rows })
	local n = table.getn(rec.meterPace)
	while n > 1 and t - Num(rec.meterPace[1].t) > 90 do
		table.remove(rec.meterPace, 1)
		n = n - 1
	end
end

local rateCache = {}

local function MeterRate(rec, window)
	if not rec or not AZS_GetMeterContext or not AZS_GetMeterSnapshot then return nil end
	local now = GetTime()
	local hit = rateCache[window]
	if hit and hit.id == rec.id and now - hit.at < 0.9 then return hit.value, hit.amount end
	local ok, ctx = pcall(AZS_GetMeterContext)
	if not ok or type(ctx) ~= "table" or ctx.runId == nil or tostring(ctx.runId) ~= rec.id then return nil end
	local ok2, snap = pcall(AZS_GetMeterSnapshot, {
		apiVersion = 1, runId = ctx.runId, metric = "damage", scope = "self",
		period = "run", groupBy = "owner", windowSeconds = window,
	})
	if not ok2 or type(snap) ~= "table" or type(snap.totals) ~= "table" then return nil end
	local rate = snap.totals.recentRate
	if type(rate) ~= "table" or rate.status ~= "ready" or not tonumber(rate.value) then return nil end
	if not hit then
		hit = {}
		rateCache[window] = hit
	end
	hit.id = rec.id
	hit.at = now
	hit.value = Num(rate.value)
	hit.amount = Num(rate.amount)
	return hit.value, hit.amount
end

local ApplyPaceMinute

local function ApplyLastMinute(sheet, rec)
	ApplyPaceMinute(sheet, rec)
	if type(sheet) ~= "table" then return end
	local dps, amount = MeterRate(rec, 60)
	if dps then
		sheet.ld = dps
		sheet.ldmg = amount
	end
end

local function ApplyLast10(sheet, rec)
	if type(sheet) ~= "table" then return end
	local dps = MeterRate(rec, 10)
	if dps then sheet.l10 = dps end
end

ApplyPaceMinute = function(sheet, rec)
	if type(sheet) ~= "table" or not rec then return end
	local now = Num(sheet.t)
	local useFight = false
	if now < 1 then return end
	local base = nil
	if now <= 60 then
		base = { t = 0, fight = 0, kills = 0, xp = 0, gold = 0, damage = 0, taken = 0 }
	else
		local pace = rec.pace
		if type(pace) ~= "table" then return end
		local want = now - 60
		local best = nil
		local bestDist = 9999
		local i
		for i = 1, table.getn(pace) do
			local row = pace[i]
			if type(row) == "table" then
				local mark = useFight and Num(row.fight) or Num(row.t)
				if useFight and row.fight == nil then mark = -9999 end
				if mark > -1 and math.abs(mark - want) < bestDist then
					best = row
					bestDist = math.abs(mark - want)
				end
			end
		end
		if type(best) ~= "table" or bestDist > 20 then return end
		base = best
	end
	if type(base) ~= "table" then return end
	local baseAt = useFight and Num(base.fight) or Num(base.t)
	local span = now - baseAt
	if now > 60 and (span < 45 or span > 75) then return end
	if span < 1 then span = 1 end
	local minutes = span / 60
	local function Delta(now, was)
		local d = Num(now) - Num(was)
		if d < 0 then d = 0 end
		return d
	end
	sheet.pace = 1
	sheet.lk = Delta(sheet.kills, base.kills) / minutes
	sheet.lx = Delta(sheet.xp, base.xp) / minutes
	sheet.lg = Delta(sheet.gold, base.gold) / minutes
	sheet.ld = Delta(sheet.damage, base.damage) / span
	sheet.ldmg = Delta(sheet.damage, base.damage)
	if base.taken ~= nil then
		local takenNow = sheet.takenTotal
		if takenNow == nil and type(sheet.taken) == "table" then
			takenNow = 0
			local i
			for i = 1, table.getn(sheet.taken) do
				takenNow = takenNow + Num(sheet.taken[i].dmg)
			end
		end
		sheet.ltaken = Delta(takenNow, base.taken)
	end
end

local function DamageTotals(sheet)
	local dealt = sheet.damage
	local takenHit = sheet.takenTotal
	if takenHit == nil and type(sheet.taken) == "table" then
		local sum = 0
		local i
		for i = 1, table.getn(sheet.taken) do
			sum = sum + Num(sheet.taken[i].dmg)
		end
		takenHit = sum
	end
	local last = RunStatsDB and RunStatsDB.dmgLast == 1
	if last then
		if sheet.ldmg ~= nil then
			dealt = sheet.ldmg
		elseif sheet.pace == 1 then
			dealt = Num(sheet.ld) * 60
		else
			dealt = nil
		end
		if sheet.ltaken ~= nil then
			takenHit = sheet.ltaken
		else
			takenHit = nil
		end
	end
	return last, dealt, takenHit
end

local function SampleBefore(list, t)
	if type(list) ~= "table" then return nil end
	local want = Num(t) - 60
	local best = nil
	local bestDist = 9999
	local i
	for i = 1, table.getn(list) do
		local row = list[i]
		if type(row) == "table" then
			local dist = math.abs(Num(row.t) - want)
			if dist < bestDist then
				best = row
				bestDist = dist
			end
		end
	end
	if type(best) ~= "table" or bestDist > 20 then return nil end
	return best
end

local function DiffRows(nowList, thenList, key)
	local prev = {}
	if type(thenList) == "table" then
		local i
		for i = 1, table.getn(thenList) do
			local row = thenList[i]
			if type(row) == "table" then prev[row[key] or "?"] = Num(row.dmg) end
		end
	end
	local out = {}
	local total = 0
	if type(nowList) ~= "table" then return out end
	local i
	for i = 1, table.getn(nowList) do
		local row = nowList[i]
		if type(row) == "table" then
			local name = row[key] or "?"
			local d = Num(row.dmg) - Num(prev[name])
			if d > 0 then
				local proc = 0
				if row.proc == 1 or row.proc == true then proc = 1 end
				tinsert(out, { name = row.name, source = row.source, dmg = d, proc = proc })
				total = total + d
			end
		end
	end
	if total < 1 then total = 1 end
	for i = 1, table.getn(out) do
		out[i].share = out[i].dmg / total
	end
	return out
end

local function ApplyLastGraphs(sheet, rec)
	if type(sheet) ~= "table" or not rec then return end
	local t = Num(sheet.t)
	if t < 1 then return end
	local function CurrentTaken()
		if type(sheet.taken) == "table" and table.getn(sheet.taken) > 0 then return sheet.taken end
		local out = {}
		local function AddRow(row)
			if type(row) == "table" and Num(row.dmg) > 0 then
				tinsert(out, { source = row.source or "?", dmg = Num(row.dmg) })
			end
		end
		if type(AZS_TAKEN) == "table" then Each(AZS_TAKEN, AddRow) end
		if table.getn(out) == 0 and type(rec.pending) == "table" then Each(rec.pending.taken, AddRow) end
		if table.getn(out) > 0 then return out end
		if type(sheet.taken) == "table" then return sheet.taken end
		return out
	end
	local nowTaken = CurrentTaken()
	if t <= 60 then
		if type(sheet.meter) == "table" then sheet.meter1 = sheet.meter end
		sheet.taken1 = nowTaken
		return
	end
	local meterThen = SampleBefore(rec.meterPace, t)
	if meterThen and type(sheet.meter) == "table" then
		sheet.meter1 = DiffRows(sheet.meter, meterThen.rows, "name")
	end
	local paceThen = SampleBefore(rec.pace, t)
	if paceThen and type(paceThen.takenRows) == "table" then
		sheet.taken1 = DiffRows(nowTaken, paceThen.takenRows, "source")
	end
end

local function FromPending(rec)
	local p = rec.pending
	local sheet
	if type(p) == "table" then
		sheet = {
			t = Num(p.t), kills = Num(p.kills), gold = Num(p.gold), xp = Num(p.xp),
			damage = Num(p.damage), lvl = Num(p.lvl),
			bosses = Num(p.bosses), guardians = Num(p.guardians), elites = Num(p.elites),
			takenTotal = Num(p.takenTotal), chests = Num(p.chests),
			points = {}, talents = {}, spells = {}, jewelry = {}, picks = {}, meter = {},
		}
		WriteStats(sheet, p)
	else
		local t = Num(rec.liveT)
		if t <= 0 and type(rec.at20) == "table" then t = Num(rec.at20.t) end
		sheet = BlankSheet(t, rec.xp)
	end
	if type(rec.picks) == "table" then
		local i
		for i = 1, table.getn(rec.picks) do
			local row = rec.picks[i]
			if type(row) == "table" then
				tinsert(sheet.picks, {
					t = Num(row.t), kind = row.kind or "", name = row.name or "",
					rank = Num(row.rank), key = row.key or "", rarity = row.rarity or "",
					icon = row.icon or "",
				})
			end
		end
	end
	AttachCache(sheet, rec)
	if Num(sheet.fight) < 1 then sheet.fight = Num(rec.fight) end
	return sheet
end

local function Announce(rec)
	if rec.told == 1 then return end
	local t = Num(rec.tEnd)
	if t <= 0 and type(rec.atEnd) == "table" then t = Num(rec.atEnd.t) end
	if t < 60 then return end
	rec.told = 1
	local who = rec.cname or rec.class or "Run"
	local where = rec.zname or rec.zone or "unknown map"
	local extra = ""
	if type(rec.atEnd) == "table" and rec.atEnd.armory == 1 and type(rec.atEnd.points) == "table" and table.getn(rec.atEnd.points) > 0 then
		local specName = SpecOf(rec.atEnd.points)
		if specName ~= "No spec" then
			extra = " · " .. specName .. " " .. SplitOf(rec.atEnd.points)
		end
	end
	Say("Saved " .. Clock(t) .. " · " .. who .. " · " .. where .. extra)
end

local function ArchiveRestart(rec)
	local kept = {
		id = (rec.id or "run") .. "#" .. tostring(table.getn(RunStatsDB.runs) + 1),
		class = rec.class, cname = rec.cname, zone = rec.zone, zname = rec.zname,
		heroic = rec.heroic, affixes = rec.affixes, hero = rec.hero, len = rec.len,
		race = rec.race, rname = rec.rname, party = rec.party,
		result = rec.result, tEnd = rec.tEnd, at20 = rec.at20, atEnd = rec.atEnd, atWin = rec.atWin,
		preview = rec.preview, watched = rec.watched, told = 1,
		bestHit = rec.bestHit, bestName = rec.bestName,
	}
	tinsert(RunStatsDB.runs, kept)
	rec.at20 = nil
	rec.atEnd = nil
	rec.atWin = nil
	rec.tEnd = nil
	rec.result = nil
	rec.xp = 0
	rec.pending = nil
	rec.cache = nil
	rec.picks = nil
	rec.seenSpells = nil
	rec.spellsBased = nil
	rec.seenTalents = nil
	rec.seenJewels = nil
	rec.based = nil
	rec.bestHit = nil
	rec.bestName = nil
	rec.pace = nil
	rec.meterPace = nil
	rec.fight = nil
	rec.fightClock = nil
	rec.baseTry = nil
	rec.trackLvl = nil
	rec.trackXp = nil
	rec.trackXpn = nil
	rec.seenT = nil
	rec.armed20 = nil
	rec.liveT = 0
	rec.preview = nil
	rec.watched = nil
	rec.told = nil
	rec.open = 1
end

local function KindName(kind)
	if kind == "spell" then return "Spell" end
	if kind == "talent" then return "Talent" end
	if kind == "ring" then return "Ring" end
	if kind == "trinket" then return "Trinket" end
	if kind == "amulet" or kind == "necklace" then return "Necklace" end
	if type(kind) ~= "string" or kind == "" then return "Gear" end
	return Pretty(kind)
end

local function TrackSpells(rec, t)
	if type(AZS_SPELLS) ~= "table" then return end
	if not rec.seenSpells then rec.seenSpells = {} end
	if not rec.picks then rec.picks = {} end
	local first = rec.spellsBased ~= 1
	local saw = false
	local i
	for i = 1, table.getn(AZS_SPELLS) do
		local row = AZS_SPELLS[i]
		if type(row) == "table" and type(row.key) == "string" and row.key ~= "" then
			saw = true
			local rank = Num(row.rank)
			if rank < 1 then rank = 1 end
			local prev = rec.seenSpells[row.key]
			if prev == nil then
				rec.seenSpells[row.key] = rank
				if not first then
					tinsert(rec.picks, {
						t = Num(t), kind = "spell", name = Pretty(row.key), rank = rank,
						key = row.key, icon = SpellBarIcon(row.key),
					})
				end
			elseif rank > Num(prev) then
				rec.seenSpells[row.key] = rank
				tinsert(rec.picks, {
					t = Num(t), kind = "spell", name = Pretty(row.key), rank = rank,
					key = row.key, icon = SpellBarIcon(row.key),
				})
			end
		end
	end
	if saw or Num(t) > 5 then rec.spellsBased = 1 end
end

local function ApplySpellNames(rec, build)
	if type(rec.picks) ~= "table" or type(build) ~= "table" then return end
	local byKey = {}
	local jewels = {}
	local i
	for i = 1, table.getn(build.spells) do
		local sp = build.spells[i]
		if type(sp.key) == "string" and sp.key ~= "" then
			byKey[sp.key] = sp
		end
	end
	if type(build.jewelry) == "table" then
		for i = 1, table.getn(build.jewelry) do
			local piece = build.jewelry[i]
			if type(piece.name) == "string" and piece.name ~= "" then
				jewels[piece.name] = piece
			end
			if type(piece.key) == "string" and piece.key ~= "" then
				jewels[piece.key] = piece
			end
		end
	end
	for i = 1, table.getn(rec.picks) do
		local pick = rec.picks[i]
		if type(pick) == "table" then
			local src = nil
			if pick.kind == "spell" then
				src = byKey[pick.key]
				if (type(pick.icon) ~= "string" or pick.icon == "") then
					local live = SpellBarIcon(pick.key)
					if live ~= "" then pick.icon = live end
				end
			else
				if type(pick.key) == "string" then src = jewels[pick.key] end
				if not src and type(pick.name) == "string" then src = jewels[pick.name] end
			end
			if src then
				if pick.kind == "spell" and type(src.name) == "string" and src.name ~= "" then
					pick.name = src.name
				end
				if (type(pick.icon) ~= "string" or pick.icon == "") and type(src.icon) == "string" and src.icon ~= "" then
					pick.icon = src.icon
				end
			end
		end
	end
end

local function NoteBuild(rec, t, silent)
	local mid = MeterId()
	if not mid then mid = rec.id end
	local build = ReadBuild(mid, rec.class)
	if type(build) ~= "table" then return end
	if table.getn(build.talents) > 0 or table.getn(build.spells) > 0 or table.getn(build.jewelry) > 0 then
		rec.cache = build
	elseif type(build.points) == "table" then
		local i
		local spent = false
		for i = 1, table.getn(build.points) do
			if Num(build.points[i].points) > 0 then spent = true end
		end
		if spent then rec.cache = build end
	end
	if not rec.seenTalents then rec.seenTalents = {} end
	if not rec.seenJewels then rec.seenJewels = {} end
	if not rec.picks then rec.picks = {} end
	local had = rec.based == 1
	local i
	for i = 1, table.getn(build.talents) do
		local row = build.talents[i]
		local id = row.key
		if id == "" then id = (row.tree or "") .. "/" .. (row.name or "") end
		local prev = rec.seenTalents[id]
		if prev == nil or Num(row.rank) > Num(prev) then
			rec.seenTalents[id] = Num(row.rank)
			if had or not silent then
				tinsert(rec.picks, { t = Num(t), kind = "talent", name = row.name or "Talent", rank = Num(row.rank), key = row.tree or "" })
			end
		end
	end
	for i = 1, table.getn(build.jewelry) do
		local row = build.jewelry[i]
		local id = row.key
		if id == "" then id = (row.category or "") .. "/" .. (row.name or "") end
		if id ~= "" and id ~= "/" and not rec.seenJewels[id] then
			rec.seenJewels[id] = 1
			if had or not silent then
				tinsert(rec.picks, {
					t = Num(t), kind = row.category or "gear", name = row.name or "Jewelry",
					rank = 0, key = id, rarity = row.rarity or "", icon = row.icon or "",
				})
			end
		end
	end
	rec.based = 1
	ApplySpellNames(rec, build)
	ShareJewelIcons(rec.picks, build.jewelry)
end

local function CaptureMeter(sheet)
	if type(sheet) ~= "table" or not AZS_GetMeter then return end
	local ok, lines, total, dps = pcall(AZS_GetMeter)
	if not ok or type(lines) ~= "table" then return end
	local meter = {}
	local i
	for i = 1, table.getn(lines) do
		local row = lines[i]
		if type(row) == "table" then
			local proc = 0
			if row.proc == 1 or row.proc == true then proc = 1 end
			tinsert(meter, {
				name = row.name or "?",
				dmg = Num(row.dmg),
				dps = Num(row.dps),
				share = Num(row.share),
				proc = proc,
			})
		end
	end
	sheet.meter = meter
	if tonumber(total) and Num(total) > 0 then sheet.damage = Num(total) end
	if tonumber(dps) and Num(dps) > 0 then sheet.dps = Num(dps) end
end

local function CopyTaken(src)
	local out = {}
	if type(src) ~= "table" then return out end
	local i
	for i = 1, table.getn(src) do
		local row = src[i]
		if type(row) == "table" and Num(row.dmg) > 0 then
			tinsert(out, { source = row.source or "?", dmg = Num(row.dmg) })
		end
	end
	return out
end

local function CaptureTaken(sheet, rec)
	if type(sheet) ~= "table" then return end
	local list = {}
	if type(AZS_TAKEN) == "table" and table.getn(AZS_TAKEN) > 0 then
		list = CopyTaken(AZS_TAKEN)
	end
	if table.getn(list) == 0 and rec and type(rec.pending) == "table" then
		list = CopyTaken(rec.pending.taken)
	end
	if table.getn(list) > 0 then sheet.taken = list end
end

local function HasRows(list)
	return type(list) == "table" and table.getn(list) > 0
end

local function PickSaved(sheet, rec, key)
	if type(sheet) == "table" and HasRows(sheet[key]) then return sheet[key] end
	if not rec then return nil end
	if type(rec.atEnd) == "table" and HasRows(rec.atEnd[key]) then return rec.atEnd[key] end
	if type(rec.preview) == "table" and HasRows(rec.preview[key]) then return rec.preview[key] end
	if type(rec.at20) == "table" and HasRows(rec.at20[key]) then return rec.at20[key] end
	return nil
end

local function TakenName(source)
	if source == "boss melee" then return "Boss melee" end
	if source == "boss spell" then return "Boss spell" end
	if source == "elite" then return "Elites" end
	if source == "mob melee" then return "Monster melee" end
	if source == "mob spell" then return "Monster spells" end
	if source == "area" then return "Ground" end
	if type(source) ~= "string" or source == "" then return "Unknown" end
	return Pretty(source)
end

local function NoteHits(rec)
	if not rec or not AZS_GetCombatTextEvents then return end
	if hitCursorRun ~= rec.id then
		hitCursor = nil
		hitCursorRun = rec.id
	end
	local function Consider(ev)
		if type(ev) ~= "table" or ev.kind ~= "damage" then return end
		local amt = Num(ev.amount)
		if amt <= Num(rec.bestHit) then return end
		local name = ev.abilityName
		if type(name) ~= "string" or name == "" then name = "Melee" end
		rec.bestHit = amt
		rec.bestName = name
	end
	local reads = 0
	while reads < 8 do
		reads = reads + 1
		local batch, err = AZS_GetCombatTextEvents(hitCursor)
		if type(err) == "table" and err.code == "STREAM_CHANGED" then
			hitCursor = nil
			batch = AZS_GetCombatTextEvents(nil)
		end
		if type(batch) ~= "table" then return end
		if type(batch.cursor) == "string" then hitCursor = batch.cursor end
		Each(batch.events, Consider)
		if not batch.hasMore then return end
	end
end

local function CloseOpen(exceptId)
	local runs = RunStatsDB.runs
	local i
	for i = 1, table.getn(runs) do
		local rec = runs[i]
		if rec.open == 1 and rec.id ~= exceptId and not rec.atEnd then
			rec.atEnd = FromPending(rec)
			ApplyLastMinute(rec.atEnd, rec)
			CaptureMeter(rec.atEnd)
			CaptureTaken(rec.atEnd, rec)
			ApplyLastGraphs(rec.atEnd, rec)
			if rec.watched == 1 then rec.preview = rec.atEnd end
			rec.tEnd = Num(rec.atEnd.t)
			rec.result = rec.result or "left"
			rec.open = nil
			rec.pending = nil
			rec.pace = nil
			rec.meterPace = nil
			Announce(rec)
		end
	end
end

local function ApplySummary(sheet, summary)
	if type(sheet) ~= "table" or type(summary) ~= "table" then return end
	if tonumber(summary.t) then sheet.t = Num(summary.t) end
	if tonumber(summary.kills) then sheet.kills = Num(summary.kills) end
	if tonumber(summary.gold) then sheet.gold = Num(summary.gold) end
	if tonumber(summary.lvl) then sheet.lvl = Num(summary.lvl) end
	if tonumber(summary.bosses) then sheet.bosses = Num(summary.bosses) end
	if tonumber(summary.guardians) then sheet.guardians = Num(summary.guardians) end
	if tonumber(summary.elites) then sheet.elites = Num(summary.elites) end
	if tonumber(summary.dmg) then sheet.damage = Num(summary.dmg) end
	if tonumber(summary.taken) then sheet.takenTotal = Num(summary.taken) end
	if tonumber(summary.chests) then sheet.chests = Num(summary.chests) end
	sheet.summary = 1
end

local function ReadSummary()
	if not AZS_GetRunSummary then return nil end
	local ok, summary = pcall(AZS_GetRunSummary)
	if ok and type(summary) == "table" then return summary end
	return nil
end

local function Finish(rec)
	NoteHits(rec)
	local summary = ReadSummary()
	if rec.atEnd then
		local changed = false
		if Num(rec.bestHit) > Num(rec.atEnd.bestHit) then
			rec.atEnd.bestHit = rec.bestHit
			rec.atEnd.bestName = rec.bestName
			changed = true
		end
		if summary and rec.atEnd.summary ~= 1 then
			ApplySummary(rec.atEnd, summary)
			rec.tEnd = Num(rec.atEnd.t)
			if type(summary.result) == "string" then rec.result = summary.result end
			if type(rec.atWin) == "table" then rec.result = "victory" end
			if rec.result == "victory" and not rec.at20 then rec.at20 = rec.atEnd end
			rec.preview = rec.atEnd
			changed = true
		end
		return changed
	end
	NoteParty(rec)
	local t = RunTime()
	if summary and tonumber(summary.t) then t = Num(summary.t) end
	if t <= 0 then t = Num(rec.liveT) end
	if t <= 0 and type(rec.pending) == "table" then t = Num(rec.pending.t) end
	NoteBuild(rec, t, false)
	TrackSpells(rec, t)
	NotePace(rec, t)
	rec.atEnd = FromPending(rec)
	if Num(rec.atEnd.t) <= 0 then rec.atEnd.t = t end
	local ok, sheet = pcall(MakeSheet, rec, rec.id, t)
	if ok and type(sheet) == "table" and (Num(sheet.t) > 0 or Num(sheet.kills) > 0) then
		rec.atEnd = sheet
	end
	ApplyLastMinute(rec.atEnd, rec)
	ApplyLast10(rec.atEnd, rec)
	AttachCache(rec.atEnd, rec)
	CaptureMeter(rec.atEnd)
	CaptureTaken(rec.atEnd, rec)
	ApplyLastGraphs(rec.atEnd, rec)
	if summary then
		ApplySummary(rec.atEnd, summary)
		if type(summary.result) == "string" then rec.result = summary.result end
	end
	rec.tEnd = Num(rec.atEnd.t)
	if rec.tEnd <= 0 then rec.tEnd = t end
	rec.open = nil
	rec.pending = nil
	rec.pace = nil
	rec.meterPace = nil
	if not rec.result then
		local ph = Phase()
		if ph == "victory" then rec.result = "victory"
		elseif ph == "dead" then rec.result = "defeat"
		else rec.result = "left" end
	end
	if type(rec.atWin) == "table" then rec.result = "victory" end
	rec.preview = rec.atEnd
	-- Full run ends when the final boss dies, not when it spawns.
	if rec.result == "victory" and type(rec.atEnd) == "table" and not rec.at20 then
		rec.at20 = rec.atEnd
	end
	Announce(rec)
	return true
end

local function Duration(rec)
	if rec.tEnd and Num(rec.tEnd) > 0 then return Num(rec.tEnd) end
	if type(rec.atEnd) == "table" and Num(rec.atEnd.t) > 0 then return Num(rec.atEnd.t) end
	if rec.liveT and Num(rec.liveT) > 0 then return Num(rec.liveT) end
	if type(rec.pending) == "table" and Num(rec.pending.t) > 0 then return Num(rec.pending.t) end
	if type(rec.at20) == "table" then return Num(rec.at20.t) > 0 and Num(rec.at20.t) or ZoneLength(rec) end
	return 0
end

local function SheetFor(rec, full)
	if rec.open == 1 and rec.watched == 1 and type(rec.preview) == "table" then
		return rec.preview
	end
	if full then
		if type(rec.atEnd) == "table" then return rec.atEnd end
		if type(rec.atWin) == "table" then return rec.atWin end
		if rec.open ~= 1 and type(rec.pending) == "table" then return rec.pending end
		return nil
	end
	if type(rec.at20) == "table" then return rec.at20 end
	if type(rec.atWin) == "table" then return rec.atWin end
	-- No victory sheet: the attempt itself (died or left before the final boss).
	if type(rec.atEnd) == "table" then return rec.atEnd end
	if rec.open ~= 1 and type(rec.pending) == "table" then return rec.pending end
end

local function ClassName(key, fallback)
	if type(fallback) == "string" and fallback ~= "" then return fallback end
	if type(key) ~= "string" or key == "" then return "Unknown" end
	return string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
end

local function Anchor()
	local now = GetTime and GetTime() or 0
	if anchorCache and (now - anchorAt) < 1 then return anchorCache end
	local ctx = nil
	local id = RunId()
	local liveT = 0
	if id then liveT = RunTime() end
	local liveKnown = false
	if id and liveT >= 30 then liveKnown = true end
	if id and type(AZS_ZONE) == "table" and type(AZS_ZONE.class) == "string" and AZS_ZONE.class ~= "" then
		liveKnown = true
	end
	if id and liveKnown then
		local rec = FindRun(id)
		local class, cname, zone, zname, heroic = "", "", "", "", 0
		if rec then
			class = rec.class or ""
			cname = rec.cname or ""
			zone = rec.zone or ""
			zname = rec.zname or ""
			heroic = Num(rec.heroic)
		end
		if type(AZS_ZONE) == "table" then
			if type(AZS_ZONE.class) == "string" and AZS_ZONE.class ~= "" then class = AZS_ZONE.class end
			if type(AZS_ZONE.cname) == "string" and AZS_ZONE.cname ~= "" then cname = AZS_ZONE.cname end
			if type(AZS_ZONE.zone) == "string" and AZS_ZONE.zone ~= "" then zone = AZS_ZONE.zone end
			if type(AZS_ZONE.zname) == "string" and AZS_ZONE.zname ~= "" then zname = AZS_ZONE.zname end
			if AZS_ZONE.heroic ~= nil then heroic = Num(AZS_ZONE.heroic) end
		end
		local build = nil
		if rec and type(rec.cache) == "table" then build = rec.cache end
		local specName, leading = "No spec", ""
		if build then specName, leading = SpecOf(build.points) end
		ctx = {
			class = class, cname = ClassName(class, cname), zone = zone,
			zname = zname ~= "" and zname or zone, heroic = heroic,
			specName = specName, leading = leading, live = 1,
		}
	else
		local runs = RunStatsDB.runs
		local i
		for i = table.getn(runs), 1, -1 do
			local rec = runs[i]
			local sheet = rec.atEnd or rec.at20 or rec.pending
			if rec.class and rec.class ~= "" or type(sheet) == "table" then
				local specName, leading = SpecOf(type(sheet) == "table" and sheet.points)
				local class = rec.class or ""
				ctx = {
					class = class,
					cname = ClassName(class, rec.cname),
					zone = rec.zone or "",
					zname = rec.zname or rec.zone or "Saved run",
					heroic = Num(rec.heroic),
					specName = specName,
					leading = leading,
					live = nil,
				}
				break
			end
		end
	end
	if not ctx then
		ctx = {
			class = "", cname = "No class", zone = "", zname = "No map",
			heroic = 0, specName = "No spec", leading = "", live = nil,
		}
	end
	anchorCache = ctx
	anchorAt = now
	return ctx
end

local function ViewClass(ctx)
	local f = RunStatsDB and RunStatsDB.classFilter
	if f == "all" then return "all" end
	if type(f) == "string" and f ~= "" then return f end
	return (ctx and ctx.class) or ""
end

local function ViewMap(ctx)
	local f = RunStatsDB and RunStatsDB.mapFilter
	if f == "all" then return "all" end
	if type(f) == "string" and f ~= "" then return f end
	return (ctx and ctx.zone) or ""
end

local function ViewDiff(ctx)
	if RunStatsDB and RunStatsDB.diff ~= nil then
		if Num(RunStatsDB.diff) < 0 then return -1 end
		return DiffLevel(RunStatsDB.diff)
	end
	return DiffLevel(ctx and ctx.heroic)
end

local function KnownClasses()
	local list = {}
	local have = {}
	local i
	for i = 1, table.getn(CFG.CLASS_ORDER) do
		local key = CFG.CLASS_ORDER[i]
		have[key] = ClassName(key)
		tinsert(list, key)
	end
	local runs = RunStatsDB.runs
	for i = 1, table.getn(runs) do
		local key = runs[i].class
		if type(key) == "string" and key ~= "" and not have[key] then
			have[key] = ClassName(key, runs[i].cname)
			tinsert(list, key)
		end
	end
	return list, have
end

local function KnownMaps()
	local list = {}
	local have = {}
	local i
	for i = 1, table.getn(CFG.MAPS) do
		local m = CFG.MAPS[i]
		have[m.key] = m.name
		tinsert(list, m.key)
	end
	local runs = RunStatsDB.runs
	for i = 1, table.getn(runs) do
		local key = runs[i].zone
		if type(key) == "string" and key ~= "" and not have[key] then
			have[key] = runs[i].zname or Pretty(key)
			tinsert(list, key)
		end
	end
	return list, have
end

local function RatesOf(sheet)
	local t = Num(sheet.t)
	if t < 1 then t = 1 end
	local minutes = t / 60
	local kpm = Num(sheet.kills) / minutes
	local xpm = Num(sheet.xp) / minutes
	local gpm = Num(sheet.gold) / minutes
	local dps = Num(sheet.dps) > 0 and Num(sheet.dps) or (Num(sheet.damage) / t)
	local pace = nil
	if RunStatsDB and RunStatsDB.lastMin == 1 then
		if sheet.pace == 1 then
			kpm = Num(sheet.lk)
			xpm = Num(sheet.lx)
			gpm = Num(sheet.lg)
			dps = Num(sheet.ld)
			pace = 1
		else
			pace = 0
		end
	end
	return {
		t = Num(sheet.t),
		lvl = Num(sheet.lvl),
		kpm = kpm,
		xpm = xpm,
		gpm = gpm,
		dps = dps,
		pace = pace,
		bosses = sheet.bosses,
		guardians = sheet.guardians,
		elites = sheet.elites,
		crit = Num(sheet.crit),
		cm = Num(sheet.cm),
		dmg = Num(sheet.dmg),
		haste = Num(sheet.haste),
		doth = Num(sheet.doth),
		area = Num(sheet.area),
		echo = Num(sheet.echo),
		cnt = Num(sheet.cnt),
		bp = Num(sheet.bp),
		luck = Num(sheet.luck),
		arm = Num(sheet.arm),
		spd = Num(sheet.spd),
		lch = Num(sheet.lch),
	}
end

local function Consider(list, rec, sheet)
	local rates = RatesOf(sheet)
	local specName, leading = SpecOf(type(sheet) == "table" and sheet.points)
	local split = ""
	tinsert(list, {
		rec = rec,
		sheet = sheet,
		rates = rates,
		specName = specName,
		leading = leading,
		split = split,
		race = (type(rec.rname) == "string" and rec.rname ~= "" and rec.rname) or rec.race or "",
		className = ClassName(rec.class, rec.cname),
		mapName = (type(rec.zname) == "string" and rec.zname ~= "" and rec.zname) or Pretty(rec.zone),
		diffName = DiffName(rec.heroic),
		heroic = DiffLevel(rec.heroic),
	})
end

local function Collect()
	local ctx = Anchor()
	local class = ViewClass(ctx)
	local mapFilter = ViewMap(ctx)
	local diff = ViewDiff(ctx)
	local full = RunStatsDB.full == 1
	local list = {}
	local runs = RunStatsDB.runs
	local i
	for i = 1, table.getn(runs) do
		local rec = runs[i]
		local sheet = SheetFor(rec, full)
		local longEnough = Duration(rec) >= MinSecs() or rec.watched == 1
		if rec.party ~= 1 and sheet and longEnough then
			local classOk = class == "all" or class == "" or rec.class == class or not rec.class or rec.class == ""
			local mapOk = mapFilter == "all" or mapFilter == "" or not rec.zone or rec.zone == "" or rec.zone == mapFilter
			local diffOk = diff < 0 or DiffLevel(rec.heroic) == diff
			if mapOk and diffOk and classOk then
				Consider(list, rec, sheet)
			end
		end
	end
	local key = RunStatsDB.sort or "kpm"
	if key == "spec" then
		key = "class"
		RunStatsDB.sort = "class"
	end
	table.sort(list, function(a, b)
		local av, bv
		if key == "diff" then
			av = Num(a.heroic)
			bv = Num(b.heroic)
			if av == bv then return a.rates.kpm > b.rates.kpm end
			return av < bv
		end
		if key == "class" or key == "race" or key == "map" then
			if key == "race" then
				av = a.race or ""
				bv = b.race or ""
			elseif key == "map" then
				av = a.mapName or ""
				bv = b.mapName or ""
			else
				av = a.className or ""
				bv = b.className or ""
			end
			if av == bv then return a.rates.kpm > b.rates.kpm end
			return av < bv
		end
		av = Num(a.rates[key])
		bv = Num(b.rates[key])
		if av == bv then return Num(a.rates.t) > Num(b.rates.t) end
		return av > bv
	end)
	return list, ctx
end

local function Cap(text, n)
	if type(text) ~= "string" then return "" end
	if string.len(text) <= n then return text end
	return string.sub(text, 1, n - 2) .. ".."
end

local function TimeText(row)
	local text = Clock(row.rates.t)
	if row.rec.open == 1 then text = text .. " *" end
	local full = Duration(row.rec)
	if RunStatsDB.full ~= 1 and full > Num(row.rates.t) + 30 then
		text = text .. " (" .. Clock(full) .. ")"
	end
	return text
end

local function Plus(n)
	n = Num(n)
	local text
	local nearest = math.floor(n + 0.5)
	if math.abs(n - nearest) < 0.05 then
		text = string.format("%d", nearest)
	else
		text = string.format("%.1f", n)
	end
	if n > 0 then return "+" .. text end
	return text
end

local function StatText(key, rates)
	if key == "t" then return "" end
	if key == "lvl" then return tostring(math.floor(rates.lvl)) end
	if key == "kpm" or key == "xpm" or key == "gpm" then
		if rates.pace == 0 then return "-" end
		return Rate(rates[key])
	end
	if key == "dps" then
		if rates.pace == 0 then return "-" end
		return Short(rates.dps)
	end
	if key == "bosses" or key == "guardians" or key == "elites" then
		if rates[key] == nil then return "-" end
		return Count(rates[key])
	end
	if key == "cm" then return string.format("%.2f", rates.cm) end
	if key == "cnt" then return Plus(rates.cnt) end
	if key == "crit" or key == "dmg" or key == "haste" or key == "doth" or key == "area" or key == "echo" or key == "bp" or key == "luck" or key == "arm" or key == "spd" or key == "lch" then
		return Pct(rates[key])
	end
	return ""
end

local function ResultWord(result)
	if result == "victory" then return "Victory" end
	if result == "defeat" then return "Defeat" end
	if result == "left" then return "Left" end
	return ""
end

local function JoinNames(list, withRank)
	local s = ""
	if type(list) ~= "table" then return s end
	local i
	for i = 1, table.getn(list) do
		local row = list[i]
		local bit = row.name or ""
		if withRank then bit = bit .. " " .. tostring(math.floor(Num(row.rank))) end
		if bit ~= "" then
			if s ~= "" then s = s .. ", " end
			s = s .. bit
		end
	end
	return s
end

local function ShowTip(row)
	if not GameTooltip or not row then return end
	local rec = row.rec
	local sheet = row.sheet
	GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
	local head = "Run"
	if type(rec.cname) == "string" and rec.cname ~= "" then
		head = rec.cname
	elseif type(rec.class) == "string" and rec.class ~= "" then
		head = rec.class
	end
	GameTooltip:SetText(head, 1, 0.82, 0)
	local where = (rec.zname or rec.zone or "") .. " · " .. DiffName(rec.heroic)
	GameTooltip:AddLine(where, 1, 1, 1)
	local outcome = ResultWord(rec.result)
	if outcome ~= "" then
		GameTooltip:AddLine(outcome .. " at " .. Clock(Duration(rec)), 0.9, 0.9, 0.9)
	end
	if type(rec.atWin) == "table" then
		GameTooltip:AddLine("Won at " .. Clock(rec.atWin.t) .. ", then endless", 0.9, 0.9, 0.9)
	end
	if type(rec.hero) == "string" and rec.hero ~= "" then
		local who = rec.hero
		if type(row.race) == "string" and row.race ~= "" then who = who .. ", " .. row.race end
		GameTooltip:AddLine(who, 0.8, 0.8, 0.8)
	elseif type(row.race) == "string" and row.race ~= "" then
		GameTooltip:AddLine(row.race, 0.8, 0.8, 0.8)
	end
	if type(rec.affixes) == "string" and rec.affixes ~= "" then
		GameTooltip:AddLine(rec.affixes, 0.85, 0.7, 0.4)
	end
	local spells = JoinNames(sheet.spells, true)
	if spells ~= "" then
		GameTooltip:AddLine("Spells: " .. spells, 0.75, 0.85, 1, true)
	end
	local jewels = ""
	if type(sheet.jewelry) == "table" then
		local i
		for i = 1, table.getn(sheet.jewelry) do
			local piece = sheet.jewelry[i]
			local bit = piece.name or ""
			if type(piece.category) == "string" and piece.category ~= "" then
				bit = piece.category .. " " .. bit
			end
			if bit ~= "" then
				if jewels ~= "" then jewels = jewels .. ", " end
				jewels = jewels .. bit
			end
		end
	end
	if jewels ~= "" then
		GameTooltip:AddLine("Jewelry: " .. jewels, 0.8, 1, 0.75, true)
	end
	GameTooltip:Show()
end

local function HideTip()
	if GameTooltip then GameTooltip:Hide() end
end

local function HidePopLines(from)
	local i
	for i = from, table.getn(popLines) do
		popLines[i]:Hide()
	end
end

local function PopLine(i)
	local fs = popLines[i]
	if not fs then
		fs = popChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH("LEFT")
		fs:SetWidth(430)
		popLines[i] = fs
	end
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", popChild, "TOPLEFT", 2, -((i - 1) * 15))
	fs:Show()
	return fs
end

local popBarN = 0

local BAR_COLORS = {
	{ 0.92, 0.58, 0.14 },
	{ 0.28, 0.52, 0.95 },
	{ 0.32, 0.78, 0.38 },
	{ 0.90, 0.32, 0.28 },
	{ 0.68, 0.38, 0.92 },
	{ 0.22, 0.78, 0.82 },
	{ 0.95, 0.48, 0.18 },
	{ 0.92, 0.42, 0.62 },
	{ 0.72, 0.86, 0.28 },
	{ 0.48, 0.68, 0.96 },
}

local function BarColor(i)
	local n = table.getn(BAR_COLORS)
	local idx = math.mod(i - 1, n) + 1
	local c = BAR_COLORS[idx]
	return c[1], c[2], c[3]
end

local function HidePopBars()
	local i
	for i = 1, popBarN do
		if popBars[i] then popBars[i]:Hide() end
	end
end

local function PopBar(i, share, r, g, b)
	local bar = popBars[i]
	if not bar then
		bar = popChild:CreateTexture(nil, "ARTWORK")
		bar:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
		bar:SetTexCoord(0, 1, 0, 1)
		popBars[i] = bar
	end
	if i > popBarN then popBarN = i end
	local w = Num(share) * 400
	if w < 3 then w = 3 end
	if w > 400 then w = 400 end
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", popChild, "TOPLEFT", 0, -((i - 1) * 15))
	bar:SetWidth(w)
	bar:SetHeight(13)
	bar:SetVertexColor(r, g, b, 0.7)
	bar:Show()
end

local popIconN = 0

local function HidePopIcons()
	local i
	for i = 1, popIconN do
		if popIcons[i] then popIcons[i]:Hide() end
	end
end

local function PopIcon(i, path)
	if type(path) ~= "string" or path == "" then return end
	local tex = popIcons[i]
	if not tex then
		tex = popChild:CreateTexture(nil, "OVERLAY")
		popIcons[i] = tex
	end
	if i > popIconN then popIconN = i end
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", popChild, "TOPLEFT", 0, -((i - 1) * 15))
	tex:SetWidth(14)
	tex:SetHeight(14)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	tex:SetTexture(path)
	tex:Show()
end

local function WriteCharacter(Add, Head, sheet)
	Head("Character")
	local showAll = RunStatsDB and RunStatsDB.allStats == 1
	local function Bit(label, value, color, raw, extra)
		if extra and not showAll then return nil end
		if not showAll and math.abs(Num(raw)) < 0.0001 then return nil end
		return "|cffb3a78a" .. label .. "|r |cff" .. color .. value .. "|r"
	end
	local function Line(a, b, c, d)
		local text = ""
		local function Join(bit)
			if not bit then return end
			if text ~= "" then text = text .. "    " end
			text = text .. bit
		end
		Join(a)
		Join(b)
		Join(c)
		Join(d)
		if text ~= "" then Add(text, 1, 1, 1) end
	end
	if sheet.hp == nil then
		Line(Bit("Armor", Pct(sheet.arm), "8eb4d4", sheet.arm))
		Line(
			Bit("Damage", PlusPct(sheet.dmg), "ffb040", sheet.dmg),
			Bit("Crit", Pct(sheet.crit), "ff6b4a", sheet.crit),
			Bit("Crit dmg", Pct(sheet.cm), "ffd060", sheet.cm))
		Line(
			Bit("Haste", PlusPct(sheet.haste), "7dffb0", sheet.haste),
			Bit("Echo", Pct(sheet.echo), "c9a0ff", sheet.echo))
		Line(
			Bit("Targets", Plus(sheet.cnt), "f0e6d2", sheet.cnt),
			Bit("Area", PlusPct(sheet.area), "6ec8ff", sheet.area))
		Line(Bit("Luck", PlusPct(sheet.luck), "5dff7a", sheet.luck))
		Line(
			Bit("Lifesteal", Pct(sheet.lch), "ff7080", sheet.lch),
			Bit("Buff power", PlusPct(sheet.bp), "d0a0ff", sheet.bp),
			Bit("Speed", PlusPct(sheet.spd), "ffe08a", sheet.spd))
		Line(Bit("DoT haste", PlusPct(sheet.doth), "6edc9a", sheet.doth))
		Add("The rest of the character pane was not saved for this run.", 0.7, 0.7, 0.65)
	else
		Line(
			Bit("Health", Count(sheet.hp), "7dce7d", sheet.hp),
			Bit("Armor", Pct(sheet.arm), "8eb4d4", sheet.arm),
			Bit("Regen", string.format("%.1f", Num(sheet.reg)), "7dcec0", sheet.reg, 1))
		Line(
			Bit("Damage", PlusPct(sheet.dmg), "ffb040", sheet.dmg),
			Bit("Crit", Pct(sheet.crit), "ff6b4a", sheet.crit),
			Bit("Crit dmg", Pct(sheet.cm), "ffd060", sheet.cm))
		Line(
			Bit("Haste", PlusPct(sheet.haste), "7dffb0", sheet.haste),
			Bit("Echo", Pct(sheet.echo), "c9a0ff", sheet.echo))
		Line(
			Bit("Targets", Plus(sheet.cnt), "f0e6d2", sheet.cnt),
			Bit("Area", PlusPct(sheet.area), "6ec8ff", sheet.area))
		Line(
			Bit("Luck", PlusPct(sheet.luck), "5dff7a", sheet.luck),
			Bit("Experience", PlusPct(sheet.sxp), "b388ff", sheet.sxp),
			Bit("Gold bonus", PlusPct(sheet.sgold), "ffd24a", sheet.sgold))
		Line(
			Bit("Lifesteal", Pct(sheet.lch), "ff7080", sheet.lch),
			Bit("Kill heal", Count(sheet.heal), "8dff8d", sheet.heal),
			Bit("Buff power", PlusPct(sheet.bp), "d0a0ff", sheet.bp))
		Line(
			Bit("Thorns", Pct(sheet.thn), "e0a060", sheet.thn),
			Bit("Speed", PlusPct(sheet.spd), "ffe08a", sheet.spd),
			Bit("Pickup", string.format("%.1f yd", Num(sheet.pick)), "9fd4ff", sheet.pick),
			Bit("Lives", Count(sheet.liv), "f0e6d2", sheet.liv, 1))
		local dotStacks = nil
		if showAll or math.abs(Num(sheet.doth)) > 0.0001 then
			dotStacks = Bit("DoT stacks", Count(sheet.dots), "9be07a", sheet.dots)
		end
		Line(dotStacks, Bit("DoT haste", PlusPct(sheet.doth), "6edc9a", sheet.doth))
	end
end

local function OpenBuild(btn)
	if not pop or not popChild or not btn.sheet then return end
	if pop.keepGraph == 1 then
		pop.keepGraph = nil
	else
		pop.graphLast = nil
	end
	local sheet = btn.sheet
	local title = "Run details"
	if btn.rec then
		local who = btn.rec.cname or btn.rec.class or ""
		local where = btn.rec.zname or ""
		if who ~= "" and where ~= "" then
			title = who .. " · " .. where
		elseif who ~= "" then
			title = who
		elseif where ~= "" then
			title = where
		end
	end
	popTitle:SetText(title)
	pop.rec = btn.rec
	pop.view = btn
	if btn.rec and btn.rec.open == 1 then ApplyLastGraphs(sheet, btn.rec) end
	HidePopBars()
	HidePopIcons()
	if pop.dmgBtn then pop.dmgBtn:Hide() end
	if pop.takenBtn then pop.takenBtn:Hide() end
	local n = 0
	local function Add(text, r, g, b, icon)
		n = n + 1
		local fs = PopLine(n)
		local x = 2
		if type(icon) == "string" and icon ~= "" then
			x = 18
			PopIcon(n, icon)
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", popChild, "TOPLEFT", x, -((n - 1) * 15))
		fs:SetWidth(x == 2 and 426 or 410)
		fs:SetText(text)
		fs:SetTextColor(r, g, b)
		return n
	end
	local function Head(text)
		if n > 0 then Add(" ", 1, 1, 1) end
		Add(text, 1, 0.82, 0)
	end
	Head("Run")
	local function Bit(label, value, color)
		return "|cffb3a78a" .. label .. "|r |cff" .. color .. value .. "|r"
	end
	local function Line(a, b, c, d)
		local text = ""
		local function Join(bit)
			if not bit or bit == "" then return end
			if text ~= "" then text = text .. "   " end
			text = text .. bit
		end
		Join(a)
		Join(b)
		Join(c)
		Join(d)
		if text ~= "" then Add(text, 1, 1, 1) end
	end
	local race = btn.race or ""
	Line(
		Bit("Time", Clock(sheet.t), "ffd24a"),
		Bit("Level", tostring(math.floor(Num(sheet.lvl))), "f0e6d2"),
		race ~= "" and Bit("Race", race, "9fd4ff") or "")
	if btn.rec and btn.rec.open == 1 then
		Add("In progress.", 0.75, 0.72, 0.55)
	end
	local seconds = Num(sheet.t)
	if seconds < 1 then seconds = 1 end
	local minutes = seconds / 60
	local dps = Num(sheet.dps)
	if dps <= 0 then dps = Num(sheet.damage) / seconds end
	Add(" ", 1, 1, 1)
	Add("|cff6ec8ffWhole run|r", 1, 1, 1)
	Line(
		Bit("K/min", Rate(Num(sheet.kills) / minutes), "ffb040"),
		Bit("XP/min", Rate(Num(sheet.xp) / minutes), "b388ff"),
		Bit("G/min", Rate(Num(sheet.gold) / minutes), "ffd24a"),
		Bit("DPS", Short(dps), "ff6b4a"))
	if sheet.pace == 1 then
		Add("|cff6ec8ffLast min|r", 1, 1, 1)
		Line(
			Bit("K/min", Rate(sheet.lk), "ffb040"),
			Bit("XP/min", Rate(sheet.lx), "b388ff"),
			Bit("G/min", Rate(sheet.lg), "ffd24a"),
			Bit("DPS", Short(sheet.ld), "ff6b4a"))
	else
		Add("|cff6ec8ffLast min|r  |cff9a9078-|r", 1, 1, 1)
	end
	local last10 = nil
	if btn.rec and btn.rec.open == 1 and sheet == btn.rec.preview then
		last10 = MeterRate(btn.rec, 10)
	end
	if not last10 and tonumber(sheet.l10) then last10 = Num(sheet.l10) end
	if last10 then
		Line(Bit("DPS last 10 s", Short(last10), "ff6b4a"))
	end
	local function EndNum(v)
		if v == nil then return "-" end
		return Comma(v)
	end
	local dealt = sheet.damage
	local takenHit = sheet.takenTotal
	if takenHit == nil and type(sheet.taken) == "table" then
		local sum = 0
		local i
		for i = 1, table.getn(sheet.taken) do
			sum = sum + Num(sheet.taken[i].dmg)
		end
		takenHit = sum
	end
	Add(" ", 1, 1, 1)
	Line(Bit("Kills", EndNum(sheet.kills), "f0e6d2"), Bit("Elites", EndNum(sheet.elites), "e0a060"))
	Line(Bit("Guardians", EndNum(sheet.guardians), "ffd24a"), Bit("Bosses", EndNum(sheet.bosses), "ff6b4a"))
	Line(Bit("Damage dealt", EndNum(dealt), "ffb040"))
	Line(Bit("Damage taken", EndNum(takenHit), "ff7080"))
	Line(Bit("Gold", EndNum(sheet.gold), "ffd24a"), Bit("Caches", EndNum(sheet.chests), "9fd4ff"))
	local hitName = sheet.bestName
	local hitAmt = sheet.bestHit
	if (type(hitName) ~= "string" or hitName == "") and btn.rec then
		hitName = btn.rec.bestName
		hitAmt = btn.rec.bestHit
	end
	if type(hitName) == "string" and hitName ~= "" and Num(hitAmt) > 0 then
		Line(Bit("Highest hit", hitName .. "  " .. Comma(hitAmt), "ff6b4a"))
	else
		Line(Bit("Highest hit", "-", "9a9078"))
	end

	WriteCharacter(Add, Head, sheet)

	Head("Spells")
	local spellN = 0
	if type(sheet.spells) == "table" then
		for i = 1, table.getn(sheet.spells) do
			local row = sheet.spells[i]
			local name = row.name or ""
			if name ~= "" and not IsRacial(row.key, name) then
				spellN = spellN + 1
				Add(name .. "  " .. tostring(math.floor(Num(row.rank))), 0.85, 0.9, 1, row.icon)
			end
		end
	end
	if spellN == 0 then Add("Not saved for this run.", 0.7, 0.7, 0.65) end

	Head("Jewelry")
	local jewelN = 0
	if type(sheet.jewelry) == "table" then
		for i = 1, table.getn(sheet.jewelry) do
			local piece = sheet.jewelry[i]
			local name = piece.name or ""
			if name ~= "" then
				jewelN = jewelN + 1
				local line = KindName(piece.category) .. "    " .. name
				if type(piece.rarity) == "string" and piece.rarity ~= "" then
					line = piece.rarity .. "    " .. line
				end
				Add(line, 0.8, 1, 0.75, piece.icon)
			end
		end
	end
	if jewelN == 0 then
		if sheet.jewelsRead == 1 then
			Add("None equipped.", 0.7, 0.7, 0.65)
		else
			Add("Not saved for this run.", 0.7, 0.7, 0.65)
		end
	end

	Head("Damage")
	local lastGraph = pop.graphLast == 1
	local function PlaceGraphBtn(btn, line)
		if not btn then return end
		btn:SetParent(popChild)
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", popChild, "TOPLEFT", 320, -((line - 1) * 15))
		if lastGraph then btn.label:SetText("Last min") else btn.label:SetText("Average") end
		btn:Show()
	end
	PlaceGraphBtn(pop.dmgBtn, n)
	local meter = nil
	if lastGraph then
		if type(sheet.meter1) == "table" then meter = sheet.meter1 end
	else
		meter = PickSaved(sheet, btn.rec, "meter")
	end
	local meterN = 0
	if meter then
		for i = 1, table.getn(meter) do
			local row = meter[i]
			meterN = meterN + 1
			local line = (row.name or "?") .. "    " .. Short(row.dmg) .. "    " .. Pct(row.share)
			local at
			if row.proc == 1 then
				at = Add(line .. "    proc", 0.75, 0.88, 1)
			else
				at = Add(line, 0.95, 0.92, 0.84)
			end
			PopBar(at, row.share, BarColor(meterN))
		end
	end
	if meterN == 0 then
		if lastGraph then
			Add("Last minute was not saved for this run.", 0.7, 0.7, 0.65)
		else
			Add("Saved when the run ends.", 0.7, 0.7, 0.65)
		end
	end

	local taken = nil
	if lastGraph then
		if type(sheet.taken1) == "table" then taken = sheet.taken1 end
	else
		taken = PickSaved(sheet, btn.rec, "taken")
	end
	Head("Damage taken")
	PlaceGraphBtn(pop.takenBtn, n)
	if not taken or table.getn(taken) == 0 then
		if lastGraph and type(sheet.taken1) ~= "table" then
			Add("Last minute was not saved for this run.", 0.7, 0.7, 0.65)
		else
			Add("None.", 0.7, 0.7, 0.65)
		end
	else
			local totalHit = Num(sheet.takenTotal)
			local i
			if lastGraph or totalHit <= 0 then
				totalHit = 0
				for i = 1, table.getn(taken) do
					totalHit = totalHit + Num(taken[i].dmg)
				end
			end
			if not lastGraph and totalHit <= 0 and btn.rec and type(btn.rec.atEnd) == "table" then
				totalHit = Num(btn.rec.atEnd.takenTotal)
			end
			if totalHit < 1 then totalHit = 1 end
			for i = 1, table.getn(taken) do
				local row = taken[i]
				local share = Num(row.share)
				if share <= 0 then share = Num(row.dmg) / totalHit end
				local at = Add(TakenName(row.source) .. "    " .. Short(row.dmg) .. "    " .. Pct(share), 1, 0.75, 0.7)
				PopBar(at, share, BarColor(i))
			end
	end

	Head("Pickups")
	local pickN = 0
	if type(sheet.picks) == "table" then
		for i = 1, table.getn(sheet.picks) do
			local row = sheet.picks[i]
			local name = row.name or ""
			if name ~= "" then
				pickN = pickN + 1
				local rank = ""
				if row.kind == "spell" or row.kind == "talent" then
					rank = "  " .. tostring(math.floor(Num(row.rank)))
				end
				local extra = ""
				if type(row.rarity) == "string" and row.rarity ~= "" then
					extra = "    " .. row.rarity
				end
				local icon = row.icon or ""
				if icon == "" and row.kind == "spell" and type(sheet.spells) == "table" then
					local s
					for s = 1, table.getn(sheet.spells) do
						local sp = sheet.spells[s]
						if type(sp.icon) == "string" and sp.icon ~= "" then
							if (type(row.key) == "string" and row.key ~= "" and sp.key == row.key) or sp.name == name then
								icon = sp.icon
							end
						end
					end
				elseif icon == "" and row.kind ~= "talent" and type(sheet.jewelry) == "table" then
					local s
					for s = 1, table.getn(sheet.jewelry) do
						local piece = sheet.jewelry[s]
						if type(piece.icon) == "string" and piece.icon ~= "" then
							local same = piece.name == name or (type(row.key) == "string" and row.key ~= "" and piece.key == row.key)
							if not same then
								same = JewelBase(piece.name) == JewelBase(name) and JewelBase(name) ~= ""
							end
							if same then icon = piece.icon end
						end
					end
				end
				Add(Clock(row.t) .. "    " .. KindName(row.kind) .. "    " .. name .. rank .. extra, 0.95, 0.92, 0.84, icon)
			end
		end
	end
	if pickN == 0 then Add("None recorded.", 0.7, 0.7, 0.65) end

	HidePopLines(n + 1)
	popChild:SetHeight(n * 15 + 8)
	local view = 360
	local maxScroll = popChild:GetHeight() - view
	if maxScroll < 1 then maxScroll = 1 end
	if popSlider then
		popSlider.busy = 1
		popSlider:SetMinMaxValues(0, maxScroll)
		popSlider:SetValue(0)
		popSlider.busy = nil
	end
	if popScroll then popScroll:SetVerticalScroll(0) end
	if pop.scrollAt and popScroll and popSlider then
		local y = pop.scrollAt
		pop.scrollAt = nil
		if y < 0 then y = 0 end
		popSlider.busy = 1
		popSlider:SetValue(y)
		popSlider.busy = nil
		popScroll:SetVerticalScroll(y)
	end
	if frame then
		pop:ClearAllPoints()
		pop:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
	end
	pop:Show()
	pop:Raise()
	if ask and ask:IsShown() then ask:Raise() end
end

local function Refresh()
	if not frame then return end
	local list, ctx = Collect()
	shown = list
	local class = ViewClass(ctx)
	local _, names = KnownClasses()
	local cname = "No class"
	if class == "all" then
		cname = "All classes"
	elseif class ~= "" then
		cname = names[class] or ClassName(class, ctx.cname)
	elseif ctx.cname and ctx.cname ~= "" then
		cname = ctx.cname
	end
	local mapFilter = ViewMap(ctx)
	local _, mapNames = KnownMaps()
	local mapLabel = "No map"
	if mapFilter == "all" then
		mapLabel = "All maps"
	elseif mapFilter ~= "" then
		mapLabel = mapNames[mapFilter] or Pretty(mapFilter)
	elseif ctx.zname and ctx.zname ~= "" then
		mapLabel = ctx.zname
	end
	local windowLabel = "Full run"
	if RunStatsDB.full == 1 then windowLabel = "Endless" end
	local diff = ViewDiff(ctx)
	sub:SetText(cname .. "  ·  " .. mapLabel .. "  ·  " .. DiffName(diff))
	classBtn.label:SetText(Cap(cname, 14))
	mapBtn.label:SetText(Cap(mapLabel, 14))
	if diffBtn then diffBtn.label:SetText(DiffName(diff)) end
	if frame and frame.minBtn then frame.minBtn.label:SetText(MinLabel()) end
	windowBtn.label:SetText(windowLabel)
	if frame.paceBtn then
		if RunStatsDB.lastMin == 1 then
			frame.paceBtn.label:SetText("Last min")
		else
			frame.paceBtn.label:SetText("Average")
		end
	end

	local pages = math.ceil(table.getn(list) / CFG.PAGE)
	if pages < 1 then pages = 1 end
	if page > pages then page = pages end
	if page < 1 then page = 1 end
	local start = (page - 1) * CFG.PAGE
	local r
	for r = 1, CFG.PAGE do
		local row = rows[r]
		local item = list[start + r]
		if item then
			local rates = item.rates
			local c
			for c = 1, table.getn(COLS) do
				local col = COLS[c]
				local text
				if col.key == "t" then
					text = TimeText(item)
				elseif col.key == "class" then
					text = Cap(item.className or "", 12)
				elseif col.key == "map" then
					text = Cap(item.mapName or "", 16)
				elseif col.key == "diff" then
					text = item.diffName or ""
				elseif col.key == "race" then
					text = item.race or ""
				else
					text = StatText(col.key, rates)
				end
				local cell = row.cells[c]
				cell:SetText(text)
				if col.key == "class" then
					local cc = nil
					if item.rec then cc = CFG.CLASS_COLOR[item.rec.class] end
					if cc then
						cell:SetTextColor(cc[1], cc[2], cc[3])
					else
						cell:SetTextColor(0.96, 0.93, 0.84)
					end
				elseif col.key == "t" then
					local result = item.rec and item.rec.result
					if result == "victory" then
						cell:SetTextColor(0.35, 0.92, 0.40)
					elseif result == "defeat" then
						cell:SetTextColor(0.95, 0.32, 0.28)
					else
						cell:SetTextColor(0.96, 0.93, 0.84)
					end
				else
					cell:SetTextColor(0.96, 0.93, 0.84)
				end
			end
			row.btn.sheet = item.sheet
			row.btn.race = item.race
			row.btn.rec = item.rec
			row.del.rec = item.rec
			row.holder.item = item
			row.holder:Show()
		else
			row.holder.item = nil
			row.btn.sheet = nil
			row.btn.race = nil
			row.btn.rec = nil
			row.del.rec = nil
			row.holder:Hide()
		end
	end
	local n = table.getn(list)
	if n == 0 then
		local need = MinSecs()
		if need <= 0 then
			foot:SetText("No runs for this filter. Party runs stay hidden.")
		else
			foot:SetText("No runs of " .. tostring(math.floor(need / 60)) .. " minutes or more for this filter. Party runs stay hidden.")
		end
		pageText:SetText("")
	else
		local last = start + CFG.PAGE
		if last > n then last = n end
		pageText:SetText((start + 1) .. "-" .. last .. " of " .. n)
		foot:SetText("K/min, XP/min, G/min and DPS use the run clock. It stops while a card is open or the run is paused. Last min is the final minute. A dash was not saved.")
	end
	PaintHeaders()
end

local ToggleDiffMenu, ToggleMinMenu, ToggleClassMenu, ToggleMapMenu

local function HideDiffMenu()
	if diffMenu then diffMenu:Hide() end
	if frame then
		if frame.minMenu then frame.minMenu:Hide() end
		if frame.classMenu then frame.classMenu:Hide() end
		if frame.mapMenu then frame.mapMenu:Hide() end
	end
end

local function Toggle()
	if not frame then return end
	if frame:IsShown() then
		SavePlace()
		frame:Hide()
		HideDiffMenu()
		if pop then pop:Hide() end
		if ask then ask:Hide() end
		if AZS_SetOnTopOfScreens then
			pcall(AZS_SetOnTopOfScreens, frame, false)
			pcall(AZS_SetOnTopOfScreens, "RunStatsTalents", false)
			pcall(AZS_SetOnTopOfScreens, "RunStatsConfirm", false)
		end
	else
		HideDiffMenu()
		anchorCache = nil
		local id = RunId()
		local rec = id and FindRun(id)
		if rec then
			local build = ReadBuild(id, rec.class)
			if type(build) == "table" and (table.getn(build.talents) > 0 or table.getn(build.spells) > 0 or table.getn(build.jewelry) > 0) then
				rec.cache = build
			end
		end
		Refresh()
		frame:Show()
		PlaceWindow()
		if AZS_SetOnTopOfScreens then
			pcall(AZS_SetOnTopOfScreens, frame, true)
			pcall(AZS_SetOnTopOfScreens, "RunStatsTalents", true)
			pcall(AZS_SetOnTopOfScreens, "RunStatsConfirm", true)
			pcall(AZS_SetOnTopOfScreens, "GameTooltip", true)
		end
		PlaceWindow()
	end
end

local function HeaderClick(key)
	RunStatsDB.sort = key
	page = 1
	Refresh()
end

PaintHeaders = function()
	local sort = RunStatsDB.sort or "kpm"
	local last = RunStatsDB.lastMin == 1
	local i
	for i = 1, table.getn(headers) do
		local key = headers[i].key
		if key == sort then
			headers[i].label:SetTextColor(1, 0.82, 0)
		elseif last and (key == "kpm" or key == "xpm" or key == "gpm" or key == "dps") then
			headers[i].label:SetTextColor(0.65, 0.88, 1)
		else
			headers[i].label:SetTextColor(0.85, 0.8, 0.65)
		end
	end
end

local function MakeButton(parent, w, h)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(w)
	b:SetHeight(h)
	b:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	b:SetBackdropColor(0.08, 0.07, 0.05, 0.95)
	b:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.9)
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("CENTER", b, "CENTER", 0, 0)
	b.label = fs
	b:SetScript("OnEnter", function()
		this:SetBackdropBorderColor(1, 0.84, 0.3, 1)
	end)
	b:SetScript("OnLeave", function()
		this:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.9)
	end)
	return b
end

ToggleDiffMenu = function()
	if not diffBtn then return end
	if not diffMenu then
		diffMenu = CreateFrame("Frame", "RunStatsDiffMenu", UIParent)
		diffMenu:SetWidth(114)
		diffMenu:SetHeight(7 * 20 + 8)
		diffMenu:SetFrameStrata("TOOLTIP")
		diffMenu:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 8, edgeSize = 8,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		diffMenu:SetBackdropColor(0.05, 0.04, 0.02, 0.97)
		diffMenu:SetBackdropBorderColor(0.9, 0.75, 0.25, 0.95)
		diffMenu:EnableMouse(true)
		diffMenu:Hide()
		local i
		for i = -1, 5 do
			local b = MakeButton(diffMenu, 104, 18)
			b:SetPoint("TOPLEFT", diffMenu, "TOPLEFT", 5, -4 - (i + 1) * 20)
			b.diff = i
			b.label:SetText(DiffName(i))
			b:SetScript("OnClick", function()
				RunStatsDB.diff = this.diff
				HideDiffMenu()
				page = 1
				anchorCache = nil
				Refresh()
			end)
		end
	end
	if diffMenu:IsShown() then
		HideDiffMenu()
		return
	end
	diffMenu:ClearAllPoints()
	diffMenu:SetPoint("TOPLEFT", diffBtn, "BOTTOMLEFT", 0, -2)
	diffMenu:Show()
	diffMenu:Raise()
end

ToggleMinMenu = function()
	if not frame or not frame.minBtn then return end
	if not frame.minMenu then
		local menu = CreateFrame("Frame", "RunStatsMinMenu", UIParent)
		menu:SetWidth(180)
		menu:SetHeight(54)
		menu:SetFrameStrata("TOOLTIP")
		menu:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 8, edgeSize = 8,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		menu:SetBackdropColor(0.05, 0.04, 0.02, 0.97)
		menu:SetBackdropBorderColor(0.9, 0.75, 0.25, 0.95)
		menu:EnableMouse(true)
		menu:Hide()
		frame.minMenu = menu
		local title = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		title:SetPoint("TOP", menu, "TOP", 0, -6)
		title:SetTextColor(0.9, 0.85, 0.7)
		menu.title = title
		local slider = CreateFrame("Slider", "RunStatsMinSlider", menu)
		slider:SetPoint("TOPLEFT", menu, "TOPLEFT", 14, -24)
		slider:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -14, -24)
		slider:SetHeight(16)
		slider:SetOrientation("HORIZONTAL")
		slider:SetMinMaxValues(0, CFG.MIN_MAX)
		if slider.SetValueStep then slider:SetValueStep(1) end
		slider:SetValue(MinMins())
		slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
		local track = slider:CreateTexture(nil, "BACKGROUND")
		track:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
		track:SetAllPoints(slider)
		local low = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		low:SetPoint("BOTTOMLEFT", menu, "BOTTOMLEFT", 10, 6)
		low:SetText("0")
		low:SetTextColor(0.7, 0.65, 0.5)
		local high = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		high:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -10, 6)
		high:SetText(tostring(CFG.MIN_MAX))
		high:SetTextColor(0.7, 0.65, 0.5)
		frame.minSlider = slider
		slider:SetScript("OnValueChanged", function()
			if this.busy then return end
			local mins = math.floor(this:GetValue() + 0.5)
			if mins < 0 then mins = 0 end
			if mins > CFG.MIN_MAX then mins = CFG.MIN_MAX end
			RunStatsDB.minTime = mins * 60
			if frame.minMenu and frame.minMenu.title then
				frame.minMenu.title:SetText("Minimum: " .. tostring(mins) .. " min")
			end
			if frame.minBtn then frame.minBtn.label:SetText(MinLabel()) end
			page = 1
			Refresh()
		end)
	end
	local menu = frame.minMenu
	if menu:IsShown() then
		HideDiffMenu()
		return
	end
	HideDiffMenu()
	if frame.minSlider then
		frame.minSlider.busy = 1
		frame.minSlider:SetValue(MinMins())
		frame.minSlider.busy = nil
	end
	menu.title:SetText("Minimum: " .. tostring(MinMins()) .. " min")
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", frame.minBtn, "BOTTOMLEFT", 0, -2)
	menu:Show()
	menu:Raise()
end

do
	local function MakeFilterMenu(name, width, rows)
		local menu = CreateFrame("Frame", name, UIParent)
		menu:SetWidth(width)
		menu:SetHeight(table.getn(rows) * 20 + 8)
		menu:SetFrameStrata("TOOLTIP")
		menu:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 8, edgeSize = 8,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		menu:SetBackdropColor(0.05, 0.04, 0.02, 0.97)
		menu:SetBackdropBorderColor(0.9, 0.75, 0.25, 0.95)
		menu:EnableMouse(true)
		menu:Hide()
		local i
		for i = 1, table.getn(rows) do
			local row = rows[i]
			local b = MakeButton(menu, width - 10, 18)
			b:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, -4 - (i - 1) * 20)
			b.pick = row.id
			b.label:SetText(row.text)
			b:SetScript("OnClick", function()
				row.apply(this.pick)
				HideDiffMenu()
				page = 1
				anchorCache = nil
				Refresh()
			end)
		end
		return menu
	end

	ToggleClassMenu = function()
		if not classBtn then return end
		if frame.classMenu and frame.classMenu:IsShown() then
			HideDiffMenu()
			return
		end
		HideDiffMenu()
		if not frame.classMenu then
			local rows = { { id = "all", text = "All classes", apply = function(id) RunStatsDB.classFilter = id end } }
			local list, names = KnownClasses()
			local i
			for i = 1, table.getn(list) do
				local key = list[i]
				tinsert(rows, {
					id = key,
					text = names[key] or ClassName(key),
					apply = function(id) RunStatsDB.classFilter = id end,
				})
			end
			frame.classMenu = MakeFilterMenu("RunStatsClassMenu", 120, rows)
		end
		frame.classMenu:ClearAllPoints()
		frame.classMenu:SetPoint("TOPLEFT", classBtn, "BOTTOMLEFT", 0, -2)
		frame.classMenu:Show()
		frame.classMenu:Raise()
	end

	ToggleMapMenu = function()
		if not mapBtn then return end
		if frame.mapMenu and frame.mapMenu:IsShown() then
			HideDiffMenu()
			return
		end
		HideDiffMenu()
		if not frame.mapMenu then
			local list, names = KnownMaps()
			local rows = { { id = "all", text = "All maps", apply = function(id) RunStatsDB.mapFilter = id end } }
			local i
			for i = 1, table.getn(list) do
				local key = list[i]
				tinsert(rows, {
					id = key,
					text = Cap(names[key] or Pretty(key), 22),
					apply = function(id) RunStatsDB.mapFilter = id end,
				})
			end
			frame.mapMenu = MakeFilterMenu("RunStatsMapMenu", 150, rows)
		end
		frame.mapMenu:ClearAllPoints()
		frame.mapMenu:SetPoint("TOPLEFT", mapBtn, "BOTTOMLEFT", 0, -2)
		frame.mapMenu:Show()
		frame.mapMenu:Raise()
	end
end

PlaceDetails = function()
	if not pop or not frame then return end
	pop:ClearAllPoints()
	pop:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
end

PlaceWindow = function()
	frame:ClearAllPoints()
	if RunStatsDB.left and RunStatsDB.top then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", RunStatsDB.left, RunStatsDB.top)
	else
		local sw = 1024
		if GetScreenWidth then sw = GetScreenWidth() end
		local sh = 768
		if GetScreenHeight then sh = GetScreenHeight() end
		local left = (sw - (CFG.FRAME_W + 6 + 480)) / 2
		if left < 12 then left = 12 end
		local top = (sh / 2) + (430 / 2) + 40
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
	PlaceDetails()
end

SavePlace = function()
	if not frame or not RunStatsDB then return end
	local x = frame:GetLeft()
	local y = frame:GetTop()
	if not x or not y then return end
	RunStatsDB.left = x
	RunStatsDB.top = y
end

local function ResetPlace()
	if not RunStatsDB then return end
	RunStatsDB.left = nil
	RunStatsDB.top = nil
	PlaceWindow()
end

local function CurrentRec()
	local id = RunId()
	if id then
		if dropped[id] then return nil end
		local rec = FindRun(id)
		if not rec then rec = StartRun(id) end
		return rec
	end
	local runs = RunStatsDB.runs
	local i
	for i = table.getn(runs), 1, -1 do
		if runs[i].open == 1 then return runs[i] end
	end
end

local function InspectCurrent()
	local rec = CurrentRec()
	if not rec then
		Say("No run in progress.")
		return
	end
	local t = RunTime()
	if t <= 0 then t = Num(rec.liveT) end
	FillIdentity(rec)
	TrackXp(rec)
	Remember(rec, t)
	NotePace(rec, t)
	NoteHits(rec)
	TrackSpells(rec, t)
	if rec.based ~= 1 then
		NoteBuild(rec, t, true)
	else
		NoteBuild(rec, t, false)
	end
	local sheet = nil
	local ok, built = pcall(MakeSheet, rec, rec.id, t)
	if ok and type(built) == "table" then sheet = built end
	if not sheet then sheet = FromPending(rec) end
	if Num(sheet.t) <= 0 then sheet.t = t end
	ApplyLastMinute(sheet, rec)
	ApplyLast10(sheet, rec)
	AttachCache(sheet, rec)
	CaptureMeter(sheet)
	CaptureTaken(sheet, rec)
	ApplyLastGraphs(sheet, rec)
	rec.preview = sheet
	rec.watched = 1
	anchorCache = nil
	Refresh()
	OpenBuild({
		sheet = sheet,
		race = (type(rec.rname) == "string" and rec.rname ~= "" and rec.rname) or rec.race or "",
		rec = rec,
	})
	Say("Saved " .. Clock(sheet.t) .. " so far.")
end

local function AskDelete(rec)
	if not rec or not ask then return end
	pendingRec = rec
	local who = rec.cname or rec.class or "this run"
	local where = rec.zname or rec.zone or ""
	local text = "Delete " .. Clock(Duration(rec)) .. "  " .. who
	if where ~= "" then text = text .. "  " .. where end
	askText:SetText(text .. "?")
	ask:SetFrameStrata("TOOLTIP")
	if ask.SetFrameLevel then ask:SetFrameLevel(100) end
	ask:Show()
	ask:Raise()
end

local function DoDelete()
	local rec = pendingRec
	pendingRec = nil
	if ask then ask:Hide() end
	if not rec or not RunStatsDB or not RunStatsDB.runs then return end
	local runs = RunStatsDB.runs
	local i
	for i = table.getn(runs), 1, -1 do
		if runs[i] == rec then tremove(runs, i) end
	end
	if rec.open == 1 and type(rec.id) == "string" then dropped[rec.id] = 1 end
	if pop and pop.rec == rec then pop:Hide() end
	anchorCache = nil
	Refresh()
end

local function BuildFilters()
	local function Tip(btn, title, a, b, c)
		btn:SetScript("OnEnter", function()
			this:SetBackdropBorderColor(1, 0.84, 0.3, 1)
			if not GameTooltip then return end
			GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
			GameTooltip:SetText(title, 1, 0.82, 0)
			if a then GameTooltip:AddLine(a, 1, 1, 1, 1) end
			if b then GameTooltip:AddLine(b, 0.9, 0.9, 0.85, 1) end
			if c then GameTooltip:AddLine(c, 0.9, 0.9, 0.85, 1) end
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function()
			this:SetBackdropBorderColor(0.55, 0.45, 0.2, 0.9)
			HideTip()
		end)
	end

	classBtn = MakeButton(frame, 110, 20)
	classBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -46)
	classBtn:SetScript("OnClick", function() ToggleClassMenu() end)
	Tip(classBtn, "Class filter",
		"All classes: every class in the list.",
		"Or pick one class.",
		"Default is your current class.")

	mapBtn = MakeButton(frame, 100, 20)
	mapBtn:SetPoint("LEFT", classBtn, "RIGHT", 6, 0)
	mapBtn:SetScript("OnClick", function() ToggleMapMenu() end)
	Tip(mapBtn, "Map filter",
		"All maps: every map in the list.",
		"Or pick one map.",
		"Default is your current map.")

	diffBtn = MakeButton(frame, 104, 20)
	diffBtn:SetPoint("LEFT", mapBtn, "RIGHT", 6, 0)
	diffBtn.label:SetText("Normal")
	diffBtn:SetScript("OnClick", function() ToggleDiffMenu() end)
	Tip(diffBtn, "Difficulty filter",
		"Any difficulty: every difficulty in the list.",
		"Or pick Normal through Heroic V.",
		"Default is the difficulty of your current run.")

	windowBtn = MakeButton(frame, 100, 20)
	windowBtn:SetPoint("LEFT", diffBtn, "RIGHT", 6, 0)
	windowBtn:SetScript("OnClick", function()
		HideDiffMenu()
		if RunStatsDB.full == 1 then RunStatsDB.full = nil else RunStatsDB.full = 1 end
		page = 1
		Refresh()
	end)
	Tip(windowBtn, "Full run / Endless",
		"Full run: stats up to when the final boss died.",
		"Endless: the whole session, including play after the win.",
		"Default is Endless.")

	local paceBtn = MakeButton(frame, 84, 20)
	paceBtn:SetPoint("LEFT", windowBtn, "RIGHT", 6, 0)
	paceBtn.label:SetText("Average")
	frame.paceBtn = paceBtn
	paceBtn:SetScript("OnClick", function()
		HideDiffMenu()
		if RunStatsDB.lastMin == 1 then RunStatsDB.lastMin = nil else RunStatsDB.lastMin = 1 end
		page = 1
		Refresh()
		PaintHeaders()
	end)
	Tip(paceBtn, "Average / Last min",
		"Average: K/min, XP/min, G/min and DPS for the whole sheet.",
		"Last min: those rates for the final minute only.",
		"Click to switch. A dash means last minute was not saved.")

	liveBtn = MakeButton(frame, 78, 20)
	liveBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -46)
	liveBtn.label:SetText("This run")
	liveBtn:SetScript("OnClick", function()
		HideDiffMenu()
		InspectCurrent()
	end)
	Tip(liveBtn, "This run",
		"Save a snapshot of the run you are in right now.",
		"It appears in the list (even under the min time) and opens Details.",
		"Use it mid-run to check pace, meter, and build.")

	local minBtn = MakeButton(frame, 72, 20)
	minBtn:SetPoint("RIGHT", liveBtn, "LEFT", -6, 0)
	minBtn.label:SetText(MinLabel())
	frame.minBtn = minBtn
	minBtn:SetScript("OnClick", function() ToggleMinMenu() end)
	Tip(minBtn, "Minimum run length",
		"Only show runs at least this many minutes long.",
		"0 minutes = show every run. Drag up to 16.",
		"This setting is kept between runs.")
end

local function BuildRows()
	headers = {}
	local c
	for c = 1, table.getn(COLS) do
		local col = COLS[c]
		local b = CreateFrame("Button", nil, frame)
		b:SetWidth(col.w)
		b:SetHeight(16)
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", col.x, -70)
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", b, "LEFT", 0, 0)
		fs:SetText(col.text)
		b.label = fs
		b.key = col.key
		b:SetScript("OnClick", function()
			HeaderClick(this.key)
			PaintHeaders()
		end)
		headers[c] = b
	end

	rows = {}
	local r
	for r = 1, CFG.PAGE do
		local holder = CreateFrame("Frame", nil, frame)
		holder:SetWidth(CFG.FRAME_W - 16)
		holder:SetHeight(CFG.ROW_H)
		holder:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -88 - (r - 1) * CFG.ROW_H)
		local bg = holder:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(holder)
		if math.mod(r, 2) == 0 then
			bg:SetTexture(0.16, 0.13, 0.07, 0.65)
		else
			bg:SetTexture(0.06, 0.05, 0.03, 0.4)
		end
		holder:EnableMouse(true)
		holder:SetScript("OnEnter", function() ShowTip(this.item) end)
		holder:SetScript("OnLeave", function() HideTip() end)
		local cells = {}
		for c = 1, table.getn(COLS) do
			local col = COLS[c]
			local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("LEFT", holder, "LEFT", col.x - 6, 0)
			fs:SetWidth(col.w)
			fs:SetJustifyH("LEFT")
			fs:SetTextColor(0.96, 0.93, 0.84)
			cells[c] = fs
		end
		local del = MakeButton(holder, 22, 18)
		del:SetPoint("RIGHT", holder, "RIGHT", -66, 0)
		del.label:SetText("X")
		del:SetScript("OnClick", function() AskDelete(this.rec) end)
		del:SetScript("OnEnter", function()
			this:SetBackdropBorderColor(0.85, 0.25, 0.2, 1)
		end)
		local btn = MakeButton(holder, 62, 18)
		btn:SetPoint("RIGHT", holder, "RIGHT", -2, 0)
		btn.label:SetText("Details")
		btn:SetScript("OnClick", function()
			pop.graphLast = nil
			OpenBuild(this)
		end)
		btn:SetScript("OnEnter", function()
			this:SetBackdropBorderColor(1, 0.84, 0.3, 1)
		end)
		rows[r] = { holder = holder, cells = cells, btn = btn, del = del }
	end
end

local function BuildList()
	frame = CreateFrame("Frame", "RunStatsFrame", UIParent)
	frame:SetWidth(CFG.FRAME_W)
	frame:SetHeight(430)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.88)
	frame:SetBackdropBorderColor(0.9, 0.75, 0.25, 0.95)
	frame:Hide()
	tinsert(UISpecialFrames, "RunStatsFrame")

	local drag = CreateFrame("Button", nil, frame)
	drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
	drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -64, -6)
	drag:SetHeight(18)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function() frame:StartMoving() end)
	drag:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local x = frame:GetLeft()
		local y = frame:GetTop()
		if x and y then
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
			SavePlace()
			if pop and pop:IsShown() then PlaceDetails() end
		else
			frame.placeWait = 1
			frame:SetScript("OnUpdate", function()
				if not this.placeWait then return end
				this.placeWait = nil
				this:SetScript("OnUpdate", nil)
				local left = this:GetLeft()
				local top = this:GetTop()
				if left and top then
					this:ClearAllPoints()
					this:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
					SavePlace()
					if pop and pop:IsShown() then PlaceDetails() end
				end
			end)
		end
	end)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", frame, "TOP", 0, -8)
	title:SetText("Run History")

	local close = MakeButton(frame, 52, 18)
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -6)
	close.label:SetText("Close")
	close:SetScript("OnClick", function() Toggle() end)

	sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -28)
	sub:SetTextColor(0.9, 0.85, 0.7)

	BuildFilters()
	BuildRows()

	prevBtn = MakeButton(frame, 28, 18)
	prevBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 8)
	prevBtn.label:SetText("<")
	prevBtn:SetScript("OnClick", function()
		if page > 1 then page = page - 1 end
		Refresh()
	end)
	nextBtn = MakeButton(frame, 28, 18)
	nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
	nextBtn.label:SetText(">")
	nextBtn:SetScript("OnClick", function()
		page = page + 1
		Refresh()
	end)
	pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pageText:SetPoint("LEFT", nextBtn, "RIGHT", 8, 0)
	pageText:SetTextColor(0.8, 0.75, 0.6)

	foot = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	foot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -96, 10)
	foot:SetJustifyH("RIGHT")
	foot:SetWidth(430)
	foot:SetTextColor(0.65, 0.6, 0.45)

	local resetBtn = MakeButton(frame, 78, 18)
	resetBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 8)
	resetBtn.label:SetText("Reset pos")
	resetBtn:SetScript("OnClick", function() ResetPlace() end)
end

local function BuildDetails()
	pop = CreateFrame("Frame", "RunStatsTalents", UIParent)
	pop:SetWidth(480)
	pop:SetHeight(420)
	pop:SetFrameStrata("DIALOG")
	pop:SetMovable(true)
	pop:EnableMouse(true)
	pop:SetClampedToScreen(true)
	pop:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	pop:SetBackdropColor(0.02, 0.02, 0.02, 0.96)
	pop:SetBackdropBorderColor(0.9, 0.75, 0.25, 0.95)
	pop:Hide()
	tinsert(UISpecialFrames, "RunStatsTalents")
	local popDrag = CreateFrame("Button", nil, pop)
	popDrag:SetPoint("TOPLEFT", pop, "TOPLEFT", 150, -6)
	popDrag:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -64, -6)
	popDrag:SetHeight(18)
	popDrag:RegisterForDrag("LeftButton")
	popDrag:SetScript("OnDragStart", function() pop:StartMoving() end)
	popDrag:SetScript("OnDragStop", function() pop:StopMovingOrSizing() end)
	popTitle = pop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	popTitle:SetPoint("TOP", pop, "TOP", -8, -8)
	popTitle:SetText("Details")
	local popDel = MakeButton(pop, 52, 18)
	popDel:SetPoint("TOPLEFT", pop, "TOPLEFT", 8, -6)
	popDel.label:SetText("Delete")
	popDel:SetScript("OnClick", function() AskDelete(pop.rec) end)
	statBtn = MakeButton(pop, 76, 18)
	statBtn:SetPoint("LEFT", popDel, "RIGHT", 4, 0)
	if RunStatsDB and RunStatsDB.allStats == 1 then
		statBtn.label:SetText("All stats")
	else
		statBtn.label:SetText("Core")
	end
	statBtn:SetScript("OnClick", function()
		if RunStatsDB.allStats == 1 then RunStatsDB.allStats = nil else RunStatsDB.allStats = 1 end
		if RunStatsDB.allStats == 1 then statBtn.label:SetText("All stats") else statBtn.label:SetText("Core") end
		if pop.view then
			pop.keepGraph = 1
			OpenBuild(pop.view)
		end
	end)
	local function MakeGraphBtn()
		local b = MakeButton(pop, 76, 16)
		b:Hide()
		b:SetScript("OnClick", function()
			if pop.graphLast == 1 then pop.graphLast = nil else pop.graphLast = 1 end
			pop.keepGraph = 1
			if popScroll and popScroll.GetVerticalScroll then pop.scrollAt = popScroll:GetVerticalScroll() end
			if pop.view then OpenBuild(pop.view) end
		end)
		return b
	end
	pop.dmgBtn = MakeGraphBtn()
	pop.takenBtn = MakeGraphBtn()
	local popClose = MakeButton(pop, 52, 18)
	popClose:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -8, -6)
	popClose.label:SetText("Close")
	popClose:SetScript("OnClick", function() pop:Hide() end)
	popScroll = CreateFrame("ScrollFrame", "RunStatsScroll", pop)
	popScroll:SetPoint("TOPLEFT", pop, "TOPLEFT", 12, -30)
	popScroll:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -26, 12)
	popChild = CreateFrame("Frame", "RunStatsScrollChild", popScroll)
	popChild:SetWidth(430)
	popChild:SetHeight(360)
	popScroll:SetScrollChild(popChild)
	popSlider = CreateFrame("Slider", "RunStatsScrollBar", pop)
	popSlider:SetWidth(12)
	popSlider:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -8, -32)
	popSlider:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -8, 12)
	popSlider:SetOrientation("VERTICAL")
	popSlider:SetMinMaxValues(0, 1)
	if popSlider.SetValueStep then popSlider:SetValueStep(15) end
	popSlider:SetValue(0)
	popSlider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	popSlider:SetScript("OnValueChanged", function()
		if this.busy then return end
		if popScroll then popScroll:SetVerticalScroll(this:GetValue()) end
	end)
	if popScroll.EnableMouseWheel then
		popScroll:EnableMouseWheel(1)
		popScroll:SetScript("OnMouseWheel", function()
			if not arg1 or not popSlider then return end
			local cur = popSlider:GetValue()
			local step = arg1
			if step > 0 then step = 45 else step = -45 end
			popSlider:SetValue(cur - step)
		end)
	end
end

local function BuildConfirm()
	ask = CreateFrame("Frame", "RunStatsConfirm", UIParent)
	ask:SetWidth(340)
	ask:SetHeight(100)
	ask:SetFrameStrata("TOOLTIP")
	if ask.SetFrameLevel then ask:SetFrameLevel(100) end
	ask:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
	ask:EnableMouse(true)
	ask:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	ask:SetBackdropColor(0.04, 0.02, 0.02, 0.97)
	ask:SetBackdropBorderColor(0.75, 0.25, 0.18, 0.95)
	ask:Hide()
	tinsert(UISpecialFrames, "RunStatsConfirm")
	ask:SetScript("OnHide", function() pendingRec = nil end)
	askText = ask:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	askText:SetPoint("TOP", ask, "TOP", 0, -18)
	askText:SetWidth(310)
	askText:SetJustifyH("CENTER")
	askText:SetText("Delete this run?")
	local yes = MakeButton(ask, 88, 22)
	yes:SetPoint("BOTTOMLEFT", ask, "BOTTOMLEFT", 28, 14)
	yes.label:SetText("Delete")
	yes:SetScript("OnClick", function() DoDelete() end)
	local no = MakeButton(ask, 88, 22)
	no:SetPoint("BOTTOMRIGHT", ask, "BOTTOMRIGHT", -28, 14)
	no.label:SetText("Cancel")
	no:SetScript("OnClick", function() ask:Hide() end)
end

local function BuildWindow()
	BuildList()
	BuildDetails()
	BuildConfirm()
	PlaceWindow()
	PaintHeaders()
end

local function PlaceMinimap()
	local btn = getglobal("RunStatsMinimapButton")
	if not btn then return end
	local angle = RunStatsDB.mmAngle or (-math.pi * 0.75)
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
end

local function BuildMinimap()
	if not Minimap then return end
	if getglobal("RunStatsMinimapButton") then
		PlaceMinimap()
		return
	end
	local btn = CreateFrame("Button", "RunStatsMinimapButton", Minimap)
	btn:SetWidth(31)
	btn:SetHeight(31)
	btn:SetFrameStrata("MEDIUM")
	local icon = btn:CreateTexture(nil, "BACKGROUND")
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
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
			RunStatsDB.mmAngle = math.atan2(py / s - my, px / s - mx)
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
		Toggle()
	end)
	btn:SetScript("OnEnter", function()
		if not GameTooltip then return end
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText("Run History")
		GameTooltip:AddLine("Left-click: open", 1, 1, 1)
		GameTooltip:AddLine("Drag: move", 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() HideTip() end)
	PlaceMinimap()
end

local sessionId = nil
local lastPh = nil

local function SyncPop(rec)
	if not rec or not pop or not pop:IsShown() or pop.rec ~= rec then return end
	local sheet = rec.atEnd or rec.preview
	if type(sheet) ~= "table" then return end
	if popScroll and popScroll.GetVerticalScroll then
		pop.scrollAt = popScroll:GetVerticalScroll()
	end
	pop.keepGraph = 1
	OpenBuild({
		sheet = sheet,
		race = (type(rec.rname) == "string" and rec.rname ~= "" and rec.rname) or rec.race or "",
		rec = rec,
	})
end

local function Tick()
	if not ready then return end
	local ph = Phase()
	local visible = frame and frame:IsShown()
	if not ph then
		if visible then Refresh() end
		return
	end
	local id = RunId()
	local sealed = nil
	if not id then
		if sessionId then
			local prev = FindRun(sessionId)
			if prev and prev.open == 1 and not prev.atEnd then
				Finish(prev)
				sealed = prev
			end
			sessionId = nil
		end
		if ph == "ready" and lastPh ~= "ready" then
			CloseOpen(nil)
			dropped = {}
			if pop and pop.rec and pop.rec.open ~= 1 then sealed = pop.rec end
		end
		lastPh = ph
		if sealed then SyncPop(sealed) end
		if visible then Refresh() end
		return
	end
	if dropped[id] then
		lastPh = ph
		if visible then Refresh() end
		return
	end
	if sessionId ~= id then
		sessionId = id
		ResetRoundFilters()
		anchorCache = nil
		lastOwed = 0
		CloseOpen(id)
	end
	local rec = FindRun(id)
	if not rec then rec = StartRun(id) end
	local t = RunTime()
	if rec.atEnd and (ph == "dead" or ph == "victory") then
		if Finish(rec) then SyncPop(rec) end
		lastPh = ph
		if visible then Refresh() end
		return
	end
	if rec.atEnd and (ph == "playing" or ph == "choosing" or ph == "paused") then
		local ended = Num(rec.tEnd)
		if ended <= 0 then ended = Num(rec.atEnd.t) end
		local endless = rec.result == "victory" and type(AZS_RUN) == "table" and Num(AZS_RUN.endl) == 1
		if not endless and (lastPh == "ready" or lastPh == nil or t + 15 < ended) then
			ArchiveRestart(rec)
			anchorCache = nil
		else
			if rec.result == "victory" then
				if not rec.at20 then rec.at20 = rec.atEnd end
				rec.atWin = rec.at20 or rec.atEnd
			else
				rec.told = nil
			end
			rec.atEnd = nil
			rec.result = nil
			rec.tEnd = nil
			rec.open = 1
		end
	end
	FillIdentity(rec)
	TrackXp(rec)
	Remember(rec, t)
	NotePace(rec, t)
	if rec.open == 1 and type(rec.preview) == "table" and type(rec.pending) == "table" then
		local sheet = rec.preview
		local p = rec.pending
		sheet.t = t
		sheet.fight = Num(rec.fight)
		sheet.kills = Num(p.kills)
		sheet.gold = Num(p.gold)
		sheet.xp = Num(p.xp)
		sheet.damage = Num(p.damage)
		sheet.lvl = Num(p.lvl)
		sheet.bosses = Num(p.bosses)
		sheet.guardians = Num(p.guardians)
		sheet.elites = Num(p.elites)
		sheet.takenTotal = Num(p.takenTotal)
		sheet.chests = Num(p.chests)
		ApplyLastMinute(sheet, rec)
		SyncPop(rec)
	end
	NoteMeter(rec, t)
	NoteHits(rec)
	TrackSpells(rec, t)
	local len = ZoneLength(rec)
	if Num(rec.len) <= 0 and len > 0 then rec.len = len end
	if t > 0 then rec.seenT = t end
	if rec.based ~= 1 and t > 0 and t < 30 then
		if not rec.baseTry or t - Num(rec.baseTry) >= 5 then
			rec.baseTry = t
			NoteBuild(rec, t, t < 8)
		end
	end
	local owed = 0
	if type(AZS_RUN) == "table" then owed = Num(AZS_RUN.owed) end
	if (lastPh == "choosing" and ph ~= "choosing") or owed < lastOwed then
		NoteBuild(rec, t, false)
		anchorCache = nil
	end
	lastOwed = owed
	lastPh = ph
	if ph == "dead" or ph == "victory" then
		Finish(rec)
		SyncPop(rec)
	end
	if visible then Refresh() end
end

local PerfCommand

do
local PERF_NAMES = { "tick", "refresh", "details", "meter", "build", "hits" }
local perf = nil
local perfStack = {}
local perfDepth = 0

-- Times are exclusive: a section nested in another is taken out of the outer one.
local function PerfMark()
	local ms = Num(debugprofilestop())
	local kb = Num(gcinfo())
	local d = kb - perf.lastKb
	if d < 0 then
		perf.gcs = perf.gcs + 1
		d = 0
	end
	perf.lastKb = kb
	if perfDepth > 0 then
		local e = perfStack[perfDepth]
		e.ms = e.ms + ms
		e.kb = e.kb + d
	end
	debugprofilestart()
end

local function PerfEnter(name)
	PerfMark()
	perfDepth = perfDepth + 1
	local e = perfStack[perfDepth]
	if not e then
		e = {}
		perfStack[perfDepth] = e
	end
	e.name = name
	e.ms = 0
	e.kb = 0
end

local function PerfLeave()
	PerfMark()
	local e = perfStack[perfDepth]
	perfDepth = perfDepth - 1
	local s = perf.sections[e.name]
	s.calls = s.calls + 1
	s.ms = s.ms + e.ms
	s.kb = s.kb + e.kb
	if e.ms > s.maxMs then s.maxMs = e.ms end
end

local function PerfWrap(name, fn)
	return function(a, b, c, d)
		if not perf then return fn(a, b, c, d) end
		PerfEnter(name)
		local ok, r1, r2 = pcall(fn, a, b, c, d)
		PerfLeave()
		if not ok then error(r1, 0) end
		return r1, r2
	end
end

Tick = PerfWrap("tick", Tick)
Refresh = PerfWrap("refresh", Refresh)
OpenBuild = PerfWrap("details", OpenBuild)
MeterRate = PerfWrap("meter", MeterRate)
ReadBuild = PerfWrap("build", ReadBuild)
NoteHits = PerfWrap("hits", NoteHits)

local function CountTables(t, seen)
	if seen[t] then return 0, 0 end
	seen[t] = 1
	local tables, values = 1, 0
	local k, v
	for k, v in pairs(t) do
		values = values + 1
		if type(v) == "table" then
			local a, b = CountTables(v, seen)
			tables = tables + a
			values = values + b
		end
	end
	return tables, values
end

local function PerfStart()
	if not debugprofilestart or not debugprofilestop or not gcinfo then
		Say("perf needs debugprofilestart, debugprofilestop and gcinfo, which this client lacks.")
		return
	end
	perf = { t0 = GetTime(), kb0 = Num(gcinfo()), lastKb = Num(gcinfo()), gcs = 0, sections = {} }
	local i
	for i = 1, table.getn(PERF_NAMES) do
		perf.sections[PERF_NAMES[i]] = { calls = 0, ms = 0, kb = 0, maxMs = 0 }
	end
	perfDepth = 0
	debugprofilestart()
	Say("perf started. Play a while, then /history perf show (keeps going) or /history perf (stops).")
end

local function PerfReport()
	local secs = GetTime() - perf.t0
	if secs < 1 then secs = 1 end
	local ph = Phase() or "none"
	local where = "window closed"
	if frame and frame:IsShown() then where = "window open" end
	if pop and pop:IsShown() then where = where .. ", details open" end
	Say(string.format("perf over %s, phase %s, %s.", Clock(secs), ph, where))
	local totalMs, totalKb = 0, 0
	local i
	for i = 1, table.getn(PERF_NAMES) do
		local name = PERF_NAMES[i]
		local s = perf.sections[name]
		totalMs = totalMs + s.ms
		totalKb = totalKb + s.kb
		if s.calls > 0 then
			Say(string.format("  %s: %d calls, %.2f ms/s, avg %.2f ms, max %.2f ms, %.1f KB/s",
				name, s.calls, s.ms / secs, s.ms / s.calls, s.maxMs, s.kb / secs))
		end
	end
	Say(string.format("  total: %.2f ms/s, %.1f KB/s made. Lua heap %d KB (was %d KB), %d cleanups seen.",
		totalMs / secs, totalKb / secs, Num(gcinfo()), perf.kb0, perf.gcs))
	if RunStatsDB then
		local tables, values = CountTables(RunStatsDB, {})
		Say(string.format("  saved data: %d runs, %d tables, %d values.",
			table.getn(RunStatsDB.runs or {}), tables, values))
	end
end

PerfCommand = function(rest)
	if rest == "show" then
		if perf then PerfReport() else Say("perf is not running. /history perf starts it.") end
		return
	end
	if perf then
		PerfReport()
		perf = nil
		Say("perf stopped.")
	else
		PerfStart()
	end
end
end

local elapsed = 0
local driver = CreateFrame("Frame", "RunStatsDriver")
driver:RegisterEvent("VARIABLES_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function()
	if event == "VARIABLES_LOADED" then
		InitDB()
		if not frame then BuildWindow() end
		BuildMinimap()
		ready = true
	elseif event == "PLAYER_LOGIN" then
		if not getglobal("RunStatsMinimapButton") then BuildMinimap() end
		if not told then
			told = true
			Say("loaded. /history opens the list. The minimap button opens it too.")
		end
	end
end)
driver:SetScript("OnUpdate", function()
	elapsed = elapsed + (arg1 or 0)
	if elapsed < 1 then return end
	elapsed = 0
	Tick()
end)

SLASH_RUNSTATS1 = "/history"
SlashCmdList["RUNSTATS"] = function(msg)
	if not ready then
		Say("still loading.")
		return
	end
	local cmd = string.lower(msg or "")
	cmd = string.gsub(cmd, "^%s+", "")
	cmd = string.gsub(cmd, "%s+$", "")
	if string.sub(cmd, 1, 4) == "perf" then
		local rest = string.gsub(string.sub(cmd, 5), "^%s+", "")
		PerfCommand(rest)
		return
	end
	Toggle()
end
