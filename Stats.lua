-- Stats.lua: pure calculations on top of MJurnalDB (no writes).
local _, MJ = ...
local St = MJ.Stats
local floor, ceil, log, sqrt, min, max = math.floor, math.ceil, math.log, math.sqrt, math.min, math.max

---------------------------------------------------------------------------
-- Probability helpers
---------------------------------------------------------------------------
-- Corpses we know the outcome of: looted + confirmed empty. This is the drop-rate denominator.
function St.Corpses(n)
	return (n.looted or 0) + (n.empty or 0)
end

function St.Rate(drops, corpses)
	if not corpses or corpses <= 0 then return nil end
	return drops / corpses
end

-- 95% Wilson score interval for a binomial proportion.
function St.Wilson(d, c, z)
	if not c or c <= 0 then return nil end
	z = z or 1.96
	local p = d / c
	local z2 = z * z
	local denom = 1 + z2 / c
	local center = (p + z2 / (2 * c)) / denom
	local margin = z * sqrt(p * (1 - p) / c + z2 / (4 * c * c)) / denom
	return max(0, center - margin), min(1, center + margin)
end

-- Corpses needed for a given chance (0..1) of at least one drop.
function St.KillsFor(p, chance)
	if not p or p <= 0 then return nil end
	if p >= 1 then return 1 end
	return max(1, ceil(log(1 - chance) / log(1 - p)))
end

-- Chance of going this many corpses in a row without the item.
function St.Drought(p, n)
	if not p or p <= 0 then return 1 end
	if p >= 1 then return n > 0 and 0 or 1 end
	return (1 - p) ^ n
end

function St.Since(n, it)
	return max(0, St.Corpses(n) - (it.lastAt or 0))
end

function St.Luck(it)
	if not it.luckN or it.luckN == 0 then return nil end
	return it.luckSum / it.luckN
end

-- Confidence label: grey numbers until we have a decent sample.
function St.Confident(corpses)
	return corpses and corpses >= 20
end

---------------------------------------------------------------------------
-- NPC aggregates
---------------------------------------------------------------------------
function St.NPCVendor(n)
	local v = 0
	local items = MJ.db.items
	for id, it in pairs(n.items) do
		local g = items[id]
		if g and g.sell then v = v + g.sell * it.qty end
	end
	return v
end

function St.NPCValuePerCorpse(n)
	local c = St.Corpses(n)
	if c <= 0 then return nil end
	return (n.money + St.NPCVendor(n)) / c
end

function St.NPCQuality(n)
	local q = {}
	local items = MJ.db.items
	for id, it in pairs(n.items) do
		local g = items[id]
		local quality = (g and g.quality) or 1
		q[quality] = (q[quality] or 0) + it.drops
	end
	return q
end

function St.BestDay(days)
	local bestK, bestV
	for k, v in pairs(days or {}) do
		local val = type(v) == "table" and (v.kills or 0) or v
		if not bestV or val > bestV then bestK, bestV = k, val end
	end
	return bestK, bestV
end

function St.DayLabel(key)
	if not key then return "-" end
	local s = tostring(key)
	return s:sub(1, 4) .. "-" .. s:sub(5, 6) .. "-" .. s:sub(7, 8)
end

-- Values for the last `count` days (oldest first). getter(dayKey) -> number
function St.LastDays(count, getter)
	local vals, keys = {}, {}
	local now = time()
	for i = count - 1, 0, -1 do
		local k = MJ.DayKey(now - i * 86400)
		vals[#vals + 1] = getter(k) or 0
		keys[#keys + 1] = k
	end
	return vals, keys
end

-- Death log entries (newest first), optionally only those involving npcId.
function St.Deaths(npcId, limit)
	local out = {}
	local log = MJ.db.log
	for i = #log, 1, -1 do
		local e = log[i]
		if e.k == "death" then
			local match = not npcId or e.npc == npcId
			if not match and e.o then
				for _, id in ipairs(e.o) do
					if id == npcId then
						match = true
						break
					end
				end
			end
			if match then
				out[#out + 1] = e
				if limit and #out >= limit then break end
			end
		end
	end
	return out
end

function St.SumDays(count, field)
	local total = 0
	local now = time()
	for i = 0, count - 1 do
		local d = MJ.db.days[MJ.DayKey(now - i * 86400)]
		if d then total = total + (d[field] or 0) end
	end
	return total
end

---------------------------------------------------------------------------
-- Item aggregates
---------------------------------------------------------------------------
function St.ItemSources(itemId)
	local g = MJ.db.items[itemId]
	local list = {}
	if not g or not g.src then return list end
	for npcId in pairs(g.src) do
		local n = MJ.db.npcs[npcId]
		local it = n and n.items[itemId]
		if it then
			local c = St.Corpses(n)
			list[#list + 1] = { npc = npcId, n = n, it = it, corpses = c, rate = St.Rate(it.drops, c) or 0 }
		end
	end
	table.sort(list, function(a, b)
		if a.rate ~= b.rate then return a.rate > b.rate end
		return a.it.drops > b.it.drops
	end)
	return list
end

function St.ItemGatherSources(itemId)
	local g = MJ.db.items[itemId]
	local list = {}
	if not g or not g.gsrc then return list end
	for npcId in pairs(g.gsrc) do
		local n = MJ.db.npcs[npcId]
		if n and n.gather then
			for kind, gk in pairs(n.gather) do
				local it = gk.items[itemId]
				if it then
					list[#list + 1] = { npc = npcId, kind = kind, it = it, count = gk.count, rate = St.Rate(it.drops, gk.count) or 0 }
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.rate > b.rate end)
	return list
end

function St.ItemLuck(itemId)
	local sum, n = 0, 0
	for _, s in ipairs(St.ItemSources(itemId)) do
		if s.it.luckN then
			sum = sum + s.it.luckSum
			n = n + s.it.luckN
		end
	end
	if n == 0 then return nil end
	return sum / n, n
end

---------------------------------------------------------------------------
-- Global aggregates (cached until data changes)
---------------------------------------------------------------------------
local cache

function St.Global()
	if cache and not MJ.globalDirty then return cache end
	MJ.globalDirty = false
	local db = MJ.db
	local G = {
		npcCount = 0, itemCount = 0, kills = 0, corpses = 0, looted = 0, empty = 0,
		money = 0, vendor = 0, xp = 0, deaths = 0, ttk = 0, drops = 0, qty = 0,
		byType = {}, byClass = {}, byZone = {}, byQuality = {},
		rankKills = {}, sortedKills = {},
	}
	for id, n in pairs(db.npcs) do
		G.npcCount = G.npcCount + 1
		G.kills = G.kills + n.kills
		local c = St.Corpses(n)
		G.corpses = G.corpses + c
		G.looted = G.looted + n.looted
		G.empty = G.empty + n.empty
		G.money = G.money + n.money
		local v = St.NPCVendor(n)
		G.vendor = G.vendor + v
		G.xp = G.xp + (n.xp or 0)
		G.deaths = G.deaths + (n.deathsTo or 0)
		G.ttk = G.ttk + (n.ttkSum or 0)
		local t = n.type or "Unknown"
		local bt = G.byType[t] or { kills = 0, money = 0, value = 0 }
		G.byType[t] = bt
		bt.kills = bt.kills + n.kills
		bt.money = bt.money + n.money
		bt.value = bt.value + n.money + v
		local cl = n.class or "normal"
		local bc = G.byClass[cl] or { kills = 0, npcs = 0 }
		G.byClass[cl] = bc
		bc.kills = bc.kills + n.kills
		bc.npcs = bc.npcs + 1
		for zone, z in pairs(n.zones) do
			local bz = G.byZone[zone] or { kills = 0, npcs = 0 }
			G.byZone[zone] = bz
			bz.kills = bz.kills + z.kills
			bz.npcs = bz.npcs + 1
		end
		G.sortedKills[#G.sortedKills + 1] = id
	end
	table.sort(G.sortedKills, function(a, b) return db.npcs[a].kills > db.npcs[b].kills end)
	for i, id in ipairs(G.sortedKills) do G.rankKills[id] = i end
	for _, g in pairs(db.items) do
		G.itemCount = G.itemCount + 1
		G.drops = G.drops + g.drops
		G.qty = G.qty + g.qty
		local q = g.quality or 1
		G.byQuality[q] = (G.byQuality[q] or 0) + g.drops
	end
	cache = G
	return G
end

-- Generic top-N helper. scoreFn(id, entry) -> score or nil (skip)
function St.Top(tbl, count, scoreFn, ascending)
	local list = {}
	for id, e in pairs(tbl) do
		local s = scoreFn(id, e)
		if s then list[#list + 1] = { id = id, e = e, score = s } end
	end
	table.sort(list, function(a, b)
		if ascending then return a.score < b.score end
		return a.score > b.score
	end)
	for i = #list, count + 1, -1 do list[i] = nil end
	return list
end

-- Every (npc, item) pair, for "rarest drop" / "luckiest" style rankings.
function St.AllDrops(minCorpses)
	local list = {}
	for npcId, n in pairs(MJ.db.npcs) do
		local c = St.Corpses(n)
		if c >= (minCorpses or 0) then
			for itemId, it in pairs(n.items) do
				list[#list + 1] = { npc = npcId, n = n, item = itemId, it = it, corpses = c, rate = it.drops / max(c, 1) }
			end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Lists for the journal (search + sort)
---------------------------------------------------------------------------
St.MONSTER_SORTS = {
	{ key = "kills", label = "Kills" },
	{ key = "name", label = "Name" },
	{ key = "last", label = "Recent" },
	{ key = "value", label = "Value" },
	{ key = "items", label = "Items" },
	{ key = "deaths", label = "Deaths" },
}
St.LOOT_SORTS = {
	{ key = "drops", label = "Drops" },
	{ key = "name", label = "Name" },
	{ key = "quality", label = "Quality" },
	{ key = "last", label = "Recent" },
	{ key = "value", label = "Value" },
}

local function matches(q, name, id)
	if not q then return true end
	if tostring(id) == q then return true end
	return name:lower():find(q, 1, true) ~= nil
end

function St.MonsterList(query, sortKey)
	local q = query and query ~= "" and query:lower() or nil
	local out = {}
	for id, n in pairs(MJ.db.npcs) do
		local name = n.name or ("NPC #" .. id)
		if matches(q, name, id) then
			local e = { id = id, name = name, n = n }
			if sortKey == "value" then e.v = St.NPCValuePerCorpse(n) or 0 end
			if sortKey == "items" then e.v = MJ.Count(n.items) end
			if sortKey == "deaths" then
				-- killing blows first, then times it was attacking you when you died
				e.v = (n.deathsTo or 0) * 10000 + (n.deathAssists or 0)
			end
			out[#out + 1] = e
		end
	end
	table.sort(out, function(a, b)
		if sortKey == "name" then return a.name < b.name end
		if sortKey == "last" then
			local ta, tb = a.n.lastKill and a.n.lastKill.t or 0, b.n.lastKill and b.n.lastKill.t or 0
			if ta ~= tb then return ta > tb end
		elseif sortKey == "value" or sortKey == "items" or sortKey == "deaths" then
			if a.v ~= b.v then return a.v > b.v end
			if sortKey == "deaths" and a.n.kills ~= b.n.kills then return a.n.kills > b.n.kills end
		else
			if a.n.kills ~= b.n.kills then return a.n.kills > b.n.kills end
		end
		return a.name < b.name
	end)
	return out
end

function St.ItemList(query, sortKey)
	local q = query and query ~= "" and query:lower() or nil
	local out = {}
	for id, g in pairs(MJ.db.items) do
		local name = g.name or ("Item #" .. id)
		if matches(q, name, id) then
			local e = { id = id, name = name, g = g }
			if sortKey == "value" then e.v = (g.sell or 0) * g.qty end
			out[#out + 1] = e
		end
	end
	table.sort(out, function(a, b)
		if sortKey == "name" then return a.name < b.name end
		if sortKey == "quality" then
			local qa, qb = a.g.quality or 1, b.g.quality or 1
			if qa ~= qb then return qa > qb end
		elseif sortKey == "last" then
			local ta, tb = a.g.last and a.g.last.t or 0, b.g.last and b.g.last.t or 0
			if ta ~= tb then return ta > tb end
		elseif sortKey == "value" then
			if a.v ~= b.v then return a.v > b.v end
		else
			if a.g.drops ~= b.g.drops then return a.g.drops > b.g.drops end
		end
		return a.name < b.name
	end)
	return out
end
