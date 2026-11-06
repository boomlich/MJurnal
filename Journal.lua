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

-- The NPC entry: what the monster is (MJ.NPC_META). What each character did to it is in
-- n.ch[charKey], see MJ:NPCStats.
function MJ:GetNPC(npcId, create)
	local n = self.db.npcs[npcId]
	if not n and create then
		n = { firstSeen = time(), ch = {} }
		self.db.npcs[npcId] = n
		self:ApplyMeta(npcId)
		self:OnNewNPC(npcId, n)
	end
	return n
end

function MJ.NewNPCStats()
	return { kills = 0, looted = 0, empty = 0, money = 0, moneyCorpses = 0, items = {}, zones = {}, days = {} }
end

-- One character's numbers for NPC entry n (the current character when ck is nil).
function MJ:NPCStats(n, ck)
	ck = ck or self.charKey or "?"
	local s = n.ch[ck]
	if not s then
		s = MJ.NewNPCStats()
		n.ch[ck] = s
	end
	return s
end

-- One character's numbers for item entry g: drops, qty, first, last, other.
function MJ:ItemStats(g, ck)
	ck = ck or self.charKey or "?"
	local s = g.ch[ck]
	if not s then
		s = { drops = 0, qty = 0 }
		g.ch[ck] = s
	end
	return s
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
	local ck = self.charKey or "?"
	local s = self:NPCStats(n, ck)

	s.kills = s.kills + 1
	if IsInGroup() then
		s.groupKills = (s.groupKills or 0) + 1
	else
		s.soloKills = (s.soloKills or 0) + 1
	end

	-- where
	local zone, sub = MJ.ZoneInfo()
	if zone ~= "" then
		local z = s.zones[zone]
		if not z then
			z = { kills = 0, sub = {} }
			s.zones[zone] = z
		end
		z.kills = z.kills + 1
		if sub ~= "" then z.sub[sub] = (z.sub[sub] or 0) + 1 end
	end
	self:SamplePosition(n)

	-- when
	local dk = self.DayKey(now)
	s.days[dk] = (s.days[dk] or 0) + 1
	local stamp = { t = now, c = ck, z = zone }
	if not s.firstKill then s.firstKill = stamp end
	s.lastKill = stamp

	-- levels (its level range belongs to the monster; yours is per character)
	local lvl = info.level
	if lvl and lvl > 0 then
		n.minLvl = min(n.minLvl or lvl, lvl)
		n.maxLvl = max(n.maxLvl or lvl, lvl)
	end
	local my = S(UnitLevel("player"))
	if my then
		s.myMin = min(s.myMin or my, my)
		s.myMax = max(s.myMax or my, my)
		if lvl and lvl > 0 then
			s.diffSum = (s.diffSum or 0) + (my - lvl)
			s.diffN = (s.diffN or 0) + 1
		end
	end

	-- combat duration (from engagement to death)
	if info.start then
		local d = GetTime() - info.start
		if d >= 0 and d < 900 then
			s.ttkSum = (s.ttkSum or 0) + d
			s.ttkN = (s.ttkN or 0) + 1
			s.ttkMin = min(s.ttkMin or d, d)
			s.ttkMax = max(s.ttkMax or d, d)
		end
	end

	-- counters
	self:Bump("kills")
	local streak = self.db.streak
	streak.cur = (streak.cur or 0) + 1
	if streak.cur > (streak.best or 0) then
		streak.best = streak.cur
		streak.bestT = now
	end
	local cd = self:CharData()
	cd.streak = (cd.streak or 0) + 1
	if cd.streak > (cd.bestStreak or 0) then cd.bestStreak = cd.streak end
	local sk = self.session.npcKills
	sk[npcId] = (sk[npcId] or 0) + 1
	if sk[npcId] > (s.bestSession or 0) then s.bestSession = sk[npcId] end

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
	return r and r.s == "pending"
end

-- "No loot" only means "empty" when the corpse was yours to loot. In a group someone else
-- may have the loot rights (round robin, master loot...), and then it looks empty to you too.
local function canJudgeEmpty()
	if not IsInGroup() then return true end
	local method
	if C_PartyInfo and C_PartyInfo.GetLootMethod then
		local ok, m = pcall(C_PartyInfo.GetLootMethod)
		method = ok and S(m) or nil
	elseif GetLootMethod then
		local ok, m = pcall(GetLootMethod)
		method = ok and S(m) or nil
	end
	if method == "freeforall" then return true end
	local LM = Enum and Enum.LootMethod
	return LM ~= nil and LM.Freeforall ~= nil and method == LM.Freeforall
end

function MJ:MarkEmpty(guid, why)
	local r = self.db.recent.kills[guid]
	if not isOpen(r) or not r.n or not canJudgeEmpty() then return end
	r.s = "empty"
	local n = self.db.npcs[r.n]
	if n then
		local s = self:NPCStats(n)
		s.empty = s.empty + 1
		r.qn = self:CountQuestCorpse(s)
	end
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
	if n then
		local s = self:NPCStats(n)
		s.empty = max(0, s.empty - 1)
		self:CountQuestCorpse(s, -1, r.qn)
		r.qn = nil
	end
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
	if not r then
		self:RecordKill(guid, npcId, { source = "loot", name = src.name, level = src.level })
		r = self.db.recent.kills[guid]
		if not r then return end
	end
	local n = self:GetNPC(npcId, true)
	if src.name and not n.name then n.name = src.name end
	local s = self:NPCStats(n)
	if r.s == "empty" then
		s.empty = max(0, s.empty - 1)
		self:Bump("corpses", -1)
		self:CountQuestCorpse(s, -1, r.qn)
	end
	r.s = "looted"

	s.looted = s.looted + 1
	self:Bump("corpses")
	r.qn = self:CountQuestCorpse(s)
	local corpseIdx = s.looted + s.empty

	local hasItems = next(src.items) ~= nil
	local money = src.money or 0
	if money > 0 then
		s.money = s.money + money
		s.moneyCorpses = s.moneyCorpses + 1
		s.moneyMin = min(s.moneyMin or money, money)
		s.moneyMax = max(s.moneyMax or money, money)
		self:Bump("money", money)
		if not hasItems then s.moneyOnly = (s.moneyOnly or 0) + 1 end
	elseif not hasItems then
		s.nothing = (s.nothing or 0) + 1
	end

	local vendor = 0
	for itemId, e in pairs(src.items) do
		vendor = vendor + self:RecordNPCItemDrop(s, npcId, itemId, e, corpseIdx)
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

-- s = the character's stats for the NPC; corpseIdx = this corpse's number in s.
function MJ:RecordNPCItemDrop(s, npcId, itemId, e, corpseIdx)
	local it = s.items[itemId]
	if not it then
		it = { drops = 0, qty = 0 }
		s.items[itemId] = it
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
	-- how often each amount dropped from one corpse: [amount] = corpses
	it.stacks = it.stacks or {}
	it.stacks[e.q] = (it.stacks[e.q] or 0) + 1
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
	if e.starter then g.questStarter = true end
	if e.quest and not e.starter then
		-- quest-only bookkeeping: did it drop while the quest wanted it?
		local name = e.name or g.name
		if name and MJ.WantedQuestItems()[name] then
			it.qDrops = (it.qDrops or 0) + 1
			it.qQty = (it.qQty or 0) + e.q
			local idx = (s.qNeed and s.qNeed[name]) or 0
			it.qDryMax = max(it.qDryMax or 0, idx - (it.qLastAt or 0) - 1)
			it.qLastAt = idx
		else
			-- dropped without being wanted: it is a general drop after all
			it.offQuest = (it.offQuest or 0) + 1
		end
	end
	g.src = g.src or {}
	g.src[npcId] = true
	self:OnItemDrop(npcId, s, itemId, it, gap, e)
	return (g.sell or 0) * e.q
end

-- Item entry (loot journal side). Returns the entry and the current character's stats for it.
function MJ:RecordGlobalItem(itemId, e, npcId, kind)
	local g = self.db.items[itemId]
	local isNew = not g
	if not g then
		g = { ch = {} }
		self.db.items[itemId] = g
	end
	if e.link and not g.link then g.link = e.link end
	if e.quality then g.quality = e.quality end
	if e.quest then g.quest = true end
	self:CacheItem(itemId, e.link)
	local gs = self:ItemStats(g)
	gs.drops = gs.drops + 1
	gs.qty = gs.qty + e.q
	local zone = MJ.ZoneInfo()
	local stamp = { t = time(), c = self.charKey, n = npcId, k = kind, z = zone }
	if not gs.first then gs.first = stamp end
	gs.last = stamp
	if isNew then self:OnNewItem(itemId, g, npcId) end
	return g, gs
end

-- Skinning / herbalism / mining from corpses and pick pocketing. Kept apart from normal drops.
function MJ:RecordGather(guid, npcId, kind, src)
	local key = guid .. ":" .. kind
	if self.db.recent.loot[key] then return end
	self.db.recent.loot[key] = time()
	local n = self:GetNPC(npcId, true)
	if src.name and not n.name then n.name = src.name end
	local gk = self:GatherStats(self:NPCStats(n), kind)
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

-- The character's gathering numbers of one kind (skin, herb, mine, pick) on an NPC.
function MJ:GatherStats(s, kind)
	s.gather = s.gather or {}
	local gk = s.gather[kind]
	if not gk then
		gk = { count = 0, money = 0, items = {} }
		s.gather[kind] = gk
	end
	return gk
end

function MJ:RecordPickAttempt(npcId)
	local gk = self:GatherStats(self:NPCStats(self:GetNPC(npcId, true)), "pick")
	gk.tries = (gk.tries or 0) + 1
end

---------------------------------------------------------------------------
-- Gathering sources: loot that does not come from an NPC
--   kind: herb, mine (nodes), object (chests and other objects), container (opened items),
--         fishing (one source per zone)
--   key:  "go:<objectID>", "container:<itemID>", "fishing:<zone>" ("legacy:<kind>" = before v6)
-- Each character has c.nodes[key] = { kind, count, money, items, zones, first, last }; the
-- name is account-wide in db.nodeNames[key].
---------------------------------------------------------------------------
function MJ:NodeStats(key, kind, ck)
	local c = self:CharData(ck)
	c.nodes = c.nodes or {}
	local nd = c.nodes[key]
	if not nd then
		nd = { kind = kind, count = 0, money = 0, items = {}, zones = {} }
		c.nodes[key] = nd
	end
	return nd
end

-- A placeholder name ("Object #1731") is replaced once the real one is known.
local function isPlaceholder(name)
	return name == nil or name:match("#%d+$") ~= nil or name == "Object"
end

function MJ:RecordNode(kind, key, name, src, zone)
	zone = zone ~= "" and zone or "Unknown"
	local names = self.db.nodeNames
	if name and isPlaceholder(names[key]) and not (isPlaceholder(name) and names[key]) then names[key] = name end
	local nd = self:NodeStats(key, kind)
	nd.count = (nd.count or 0) + 1
	nd.money = nd.money + (src.money or 0)
	nd.zones[zone] = (nd.zones[zone] or 0) + 1
	local stamp = { t = time(), z = zone }
	if not nd.first then nd.first = stamp end
	nd.last = stamp
	local vendor = 0
	for itemId, e in pairs(src.items) do
		local it = nd.items[itemId]
		if not it then
			it = { drops = 0, qty = 0 }
			nd.items[itemId] = it
		end
		it.drops = it.drops + 1
		it.qty = it.qty + e.q
		it.sMin = min(it.sMin or e.q, e.q)
		it.sMax = max(it.sMax or e.q, e.q)
		it.stacks = it.stacks or {}
		it.stacks[e.q] = (it.stacks[e.q] or 0) + 1
		local g = self:RecordGlobalItem(itemId, e, nil, kind)
		g.nsrc = g.nsrc or {}
		g.nsrc[key] = true
		vendor = vendor + (g.sell or 0) * e.q
	end
	if (src.money or 0) > 0 then self:Bump("money", src.money) end
	if vendor > 0 then self:Bump("vendor", vendor) end
	self:Debug("%s: %s (%d item types)", kind, names[key] or key, self.Count(src.items))
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
			local s = self:NPCStats(n)
			s.xp = (s.xp or 0) + p.xp
			s.xpN = (s.xpN or 0) + 1
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
	local s = self:NPCStats(n)
	s.rep = s.rep or {}
	s.rep[faction] = (s.rep[faction] or 0) + amount
end

---------------------------------------------------------------------------
-- Player deaths
---------------------------------------------------------------------------
-- A death record D (also the log entry) looks like:
-- { k = "death", t, c, npc = killer, o = { other attackers }, z, sz, lvl = your level,
--   mlvl = killer level, adds = enemies on you, dur = fight length, g = in group,
--   kb = { s = spellID, sn = spell name, a = amount, o = overkill, src = name, env = type },
--   dmg = damage in the recap, hits, win = seconds covered, hp = your max health }

function MJ.NPCIdByName(name)
	if not name then return nil end
	for _, e in pairs(MJ.engaged or {}) do
		if e.name == name then return e.npc end
	end
	for id, m in pairs(MJ.meta) do
		if m.name == name then return id end
	end
	for id, n in pairs(MJ.db.npcs) do
		if n.name == name then return id end
	end
end

-- Adds (sign = 1) or removes (sign = -1) one death of character D.c caused by npcId.
local function applyKiller(self, npcId, D, sign)
	if not npcId then return end
	local n = self:NPCStats(self:GetNPC(npcId, true), D.c)
	n.deathsTo = max(0, (n.deathsTo or 0) + sign)
	if D.lvl and D.mlvl then
		n.deathDiffSum = (n.deathDiffSum or 0) + sign * (D.lvl - D.mlvl)
		n.deathDiffN = max(0, (n.deathDiffN or 0) + sign)
	end
	if D.adds then n.deathAddsSum = (n.deathAddsSum or 0) + sign * D.adds end
	if D.dur then n.deathDurSum = (n.deathDurSum or 0) + sign * D.dur end
	if sign > 0 then
		local stamp = { t = D.t, c = D.c, z = D.z }
		if not n.firstDeathTo then n.firstDeathTo = stamp end
		n.lastDeathTo = stamp
	end
end

local function applyAssist(self, npcId, D, sign)
	local n = self:NPCStats(self:GetNPC(npcId, true), D.c)
	n.deathAssists = max(0, (n.deathAssists or 0) + sign)
end

-- info = { npc = primary killer, others = { npcIds }, adds, dur, mobLvl }
function MJ:RecordDeath(info)
	info = info or {}
	local db = self.db
	local zone, sub = MJ.ZoneInfo()
	local D = {
		k = "death", t = time(), c = self.charKey, npc = info.npc, z = zone, sz = sub ~= "" and sub or nil,
		lvl = S(UnitLevel("player")), mlvl = info.mobLvl, adds = info.adds, dur = info.dur,
		g = IsInGroup() or nil,
	}
	if info.others and #info.others > 0 then D.o = info.others end

	self:Bump("deaths")
	local c = self:CharData()
	if zone ~= "" then
		c.deathZones = c.deathZones or {}
		c.deathZones[zone] = (c.deathZones[zone] or 0) + 1
	end
	db.streak.cur = 0
	db.streak.lastDeath = D.t
	c.streak = 0
	c.lastDeath = D.t

	applyKiller(self, D.npc, D, 1)
	for _, id in ipairs(D.o or {}) do applyAssist(self, id, D, 1) end

	self:Log(D)
	self:ScheduleDeathRecap(D)
	self:Debug("death: killer %s, %d enemies", D.npc and self:NPCName(D.npc) or "?", D.adds or 0)
	self:Changed()
end

-- Finds the recap ID of your latest death through the damage meter, when it is readable.
local function latestRecapID()
	local DM = C_DamageMeter
	local T = Enum and Enum.DamageMeterType
	if not DM or not T or not T.Deaths or not DM.GetCombatSessionFromType then return nil end
	local best
	for _, sessionType in ipairs({ 1, 0 }) do
		local ok, session = pcall(DM.GetCombatSessionFromType, sessionType, T.Deaths)
		if ok and type(session) == "table" and type(session.combatSources) == "table" then
			for _, src in ipairs(session.combatSources) do
				local id = S(src.deathRecapID)
				if S(src.isLocalPlayer) and id and id > 0 and (not best or id > best) then best = id end
			end
		end
		if best then return best end
	end
end

-- Reads the death recap (the "what killed me" window) a moment after death and
-- corrects the killer to whoever landed the killing blow.
function MJ:ScheduleDeathRecap(D)
	if not C_DeathRecap or not C_DeathRecap.GetRecapEvents or not C_Timer then return end
	local tries = 0
	local function read()
		tries = tries + 1
		local recapID = latestRecapID()
		local ok, events = pcall(C_DeathRecap.GetRecapEvents, recapID)
		local kb = ok and type(events) == "table" and events[1]
		local ready = kb and not self.issecret(kb.timestamp) and not self.issecret(kb.amount) and not self.issecret(kb.sourceName)
		local sig = ready and (tostring(kb.timestamp) .. ":" .. tostring(kb.amount) .. ":" .. tostring(kb.sourceName))
		if not ready or sig == self.db.streak.lastRecap then
			if tries < 6 then C_Timer.After(2, read) end
			return
		end
		self.db.streak.lastRecap = sig

		local spellID = S(kb.spellId)
		if kb.event == "SWING_DAMAGE" then spellID = 0 end
		local env = S(kb.environmentalType)
		D.kb = {
			s = spellID, sn = S(kb.spellName), a = S(kb.amount), o = S(kb.overkill),
			src = not S(kb.hideCaster) and S(kb.sourceName) or nil, env = env,
		}
		local total, first, last = 0, nil, nil
		for _, ev in ipairs(events) do
			local a, ts = S(ev.amount), S(ev.timestamp)
			if a then total = total + a end
			if ts then
				first = first and math.min(first, ts) or ts
				last = last and math.max(last, ts) or ts
			end
		end
		D.dmg, D.hits = total, #events
		if first and last then D.win = last - first end
		local okHP, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
		D.hp = okHP and S(hp) or nil

		-- the killing blow decides who gets the kill
		local killer
		if not env then killer = MJ.NPCIdByName(D.kb.src) end
		if env then
			local c = self:CharData(D.c)
			c.deathEnv = c.deathEnv or {}
			c.deathEnv[env] = (c.deathEnv[env] or 0) + 1
		end
		if (killer or env) and killer ~= D.npc then
			local old = D.npc
			applyKiller(self, old, D, -1)
			D.npc = killer
			if killer then applyKiller(self, killer, D, 1) end
			if old then
				D.o = D.o or {}
				table.insert(D.o, old)
				applyAssist(self, old, D, 1)
			end
			if killer and D.o then
				for i = #D.o, 1, -1 do
					if D.o[i] == killer then
						table.remove(D.o, i)
						applyAssist(self, killer, D, -1)
					end
				end
			end
		end
		if D.npc then
			local n = self:NPCStats(self:GetNPC(D.npc, true), D.c)
			n.deathSpells = n.deathSpells or {}
			local key = D.kb.s or 0
			local ds = n.deathSpells[key]
			if not ds then
				ds = { c = 0 }
				n.deathSpells[key] = ds
			end
			ds.c = ds.c + 1
			ds.name = D.kb.sn or ds.name
			if D.kb.a then
				ds.max = max(ds.max or 0, D.kb.a)
				n.kbMax = max(n.kbMax or 0, D.kb.a)
			end
		end
		self:Debug("death recap: %s by %s (%s)", tostring(D.kb.a), tostring(D.kb.src), tostring(D.kb.sn or D.kb.env))
		self:Changed()
	end
	C_Timer.After(1, read)
end

---------------------------------------------------------------------------
-- Maintenance
---------------------------------------------------------------------------
-- Takes one NPC's drops of an item away from character ck's stats for the item, and drops
-- the item entry once no character has any of it left.
local function removeDrops(self, itemId, ck, it, srcKey, npcId)
	local g = self.db.items[itemId]
	if not g then return end
	if g[srcKey] then g[srcKey][npcId] = nil end
	local gs = g.ch[ck]
	if gs then
		gs.drops = max(0, gs.drops - it.drops)
		gs.qty = max(0, gs.qty - it.qty)
		if gs.drops == 0 then g.ch[ck] = nil end
	end
	if not next(g.ch) then self.db.items[itemId] = nil end
end

-- Deletes the NPC for every character.
function MJ:DeleteNPC(npcId)
	local n = self.db.npcs[npcId]
	if not n then return end
	for ck, s in pairs(n.ch) do
		for itemId, it in pairs(s.items) do removeDrops(self, itemId, ck, it, "src", npcId) end
		for _, gk in pairs(s.gather or {}) do
			for itemId, it in pairs(gk.items) do removeDrops(self, itemId, ck, it, "gsrc", npcId) end
		end
	end
	self.db.npcs[npcId] = nil
	self:Changed()
end

-- Deletes a gathering source for every character.
function MJ:DeleteNode(key)
	for ck, c in pairs(self.db.chars) do
		local nd = c.nodes and c.nodes[key]
		if nd then
			for itemId, it in pairs(nd.items) do removeDrops(self, itemId, ck, it, "nsrc", key) end
			c.nodes[key] = nil
		end
	end
	self.db.nodeNames[key] = nil
	self:Changed()
end

-- Whether any character still has itemId in gathering source key.
local function nodeHasItem(db, key, itemId)
	for _, c in pairs(db.chars) do
		local nd = c.nodes and c.nodes[key]
		if nd and nd.items[itemId] then return true end
	end
	return false
end

-- Whether any character still has itemId among the drops (or gathering) of NPC entry n.
local function npcHasItem(n, itemId, gather)
	for _, s in pairs(n.ch) do
		if gather then
			for _, gk in pairs(s.gather or {}) do
				if gk.items[itemId] then return true end
			end
		elseif s.items[itemId] then
			return true
		end
	end
	return false
end

-- Deletes everything one character recorded: its numbers on every monster, item and gathering
-- source, its counters, days and deaths, and its history log entries and rares. Monsters and
-- items no other character has are removed. The account kill streak is left alone.
function MJ:DeleteCharacter(ck)
	local db = self.db
	for id, n in pairs(db.npcs) do
		n.ch[ck] = nil
		if not next(n.ch) then db.npcs[id] = nil end
	end
	for id, g in pairs(db.items) do
		g.ch[ck] = nil
		if not next(g.ch) then
			db.items[id] = nil
		else
			-- forget sources only this character had
			for _, key in ipairs({ "src", "gsrc" }) do
				for npcId in pairs(g[key] or {}) do
					local n = db.npcs[npcId]
					if not n or not npcHasItem(n, id, key == "gsrc") then g[key][npcId] = nil end
				end
			end
		end
	end

	local c = db.chars[ck]
	db.chars[ck] = nil
	for id, g in pairs(db.items) do
		for key in pairs(g.nsrc or {}) do
			if not nodeHasItem(db, key, id) then g.nsrc[key] = nil end
		end
	end
	if c then
		for _, f in ipairs(MJ.COUNTERS) do
			if c[f] and db.totals[f] then db.totals[f] = max(0, db.totals[f] - c[f]) end
		end
	end

	local kept = {}
	for _, e in ipairs(db.log) do
		if e.c ~= ck then kept[#kept + 1] = e end
	end
	db.log = kept
	for id, r in pairs(db.rares) do
		if r.c == ck then db.rares[id] = nil end
	end

	if ck == self.charKey then
		-- you are playing this character: start it over
		self.session = { start = time(), npcKills = {} }
		self.recentKills, self.lastKill = {}, nil
		self:CharData().class = select(2, UnitClass("player"))
	end
	local filter = self:CharFilter()
	if filter and filter[ck] then
		filter[ck] = nil
		self:SetCharFilter(filter)
	end
	self:Changed()
end
