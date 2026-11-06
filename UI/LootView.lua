-- UI/LootView.lua: the loot journal - one item and everything that dropped it.
local _, MJ = ...
local UI, St = MJ.UI, MJ.Stats
local Num, Pct, Money = MJ.Num, MJ.Pct, MJ.Money
local Grey = UI.Grey
local format, max = string.format, math.max

-- Days shown in the auction price chart (switchable on the item page).
local RANGES = { 30, 90 }
local range = 30

-- The auction price over time: a bar per day (lowest buyout that day) and a summary.
local function renderAHHistory(c, itemId)
	local vals, keys, sum = St.AHHistory(itemId, range)
	if sum.n == 0 then return end
	c:Section("Auction price", "lowest buyout per unit each day")
	local x = 12
	for _, days in ipairs(RANGES) do
		local b = c:Button(days .. " days", x, 70, function()
			range = days
			UI:RenderDetail(false)
		end)
		if days == range then b:Disable() end
		x = x + 76
	end
	c:Space(28)
	local now = St.AHPrice(itemId)
	local change = sum.first and sum.last and sum.first > 0 and (sum.last - sum.first) / sum.first
	local changeText = "-"
	if change and sum.n > 1 then
		changeText = format("%+.0f%%", change * 100)
		if change >= 0.05 then changeText = UI.Green(changeText) elseif change <= -0.05 then changeText = UI.Red(changeText) end
	end
	c:Grid({
		{ "Now", UI.AHPriceText(itemId), UI.AH_NOTE },
		{ "Average", sum.avg and Money(sum.avg) or "-", format("Average of the days with a price in the last %d days.", range) },
		{ "Low / high", Money(sum.low) .. " / " .. Money(sum.high) },
		{ "Change", changeText, "First day with a price in the range compared to the last one." },
		{ "Days with a price", Num(sum.n) .. " / " .. range, "Days you scanned or searched for it on the auction house." },
		{ "Vs vendor", (now and MJ.db.items[itemId] and (MJ.db.items[itemId].sell or 0) > 0) and format("%.1fx", now / MJ.db.items[itemId].sell) or "-",
			"Auction price divided by vendor price." },
	}, 3)
	c:Bars(vals, 70, function(i, tt)
		tt:SetText(St.DayLabel(keys[i]), 1, 1, 1)
		if vals[i] > 0 then
			tt:AddLine(Money(vals[i]) .. " each", 1, 0.82, 0)
		else
			tt:AddLine("No price seen that day.", 0.7, 0.7, 0.7)
		end
	end, St.DayLabel(keys[1]), "today", Money)
end

local function stampText(s)
	if not s then return "-" end
	local from = s.n and MJ:NPCName(s.n) or (s.k and (UI.GATHER_LABEL[s.k] or UI.NODE_KIND[s.k] or s.k)) or "?"
	return format("%s · %s · %s", MJ.Date(s.t), MJ:CharName(s.c), from)
end

function UI.views.loot(c, itemId)
	local V = St.View()
	local g = itemId and V.items[itemId]
	if not g and itemId and MJ.db.items[itemId] then
		c:Title(MJ:ItemText(itemId), UI.CharFilterLabel(), MJ:ItemIcon(itemId), function(_, tt) tt:SetItemByID(itemId) end)
		c:Text("None of the selected characters has looted this item. Pick other characters in the character filter (top right) to see it.")
		return
	end
	if not g then
		c:Title("Loot journal", "Select an item from the list.")
		if not next(V.items) then
			c:Text(MJ:CharFilter() and "The selected characters have not looted anything yet." or "Nothing looted yet.")
		end
		return
	end
	MJ:CacheItem(itemId)

	local sub = { MJ.QualityHex(g.quality) .. MJ.QualityName(g.quality) .. "|r" }
	if g.itype then sub[#sub + 1] = g.itype .. ((g.isub and g.isub ~= g.itype) and (" / " .. g.isub) or "") end
	if g.sell and g.sell > 0 then sub[#sub + 1] = "Sells for " .. Money(g.sell) end
	local ahPrice = St.AHPrice(itemId)
	if ahPrice then sub[#sub + 1] = "AH " .. UI.AHPriceText(itemId) end
	if g.quest then sub[#sub + 1] = "|cffff8020Quest item|r" end
	sub[#sub + 1] = Grey("ID " .. itemId)
	c:Title(MJ.QualityHex(g.quality) .. (g.name or ("Item #" .. itemId)) .. "|r", table.concat(sub, "  ·  "), MJ:ItemIcon(itemId),
		function(_, tt) tt:SetItemByID(itemId) end)

	local sources = St.ItemSources(itemId)
	local gsources = St.ItemGatherSources(itemId)
	local best = sources[1]
	local luck, luckN = St.ItemLuck(itemId)

	c:Section("Summary")
	c:Grid({
		{ "Times looted", Num(g.drops), "Number of loot windows (corpses, catches, containers...) that had this item." },
		{ "Total quantity", Num(g.qty) },
		{ "Avg per loot", format("%.2f", g.qty / max(g.drops, 1)), "Average quantity each time it was looted (several units from one corpse count as one loot)." },
		{ "Vendor value earned", Money((g.sell or 0) * g.qty) },
		{ "AH price", UI.AHPriceText(itemId), UI.AH_NOTE },
		{ "AH value of loot", ahPrice and Money(ahPrice * g.qty) or "-", "Everything you looted of it at today's auction price." },
		{ "Monsters that drop it", Num(#sources) },
		{ "Best source", best and (MJ:NPCName(best.npc) .. " (" .. Pct(best.rate) .. ")") or "-" },
		{ "Luck", luck and format("%.2fx", luck) or "-", luck and format("Across %d measured drops. Above 1x = it came sooner than the rate predicted.", luckN) or nil },
		{ "First looted", g.first and MJ.Ago(g.first.t) or "-", g.first and stampText(g.first) },
		{ "Last looted", g.last and MJ.Ago(g.last.t) or "-", g.last and stampText(g.last) },
	}, 3)

	renderAHHistory(c, itemId)

	local questOnly = sources[1] and sources[1].questOnly
	if questOnly then
		local wantedBy = MJ.WantedQuestItems()[g.name or ""]
		c:Text("|cffff8020Quest drop:|r it only drops while a quest needs it, so rates count only corpses looted while an unfinished quest in your log wanted it."
			.. (wantedBy and UI.Green("  Needed by a quest in your log right now.") or ""))
	elseif g.quest then
		c:Text(Grey("Quest item that has also dropped without the quest, so it uses normal per-corpse rates."))
	end

	c:Section("Dropped by", (questOnly and "corpses = on-quest corpses · " or "") .. "click a monster to open it")
	local rows = {}
	for _, s in ipairs(sources) do
		local p = s.rate
		local since = s.since
		rows[#rows + 1] = {
			cells = {
				UI.NPCLabel(s.npc), Num(s.drops), Num(s.it.qty), Num(s.corpses), UI.PerCorpseText(s.perCorpse, s.corpses),
				UI.RateText(p, s.corpses), UI.OneIn(p),
				Num(since), Num(St.KillsFor(p, 0.9)), s.questOnly and Grey("-") or UI.LuckText(St.Luck(s.it)),
			},
			onEnter = function(_, tt)
				tt:SetText(MJ:NPCName(s.npc), 1, 1, 1)
				local lo, hi = St.Wilson(s.drops, s.corpses)
				tt:AddDoubleLine(s.questOnly and "Drop rate while on the quest" or "Drop rate", Pct(p), 0.8, 0.8, 0.8, 1, 1, 1)
				if lo then tt:AddDoubleLine("95% confidence", Pct(lo) .. " - " .. Pct(hi), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8) end
				if s.perCorpse then
					tt:AddDoubleLine(s.questOnly and "Avg per corpse on quest" or "Avg per corpse", format("%.3f", s.perCorpse), 0.8, 0.8, 0.8, 1, 1, 1)
				end
				local stacks = St.StackText(s.it)
				if stacks then tt:AddDoubleLine("Amounts per drop", stacks, 0.8, 0.8, 0.8, 1, 1, 1) end
				tt:AddDoubleLine("Kills", Num(s.n.kills), 0.8, 0.8, 0.8, 1, 1, 1)
				tt:AddDoubleLine("Longest dry streak", Num(s.dry), 0.8, 0.8, 0.8, 1, 1, 1)
				if since > 0 and p > 0 then
					tt:AddDoubleLine("Chance of current dry streak", Pct(St.Drought(p, since)), 0.8, 0.8, 0.8, 1, 1, 1)
				end
				tt:AddDoubleLine("Last drop", s.it.lastT and MJ.Ago(s.it.lastT) or "-", 0.8, 0.8, 0.8, 1, 1, 1)
				tt:AddLine("Click to open in the monster journal.", 0.5, 0.5, 0.5)
			end,
			onClick = function() UI:Open(UI.TAB_MONSTERS, s.npc) end,
		}
	end
	c:Table({
		{ "Monster", 190 }, { "Drops", 44, "RIGHT", "Corpses that had this item." }, { "Qty", 44, "RIGHT" }, { "Corpses", 54, "RIGHT" },
		{ "Per corpse", 60, "RIGHT", "Average number of this item per corpse, counting every unit of a stack." },
		{ "Rate", 56, "RIGHT", "Chance that a corpse has at least one." }, { "1 in", 44, "RIGHT" }, { "Since", 44, "RIGHT", "Corpses since the last drop from this monster." },
		{ "90%", 44, "RIGHT", "Corpses for a 90% chance of at least one." }, { "Luck", 44, "RIGHT" },
	}, rows, { empty = "No monster drops recorded." })

	if #gsources > 0 then
		c:Section("Gathered from monsters")
		local grows = {}
		for _, s in ipairs(gsources) do
			grows[#grows + 1] = {
				cells = { UI.NPCLabel(s.npc), UI.GATHER_LABEL[s.kind] or s.kind, Num(s.it.drops), Num(s.it.qty), Num(s.count), UI.RateText(s.rate, s.count) },
				onClick = function() UI:Open(UI.TAB_MONSTERS, s.npc) end,
			}
		end
		c:Table({ { "Monster", 190 }, { "Method", 90 }, { "Times", 50, "RIGHT" }, { "Qty", 50, "RIGHT" }, { "Attempts", 60, "RIGHT" }, { "Rate", 60, "RIGHT" } }, grows)
	end

	local nsources = St.ItemNodeSources(itemId, V)
	if #nsources > 0 then
		c:Section("Gathered from", "herbs, ore, chests, containers, fishing · click to open")
		local nrows = {}
		for _, s in ipairs(nsources) do
			local nd = s.nd
			nrows[#nrows + 1] = {
				icon = UI.NodeIcon(nd.kind),
				cells = {
					nd.legacy and Grey(nd.name) or nd.name, UI.NODE_KIND[nd.kind] or nd.kind, Num(s.it.drops), Num(s.it.qty),
					nd.count and Num(nd.count) or Grey("-"), UI.PerCorpseText(s.perGather, s.count), UI.RateText(s.count and s.rate, s.count),
				},
				onClick = function() UI:Open(UI.TAB_GATHER, s.key) end,
			}
		end
		c:Table({
			{ "Source", 190 }, { "Type", 110 }, { "Times", 50, "RIGHT", "Loots that had this item." }, { "Qty", 50, "RIGHT" },
			{ "Looted", 54, "RIGHT", "Times you looted this source (unknown for data from before sources were tracked)." },
			{ "Per loot", 60, "RIGHT", "Average number of this item per loot." }, { "Rate", 56, "RIGHT" },
		}, nrows)
	end

	c:Space(6)
	if g.link then
		c:Button("Link in chat", 12, 120, function() UI.InsertLink(g.link) end)
		c:Space(28)
	end
end

UI.views[UI.TAB_LOOT] = UI.views.loot
