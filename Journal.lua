-- Journal.lua: every write into MJurnalDB goes through here.
local _, MJ = ...
local S = MJ.S
local GetTime, time, floor, min, max = GetTime, time, math.floor, math.min, math.max

function MJ.ZoneInfo()
	local zone = GetRealZoneText and S(GetRealZoneText()) or ""
	local sub = GetSubZoneText and S(GetSubZoneText()) or ""
	return zone or "", sub or ""
end

---------------------------------------------------------------------------
-- NPC entries
---------------------------------------------------------------------------
MJ.meta = MJ.meta or {}   -- session cache of what we saw on units: [npcId] = {name, class, type, family}

function MJ:GetNPC(npcId, create)
	local n = self.db.npcs[npcId]
	if not n and create then
		n = {
			kills = 0, looted = 0, empty = 0, money = 0, moneyCorpses = 0,
			items = {}, byChar = {}, zones = {}, days = {}, firstSeen = time(),
		}
		self.db.npcs[npcId] = n
		self:ApplyMeta(npcId)
		self:OnNewNPC(npcId, n)
	end
	return n
end

function MJ:ApplyMeta(npcId)
	local n, m = self.db.npcs[npcId], self.meta[npcId]
	if not n or not m then return end
	if m.name then n.name = m.name end
	if m.class then n.class = m.class end
	if m.type then n.type = m.type end
	if m.family then n.family = m.family end
end

function MJ:SamplePosition(n)
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
	local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = ok and S(mapID)
	if not mapID then return end
	local ok2, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
	if not ok2 or not pos then return end
	local ok3, x, y = pcall(pos.GetXY, pos)
	x, y = ok3 and S(x), ok3 and S(y)
	if not x or not y or (x == 0 and y == 0) then return end
	n.pos = n.pos or {}
	local list = n.pos[mapID]
	if not list then
		list = {}
		n.pos[mapID] = list
	end
	local entry = { floor(x * 1000 + 0.5) / 1000, floor(y * 1000 + 0.5) / 1000 }
	if #list < 30 then
		list[#list + 1] = entry
	else
		list[math.random(1, 30)] = entry
	end
end

---------------------------------------------------------------------------
-- Kills
---------------------------------------------------------------------------
MJ.recentKills = {}  -- last kills this session, for XP / reputation attribution

-- info = { source = "unit"|"xp"|"loot", start = GetTime() of engagement, level, name }
function MJ:RecordKill(guid, npcId, info)
	-- never let a secret or malformed id reach the tables (it would leave a half-written kill)
	if type(guid) ~= "string" or type(npcId) ~= "number" or self.issecret(guid) or self.issecret(npcId) then
		return false
	end
	local recent = self.db.recent.kills
	if recent[guid] then return false end
	info = info or {}
	local now = time()
	recent[guid] = { t = now, n = npcId, s = "pending" }

	local n = self:GetNPC(npcId, true)
	self:ApplyMeta(npcId)
	if info.name and not n.name then n.name = info.name end

	n.kills = n.kills + 1
	local ck = self.charKey or "?"
	n.byChar[ck] = (n.byChar[ck] or 0) + 1
	if IsInGroup() then
		n.groupKills = (n.groupKills or 0) + 1
	else
		n.soloKills = (n.soloKills or 0) + 1
	end
	if info.source == "loot" then n.lootDetected = (n.lootDetected or 0) + 1 end

	-- where
	local zone, sub = MJ.ZoneInfo()
	if zone ~= "" then
		local z = n.zones[zone]
		if not z then
			z = { kills = 0, sub = {} }
			n.zones[zone] = z
		end
		z.kills = z.kills + 1
		if sub ~= "" then z.sub[sub] = (z.sub[sub] or 0) + 1 end
	end
	self:SamplePosition(n)

	-- when
	local dk = self.DayKey(now)
	n.days[dk] = (n.days[dk] or 0) + 1
	local stamp = { t = now, c = ck, z = zone }
	if not n.firstKill then n.firstKill = stamp end
	n.lastKill = stamp

	-- levels
	local lvl = info.level
	if lvl and lvl > 0 then
		n.minLvl = min(n.minLvl or lvl, lvl)
		n.maxLvl = max(n.maxLvl or lvl, lvl)
	end
	local my = S(UnitLevel("player"))
	if my then
		n.myMin = min(n.myMin or my, my)
		n.myMax = max(n.myMax or my, my)
		if lvl and lvl > 0 then
			n.diffSum = (n.diffSum or 0) + (my - lvl)
			n.diffN = (n.diffN or 0) + 1
		end
	end

	-- combat duration (from engagement to death)
	if info.start then
		local d = GetTime() - info.start
		if d >= 0 and d < 900 then
			n.ttkSum = (n.ttkSum or 0) + d
			n.ttkN = (n.ttkN or 0) + 1
			n.ttkMin = min(n.ttkMin or d, d)
			n.ttkMax = max(n.ttkMax or d, d)
		end
	end

	-- counters
	self:Bump("kills")
	local sk = self.session.npcKills
	sk[npcId] = (sk[npcId] or 0) + 1
	if sk[npcId] > (n.bestSession or 0) then n.bestSession = sk[npcId] end

	local rk = { npc = npcId, guid = guid, name = n.name, t = GetTime() }
	self.lastKill = rk
	table.insert(self.recentKills, rk)
	if #self.recentKills > 20 then table.remove(self.recentKills, 1) end
	self:ClaimPendingXP()
	self:Fire("KILL", npcId, n.name)

	if n.class == "rare" or n.class == "rareelite" then
		self:Log({ k = "rarekill", npc = npcId, z = zone })
	end
	self:CheckKillMilestones(npcId, n)
	if info.source ~= "loot" then self:ScheduleLootCheck(guid, npcId) end

	self:Debug("kill %s (%d) via %s", n.name or "?", npcId, info.source or "?")
	self:Changed()
	return true
end

-- Corpse states in db.recent.kills: "pending" (outcome unknown), "empty" (no loot at all),
-- "looted". Corpses with no loot count as "empty" so drop rates are per corpse.
local function isOpen(r)
	-- "other" was written by v1 (misread canLoot); treat it like pending
	return r and (r.s == "pending" or r.s == "other")
end

function MJ:MarkEmpty(guid, why)
	local r = self.db.recent.kills[guid]
	if not isOpen(r) or not r.n then return end
	r.s = "empty"
	local n = self.db.npcs[r.n]
	if n then n.empty = n.empty + 1 end
	self:Bump("corpses")
	self:Debug("empty corpse %s (%s)", self:NPCName(r.n), why)
	self:Changed()
end

-- The client said the corpse has loot after all (loot can appear a moment after death).
function MJ:UnmarkEmpty(guid)
	local r = self.db.recent.kills[guid]
	if not r or r.s ~= "empty" or not r.n then return end
	r.s = "pending"
	local n = self.db.npcs[r.n]
	if n then n.empty = max(0, n.empty - 1) end
	self:Bump("corpses", -1)
	self:Changed()
end

-- UNIT_LOOT(unitGUID, hasLoot): the client's own notification of a corpse's loot state.
function MJ:OnUnitLoot(guid, hasLoot)
	if guid == nil or self.issecret(guid) or self.issecret(hasLoot) then return end
	local r = self.db.recent.kills[guid]
	if not r then return end
	if hasLoot == false then
		-- only right after the kill: later on a corpse can lose its loot by despawning
		if time() - (r.t or 0) > 15 then return end
		self:MarkEmpty(guid, "UNIT_LOOT")
	elseif hasLoot == true then
		self:UnmarkEmpty(guid)
	end
end

-- Fallback poll after a kill. Only hasLoot matters: canLoot is false when you are simply
-- out of range of the corpse (e.g. a kill at spell range), so it says nothing about ownership.
function MJ:ScheduleLootCheck(guid, npcId)
	if not CanLootUnit or not C_Timer then return end
	local misses = 0
	local function check()
		if not isOpen(self.db.recent.kills[guid]) then return end
		local ok, hasLoot = pcall(CanLootUnit, guid)
		if not ok then return end
		hasLoot = S(hasLoot)
		if hasLoot == false then
			misses = misses + 1
			if misses < 2 then
				C_Timer.After(2, check)
				return
			end
			self:MarkEmpty(guid, "CanLootUnit")
		end
	end
	C_Timer.After(1.5, check)
end

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------
-- src = { items = { [itemId] = { q, link, quality, quest } }, money = copper, name, level }
function MJ:RecordCorpseLoot(guid, npcId, src)
	local recentLoot = self.db.recent.loot
	if recentLoot[guid] then return end
	recentLoot[guid] = time()

	local r = self.db.recent.kills[guid]
	if r and r.n == nil then
		-- half-written kill from v1 (see RecordKill guard): redo it properly
		self.db.recent.kills[guid] = nil
		r = nil
	end
	if not r then
		self:RecordKill(guid, npcId, { source = "loot", name = src.name, level = src.level })
		r = self.db.recent.kills[guid]
		if not r then return end
	end
	local n = self:GetNPC(npcId, true)
	if src.name and not n.name then n.name = src.name end
	if r.s == "empty" then
		n.empty = max(0, n.empty - 1)
		self:Bump("corpses", -1)
	end
	r.s = "looted"

	n.looted = n.looted + 1
	self:Bump("corpses")
	local corpseIdx = n.looted + n.empty

	local hasItems = next(src.items) ~= nil
	local money = src.money or 0
	if money > 0 then
		n.money = n.money + money
		n.moneyCorpses = n.moneyCorpses + 1
		n.moneyMin = min(n.moneyMin or money, money)
		n.moneyMax = max(n.moneyMax or money, money)
		self:Bump("money", money)
		if not hasItems then n.moneyOnly = (n.moneyOnly or 0) + 1 end
	elseif not hasItems then
		n.nothing = (n.nothing or 0) + 1
	end

	local vendor = 0
	for itemId, e in pairs(src.items) do
		vendor = vendor + self:RecordNPCItemDrop(n, npcId, itemId, e, corpseIdx)
	end
	if vendor > 0 then self:Bump("vendor", vendor) end
	self:Debug("looted %s: %d item types, %d copper", n.name or "?", self.Count(src.items), money)
	self:Changed()
end

function MJ.Count(t)
	local c = 0
	for _ in pairs(t) do c = c + 1 end
	return c
end

function MJ:RecordNPCItemDrop(n, npcId, itemId, e, corpseIdx)
	local it = n.items[itemId]
	if not it then
		it = { drops = 0, qty = 0 }
		n.items[itemId] = it
	end
	local prev = corpseIdx - 1
	local gap = corpseIdx - (it.lastAt or 0)
	-- luck: how many corpses we "expected" this to take (from earlier data) vs how many it took
	if it.drops >= 2 and prev > 0 then
		local expected = prev / it.drops
		it.luckSum = (it.luckSum or 0) + expected / gap
		it.luckN = (it.luckN or 0) + 1
	end
	it.drops = it.drops + 1
	it.qty = it.qty + e.q
	it.sMin = min(it.sMin or e.q, e.q)
	it.sMax = max(it.sMax or e.q, e.q)
	it.dryMax = max(it.dryMax or 0, gap - 1)
	it.gapMin = min(it.gapMin or gap, gap)
	it.lastAt = corpseIdx
	it.lastT = time()
	if not it.firstT then
		it.firstT = it.lastT
		it.firstAt = corpseIdx
	end
	if e.quest then it.quest = true end

	local g = self:RecordGlobalItem(itemId, e, npcId, "npc")
	g.src = g.src or {}
	g.src[npcId] = true
	self:OnItemDrop(npcId, n, itemId, it, gap, e)
	return (g.sell or 0) * e.q
end

-- Account-wide item entry (loot journal side).
function MJ:RecordGlobalItem(itemId, e, npcId, kind)
	local g = self.db.items[itemId]
	local isNew = not g
	if not g then
		g = { drops = 0, qty = 0 }
		self.db.items[itemId] = g
	end
	if e.link and not g.link then g.link = e.link end
	if e.quality then g.quality = e.quality end
	if e.quest then g.quest = true end
	self:CacheItem(itemId, e.link)
	g.drops = g.drops + 1
	g.qty = g.qty + e.q
	local zone = MJ.ZoneInfo()
	local stamp = { t = time(), c = self.charKey, n = npcId, k = kind, z = zone }
	if not g.first then g.first = stamp end
	g.last = stamp
	if isNew then self:OnNewItem(itemId, g, npcId) end
	return g
end

-- Skinning / herbalism / mining from corpses and pick pocketing. Kept apart from normal drops.
function MJ:RecordGather(guid, npcId, kind, src)
	local key = guid .. ":" .. kind
	if self.db.recent.loot[key] then return end
	self.db.recent.loot[key] = time()
	local n = self:GetNPC(npcId, true)
	if src.name and not n.name then n.name = src.name end
	n.gather = n.gather or {}
	local gk = n.gather[kind]
	if not gk then
		gk = { count = 0, money = 0, items = {} }
		n.gather[kind] = gk
	end
	gk.count = gk.count + 1
	gk.money = gk.money + (src.money or 0)
	local vendor = 0
	for itemId, e in pairs(src.items) do
		local it = gk.items[itemId]
		if not it then
			it = { drops = 0, qty = 0 }
			gk.items[itemId] = it
		end
		it.drops = it.drops + 1
		it.qty = it.qty + e.q
		local g = self:RecordGlobalItem(itemId, e, npcId, kind)
		g.gsrc = g.gsrc or {}
		g.gsrc[npcId] = true
		vendor = vendor + (g.sell or 0) * e.q
	end
	if (src.money or 0) > 0 then self:Bump("money", src.money) end
	if vendor > 0 then self:Bump("vendor", vendor) end
	self:Debug("%s on %s", kind, n.name or "?")
	self:Changed()
end

function MJ:RecordPickAttempt(npcId)
	local n = self:GetNPC(npcId, true)
	n.gather = n.gather or {}
	local gk = n.gather.pick
	if not gk then
		gk = { count = 0, money = 0, items = {} }
		n.gather.pick = gk
	end
	gk.tries = (gk.tries or 0) + 1
end

-- Loot that does not come from an NPC: fishing, containers, chests, herb/mining nodes.
function MJ:RecordOther(kind, src, zone)
	zone = zone ~= "" and zone or "Unknown"
	local vendor = 0
	local fish
	if kind == "fishing" then
		fish = self.db.fishing[zone]
		if not fish then
			fish = { catches = 0, items = {} }
			self.db.fishing[zone] = fish
		end
		fish.catches = fish.catches + 1
	end
	for itemId, e in pairs(src.items) do
		local g = self:RecordGlobalItem(itemId, e, nil, kind)
		g.other = g.other or {}
		local o
		if kind == "fishing" then
			g.other.fishing = g.other.fishing or {}
			o = g.other.fishing[zone]
			if not o then
				o = { d = 0, q = 0 }
				g.other.fishing[zone] = o
			end
			fish.items[itemId] = (fish.items[itemId] or 0) + e.q
		else
			o = g.other[kind]
			if not o then
				o = { d = 0, q = 0 }
				g.other[kind] = o
			end
		end
		o.d = o.d + 1
		o.q = o.q + e.q
		vendor = vendor + (g.sell or 0) * e.q
	end
	if (src.money or 0) > 0 then self:Bump("money", src.money) end
	if vendor > 0 then self:Bump("vendor", vendor) end
	self:Changed()
end

---------------------------------------------------------------------------
-- XP, reputation, deaths
---------------------------------------------------------------------------
local function FindRecentKill(name)
	local now = GetTime()
	for i = 1, #MJ.recentKills do
		local rk = MJ.recentKills[i]
		if not rk.xp and rk.name == name and now - rk.t < 6 then return rk end
	end
end

function MJ:ClaimPendingXP()
	local p = self.pendingXP
	if not p then return end
	if GetTime() - p.t > 6 then
		self.pendingXP = nil
		return
	end
	local rk = FindRecentKill(p.name)
	if rk then
		self.pendingXP = nil
		rk.xp = true
		local n = self.db.npcs[rk.npc]
		if n then
			n.xp = (n.xp or 0) + p.xp
			n.xpN = (n.xpN or 0) + 1
		end
	end
end

function MJ:OnXPGain(name, xp)
	self:Bump("xp", xp)
	self.pendingXP = { name = name, xp = xp, t = GetTime() }
	if FindRecentKill(name) then
		self:ClaimPendingXP()
		return
	end
	-- The death may not have been seen yet: look for a fresh corpse with that name.
	local guid, npcId, level = self.FindDeadUnitByName and self.FindDeadUnitByName(name)
	if guid then
		self:RecordKill(guid, npcId, { source = "xp", name = name, level = level })
	end
end

function MJ:OnRepGain(faction, amount)
	local lk = self.lastKill
	if not lk or GetTime() - lk.t > 4 then return end
	local n = self.db.npcs[lk.npc]
	if not n then return end
	n.rep = n.rep or {}
	n.rep[faction] = (n.rep[faction] or 0) + amount
end

function MJ:RecordDeath(killers)
	self:Bump("deaths")
	local any = false
	for npcId in pairs(killers) do
		local n = self.db.npcs[npcId] or self:GetNPC(npcId, true)
		n.deathsTo = (n.deathsTo or 0) + 1
		self:Log({ k = "death", npc = npcId, z = (MJ.ZoneInfo()) })
		any = true
	end
	if not any then self:Log({ k = "death", z = (MJ.ZoneInfo()) }) end
	self:Changed()
end

---------------------------------------------------------------------------
-- Maintenance
---------------------------------------------------------------------------
function MJ:DeleteNPC(npcId)
	local n = self.db.npcs[npcId]
	if not n then return end
	for itemId, it in pairs(n.items) do
		local g = self.db.items[itemId]
		if g then
			g.drops = max(0, g.drops - it.drops)
			g.qty = max(0, g.qty - it.qty)
			if g.src then g.src[npcId] = nil end
			if g.drops == 0 then self.db.items[itemId] = nil end
		end
	end
	if n.gather then
		for _, gk in pairs(n.gather) do
			for itemId, it in pairs(gk.items) do
				local g = self.db.items[itemId]
				if g then
					g.drops = max(0, g.drops - it.drops)
					g.qty = max(0, g.qty - it.qty)
					if g.gsrc then g.gsrc[npcId] = nil end
					if g.drops == 0 then self.db.items[itemId] = nil end
				end
			end
		end
	end
	self.db.npcs[npcId] = nil
	self:Changed()
end
