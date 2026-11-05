-- UI/OverviewView.lua: account-wide dashboard.
local _, MJ = ...
local UI, St = MJ.UI, MJ.Stats
local Num, Pct, Money, Dur = MJ.Num, MJ.Pct, MJ.Money, MJ.Dur
local Grey = UI.Grey
local format, max = string.format, math.max

local function npcRow(npcId, cells)
	return {
		cells = cells,
		onClick = function() UI:Navigate(UI.TAB_MONSTERS, npcId) end,
	}
end

local function dropRow(d, extra)
	return {
		icon = MJ:ItemIcon(d.item),
		cells = { MJ:ItemText(d.item), UI.NPCLabel(d.npc), extra[1], extra[2] },
		onEnter = function(_, tt) tt:SetItemByID(d.item) end,
		onClick = function() UI:Navigate(UI.TAB_LOOT, d.item) end,
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

local function sumDays(count)
	local r = {}
	for _, f in ipairs({ "kills", "corpses", "money", "vendor", "xp" }) do r[f] = St.SumDays(count, f) end
	return r
end

function UI.views.overview(c)
	local db = MJ.db
	local G = St.Global()
	local T = db.totals

	c:Section("Totals")
	c:Grid({
		{ "Kills", Num(G.kills) },
		{ "Monsters discovered", Num(G.npcCount) },
		{ "Items discovered", Num(G.itemCount) },
		{ "Corpses looted", Num(G.looted) },
		{ "Empty corpses", Num(G.empty) },
		{ "Items looted (qty)", Num(G.qty) },
		{ "Gold looted", Money(T.money or 0), "All money from loot windows (corpses, gathering, containers, fishing)." },
		{ "Vendor value", Money(T.vendor or 0), "Vendor value of loot at the time it was looted." },
		{ "Total value", Money((T.money or 0) + (T.vendor or 0)) },
		{ "XP from kills", Num(T.xp or 0) },
		{ "Deaths", Num(T.deaths or 0) },
		{ "Time in combat", Dur(G.ttk), "Summed engagement time of all recorded kills." },
		{ "Damage dealt", Num(T.dmgDone or 0), "Your (and your pet's) damage to monsters, read from the built-in damage meter after each fight." },
		{ "Damage taken", Num(T.dmgTaken or 0), "Damage monsters dealt to you, from the built-in damage meter." },
		{ "Rares found", Num(MJ.Count(db.rares)) },
	}, 3)

	c:Section("Periods")
	local s = MJ.session
	local hours = max((time() - s.start) / 3600, 1 / 60)
	c:Table({
		{ "Period", 110 }, { "Kills", 60, "RIGHT" }, { "Corpses", 60, "RIGHT" }, { "Gold", 100, "RIGHT" },
		{ "Vendor", 100, "RIGHT" }, { "XP", 70, "RIGHT" }, { "Per hour", 200, "RIGHT" },
	}, {
		periodRow("This session", s, hours),
		periodRow("Today", db.days[MJ.DayKey()] or {}),
		periodRow("Last 7 days", sumDays(7)),
		periodRow("Last 30 days", sumDays(30)),
		periodRow("All time", T),
	})
	c:Text(Grey("Session started " .. MJ.Date(s.start) .. " (" .. Dur(time() - s.start) .. ")."))

	c:Section("Kills - last 30 days")
	local vals, keys = St.LastDays(30, function(k) return db.days[k] and db.days[k].kills end)
	c:Bars(vals, 70, function(i, tt)
		local d = db.days[keys[i]] or {}
		tt:SetText(St.DayLabel(keys[i]), 1, 1, 1)
		tt:AddDoubleLine("Kills", Num(d.kills or 0), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddDoubleLine("Corpses", Num(d.corpses or 0), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddDoubleLine("Gold", Money(d.money or 0), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddDoubleLine("Vendor value", Money(d.vendor or 0), 0.8, 0.8, 0.8, 1, 1, 1)
		tt:AddDoubleLine("XP", Num(d.xp or 0), 0.8, 0.8, 0.8, 1, 1, 1)
	end, St.DayLabel(keys[1]), "today")
	local bestK, bestV = St.BestDay(db.days)
	if bestK then c:Text("Best day ever: " .. UI.Gold(Num(bestV)) .. " kills on " .. St.DayLabel(bestK) .. ".") end

	-- records
	c:Section("Most killed")
	local rows = {}
	for i = 1, math.min(10, #G.sortedKills) do
		local id = G.sortedKills[i]
		local n = db.npcs[id]
		rows[#rows + 1] = npcRow(id, { "#" .. i, UI.NPCLabel(id), Num(n.kills), Pct(n.kills / max(G.kills, 1)) })
	end
	c:Table({ { "#", 30 }, { "Monster", 260 }, { "Kills", 70, "RIGHT" }, { "Share", 70, "RIGHT" } }, rows, { empty = "No kills yet." })

	c:Section("Best farm (value per corpse)", "min. 10 corpses")
	rows = {}
	for _, e in ipairs(St.Top(db.npcs, 10, function(_, n)
		if St.Corpses(n) < 10 then return nil end
		return St.NPCValuePerCorpse(n)
	end)) do
		local n = e.e
		rows[#rows + 1] = npcRow(e.id, { UI.NPCLabel(e.id), Money(e.score), Money(n.money / St.Corpses(n)), Num(St.Corpses(n)) })
	end
	c:Table({ { "Monster", 260 }, { "Value/corpse", 110, "RIGHT" }, { "Gold/corpse", 110, "RIGHT" }, { "Corpses", 70, "RIGHT" } }, rows, { empty = "Not enough data yet." })

	c:Section("Fastest kills (avg time in combat)", "min. 5 kills")
	rows = {}
	for _, e in ipairs(St.Top(db.npcs, 10, function(_, n)
		if (n.ttkN or 0) < 5 then return nil end
		return n.ttkSum / n.ttkN
	end, true)) do
		rows[#rows + 1] = npcRow(e.id, { UI.NPCLabel(e.id), Dur(e.score), Dur(e.e.ttkMin), Num(e.e.ttkN) })
	end
	c:Table({ { "Monster", 260 }, { "Avg", 80, "RIGHT" }, { "Fastest", 80, "RIGHT" }, { "Kills", 70, "RIGHT" } }, rows, { empty = "Not enough data yet." })

	c:Section("Hardest hitters", "damage taken per kill")
	rows = {}
	for _, e in ipairs(St.Top(db.npcs, 10, function(_, n)
		if (n.dmgKills or 0) < 3 or not n.dmgKillTaken then return nil end
		return n.dmgKillTaken / n.dmgKills
	end)) do
		rows[#rows + 1] = npcRow(e.id, { UI.NPCLabel(e.id), Num(e.score), Num(e.e.dmgTaken or 0), Num(e.e.dmgKills) })
	end
	c:Table({ { "Monster", 260 }, { "Taken/kill", 90, "RIGHT" }, { "Total taken", 100, "RIGHT" }, { "Kills", 70, "RIGHT" } }, rows, { empty = "Not enough data yet." })

	c:Section("Nemesis", "monsters that killed you")
	rows = {}
	for _, e in ipairs(St.Top(db.npcs, 10, function(_, n) return (n.deathsTo or 0) > 0 and n.deathsTo or nil end)) do
		rows[#rows + 1] = npcRow(e.id, { UI.NPCLabel(e.id), Num(e.score), Num(e.e.kills), format("%.1f", e.e.kills / e.score) })
	end
	c:Table({ { "Monster", 260 }, { "Deaths", 70, "RIGHT" }, { "Your kills", 80, "RIGHT" }, { "Kills/death", 80, "RIGHT" } }, rows, { empty = "You haven't died yet. Nice." })

	local all = St.AllDrops(20)
	c:Section("Rarest drops found", "lowest rate · min. 20 corpses")
	table.sort(all, function(a, b) return a.rate < b.rate end)
	rows = {}
	for i = 1, math.min(10, #all) do rows[#rows + 1] = dropRow(all[i], { Pct(all[i].rate), Num(all[i].it.drops) .. " / " .. Num(all[i].corpses) }) end
	c:Table({ { "Item", 220 }, { "From", 200 }, { "Rate", 70, "RIGHT" }, { "Drops/corpses", 100, "RIGHT" } }, rows, { empty = "Not enough data yet." })

	c:Section("Luckiest drops", "came sooner than expected")
	local lucky = {}
	for _, d in ipairs(St.AllDrops(0)) do
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
	for _, d in ipairs(St.AllDrops(10)) do
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
	for key, ch in pairs(db.chars) do
		rows[#rows + 1] = { k = ch.kills or 0, cells = { MJ:CharName(key), Num(ch.kills or 0), Num(ch.corpses or 0), Money(ch.money or 0), Money(ch.vendor or 0), Num(ch.xp or 0), Num(ch.deaths or 0) } }
	end
	table.sort(rows, function(a, b) return a.k > b.k end)
	c:Table({ { "Character", 150 }, { "Kills", 60, "RIGHT" }, { "Corpses", 60, "RIGHT" }, { "Gold", 100, "RIGHT" }, { "Vendor", 100, "RIGHT" }, { "XP", 70, "RIGHT" }, { "Deaths", 50, "RIGHT" } }, rows)

	c:Section("Drops by quality")
	rows = {}
	for q = 7, 0, -1 do
		if G.byQuality[q] then
			rows[#rows + 1] = { cells = { MJ.QualityHex(q) .. MJ.QualityName(q) .. "|r", Num(G.byQuality[q]), Pct(G.byQuality[q] / max(G.drops, 1)) } }
		end
	end
	c:Table({ { "Quality", 180 }, { "Drops", 70, "RIGHT" }, { "Share", 70, "RIGHT" } }, rows)

	if next(db.fishing) then
		c:Section("Fishing")
		rows = {}
		for zone, f in pairs(db.fishing) do rows[#rows + 1] = { k = f.catches, cells = { zone, Num(f.catches), Num(MJ.Count(f.items)) } } end
		table.sort(rows, function(a, b) return a.k > b.k end)
		c:Table({ { "Zone", 220 }, { "Catches", 70, "RIGHT" }, { "Distinct items", 100, "RIGHT" } }, rows)
	end
end

UI.views[1] = UI.views.overview
