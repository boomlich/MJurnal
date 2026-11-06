-- UI/OverviewView.lua: account-wide dashboard.
local _, MJ = ...
local UI, St = MJ.UI, MJ.Stats
local Num, Pct, Money, Dur = MJ.Num, MJ.Pct, MJ.Money, MJ.Dur
local Grey = UI.Grey
local format, max = string.format, math.max

local function npcRow(npcId, cells)
	return {
		cells = cells,
		onClick = function() UI:Open(UI.TAB_MONSTERS, npcId) end,
	}
end

local function dropRow(d, extra)
	return {
		icon = MJ:ItemIcon(d.item),
		cells = { MJ:ItemText(d.item), UI.NPCLabel(d.npc), extra[1], extra[2] },
		onEnter = function(_, tt) tt:SetItemByID(d.item) end,
		onClick = function() UI:Open(UI.TAB_LOOT, d.item) end,
	}
end

local function periodRow(label, p, hours)
	local cells = { label, Num(p.kills or 0), Num(p.corpses or 0), Money(p.money or 0), Money(p.vendor or 0), Num(p.xp or 0) }
	if hours then
		cells[#cells + 1] = Num((p.kills or 0) / hours) .. "/h  ·  " .. Money(((p.money or 0) + (p.vendor or 0)) / hours) .. "/h"
	else
		cells[#cells + 1] = ""
	end
	return { cells = cells }
end

local function sumDays(V, count)
	local r = {}
	for _, f in ipairs({ "kills", "corpses", "money", "vendor", "xp" }) do r[f] = St.SumDays(count, f, V) end
	return r
end

function UI.views.overview(c)
	local V = St.View()
	local G = St.Global(V)
	local T = V.totals
	local npcs, days = V.npcs, V.days

	c:Section("Totals")
	c:Grid({
		{ "Kills", Num(T.kills or 0) },
		{ "Monsters discovered", Num(G.npcCount) },
		{ "Items discovered", Num(G.itemCount) },
		{ "Corpses looted", Num(G.looted) },
		{ "Empty corpses", Num(G.empty) },
		{ "Items looted (qty)", Num(G.qty) },
		{ "Gold looted", Money(T.money or 0), "All money from loot windows (corpses, gathering, containers, fishing)." },
		{ "Vendor value", Money(T.vendor or 0), "Vendor value of loot at the time it was looted." },
		{ "Total value", Money((T.money or 0) + (T.vendor or 0)) },
		{ "AH value of loot", (function()
			local v, priced = St.AHValue(V.items)
			return priced > 0 and Money(v) or "-"
		end)(), "Everything you looted at today's auction price (items with a price only). " .. UI.AH_NOTE },
		{ "XP from kills", Num(T.xp or 0) },
		{ "Deaths", Num(T.deaths or 0) },
		{ "Time in combat", Dur(G.ttk), "Summed engagement time of all recorded kills." },
		{ "Damage dealt", Num(T.dmgDone or 0), "Your (and your pet's) damage to monsters, read from the built-in damage meter after each fight." },
		{ "Damage taken", Num(T.dmgTaken or 0), "Damage monsters dealt to you, from the built-in damage meter." },
		{ "Rares found", Num(MJ.Count(V.rares)) },
	}, 3)

	c:Section("Periods")
	local s = MJ.session
	local hours = max((time() - s.start) / 3600, 1 / 60)
	-- the session is the character you are playing; only show it when that character is selected
	local showSession = V.Includes(MJ.charKey)
	local periods = {}
	if showSession then periods[#periods + 1] = periodRow("This session", s, hours) end
	periods[#periods + 1] = periodRow("Today", days[MJ.DayKey()] or {})
	periods[#periods + 1] = periodRow("Last 7 days", sumDays(V, 7))
	periods[#periods + 1] = periodRow("Last 30 days", sumDays(V, 30))
	periods[#periods + 1] = periodRow("All time", T)
	c:Table({
		{ "Period", 110 }, { "Kills", 60, "RIGHT" }, { "Corpses", 60, "RIGHT" }, { "Gold", 100, "RIGHT" },
		{ "Vendor", 100, "RIGHT" }, { "XP", 70, "RIGHT" }, { "Per hour", 200, "RIGHT" },
	}, periods)
	if showSession then
		c:Text(Grey("Session started " .. MJ.Date(s.start) .. " (" .. Dur(time() - s.start) .. ")."))
	end

	c:Section("Kills - last 30 days")
	local vals, keys = St.LastDays(30, function(k) return days[k] and days[k].kills end)
	c:Bars(vals, 70, function(i, tt)
		local d = days[keys[i]] or {}
		tt:SetText(St.DayLabel(keys[i]), 1, 1, 1)
		tt:AddDoubleLine("Kills", Num(d.kills or 0), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddDoubleLine("Corpses", Num(d.corpses or 0), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddDoubleLine("Gold", Money(d.money or 0), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddDoubleLine("Vendor value", Money(d.vendor or 0), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddDoubleLine("XP", Num(d.xp or 0), 0.8, 0.8, 0.8, 1, 1, 1)
	end, St.DayLabel(keys[1]), "today")
	local bestK, bestV = St.BestDay(days)
	if bestK then c:Text("Best day ever: " .. UI.Gold(Num(bestV)) .. " kills on " .. St.DayLabel(bestK) .. ".") end

	-- records
	c:Section("Most killed")
	local rows = {}
	for i = 1, math.min(10, #G.sortedKills) do
		local id = G.sortedKills[i]
		local n = npcs[id]
		rows[#rows + 1] = npcRow(id, { "#" .. i, UI.NPCLabel(id), Num(n.kills), Pct(n.kills / max(G.kills, 1)) })
	end
	c:Table({ { "#", 30 }, { "Monster", 260 }, { "Kills", 70, "RIGHT" }, { "Share", 70, "RIGHT" } }, rows, { empty = "No kills yet." })

	c:Section("Best farm (value per corpse)", "min. 10 corpses")
	rows = {}
	for _, e in ipairs(St.Top(npcs, 10, function(_, n)
		if St.Corpses(n) < 10 then return nil end
		return St.NPCValuePerCorpse(n)
	end)) do
		local n = e.e
		local corpses = St.Corpses(n)
		rows[#rows + 1] = npcRow(e.id, {
			UI.NPCLabel(e.id), Money(e.score), Money((n.money + St.MarketValue(n.items)) / corpses), Money(n.money / corpses), Num(corpses),
		})
	end
	c:Table({
		{ "Monster", 260 }, { "Value/corpse", 110, "RIGHT", "Gold + vendor value per corpse." },
		{ "AH value/corpse", 120, "RIGHT", "Gold + items at their auction price (vendor price without one) per corpse." },
		{ "Gold/corpse", 110, "RIGHT" }, { "Corpses", 70, "RIGHT" },
	}, rows, { empty = "Not enough data yet." })

	c:Section("Fastest kills (avg time in combat)", "min. 5 kills")
	rows = {}
	for _, e in ipairs(St.Top(npcs, 10, function(_, n)
		if (n.ttkN or 0) < 5 then return nil end
		return n.ttkSum / n.ttkN
	end, true)) do
		rows[#rows + 1] = npcRow(e.id, { UI.NPCLabel(e.id), Dur(e.score), Dur(e.e.ttkMin), Num(e.e.ttkN) })
	end
	c:Table({ { "Monster", 260 }, { "Avg", 80, "RIGHT" }, { "Fastest", 80, "RIGHT" }, { "Kills", 70, "RIGHT" } }, rows, { empty = "Not enough data yet." })

	c:Section("Hardest hitters", "damage taken per kill")
	rows = {}
	for _, e in ipairs(St.Top(npcs, 10, function(_, n)
		if (n.dmgKills or 0) < 3 or not n.dmgKillTaken then return nil end
		return n.dmgKillTaken / n.dmgKills
	end)) do
		rows[#rows + 1] = npcRow(e.id, { UI.NPCLabel(e.id), Num(e.score), Num(e.e.dmgTaken or 0), Num(e.e.dmgKills) })
	end
	c:Table({ { "Monster", 260 }, { "Taken/kill", 90, "RIGHT" }, { "Total taken", 100, "RIGHT" }, { "Kills", 70, "RIGHT" } }, rows, { empty = "Not enough data yet." })

	-- deaths
	local deaths = T.deaths or 0
	local streak = V.streak
	c:Section("Deaths", deaths > 0 and ("|cffff4040" .. Num(deaths) .. " total|r") or nil)
	local lastDeath = St.Deaths(nil, 1, V)[1]
	c:Grid({
		{ "Deaths", Num(deaths) },
		{ "Kills per death", deaths > 0 and format("%.1f", (T.kills or 0) / deaths) or "-" },
		{ "Deaths today", Num((days[MJ.DayKey()] or {}).deaths or 0) },
		{ "Current kill streak", Num(streak.cur or 0), MJ:CharFilter() and "Kills since the last death, per character (the highest of the selected)." or "Kills since your last death (any character on the account)." },
		{ "Best kill streak", Num(streak.best or 0), streak.bestT and ("Reached " .. MJ.Date(streak.bestT)) or nil },
		{ "Last 7 / 30 days", Num(St.SumDays(7, "deaths", V)) .. " / " .. Num(St.SumDays(30, "deaths", V)) },
		{ "Last death", lastDeath and MJ.Ago(lastDeath.t) or "-", lastDeath and function(tt) UI.DeathTooltip(tt, lastDeath) end },
		{ "Time alive", streak.lastDeath and Dur(time() - streak.lastDeath) or "-", "Time since your last death (real time, any character)." },
		{ "Environment deaths", Num((function() local s = 0 for _, v in pairs(V.deathEnv) do s = s + v end return s end)()), "Falling, drowning, fatigue, lava..." },
	}, 3)

	if deaths > 0 then
		local dvals, dkeys = St.LastDays(30, function(k) return days[k] and days[k].deaths end)
		c:Bars(dvals, 40, function(i, tt)
			tt:SetText(St.DayLabel(dkeys[i]), 1, 1, 1)
			tt:AddLine(Num(dvals[i]) .. " deaths", 1, 0.3, 0.3)
		end, St.DayLabel(dkeys[1]), "today")

		c:Text(UI.Gold("Recent deaths"), GameFontNormal)
		rows = {}
		for _, e in ipairs(St.Deaths(nil, 10, V)) do
			rows[#rows + 1] = {
				cells = { MJ.Date(e.t), UI.DeathKiller(e), UI.DeathCause(e), e.adds and Num(e.adds) or "-", e.z or "-", MJ:CharName(e.c) },
				onEnter = function(_, tt) UI.DeathTooltip(tt, e) end,
				onClick = function() if e.npc and npcs[e.npc] then UI:Open(UI.TAB_MONSTERS, e.npc) end end,
			}
		end
		c:Table({ { "When", 110 }, { "Killed by", 190 }, { "Killing blow", 230 }, { "Enemies", 54, "RIGHT" }, { "Zone", 150 }, { "Character", 90 } }, rows)
	end

	c:Text(UI.Gold("Nemesis") .. UI.Grey("  ·  monsters that killed you"), GameFontNormal)
	rows = {}
	for _, e in ipairs(St.Top(npcs, 10, function(_, n) return (n.deathsTo or 0) > 0 and n.deathsTo or nil end)) do
		local n = e.e
		rows[#rows + 1] = npcRow(e.id, {
			UI.NPCLabel(e.id), Num(e.score), Num(n.deathAssists or 0), Num(n.kills), format("%.1f", n.kills / e.score),
			Pct(e.score / max(n.kills + e.score, 1)), n.kbMax and Num(n.kbMax) or "-",
		})
	end
	c:Table({
		{ "Monster", 220 }, { "Killed you", 70, "RIGHT" }, { "Attacking", 66, "RIGHT", "Deaths where it was attacking you but did not land the killing blow." },
		{ "Your kills", 70, "RIGHT" }, { "Kills/death", 74, "RIGHT" }, { "Fights lost", 74, "RIGHT", "Deaths / (kills + deaths)." },
		{ "Biggest hit", 80, "RIGHT", "Biggest killing blow it dealt you." },
	}, rows, { empty = "You haven't died yet. Nice." })

	if next(V.deathZones) or next(V.deathEnv) then
		rows = {}
		for zone, k in pairs(V.deathZones) do
			rows[#rows + 1] = { k = k, cells = { zone, Num(k), Pct(k / max(deaths, 1)) } }
		end
		table.sort(rows, function(a, b) return a.k > b.k end)
		c:Text(UI.Gold("Deaths by zone"), GameFontNormal)
		c:Table({ { "Zone", 220 }, { "Deaths", 70, "RIGHT" }, { "Share", 70, "RIGHT" } }, rows, { max = 10 })

		-- causes: killing abilities across all monsters + environment
		local causes = {}
		for npcId, n in pairs(npcs) do
			for spellID, ds in pairs(n.deathSpells or {}) do
				local label = (spellID == 0 and "Melee" or (ds.name or UI.SpellLabel(spellID)))
				causes[#causes + 1] = { k = ds.c, cells = { label, UI.NPCLabel(npcId), Num(ds.c), Num(ds.max or 0) } }
			end
		end
		for env, k in pairs(V.deathEnv) do
			causes[#causes + 1] = { k = k, cells = { UI.DeathCause({ kb = { env = env } }), UI.Grey("environment"), Num(k), "-" } }
		end
		if #causes > 0 then
			table.sort(causes, function(a, b) return a.k > b.k end)
			c:Text(UI.Gold("What killed you"), GameFontNormal)
			c:Table({ { "Killing blow", 200 }, { "From", 200 }, { "Deaths", 70, "RIGHT" }, { "Biggest", 80, "RIGHT" } }, causes, { max = 10 })
		end
	end

	local all = St.AllDrops(20, V)
	c:Section("Rarest drops found", "lowest rate · min. 20 corpses")
	table.sort(all, function(a, b) return a.rate < b.rate end)
	rows = {}
	for i = 1, math.min(10, #all) do rows[#rows + 1] = dropRow(all[i], { Pct(all[i].rate), Num(all[i].it.drops) .. " / " .. Num(all[i].corpses) }) end
	c:Table({ { "Item", 220 }, { "From", 200 }, { "Rate", 70, "RIGHT" }, { "Drops/corpses", 100, "RIGHT" } }, rows, { empty = "Not enough data yet." })

	c:Section("Luckiest drops", "came sooner than expected")
	local lucky = {}
	for _, d in ipairs(St.AllDrops(0, V)) do
		local l = St.Luck(d.it)
		if l and d.it.luckN >= 2 then
			d.luck = l
			lucky[#lucky + 1] = d
		end
	end
	table.sort(lucky, function(a, b) return a.luck > b.luck end)
	rows = {}
	for i = 1, math.min(5, #lucky) do rows[#rows + 1] = dropRow(lucky[i], { UI.LuckText(lucky[i].luck), Num(lucky[i].it.luckN) .. " drops" }) end
	c:Table({ { "Item", 220 }, { "From", 200 }, { "Luck", 70, "RIGHT" }, { "Measured", 100, "RIGHT" } }, rows, { empty = "Not enough data yet." })

	c:Section("Most overdue", "current dry streak vs. drop rate")
	local overdue = {}
	for _, d in ipairs(St.AllDrops(10, V)) do
		if d.it.drops >= 2 then
			local since = St.Since(d.n, d.it)
			d.since = since
			d.drought = St.Drought(d.rate, since)
			overdue[#overdue + 1] = d
		end
	end
	table.sort(overdue, function(a, b) return a.drought < b.drought end)
	rows = {}
	for i = 1, math.min(5, #overdue) do
		local d = overdue[i]
		rows[#rows + 1] = dropRow(d, { Num(d.since) .. Grey(" / " .. UI.OneIn(d.rate)), Pct(d.drought) })
	end
	c:Table({ { "Item", 220 }, { "From", 200 }, { "Since / 1 in", 100, "RIGHT" }, { "Chance", 70, "RIGHT", "Probability of a dry streak at least this long." } }, rows, { empty = "Not enough data yet." })

	-- breakdowns
	c:Section("By creature type")
	rows = {}
	for t, b in pairs(G.byType) do rows[#rows + 1] = { k = b.kills, cells = { t, Num(b.kills), Pct(b.kills / max(G.kills, 1)), Money(b.money), Money(b.value) } } end
	table.sort(rows, function(a, b) return a.k > b.k end)
	c:Table({ { "Type", 180 }, { "Kills", 70, "RIGHT" }, { "Share", 70, "RIGHT" }, { "Gold", 110, "RIGHT" }, { "Total value", 110, "RIGHT" } }, rows)

	c:Section("By classification")
	rows = {}
	for cl, b in pairs(G.byClass) do
		local label = UI.CLASS_LABEL[cl]
		rows[#rows + 1] = { k = b.kills, cells = { (label and label ~= "") and label or "Normal", Num(b.kills), Num(b.npcs) } }
	end
	table.sort(rows, function(a, b) return a.k > b.k end)
	c:Table({ { "Classification", 180 }, { "Kills", 70, "RIGHT" }, { "Monsters", 70, "RIGHT" } }, rows)

	c:Section("By zone")
	rows = {}
	for zone, b in pairs(G.byZone) do rows[#rows + 1] = { k = b.kills, cells = { zone, Num(b.kills), Num(b.npcs), Pct(b.kills / max(G.kills, 1)) } } end
	table.sort(rows, function(a, b) return a.k > b.k end)
	c:Table({ { "Zone", 220 }, { "Kills", 70, "RIGHT" }, { "Monsters", 70, "RIGHT" }, { "Share", 70, "RIGHT" } }, rows, { max = 15 })

	c:Section("By character")
	rows = {}
	for key, ch in pairs(V.chars) do
		local d = ch.deaths or 0
		rows[#rows + 1] = { k = ch.kills or 0, cells = {
			MJ:CharName(key), Num(ch.kills or 0), Num(ch.corpses or 0), Money(ch.money or 0), Money(ch.vendor or 0), Num(ch.xp or 0),
			Num(d), d > 0 and format("%.1f", (ch.kills or 0) / d) or "-", Num(ch.bestStreak or 0),
		} }
	end
	table.sort(rows, function(a, b) return a.k > b.k end)
	c:Table({
		{ "Character", 140 }, { "Kills", 60, "RIGHT" }, { "Corpses", 60, "RIGHT" }, { "Gold", 100, "RIGHT" }, { "Vendor", 100, "RIGHT" },
		{ "XP", 70, "RIGHT" }, { "Deaths", 50, "RIGHT" }, { "K/D", 50, "RIGHT" }, { "Best streak", 76, "RIGHT", "Most kills in a row without dying." },
	}, rows)

	c:Section("Drops by quality")
	rows = {}
	for q = 7, 0, -1 do
		if G.byQuality[q] then
			rows[#rows + 1] = { cells = { MJ.QualityHex(q) .. MJ.QualityName(q) .. "|r", Num(G.byQuality[q]), Pct(G.byQuality[q] / max(G.drops, 1)) } }
		end
	end
	c:Table({ { "Quality", 180 }, { "Drops", 70, "RIGHT" }, { "Share", 70, "RIGHT" } }, rows)

	if next(V.nodes) then
		-- herbs, ore, chests, containers and fishing; the Gathering tab has each source
		c:Section("Gathering", "click a type or source to open it")
		local byKind = {}
		for _, nd in pairs(V.nodes) do
			local b = byKind[nd.kind] or { count = 0, sources = 0, qty = 0, value = 0 }
			byKind[nd.kind] = b
			b.count = b.count + (nd.count or 0)
			b.sources = b.sources + 1
			for _, it in pairs(nd.items) do b.qty = b.qty + it.qty end
			b.value = b.value + nd.money + St.NodeVendor(nd)
		end
		rows = {}
		for kind, b in pairs(byKind) do
			rows[#rows + 1] = {
				k = b.count,
				cells = { UI.NODE_KIND[kind] or kind, Num(b.count), Num(b.sources), Num(b.qty), Money(b.value) },
				onClick = function()
					UI.state.category[UI.TAB_GATHER] = "gkind:" .. kind
					UI:Open(UI.TAB_GATHER)
				end,
			}
		end
		table.sort(rows, function(a, b) return a.k > b.k end)
		c:Table({
			{ "Type", 180 }, { "Times", 70, "RIGHT" }, { "Sources", 70, "RIGHT" }, { "Items (qty)", 90, "RIGHT" },
			{ "Total value", 110, "RIGHT", "Money + vendor value of everything it gave." },
		}, rows)

		rows = {}
		for _, e in ipairs(St.Top(V.nodes, 10, function(_, nd)
			if (nd.count or 0) < 5 then return nil end
			return St.NodeValuePer(nd)
		end)) do
			local nd = e.e
			rows[#rows + 1] = {
				icon = UI.NodeIcon(nd.kind),
				cells = { nd.name, UI.NODE_KIND[nd.kind] or nd.kind, Money(e.score), Money((nd.money + St.MarketValue(nd.items)) / nd.count), Num(nd.count) },
				onClick = function() UI:Open(UI.TAB_GATHER, e.id) end,
			}
		end
		c:Text(UI.Gold("Best sources") .. Grey("  ·  value per loot, min. 5 loots"), GameFontNormal)
		c:Table({
			{ "Source", 220 }, { "Type", 130 }, { "Value/loot", 100, "RIGHT", "Money + vendor value per loot." },
			{ "AH value/loot", 110, "RIGHT", "Money + items at their auction price (vendor price without one) per loot." }, { "Times", 70, "RIGHT" },
		}, rows, { empty = "Not enough data yet." })
	end
end

UI.views[UI.TAB_OVERVIEW] = UI.views.overview
