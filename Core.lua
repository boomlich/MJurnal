local ADDON, MJ = ...
_G.MJurnal = MJ

MJ.name = ADDON
MJ.UI = {}
MJ.Stats = {}

-- Journal tabs (also the index of each view in MJ.UI.views)
MJ.UI.TAB_OVERVIEW, MJ.UI.TAB_MONSTERS, MJ.UI.TAB_LOOT, MJ.UI.TAB_HISTORY = 1, 2, 3, 4

local floor, format, tonumber, type = math.floor, string.format, tonumber, type

---------------------------------------------------------------------------
-- Secret-value helpers (WoW Forever runs on the Midnight engine rules)
---------------------------------------------------------------------------
local issecretvalue = issecretvalue or function() return false end
MJ.issecret = issecretvalue

-- Returns v, or nil when v is a secret value we are not allowed to inspect.
function MJ.S(v)
	if issecretvalue(v) then return nil end
	return v
end
local S = MJ.S

function MJ.SafeGUID(unit)
	if not unit or issecretvalue(unit) then return nil end
	if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
		local ok, secret = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
		if ok and S(secret) then return nil end
	end
	local ok, guid = pcall(UnitGUID, unit)
	if not ok then return nil end
	return S(guid)
end

-- Creature-0-[server]-[instance]-[zone]-[npcID]-[spawnUID]
function MJ.ParseGUID(guid)
	if type(guid) ~= "string" then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	if kind == "Creature" or kind == "Vehicle" then
		return tonumber(id), kind
	end
	return nil, kind
end

function MJ.UnitNPC(unit)
	local guid = MJ.SafeGUID(unit)
	if not guid then return nil end
	return (MJ.ParseGUID(guid)), guid
end

---------------------------------------------------------------------------
-- Events & internal messages
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function MJ:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		-- events this client does not have are skipped instead of raising an error
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	handlers[event][#handlers[event] + 1] = fn
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		xpcall(list[i], geterrorhandler(), ...)
	end
end)

local listeners = {}
function MJ:Listen(msg, fn)
	listeners[msg] = listeners[msg] or {}
	listeners[msg][#listeners[msg] + 1] = fn
end

function MJ:Fire(msg, ...)
	local list = listeners[msg]
	if not list then return end
	for i = 1, #list do
		xpcall(list[i], geterrorhandler(), ...)
	end
end

function MJ:Changed()
	self.globalDirty = true
	self:Fire("DATA_CHANGED")
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local DEFAULT_SETTINGS = {
	unitTooltip = true,   -- line on NPC tooltips
	itemTooltip = true,   -- line on item tooltips
	milestones = true,    -- chat message on kill milestones
	dropAlerts = true,    -- chat message on rare drops
	newEntries = true,    -- chat message on new monsters / notable new items
	rareAlerts = true,    -- chat message when a rare is spotted
	minimapButton = true, -- show the minimap button
	minimapAngle = 215,   -- position of the minimap button (degrees)
	fadeMoving = true,    -- fade the journal while the player moves
	fadeAlpha = 0.35,     -- journal opacity while moving
	logQuality = 2,       -- log drops of this quality or better (2 = uncommon)
	alertRate = 0.05,     -- drops with a rate at or below this are "rare drops"
	debug = false,
}

function MJ:InitDB()
	MJurnalDB = MJurnalDB or {}
	local db = MJurnalDB
	db.version = db.version or 1
	db.settings = db.settings or {}
	for k, v in pairs(DEFAULT_SETTINGS) do
		if db.settings[k] == nil then db.settings[k] = v end
	end
	db.npcs = db.npcs or {}
	db.items = db.items or {}
	db.chars = db.chars or {}
	db.days = db.days or {}
	db.totals = db.totals or {}
	db.fishing = db.fishing or {}
	db.rares = db.rares or {}
	db.log = db.log or {}
	db.recent = db.recent or {}
	db.recent.kills = db.recent.kills or {}
	db.recent.loot = db.recent.loot or {}
	db.ui = db.ui or {}
	db.deathZones = db.deathZones or {}
	db.deathEnv = db.deathEnv or {}
	db.streak = db.streak or { cur = 0, best = 0 }
	self.db = db
	self:Migrate()
	self:PruneRecent()
end

local function dec(t, key, amount)
	if t and t[key] then t[key] = math.max(0, t[key] - (amount or 1)) end
end

function MJ:Migrate()
	local db = self.db
	if db.version < 2 then
		-- v1 could record one death twice (PLAYER_DEAD fired twice). Remove duplicate
		-- death log entries (same time, character and killer) and undo their counters.
		-- Each PLAYER_DEAD logged one entry per killer and bumped "deaths" once, so the number
		-- of extra events at a moment is the highest repeat count of any killer at that moment.
		local seen, extraEvents, kept = {}, {}, {}
		for _, e in ipairs(db.log) do
			local dup = false
			if e.k == "death" then
				local moment = tostring(e.t) .. "|" .. tostring(e.c)
				local key = moment .. "|" .. tostring(e.npc)
				seen[key] = (seen[key] or 0) + 1
				if seen[key] > 1 then
					dup = true
					if e.npc and db.npcs[e.npc] then dec(db.npcs[e.npc], "deathsTo") end
					local m = extraEvents[moment]
					if not m then
						m = { t = e.t, c = e.c, n = 0 }
						extraEvents[moment] = m
					end
					m.n = math.max(m.n, seen[key] - 1)
				end
			end
			if not dup then kept[#kept + 1] = e end
		end
		for _, m in pairs(extraEvents) do
			dec(db.totals, "deaths", m.n)
			dec(db.days[tonumber(date("%Y%m%d", m.t))], "deaths", m.n)
			dec(db.chars[m.c], "deaths", m.n)
		end
		db.log = kept
		db.version = 2
	end
	if db.version < 3 then
		-- v2 could leave a kill half-written (no npc id), so a corpse could be looted
		-- without its kill being counted. A corpse is always at least one kill.
		for _, n in pairs(db.npcs) do
			local missing = (n.looted or 0) + (n.empty or 0) - (n.kills or 0)
			if missing > 0 then
				n.kills = n.kills + missing
				db.totals.kills = (db.totals.kills or 0) + missing
			end
		end
		for guid, r in pairs(db.recent.kills) do
			if r.n == nil then db.recent.kills[guid] = nil end
			if r.s == "other" then r.s = "pending" end
		end
		db.version = 3
	end
	if db.version < 4 then
		-- v4 adds per-zone death counts and first/last death per killer; rebuild them from the log
		-- (one death per time + character, as v1-v3 logged one entry per attacker).
		local seenDeath = {}
		for _, e in ipairs(db.log) do
			if e.k == "death" then
				local key = tostring(e.t) .. "|" .. tostring(e.c)
				if not seenDeath[key] then
					seenDeath[key] = true
					if e.z and e.z ~= "" then db.deathZones[e.z] = (db.deathZones[e.z] or 0) + 1 end
					db.streak.lastDeath = math.max(db.streak.lastDeath or 0, e.t or 0)
				end
				local n = e.npc and db.npcs[e.npc]
				if n then
					local stamp = { t = e.t, c = e.c, z = e.z }
					if not n.firstDeathTo or n.firstDeathTo.t > e.t then n.firstDeathTo = stamp end
					if not n.lastDeathTo or n.lastDeathTo.t < e.t then n.lastDeathTo = stamp end
				end
			end
		end
		db.version = 4
	end
end

-- Dedupe tables survive /reload but are only needed for a short while.
function MJ:PruneRecent()
	local cutoff = time() - 1800
	for guid, r in pairs(self.db.recent.kills) do
		if (r.t or 0) < cutoff then self.db.recent.kills[guid] = nil end
	end
	for guid, t in pairs(self.db.recent.loot) do
		if t < cutoff then self.db.recent.loot[guid] = nil end
	end
end

function MJ:ResetAll()
	local settings, ui = self.db.settings, self.db.ui
	wipe(MJurnalDB)
	MJurnalDB.settings, MJurnalDB.ui = settings, ui
	self:InitDB()
	self:Changed()
end

---------------------------------------------------------------------------
-- Session, characters, counters
---------------------------------------------------------------------------
MJ.session = { start = time(), npcKills = {} }

function MJ.DayKey(t)
	return tonumber(date("%Y%m%d", t or time()))
end

function MJ:CharData()
	local key = self.charKey or "?"
	local c = self.db.chars[key]
	if not c then
		c = {}
		self.db.chars[key] = c
	end
	return c
end

-- Adds to the day bucket, the character, the session and the account totals.
function MJ:Bump(field, amount)
	amount = amount or 1
	local dk = self.DayKey()
	local d = self.db.days[dk]
	if not d then
		d = {}
		self.db.days[dk] = d
	end
	d[field] = (d[field] or 0) + amount
	local c = self:CharData()
	c[field] = (c[field] or 0) + amount
	self.session[field] = (self.session[field] or 0) + amount
	self.db.totals[field] = (self.db.totals[field] or 0) + amount
end

---------------------------------------------------------------------------
-- Item info
---------------------------------------------------------------------------
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemIconByID = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID

function MJ.ItemInfo(id)
	if not id then return nil end
	return GetItemInfo(id)
end

-- Fills name/link/quality/icon/sell price on the journal item when known.
function MJ:CacheItem(itemId, link)
	local g = self.db.items[itemId]
	if not g then return end
	if link and not g.link then g.link = link end
	if g.name and g.sell and g.icon and g.classId then return end
	local name, ilink, quality, _, _, itemType, subType, _, _, icon, sell, classId = GetItemInfo(itemId)
	if name then
		g.name = name
		g.link = ilink or g.link
		g.quality = quality or g.quality
		g.icon = icon or g.icon
		g.sell = sell or g.sell or 0
		g.itype, g.isub, g.classId = itemType, subType, classId
	else
		g.icon = g.icon or (GetItemIconByID and GetItemIconByID(itemId))
		if RequestLoad then pcall(RequestLoad, itemId) end
		self.pendingItems = self.pendingItems or {}
		self.pendingItems[itemId] = true
	end
end

function MJ:ItemIcon(itemId)
	local g = self.db.items[itemId]
	return (g and g.icon) or (GetItemIconByID and GetItemIconByID(itemId)) or 134400
end

function MJ.SpellName(spellID)
	if not spellID then return nil end
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
	if GetSpellInfo then return (GetSpellInfo(spellID)) end
end

local function OnItemData(itemId, success)
	if not MJ.db or not MJ.pendingItems or not MJ.pendingItems[itemId] then return end
	MJ.pendingItems[itemId] = nil
	if success == false then return end
	MJ:CacheItem(itemId)
	MJ:Changed()
end
MJ:On("GET_ITEM_INFO_RECEIVED", OnItemData)
MJ:On("ITEM_DATA_LOAD_RESULT", OnItemData)

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

function MJ.Num(n, decimals)
	if n == nil then return "-" end
	if decimals and n ~= floor(n) then
		return format("%." .. decimals .. "f", n)
	end
	n = floor(n + 0.5)
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
	return tostring(n)
end

function MJ.Money(c)
	if c == nil then return "-" end
	c = floor(c + 0.5)
	local g, s, co = floor(c / 10000), floor(c / 100) % 100, c % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = MJ.Num(g) .. GOLD_ICON end
	if s > 0 then parts[#parts + 1] = s .. SILVER_ICON end
	if co > 0 or #parts == 0 then parts[#parts + 1] = co .. COPPER_ICON end
	return table.concat(parts, " ")
end

function MJ.Pct(p)
	if p == nil then return "-" end
	local v = p * 100
	if v >= 10 or v == 0 then return format("%.1f%%", v) end
	if v >= 1 then return format("%.2f%%", v) end
	return format("%.3f%%", v)
end

function MJ.Dur(sec)
	if sec == nil then return "-" end
	if sec < 60 then return format("%.1fs", sec) end
	if sec < 3600 then return format("%dm %02ds", floor(sec / 60), floor(sec % 60)) end
	if sec < 86400 then return format("%dh %02dm", floor(sec / 3600), floor(sec % 3600 / 60)) end
	return format("%dd %02dh", floor(sec / 86400), floor(sec % 86400 / 3600))
end

function MJ.Date(t)
	if not t then return "-" end
	return date("%Y-%m-%d %H:%M", t)
end

function MJ.Ago(t)
	if not t then return "-" end
	local d = time() - t
	if d < 60 then return "just now" end
	if d < 3600 then return floor(d / 60) .. "m ago" end
	if d < 86400 then return floor(d / 3600) .. "h ago" end
	return floor(d / 86400) .. "d ago"
end

local QUALITY_FALLBACK = {
	[0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd",
	[4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff",
}
function MJ.QualityHex(q)
	q = q or 1
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c and c.hex then return c.hex end
	return "|c" .. (QUALITY_FALLBACK[q] or "ffffffff")
end

function MJ.QualityName(q)
	return (q and _G["ITEM_QUALITY" .. q .. "_DESC"]) or "?"
end

function MJ:ItemText(itemId)
	local g = self.db.items[itemId]
	if g and g.link then return g.link end
	local name = (g and g.name) or ("Item #" .. itemId)
	return MJ.QualityHex(g and g.quality) .. name .. "|r"
end

function MJ:NPCName(npcId)
	local n = self.db.npcs[npcId]
	return (n and n.name) or (self.meta and self.meta[npcId] and self.meta[npcId].name) or ("NPC #" .. tostring(npcId))
end

function MJ:CharName(key)
	if not key then return "-" end
	local c = self.db.chars[key]
	local name = key:match("^[^-]+") or key
	if c and c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class] then
		return "|c" .. RAID_CLASS_COLORS[c.class].colorStr .. name .. "|r"
	end
	return name
end

-- Turns a localized format string ("%s dies, you gain %d experience.") into a Lua pattern.
function MJ.FormatToPattern(fmt)
	if not fmt then return nil end
	fmt = fmt:gsub("%%%d%$", "%%")
	local p = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	p = p:gsub("%%s", "(.-)"):gsub("%%d", "([%%d,%%.]+)")
	return "^" .. p
end

local moneyPatterns
function MJ.ParseMoney(text)
	if not text then return nil end
	if not moneyPatterns then
		moneyPatterns = {}
		local function add(fmt, mult, fallback)
			fmt = fmt or fallback
			local p = fmt:gsub("%%d", "(%%d+)")
			moneyPatterns[#moneyPatterns + 1] = { p, mult }
		end
		add(GOLD_AMOUNT, 10000, "%d Gold")
		add(SILVER_AMOUNT, 100, "%d Silver")
		add(COPPER_AMOUNT, 1, "%d Copper")
	end
	local total, found = 0, false
	for _, mp in ipairs(moneyPatterns) do
		local v = text:match(mp[1])
		if v then
			total = total + tonumber(v) * mp[2]
			found = true
		end
	end
	return found and total or nil
end

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------
local PREFIX = "|cffd4a017MJurnal|r: "
function MJ:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
end

function MJ:Debug(msg, ...)
	if self.db and self.db.settings.debug then
		DEFAULT_CHAT_FRAME:AddMessage("|cff888888MJ debug:|r " .. format(msg, ...))
	end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
MJ:On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	MJ:InitDB()
	MJ:Fire("DB_READY")
end)

MJ:On("PLAYER_LOGIN", function()
	local name, realm = UnitFullName("player")
	realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
	MJ.charKey = (name or "?") .. "-" .. (realm or "?")
	local c = MJ:CharData()
	c.class = select(2, UnitClass("player"))
	MJ.session.start = time()
	MJ:Fire("LOGIN")
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function toggleSetting(key, label)
	MJ.db.settings[key] = not MJ.db.settings[key]
	MJ:Print(label .. ": " .. (MJ.db.settings[key] and "|cff20ff20on|r" or "|cffff2020off|r"))
	MJ:Fire("SETTING_CHANGED", key)
end

SLASH_MJURNAL1 = "/mj"
SLASH_MJURNAL2 = "/mjurnal"
SlashCmdList.MJURNAL = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		MJ.UI:Toggle()
	elseif cmd == "help" then
		MJ:Print("/mj - toggle journal")
		MJ:Print("/mj <text> - search monsters (falls back to loot)")
		MJ:Print("/mj loot <text> - search loot")
		MJ:Print("/mj overview | history - open a tab")
		MJ:Print("/mj session - print this session's numbers")
		MJ:Print("/mj tooltip | itemtooltip | alerts | milestones | minimap | fade - toggle features")
		MJ:Print("/mj fade <percent> - opacity while moving, e.g. /mj fade 30")
		MJ:Print("/mj options - open settings")
		MJ:Print("/mj debug - toggle detection debug messages")
	elseif cmd == "debug" then
		toggleSetting("debug", "Debug")
	elseif cmd == "tooltip" then
		toggleSetting("unitTooltip", "NPC tooltip line")
	elseif cmd == "itemtooltip" then
		toggleSetting("itemTooltip", "Item tooltip line")
	elseif cmd == "alerts" then
		toggleSetting("dropAlerts", "Rare drop alerts")
	elseif cmd == "milestones" then
		toggleSetting("milestones", "Milestone messages")
	elseif cmd == "minimap" then
		toggleSetting("minimapButton", "Minimap button")
	elseif cmd == "fade" then
		local pct = tonumber(rest)
		if pct then
			MJ.db.settings.fadeAlpha = math.max(0.05, math.min(1, pct / 100))
			MJ.db.settings.fadeMoving = true
			MJ:Print(format("Opacity while moving: %d%%", math.floor(MJ.db.settings.fadeAlpha * 100 + 0.5)))
		else
			toggleSetting("fadeMoving", "Fade while moving")
		end
	elseif cmd == "options" or cmd == "config" or cmd == "settings" then
		MJ.UI:OpenSettings()
	elseif cmd == "overview" then
		MJ.UI:Open(MJ.UI.TAB_OVERVIEW)
	elseif cmd == "history" then
		MJ.UI:Open(MJ.UI.TAB_HISTORY)
	elseif cmd == "loot" then
		MJ.UI:Search(MJ.UI.TAB_LOOT, rest)
	elseif cmd == "session" then
		local s = MJ.session
		local hours = max((time() - s.start) / 3600, 1 / 60)
		MJ:Print(format("Session %s: %s kills (%s/h), %s corpses, %s gold, %s vendor value, %s XP",
			MJ.Dur(time() - s.start), MJ.Num(s.kills or 0), MJ.Num((s.kills or 0) / hours),
			MJ.Num(s.corpses or 0), MJ.Money(s.money or 0), MJ.Money(s.vendor or 0), MJ.Num(s.xp or 0)))
	else
		MJ.UI:Search(MJ.UI.TAB_MONSTERS, msg)
	end
end

---------------------------------------------------------------------------
-- Key bindings & addon compartment
---------------------------------------------------------------------------
BINDING_HEADER_MJURNAL = "MJurnal"
BINDING_NAME_MJURNAL_TOGGLE = "Toggle journal"
BINDING_NAME_MJURNAL_MOUSEOVER = "Open journal for mouseover NPC"

function MJurnal_Toggle()
	MJ.UI:Toggle()
end

function MJurnal_OpenMouseover()
	local unit = "mouseover"
	local npcId = MJ.UnitNPC(unit)
	if not npcId then
		unit = "target"
		npcId = MJ.UnitNPC(unit)
	end
	if not npcId then
		MJ:Print("Mouse over (or target) an NPC first.")
		return
	end
	if MJ.db.npcs[npcId] then
		MJ.UI:Open(MJ.UI.TAB_MONSTERS, npcId)
	else
		local name = S(UnitName(unit)) or MJ:NPCName(npcId)
		MJ:Print(format("No journal data for %s yet - kill or loot one first.", name))
	end
end

function MJurnal_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then
		MJ.UI:OpenSettings()
	else
		MJ.UI:Toggle()
	end
end

function MJurnal_OnAddonCompartmentEnter(_, frame)
	GameTooltip:SetOwner(frame or UIParent, "ANCHOR_LEFT")
	MJ.UI.FillLauncherTooltip(GameTooltip)
	GameTooltip:Show()
end

function MJurnal_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
