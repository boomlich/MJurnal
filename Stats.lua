-- Stats.lua: pure calculations on top of MJurnalDB (no writes): character views, rates, lists.
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

-- Quest-only drop: flagged as a quest item, does not start a quest, and has never
-- dropped while you didn't need it.
function St.IsQuestOnly(itemId, it)
	local g = MJ.db.items[itemId]
	if not (it.quest or (g and g.quest)) then return false end
	if g and g.questStarter then return false end
	if (it.offQuest or 0) > 0 then return false end
	return true
end

-- The numbers a drop rate is built from for one item from one monster:
-- drops, corpses, questOnly, corpses since last drop, longest dry streak, quantity.
-- Quest-only items only count corpses looted while the quest wanted them.
-- drops counts corpses that had the item (for the drop chance); qty counts every unit.
function St.ItemBase(n, itemId, it)
	if St.IsQuestOnly(itemId, it) then
		local g = MJ.db.items[itemId]
		local need = (g and g.name and n.qNeed and n.qNeed[g.name]) or 0
		local d = it.qDrops or 0
		-- older data has no on-quest quantity: estimate it from the average stack
		local qty = it.qQty or (d * it.qty / max(it.drops, 1))
		return d, need, true, max(0, need - (it.qLastAt or 0)), it.qDryMax or 0, qty
	end
	return it.drops, St.Corpses(n), false, St.Since(n, it), it.dryMax or 0, it.qty
end

-- Average number of units per corpse (not just the chance of at least one).
function St.PerCorpse(qty, corpses)
	if not corpses or corpses <= 0 then return nil end
	return qty / corpses
end

-- "1x 40 · 2x 12 · 3x 3": how often each amount dropped from one corpse, smallest first.
function St.StackText(it)
	if not it.stacks then return nil end
	local amounts = {}
	for q in pairs(it.stacks) do amounts[#amounts + 1] = q end
	table.sort(amounts)
	local parts = {}
	for _, q in ipairs(amounts) do parts[#parts + 1] = q .. "x " .. MJ.Num(it.stacks[q]) end
	return table.concat(parts, "  ·  ")
end

-- Confidence label: grey numbers until we have a decent sample.
function St.Confident(corpses)
	return corpses and corpses >= 20
end

---------------------------------------------------------------------------
-- Character views
--
-- Everything is stored per character (see the data model in Core.lua). A view combines the
-- characters selected in the journal into the shape the journal reads: npcs[npcId] and
-- items[itemId] look like one entry with identity + numbers, plus account-level tables.
-- Views are cached until the data or the filter changes.
---------------------------------------------------------------------------
-- How numbers combine across characters (anything else is summed).
local MIN = { moneyMin = true, ttkMin = true, sMin = true, gapMin = true, myMin = true }
local MAX = {
	moneyMax = true, ttkMax = true, sMax = true, dryMax = true, qDryMax = true, myMax = true,
	bestSession = true, kbMax = true, max = true,
}
local EARLIEST = { firstKill = true, firstDeathTo = true, first = true, firstT = true }
local LATEST = { lastKill = true, lastDeathTo = true, last = true, lastT = true }
-- Corpse positions within one character's sequence; rebuilt after merging (see fixSequences).
local SEQUENCE = { lastAt = true, qLastAt = true, firstAt = true }

local function copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = copy(x) end
	return t
end

local function stampTime(v)
	return type(v) == "table" and (v.t or 0) or v
end

-- Adds src into dst (both shaped like a character's stats).
local function mergeInto(dst, src)
	for k, v in pairs(src) do
		local d = dst[k]
		if SEQUENCE[k] then
			-- rebuilt by the caller
		elseif d == nil then
			dst[k] = copy(v)
		elseif EARLIEST[k] then
			if stampTime(v) < stampTime(d) then dst[k] = copy(v) end
		elseif LATEST[k] then
			if stampTime(v) > stampTime(d) then dst[k] = copy(v) end
		elseif type(v) == "number" and type(d) == "number" then
			if MIN[k] then
				dst[k] = min(d, v)
			elseif MAX[k] then
				dst[k] = max(d, v)
			else
				dst[k] = d + v
			end
		elseif type(v) == "table" and type(d) == "table" then
			mergeInto(d, v)
		elseif type(v) == "boolean" then
			dst[k] = d or v
		end
	end
	return dst
end

-- "Corpses since the last drop" only exists within one character's corpse sequence. For a
-- combined view, use the character that saw the item most recently (fewest corpses since).
local function fixSequences(m, buckets)
	local corpses = St.Corpses(m)
	for itemId, it in pairs(m.items) do
		local g = MJ.db.items[itemId]
		local name = g and g.name
		local since, qSince
		for _, b in ipairs(buckets) do
			local bi = b.items[itemId]
			if bi then
				local s = St.Corpses(b) - (bi.lastAt or 0)
				if not since or s < since then since = s end
				if bi.qLastAt and name then
					local qs = ((b.qNeed and b.qNeed[name]) or 0) - bi.qLastAt
					if not qSince or qs < qSince then qSince = qs end
				end
			end
		end
		it.lastAt = corpses - (since or corpses)
		it.firstAt = nil
		if qSince then it.qLastAt = ((m.qNeed and m.qNeed[name]) or 0) - qSince end
	end
end

-- Combines character buckets into one table (shallow copy when there is only one).
local function combine(buckets, fix)
	if #buckets == 1 then
		local e = {}
		for k, v in pairs(buckets[1]) do e[k] = v end
		return e
	end
	local e = copy(buckets[1])
	for i = 2, #buckets do mergeInto(e, buckets[i]) end
	if fix then fixSequences(e, buckets) end
	return e
end

function St.BuildView(filter)
	local db = MJ.db
	local function includes(ck) return filter == nil or filter[ck] == true end
	local V = {
		filter = filter, Includes = includes,
		npcs = {}, items = {}, chars = {}, rares = {},
		totals = {}, days = {}, fishing = {}, deathZones = {}, deathEnv = {},
	}

	for id, n in pairs(db.npcs) do
		local buckets, byChar = {}, {}
		for ck, s in pairs(n.ch) do
			if includes(ck) then
				buckets[#buckets + 1] = s
				byChar[ck] = s.kills
			end
		end
		if #buckets > 0 then
			local e = combine(buckets, true)
			for k in pairs(MJ.NPC_META) do e[k] = n[k] end
			e.ch = nil
			e.byChar = byChar
			V.npcs[id] = e
		end
	end

	for id, g in pairs(db.items) do
		local buckets = {}
		for ck, s in pairs(g.ch) do
			if includes(ck) then buckets[#buckets + 1] = s end
		end
		if #buckets > 0 then
			local e = combine(buckets, false)
			for k, v in pairs(g) do
				if k ~= "ch" then e[k] = v end
			end
			V.items[id] = e
		end
	end

	local streak = { cur = 0, best = 0 }
	for ck, c in pairs(db.chars) do
		if includes(ck) then
			V.chars[ck] = c
			for _, f in ipairs(MJ.COUNTERS) do V.totals[f] = (V.totals[f] or 0) + (c[f] or 0) end
			mergeInto(V.days, c.days or {})
			mergeInto(V.fishing, c.fishing or {})
			mergeInto(V.deathZones, c.deathZones or {})
			mergeInto(V.deathEnv, c.deathEnv or {})
			streak.cur = max(streak.cur, c.streak or 0)
			streak.best = max(streak.best, c.bestStreak or 0)
			if c.lastDeath then streak.lastDeath = max(streak.lastDeath or 0, c.lastDeath) end
		end
	end
	if filter == nil then
		-- the whole account: its own counters and its kill streak across characters
		V.totals = db.totals
		streak = db.streak
	end
	V.streak = streak

	for id, r in pairs(db.rares) do
		if includes(r.c) then V.rares[id] = r end
	end
	return V
end

-- The journal's character filter: nil = every character, else a set { [charKey] = true }.
function MJ:CharFilter()
	return self.db.ui.chars
end

function MJ:SetCharFilter(set)
	if set and not next(set) then set = nil end
	self.db.ui.chars = set
	self:Fire("FILTER_CHANGED")
end

local function filterKey(filter)
	if not filter then return "*" end
	local keys = {}
	for ck in pairs(filter) do keys[#keys + 1] = ck end
	table.sort(keys)
	return table.concat(keys, "\1")
end

local views = {} -- [filterKey] = { version, view }

function St.ViewFor(filter)
	local key = filterKey(filter)
	local c = views[key]
	if not c or c.version ~= MJ.dataVersion then
		-- keep at most the account view and the journal's current view
		if key ~= "*" then
			for k in pairs(views) do
				if k ~= "*" then views[k] = nil end
			end
		end
		c = { version = MJ.dataVersion, view = St.BuildView(filter) }
		views[key] = c
	end
	return c.view
end

-- The journal's current view, and the whole account (tooltips, chat).
function St.View() return St.ViewFor(MJ:CharFilter()) end
function St.AccountView() return St.ViewFor(nil) end

-- Kills of an NPC entry by every character.
function St.NPCKills(n)
	local k = 0
	for _, s in pairs(n.ch) do k = k + (s.kills or 0) end
	return k
end

---------------------------------------------------------------------------
-- NPC aggregates (n = a view entry)
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

-- Death log entries (newest first) of the view's characters, optionally only those involving npcId.
function St.Deaths(npcId, limit, V)
	V = V or St.View()
	local out = {}
	local log = MJ.db.log
	for i = #log, 1, -1 do
		local e = log[i]
		if e.k == "death" and V.Includes(e.c) then
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

function St.SumDays(count, field, V)
	V = V or St.View()
	local total = 0
	local now = time()
	for i = 0, count - 1 do
		local d = V.days[MJ.DayKey(now - i * 86400)]
		if d then total = total + (d[field] or 0) end
	end
	return total
end

---------------------------------------------------------------------------
-- Item aggregates
---------------------------------------------------------------------------
function St.ItemSources(itemId, V)
	V = V or St.View()
	local g = MJ.db.items[itemId]
	local list = {}
	if not g or not g.src then return list end
	for npcId in pairs(g.src) do
		local n = V.npcs[npcId]
		local it = n and n.items[itemId]
		if it then
			local d, c, questOnly, since, dry, qty = St.ItemBase(n, itemId, it)
			list[#list + 1] = {
				npc = npcId, n = n, it = it, drops = d, corpses = c, rate = St.Rate(d, c) or 0,
				questOnly = questOnly, since = since, dry = dry, qty = qty, perCorpse = St.PerCorpse(qty, c),
			}
		end
	end
	table.sort(list, function(a, b)
		if a.rate ~= b.rate then return a.rate > b.rate end
		return a.it.drops > b.it.drops
	end)
	return list
end

function St.ItemGatherSources(itemId, V)
	V = V or St.View()
	local g = MJ.db.items[itemId]
	local list = {}
	if not g or not g.gsrc then return list end
	for npcId in pairs(g.gsrc) do
		local n = V.npcs[npcId]
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

function St.ItemLuck(itemId, V)
	local sum, n = 0, 0
	for _, s in ipairs(St.ItemSources(itemId, V)) do
		if s.it.luckN and not s.questOnly then
			sum = sum + s.it.luckSum
			n = n + s.it.luckN
		end
	end
	if n == 0 then return nil end
	return sum / n, n
end

---------------------------------------------------------------------------
-- Global aggregates (cached on the view)
---------------------------------------------------------------------------
function St.Global(V)
	V = V or St.View()
	if V.G then return V.G end
	local G = {
		npcCount = 0, itemCount = 0, kills = 0, corpses = 0, looted = 0, empty = 0,
		money = 0, vendor = 0, xp = 0, deaths = 0, ttk = 0, drops = 0, qty = 0,
		byType = {}, byClass = {}, byZone = {}, byQuality = {},
		rankKills = {}, sortedKills = {},
	}
	local npcs = V.npcs
	for id, n in pairs(npcs) do
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
	table.sort(G.sortedKills, function(a, b) return npcs[a].kills > npcs[b].kills end)
	for i, id in ipairs(G.sortedKills) do G.rankKills[id] = i end
	for _, g in pairs(V.items) do
		G.itemCount = G.itemCount + 1
		G.drops = G.drops + g.drops
		G.qty = G.qty + g.qty
		local q = g.quality or 1
		G.byQuality[q] = (G.byQuality[q] or 0) + g.drops
	end
	V.G = G
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
function St.AllDrops(minCorpses, V)
	V = V or St.View()
	local list = {}
	for npcId, n in pairs(V.npcs) do
		local c = St.Corpses(n)
		if c >= (minCorpses or 0) then
			for itemId, it in pairs(n.items) do
				-- quest-only drops have their own denominator; keep them out of these rankings
				if not St.IsQuestOnly(itemId, it) then
					list[#list + 1] = { npc = npcId, n = n, item = itemId, it = it, corpses = c, rate = it.drops / max(c, 1) }
				end
			end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Categories (the list filter next to the search box)
--   monsters: "type:<creature type>" or "class:<classification>"
--   loot:     "itype:<item type>", "isub:<item type>:<subtype>" (Armor:Cloth, Weapon:Staves)
--             or "quest"
-- nil = no category (the full list).
---------------------------------------------------------------------------
local OTHER = "Other"

local function monsterInCategory(n, cat)
	if not cat then return true end
	local kind, value = cat:match("^(%a+):(.*)$")
	if kind == "type" then return (n.type or OTHER) == value end
	if kind == "class" then return (n.class or "normal") == value end
	return true
end

local function itemInCategory(g, cat)
	if not cat then return true end
	if cat == "quest" then return g.quest == true end
	local value = cat:match("^itype:(.*)$")
	if value then return (g.itype or OTHER) == value end
	local t, sub = cat:match("^isub:([^:]*):(.*)$")
	if t then return (g.itype or OTHER) == t and g.isub == sub end
	return true
end

-- Categories present in the view: { { key, kind, value, count }, ... } sorted by count.
local function collect(tbl, keysOf)
	local counts, kinds = {}, {}
	for _, e in pairs(tbl) do
		for _, k in ipairs(keysOf(e)) do
			counts[k[1]] = (counts[k[1]] or 0) + 1
			kinds[k[1]] = k
		end
	end
	local list = {}
	for key, count in pairs(counts) do
		local k = kinds[key]
		list[#list + 1] = { key = key, kind = k[2], value = k[3], count = count }
	end
	table.sort(list, function(a, b)
		if a.kind ~= b.kind then return a.kind < b.kind end
		if a.count ~= b.count then return a.count > b.count end
		return tostring(a.value) < tostring(b.value)
	end)
	return list
end

function St.MonsterCategories(V)
	V = V or St.View()
	return collect(V.npcs, function(n)
		local t = n.type or OTHER
		local keys = { { "type:" .. t, "type", t } }
		local cl = n.class or "normal"
		if cl ~= "normal" then keys[2] = { "class:" .. cl, "class", cl } end
		return keys
	end)
end

-- Item types, each followed by its subtypes (sub = true) when it has more than one.
function St.ItemCategories(V)
	V = V or St.View()
	local subs = {} -- [item type] = { [subtype] = count }
	for _, g in pairs(V.items) do
		local t = g.itype or OTHER
		-- many types have a single subtype named like the type itself (Trade Goods / Trade Goods)
		if g.isub and g.isub ~= t then
			subs[t] = subs[t] or {}
			subs[t][g.isub] = (subs[t][g.isub] or 0) + 1
		end
	end
	local list = {}
	for _, cat in ipairs(collect(V.items, function(g)
		local t = g.itype or OTHER
		local keys = { { "itype:" .. t, "itype", t } }
		if g.quest then keys[2] = { "quest", "quest", "quest" } end
		return keys
	end)) do
		list[#list + 1] = cat
		local children = {}
		for name, count in pairs(cat.kind == "itype" and subs[cat.value] or {}) do
			children[#children + 1] = { key = "isub:" .. cat.value .. ":" .. name, kind = "itype", value = name, count = count, sub = true }
		end
		-- a single subtype covering the whole type adds nothing
		if #children > 1 or (#children == 1 and children[1].count < cat.count) then
			table.sort(children, function(a, b)
				if a.count ~= b.count then return a.count > b.count end
				return a.value < b.value
			end)
			for _, c in ipairs(children) do list[#list + 1] = c end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Lists for the journal (search + category + sort)
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

function St.MonsterList(query, sortKey, category, V)
	V = V or St.View()
	local q = query and query ~= "" and query:lower() or nil
	local out = {}
	for id, n in pairs(V.npcs) do
		local name = n.name or ("NPC #" .. id)
		if monsterInCategory(n, category) and matches(q, name, id) then
			local e = { id = id, name = name, n = n }
			if sortKey == "value" then e.v = St.NPCValuePerCorpse(n) or 0 end
			if sortKey == "items" then e.v = MJ.Count(n.items) end
			out[#out + 1] = e
		end
	end
	table.sort(out, function(a, b)
		if sortKey == "name" then return a.name < b.name end
		if sortKey == "last" then
			local ta, tb = a.n.lastKill and a.n.lastKill.t or 0, b.n.lastKill and b.n.lastKill.t or 0
			if ta ~= tb then return ta > tb end
		elseif sortKey == "value" or sortKey == "items" then
			if a.v ~= b.v then return a.v > b.v end
		elseif sortKey == "deaths" then
			-- killing blows first, then times it was attacking you when you died
			local da, db = a.n.deathsTo or 0, b.n.deathsTo or 0
			if da ~= db then return da > db end
			local aa, ab = a.n.deathAssists or 0, b.n.deathAssists or 0
			if aa ~= ab then return aa > ab end
			if a.n.kills ~= b.n.kills then return a.n.kills > b.n.kills end
		else
			if a.n.kills ~= b.n.kills then return a.n.kills > b.n.kills end
		end
		return a.name < b.name
	end)
	return out
end

function St.ItemList(query, sortKey, category, V)
	V = V or St.View()
	local q = query and query ~= "" and query:lower() or nil
	local out = {}
	for id, g in pairs(V.items) do
		local name = g.name or ("Item #" .. id)
		if itemInCategory(g, category) and matches(q, name, id) then
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
