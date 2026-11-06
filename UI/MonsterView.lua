-- UI/MonsterView.lua: everything we know about one NPC.
local _, MJ = ...
local UI, St = MJ.UI, MJ.Stats
local Num, Pct, Money, Dur = MJ.Num, MJ.Pct, MJ.Money, MJ.Dur
local Grey, Gold = UI.Grey, UI.Gold
local format, floor, max = string.format, math.floor, math.max

local GATHER_LABEL = { skin = "Skinning", herb = "Herbalism", mine = "Mining", pick = "Pick Pocket" }
UI.GATHER_LABEL = GATHER_LABEL

-- loot table sorting (one state per table): column index -> value getter
local lootSort = { col = 4, desc = true }
local questSort = { col = 4, desc = true }
-- "1 in" and "50%/90%" both grow with 1 / rate, so they sort on that (not on the rate itself)
local function oneIn(r) return r.p > 0 and 1 / r.p or math.huge end
local SORT_GETTERS = {
	[1] = function(r) return r.name end,
	[2] = function(r) return r.d end,
	[3] = function(r) return r.qOrQty end,
	[4] = function(r) return r.p end,
	[5] = oneIn,
	[6] = function(r) return r.since end,
	[7] = oneIn,
	[8] = function(r) return r.dry end,
	[9] = function(r) return r.last end,
}

local function confirmDelete(npcId)
	StaticPopupDialogs.MJURNAL_DELETE_NPC = StaticPopupDialogs.MJURNAL_DELETE_NPC or {
		text = "Delete the journal entry for %s?\n\nIts kills, loot and stats are removed. Account totals, daily counts and the history log keep counting it.",
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function(_, data)
			MJ:DeleteNPC(data)
			UI.state.selected[UI.TAB_MONSTERS] = nil
			UI:SelectTab(UI.TAB_MONSTERS)
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
	StaticPopup_Show("MJURNAL_DELETE_NPC", MJ:NPCName(npcId), nil, npcId)
end

local function itemRowTooltip(tt, npcId, n, itemId, it)
	local g = MJ.db.items[itemId]
	if g and g.link then tt:SetHyperlink(g.link) else tt:SetItemByID(itemId) end
	local d, corpses, questOnly, since, dry = St.ItemBase(n, itemId, it)
	local p = St.Rate(d, corpses)
	local lo, hi = St.Wilson(d, corpses)
	local function line(l, r) tt:AddDoubleLine(l, r, 0.8, 0.8, 0.8, 1, 1, 1) end
	tt:AddLine(" ")
	tt:AddLine("MJurnal - from " .. MJ:NPCName(npcId), 1, 0.82, 0)
	tt:AddDoubleLine(questOnly and "Drop rate while on the quest" or "Drop rate", Pct(p), 1, 1, 1, 1, 1, 1)
	if lo then tt:AddDoubleLine("95% confidence", Pct(lo) .. " - " .. Pct(hi), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8) end
	line(questOnly and "Dropped / corpses on quest" or "Dropped / corpses", Num(d) .. " / " .. Num(corpses))
	if questOnly and it.drops ~= d then line("Drops before tracking", Num(it.drops - d)) end
	line("Total quantity", Num(it.qty))
	line("Stack min / avg / max", format("%d / %.1f / %d", it.sMin or 0, it.qty / max(it.drops, 1), it.sMax or 0))
	line("Corpses for 50% / 90% / 99%", format("%s / %s / %s", Num(St.KillsFor(p, 0.5)), Num(St.KillsFor(p, 0.9)), Num(St.KillsFor(p, 0.99))))
	line("Corpses since last drop", Num(since))
	if since > 0 and p then line("Chance of a dry streak this long", Pct(St.Drought(p, since))) end
	line("Longest dry streak", Num(dry))
	if not questOnly then
		line("Shortest gap between drops", Num(it.gapMin))
		line("Avg corpses per drop", it.lastAt and format("%.1f", it.lastAt / it.drops) or "-")
	end
	line("First drop", it.firstT and (MJ.Date(it.firstT) .. (questOnly and "" or (" (corpse #" .. (it.firstAt or "?") .. ")"))) or "-")
	line("Last drop", it.lastT and (MJ.Date(it.lastT) .. " (" .. MJ.Ago(it.lastT) .. ")") or "-")
	local luck = not questOnly and St.Luck(it)
	if luck then line("Luck", format("%.2fx over %d drops", luck, it.luckN)) end
	if questOnly then
		tt:AddLine("Quest drop: only counts corpses you looted while an unfinished quest in your log needed this item.", 1, 0.5, 0.2, true)
	elseif it.quest then
		tt:AddLine("Quest item that also drops without the quest, so it uses the normal rate.", 1, 0.5, 0.2, true)
	end
	tt:AddLine("Click: open in loot journal · Shift-click: link in chat", 0.5, 0.5, 0.5)
end

local function sinceText(p, since)
	if not p or since == 0 then return Num(since) end
	local d = St.Drought(p, since)
	if d < 0.02 then return UI.Red(Num(since)) end
	if d < 0.10 then return UI.Orange(Num(since)) end
	return Num(since)
end

-- quest = false: normal drops table; quest = true: quest-only drops table.
-- Returns the number of rows rendered.
local function renderLootTable(c, npcId, n, quest)
	local wanted = MJ.WantedQuestItems()
	local rows = {}
	for itemId, it in pairs(n.items) do
		local d, corpses, questOnly, since, dry = St.ItemBase(n, itemId, it)
		if questOnly == quest then
			local g = MJ.db.items[itemId]
			local name = (g and g.name) or ("Item #" .. itemId)
			rows[#rows + 1] = {
				itemId = itemId, it = it, d = d, corpses = corpses, p = St.Rate(d, corpses) or 0,
				since = since, dry = dry, name = name,
				qOrQty = quest and corpses or it.qty,
				wanted = wanted[name] ~= nil,
				last = quest and (wanted[name] and 1 or 0) or (St.Luck(it) or 0),
			}
		end
	end
	if #rows == 0 then return 0 end
	local sortState = quest and questSort or lootSort
	local getter = SORT_GETTERS[sortState.col] or SORT_GETTERS[4]
	table.sort(rows, function(a, b)
		local va, vb = getter(a), getter(b)
		if va == vb then return a.name < b.name end
		if sortState.desc then return va > vb end
		return va < vb
	end)
	local tableRows = {}
	for _, r in ipairs(rows) do
		local it, p = r.it, r.p
		local k50, k90 = St.KillsFor(p, 0.5), St.KillsFor(p, 0.9)
		local lastCell
		if quest then
			lastCell = r.wanted and UI.Green("needed") or Grey("-")
		else
			lastCell = UI.LuckText(St.Luck(it))
		end
		tableRows[#tableRows + 1] = {
			icon = MJ:ItemIcon(r.itemId),
			cells = {
				MJ:ItemText(r.itemId) .. ((it.quest and not quest) and Grey(" (Q)") or ""),
				Num(r.d), quest and Num(r.corpses) or Num(it.qty), UI.RateText(p, r.corpses), UI.OneIn(p),
				sinceText(p, r.since),
				(k50 and Num(k50) or "-") .. " / " .. (k90 and Num(k90) or "-"),
				Num(r.dry), lastCell,
			},
			onEnter = function(_, tt) itemRowTooltip(tt, npcId, n, r.itemId, it) end,
			onClick = function()
				local g = MJ.db.items[r.itemId]
				if IsModifiedClick("CHATLINK") and g and g.link then
					UI.InsertLink(g.link)
				else
					UI:Open(UI.TAB_LOOT, r.itemId)
				end
			end,
		}
	end
	local cols
	if quest then
		cols = {
			{ "Quest item", 196 },
			{ "Drops", 42, "RIGHT", "Drops while the quest needed it." },
			{ "Corpses", 50, "RIGHT", "Corpses you looted while an unfinished quest in your log needed this item." },
			{ "Rate", 56, "RIGHT", "Drops divided by on-quest corpses. Grey until 20 corpses." },
			{ "1 in", 44, "RIGHT", "Expected on-quest corpses per drop." },
			{ "Since", 44, "RIGHT", "On-quest corpses since the last drop." },
			{ "50%/90%", 66, "RIGHT", "On-quest corpses needed for a 50% / 90% chance of at least one drop." },
			{ "Max dry", 50, "RIGHT", "Longest streak of on-quest corpses without this item." },
			{ "Now", 44, "RIGHT", "Whether a quest in your log needs it right now." },
		}
	else
		cols = {
			{ "Item", 196 },
			{ "Drops", 42, "RIGHT", "Number of corpses that had this item." },
			{ "Qty", 44, "RIGHT", "Total quantity (stacks summed)." },
			{ "Rate", 56, "RIGHT", "Drops divided by corpses (looted + confirmed empty). Grey until 20 corpses." },
			{ "1 in", 44, "RIGHT", "Expected corpses per drop (1 / rate)." },
			{ "Since", 44, "RIGHT", "Corpses since the last drop. Orange/red when a dry streak this long is unlikely (<10% / <2%)." },
			{ "50%/90%", 66, "RIGHT", "Corpses needed for a 50% / 90% chance of at least one drop." },
			{ "Max dry", 50, "RIGHT", "Longest streak of corpses without this item." },
			{ "Luck", 44, "RIGHT", "Average of expected/actual corpses per drop. Above 1x = luckier than average." },
		}
	end
	c:Table(cols, tableRows, {
		sortCol = sortState.col, sortDesc = sortState.desc,
		onSort = function(i)
			if sortState.col == i then sortState.desc = not sortState.desc else sortState.col, sortState.desc = i, i ~= 1 end
			UI:RenderDetail(false)
		end,
	})
	return #rows
end

local function renderGather(c, n)
	if not n.gather then return end
	for kind, gk in pairs(n.gather) do
		c:Section(GATHER_LABEL[kind] or kind)
		local grid = { { kind == "pick" and "Successful" or "Times", Num(gk.count) } }
		if kind == "pick" then
			grid[#grid + 1] = { "Attempts", Num(gk.tries or 0) }
			grid[#grid + 1] = { "Success rate", (gk.tries or 0) > 0 and Pct(gk.count / gk.tries) or "-" }
		end
		if gk.money > 0 then
			grid[#grid + 1] = { "Money", Money(gk.money) }
			grid[#grid + 1] = { "Avg money", Money(gk.money / max(gk.count, 1)) }
		end
		c:Grid(grid, 3)
		local rows = {}
		for itemId, it in pairs(gk.items) do
			local p = St.Rate(it.drops, gk.count)
			rows[#rows + 1] = {
				sortv = p or 0,
				icon = MJ:ItemIcon(itemId),
				cells = { MJ:ItemText(itemId), Num(it.drops), Num(it.qty), UI.RateText(p, gk.count), UI.OneIn(p), format("%.2f", it.qty / max(gk.count, 1)) },
				onEnter = function(_, tt) tt:SetItemByID(itemId) end,
				onClick = function() UI:Open(UI.TAB_LOOT, itemId) end,
			}
		end
		table.sort(rows, function(a, b) return a.sortv > b.sortv end)
		c:Table({ { "Item", 220 }, { "Times", 50, "RIGHT" }, { "Qty", 50, "RIGHT" }, { "Rate", 60, "RIGHT" }, { "1 in", 50, "RIGHT" }, { "Avg qty", 60, "RIGHT", "Average quantity per attempt." } }, rows, { empty = "No items." })
	end
end

local function renderDeaths(c, npcId, n)
	local deaths, assists = n.deathsTo or 0, n.deathAssists or 0
	c:Section("Deaths", deaths > 0 and ("|cffff4040" .. Num(deaths) .. " killing blow" .. (deaths == 1 and "" or "s") .. "|r") or nil)
	if deaths == 0 and assists == 0 then
		c:Text(Grey("It has never killed you."))
		return
	end
	local rank
	if deaths > 0 then
		rank = 1
		for _, other in pairs(MJ.db.npcs) do
			if (other.deathsTo or 0) > deaths then rank = rank + 1 end
		end
	end
	local encounters = n.kills + deaths
	c:Grid({
		{ "Killed you", Num(deaths), "Deaths where this monster landed the killing blow (from the death recap), or was the one fighting you." },
		{ "Was attacking", Num(assists), "Deaths where it was attacking you, but something else got the killing blow." },
		{ "Nemesis rank", rank and ("#" .. rank) or "-", "Your deadliest monsters, ranked by killing blows." },
		{ "Kills per death", deaths > 0 and format("%.1f", n.kills / deaths) or "-" },
		{ "Fights lost", encounters > 0 and Pct(deaths / encounters) or "-", "Deaths / (kills + deaths)." },
		{ "Share of your deaths", (MJ.db.totals.deaths or 0) > 0 and Pct(deaths / MJ.db.totals.deaths) or "-" },
		{ "Biggest killing blow", n.kbMax and Num(n.kbMax) or "-" },
		{ "Avg level difference", (n.deathDiffN or 0) > 0 and format("%+.1f", n.deathDiffSum / n.deathDiffN) or "-", "Your level minus its level when it killed you." },
		{ "Avg enemies on you", deaths > 0 and n.deathAddsSum and format("%.1f", n.deathAddsSum / deaths) or "-", "How many enemies were attacking you when you died." },
		{ "Avg fight length", deaths > 0 and n.deathDurSum and Dur(n.deathDurSum / deaths) or "-" },
		{ "First death", n.firstDeathTo and MJ.Date(n.firstDeathTo.t) or "-", n.firstDeathTo and ("By " .. MJ:CharName(n.firstDeathTo.c) .. " in " .. (n.firstDeathTo.z or "?")) },
		{ "Last death", n.lastDeathTo and MJ.Ago(n.lastDeathTo.t) or "-", n.lastDeathTo and (MJ.Date(n.lastDeathTo.t) .. " · " .. MJ:CharName(n.lastDeathTo.c)) },
	}, 3)

	if n.deathSpells and next(n.deathSpells) then
		local rows = {}
		for spellID, ds in pairs(n.deathSpells) do
			rows[#rows + 1] = {
				c = ds.c,
				icon = spellID ~= 0 and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID) or nil,
				cells = { spellID == 0 and "Melee" or (ds.name or UI.SpellLabel(spellID)), Num(ds.c), Pct(ds.c / math.max(deaths, 1)), Num(ds.max or 0) },
				onEnter = spellID ~= 0 and function(_, tt) tt:SetSpellByID(spellID) end or nil,
			}
		end
		table.sort(rows, function(a, b) return a.c > b.c end)
		c:Text(Gold("Killing blows"), GameFontNormal)
		c:Table({ { "Ability", 200 }, { "Deaths", 60, "RIGHT" }, { "Share", 60, "RIGHT" }, { "Biggest", 80, "RIGHT" } }, rows)
	end

	local recent = St.Deaths(npcId, 8)
	if #recent > 0 then
		local rows = {}
		for _, e in ipairs(recent) do
			rows[#rows + 1] = {
				cells = {
					MJ.Date(e.t), e.npc == npcId and UI.Red("killed you") or UI.Grey("attacking"),
					UI.DeathCause(e), e.adds and Num(e.adds) or "-", e.lvl and (e.lvl .. (e.mlvl and (" vs " .. e.mlvl) or "")) or "-",
					MJ:CharName(e.c),
				},
				onEnter = function(_, tt) UI.DeathTooltip(tt, e) end,
			}
		end
		c:Text(Gold("Recent deaths"), GameFontNormal)
		c:Table({ { "When", 110 }, { "Role", 70 }, { "Killing blow", 210 }, { "Enemies", 54, "RIGHT" }, { "Level", 70, "RIGHT" }, { "Character", 90 } }, rows)
	end
end

local function setWaypoint(mapID, x, y)
	if not (C_Map and C_Map.CanSetUserWaypointOnMap and UiMapPoint) then return end
	local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
	if not ok or not can then
		MJ:Print("Can't place a waypoint on that map.")
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
	MJ:Print(format("Waypoint set at %.1f, %.1f.", x * 100, y * 100))
end

local function renderLocation(c, n)
	local zoneRows = {}
	for zone, z in pairs(n.zones) do
		local subs = {}
		for sub, k in pairs(z.sub) do subs[#subs + 1] = { sub, k } end
		table.sort(subs, function(a, b) return a[2] > b[2] end)
		zoneRows[#zoneRows + 1] = {
			k = z.kills,
			cells = { zone, Num(z.kills), Pct(z.kills / max(n.kills, 1)), subs[1] and subs[1][1] or Grey("-") },
			onEnter = function(_, tt)
				tt:SetText(zone, 1, 1, 1)
				for _, s in ipairs(subs) do tt:AddDoubleLine(s[1], Num(s[2]), 0.8, 0.8, 0.8, 1, 1, 1) end
			end,
		}
	end
	table.sort(zoneRows, function(a, b) return a.k > b.k end)
	c:Table({ { "Zone", 200 }, { "Kills", 60, "RIGHT" }, { "Share", 60, "RIGHT" }, { "Top subzone", 220 } }, zoneRows, { empty = "No locations recorded." })

	if n.pos and next(n.pos) then
		local rows = {}
		for mapID, list in pairs(n.pos) do
			local sx, sy = 0, 0
			for _, p in ipairs(list) do sx, sy = sx + p[1], sy + p[2] end
			local ax, ay = sx / #list, sy / #list
			local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
			rows[#rows + 1] = {
				cells = { info and info.name or ("Map " .. mapID), format("%.1f, %.1f", ax * 100, ay * 100), Num(#list) },
				onEnter = function(_, tt)
					tt:SetText("Kill hotspot", 1, 1, 1)
					tt:AddLine("Average position of sampled kill locations. Click to set a map waypoint.", nil, nil, nil, true)
				end,
				onClick = function() setWaypoint(mapID, ax, ay) end,
			}
		end
		c:Table({ { "Map", 200 }, { "Hotspot", 100, "RIGHT" }, { "Samples", 60, "RIGHT" } }, rows)
	end
end

function UI.views.monster(c, npcId)
	local db = MJ.db
	local n = npcId and db.npcs[npcId]
	if not n then
		c:Title("Monster journal", "Select a monster from the list.")
		if not next(db.npcs) then
			c:Text("Your journal is empty. Kill and loot something - every monster you kill (while you or your group has the tag) and every corpse you loot is recorded here.\n\nTip: bind 'Open journal for mouseover NPC' under Key Bindings > AddOns to jump straight to the monster under your mouse.")
		end
		return
	end

	local corpses = St.Corpses(n)
	local G = St.Global()

	-- header
	local sub = {}
	if n.minLvl then sub[#sub + 1] = "Level " .. (n.minLvl == n.maxLvl and n.minLvl or (n.minLvl .. "-" .. n.maxLvl)) end
	local cl = UI.CLASS_LABEL[n.class or "normal"]
	if cl and cl ~= "" then sub[#sub + 1] = cl end
	if n.type then sub[#sub + 1] = n.type .. (n.family and (" (" .. n.family .. ")") or "") end
	if G.rankKills[npcId] then sub[#sub + 1] = "#" .. G.rankKills[npcId] .. " most killed of " .. G.npcCount end
	sub[#sub + 1] = Grey("ID " .. npcId)
	c:Title(UI.NPCLabel(npcId), table.concat(sub, "  ·  "))

	-- kills & corpses
	c:Section("Kills & corpses")
	local unresolved = max(0, n.kills - n.looted - n.empty)
	local bestDay, bestDayV = St.BestDay(n.days)
	local today = n.days[MJ.DayKey()] or 0
	c:Grid({
		{ "Kills", Num(n.kills), "Mobs that died while you or your group had the tag." },
		{ "Corpses looted", Num(n.looted) },
		{ "Empty corpses", Num(n.empty), "Kills whose corpse had no loot at all (detected automatically; in a group only with free-for-all loot). Counted in the drop-rate denominator." },
		{ "Not looted", Num(unresolved), "Kills you did not loot, or that someone else in the group had loot rights to. Not used for drop rates." },
		{ "Loot rate", n.kills > 0 and Pct(n.looted / n.kills) or "-" },
		{ "Corpses (rate base)", Num(corpses), "Looted + confirmed empty corpses. All drop rates use this number." },
		{ "Solo / group kills", Num(n.soloKills or 0) .. " / " .. Num(n.groupKills or 0) },
		{ "Kills today", Num(today) },
		{ "Best session", Num(n.bestSession or 0), "Most kills of this monster in one play session." },
		{ "Best day", bestDay and (Num(bestDayV) .. " (" .. St.DayLabel(bestDay) .. ")") or "-" },
		{ "First kill", n.firstKill and MJ.Date(n.firstKill.t) or "-", n.firstKill and function(tt)
			tt:AddLine("By " .. MJ:CharName(n.firstKill.c) .. (n.firstKill.z ~= "" and (" in " .. n.firstKill.z) or ""), 1, 1, 1)
		end },
		{ "Last kill", n.lastKill and MJ.Ago(n.lastKill.t) or "-", n.lastKill and function(tt)
			tt:AddLine(MJ.Date(n.lastKill.t) .. " by " .. MJ:CharName(n.lastKill.c), 1, 1, 1)
		end },
	}, 3)

	-- money & value
	c:Section("Money & value")
	local vendor = St.NPCVendor(n)
	local combatHours = (n.ttkSum or 0) / 3600
	c:Grid({
		{ "Gold looted", Money(n.money) },
		{ "Avg gold / corpse", corpses > 0 and Money(n.money / corpses) or "-" },
		{ "Gold chance", corpses > 0 and Pct(n.moneyCorpses / corpses) or "-", "Share of corpses that had money." },
		{ "Avg when gold drops", n.moneyCorpses > 0 and Money(n.money / n.moneyCorpses) or "-" },
		{ "Min / max gold", n.moneyMin and (Money(n.moneyMin) .. " / " .. Money(n.moneyMax)) or "-" },
		{ "Only gold", Num(n.moneyOnly or 0), "Corpses that had money but no items." },
		{ "Vendor value (items)", Money(vendor), "Sum of vendor sell price x quantity for everything this monster dropped." },
		{ "Avg vendor / corpse", corpses > 0 and Money(vendor / corpses) or "-" },
		{ "Total value / corpse", corpses > 0 and Money((n.money + vendor) / corpses) or "-", "Gold + vendor value per corpse. Use it to compare farm spots." },
		{ "Value / combat hour", combatHours > 0.01 and Money((n.money + vendor) / combatHours) or "-", "Gold + vendor value divided by time spent fighting this monster." },
		{ "Distinct items", Num(MJ.Count(n.items)) },
	}, 3)

	-- loot table
	c:Section("Loot", "rates per corpse · hover for full stats")
	if renderLootTable(c, npcId, n, false) == 0 then
		c:Text(Grey("Nothing looted from this monster yet."))
	end
	local q = St.NPCQuality(n)
	local parts = {}
	for quality = 0, 7 do
		if q[quality] then parts[#parts + 1] = MJ.QualityHex(quality) .. Num(q[quality]) .. " " .. MJ.QualityName(quality) .. "|r" end
	end
	if #parts > 0 then c:Text("Drops by quality: " .. table.concat(parts, "  ·  ")) end

	local hasQuest = false
	for itemId, it in pairs(n.items) do
		if St.IsQuestOnly(itemId, it) then
			hasQuest = true
			break
		end
	end
	if hasQuest then
		c:Section("Quest drops", "rates per corpse looted while on the quest")
		renderLootTable(c, npcId, n, true)
		c:Text(Grey("These only drop while a quest needs them. Corpses are only counted while an unfinished quest in your log wants the item, so the rate shows how fast you collect it while on the quest."))
	end

	renderGather(c, n)

	-- combat
	c:Section("Combat")
	c:Grid({
		{ "Avg time to kill", n.ttkN and Dur(n.ttkSum / n.ttkN) or "-", "From the moment it engaged you/your group until it died." },
		{ "Fastest kill", n.ttkMin and Dur(n.ttkMin) or "-" },
		{ "Slowest kill", n.ttkMax and Dur(n.ttkMax) or "-" },
		{ "Total combat time", n.ttkSum and Dur(n.ttkSum) or "-" },
		{ "Kills / combat hour", combatHours > 0.01 and Num((n.ttkN or 0) / combatHours) or "-" },
	}, 3)

	local dk = n.dmgKills or 0
	local dmgNote = "From the built-in damage meter, read after each fight (aggregated per monster type per fight)."
	c:Grid({
		{ "Damage dealt (you)", Num(n.dmgMine or 0), "You and your pet. " .. dmgNote },
		{ "Damage dealt (group)", Num(n.dmgDone or 0), dmgNote },
		{ "Your share", (n.dmgDone or 0) > 0 and Pct((n.dmgMine or 0) / n.dmgDone) or "-" },
		{ "Damage per kill", dk > 0 and Num(n.dmgKillDone / dk) or "-", "Group damage per kill in fights where it died. Close to its health (overkill included)." },
		{ "Damage taken", Num(n.dmgTaken or 0), "Damage this monster type dealt to you. " .. dmgNote },
		{ "Taken per kill", dk > 0 and Num(n.dmgKillTaken / dk) or "-" },
		{ "Fights measured", Num(n.dmgFights or 0) },
		{ "DPS on it", (n.ttkSum or 0) > 0 and (n.dmgMine or 0) > 0 and Num(n.dmgMine / n.ttkSum) or "-", "Your damage divided by total time in combat with it (approximate)." },
	}, 3)
	if MJ.damageMeterMissing then
		c:Text(Grey("Damage stats unavailable: this client has no built-in damage meter API."))
	end

	if n.spells and next(n.spells) then
		local rows = {}
		local total = 0
		for _, s in pairs(n.spells) do total = total + s.amt end
		for spellID, s in pairs(n.spells) do
			rows[#rows + 1] = {
				amt = s.amt,
				icon = spellID ~= 0 and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID) or nil,
				cells = { UI.SpellLabel(spellID), Num(s.amt), Pct(s.amt / math.max(total, 1)), Num(s.amt / math.max(s.fights, 1)), Num(s.max or 0) },
				onEnter = spellID ~= 0 and function(_, tt) tt:SetSpellByID(spellID) end or nil,
			}
		end
		table.sort(rows, function(a, b) return a.amt > b.amt end)
		c:Text(Gold("What it hits you with"), GameFontNormal)
		c:Table({ { "Ability", 200 }, { "Damage", 80, "RIGHT" }, { "Share", 60, "RIGHT" }, { "Per fight", 80, "RIGHT" }, { "Worst fight", 80, "RIGHT", "Most damage from this ability in a single fight." } }, rows, { max = 10 })
	end

	renderDeaths(c, npcId, n)

	-- progress
	c:Section("Experience & reputation")
	local diff = n.diffN and n.diffN > 0 and (n.diffSum / n.diffN) or nil
	local grid = {
		{ "XP from kills", Num(n.xp or 0) },
		{ "Avg XP / kill", n.xpN and n.xpN > 0 and Num(n.xp / n.xpN) or "-", "Only kills that gave you experience." },
		{ "Your level at kill", n.myMin and (n.myMin == n.myMax and n.myMin or (n.myMin .. "-" .. n.myMax)) or "-" },
		{ "Avg level difference", diff and format("%+.1f", diff) or "-", "Your level minus the monster's level, averaged." },
	}
	if n.rep then
		for faction, amount in pairs(n.rep) do grid[#grid + 1] = { faction, "+" .. Num(amount) } end
	end
	c:Grid(grid, 3)

	-- location
	c:Section("Where")
	renderLocation(c, n)

	-- characters
	c:Section("Characters")
	local charRows = {}
	for key, k in pairs(n.byChar) do
		charRows[#charRows + 1] = { k = k, cells = { MJ:CharName(key), Num(k), Pct(k / max(n.kills, 1)) } }
	end
	table.sort(charRows, function(a, b) return a.k > b.k end)
	c:Table({ { "Character", 200 }, { "Kills", 60, "RIGHT" }, { "Share", 60, "RIGHT" } }, charRows)

	-- history
	c:Section("Last 30 days")
	local vals, keys = St.LastDays(30, function(k) return n.days[k] end)
	c:Bars(vals, 60, function(i, tt)
		tt:SetText(St.DayLabel(keys[i]), 1, 1, 1)
		tt:AddLine(Num(vals[i]) .. " kills", 1, 0.82, 0)
	end, St.DayLabel(keys[1]), "today")

	c:Space(6)
	c:Button("Delete entry", 12, 120, function() confirmDelete(npcId) end)
	c:Space(28)
end

UI.views[UI.TAB_MONSTERS] = UI.views.monster
