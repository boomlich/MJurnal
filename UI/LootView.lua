-- UI/LootView.lua: the loot journal - one item and everything that dropped it.
local _, MJ = ...
local UI, St = MJ.UI, MJ.Stats
local Num, Pct, Money = MJ.Num, MJ.Pct, MJ.Money
local Grey = UI.Grey
local format, max = string.format, math.max

local OTHER_LABEL = {
	container = "Opened containers", object = "Chests & objects", herb = "Herb nodes", mine = "Mining nodes",
}

local function stampText(s)
	if not s then return "-" end
	local from = s.n and MJ:NPCName(s.n) or (s.k and (UI.GATHER_LABEL[s.k] or OTHER_LABEL[s.k] or s.k)) or "?"
	return format("%s · %s · %s", MJ.Date(s.t), MJ:CharName(s.c), from)
end

function UI.views.loot(c, itemId)
	local g = itemId and MJ.db.items[itemId]
	if not g then
		c:Title("Loot journal", "Select an item from the list.")
		if not next(MJ.db.items) then c:Text("Nothing looted yet.") end
		return
	end
	MJ:CacheItem(itemId)

	local sub = { MJ.QualityHex(g.quality) .. MJ.QualityName(g.quality) .. "|r" }
	if g.itype then sub[#sub + 1] = g.itype .. ((g.isub and g.isub ~= g.itype) and (" / " .. g.isub) or "") end
	if g.sell and g.sell > 0 then sub[#sub + 1] = "Sells for " .. Money(g.sell) end
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
		{ "Avg stack", format("%.2f", g.qty / max(g.drops, 1)) },
		{ "Vendor value earned", Money((g.sell or 0) * g.qty) },
		{ "Monsters that drop it", Num(#sources) },
		{ "Best source", best and (MJ:NPCName(best.npc) .. " (" .. Pct(best.rate) .. ")") or "-" },
		{ "Luck", luck and format("%.2fx", luck) or "-", luck and format("Across %d measured drops. Above 1x = it came sooner than the rate predicted.", luckN) or nil },
		{ "First looted", g.first and MJ.Ago(g.first.t) or "-", g.first and stampText(g.first) },
		{ "Last looted", g.last and MJ.Ago(g.last.t) or "-", g.last and stampText(g.last) },
	}, 3)

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
				UI.NPCLabel(s.npc), Num(s.drops), Num(s.it.qty), Num(s.corpses), UI.RateText(p, s.corpses), UI.OneIn(p),
				Num(since), Num(St.KillsFor(p, 0.9)), s.questOnly and Grey("-") or UI.LuckText(St.Luck(s.it)),
			},
			onEnter = function(_, tt)
				tt:SetText(MJ:NPCName(s.npc), 1, 1, 1)
				local lo, hi = St.Wilson(s.drops, s.corpses)
				tt:AddDoubleLine(s.questOnly and "Drop rate while on the quest" or "Drop rate", Pct(p), 0.8, 0.8, 0.8, 1, 1, 1)
				if lo then tt:AddDoubleLine("95% confidence", Pct(lo) .. " - " .. Pct(hi), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8) end
				tt:AddDoubleLine("Kills", Num(s.n.kills), 0.8, 0.8, 0.8, 1, 1, 1)
				tt:AddDoubleLine("Longest dry streak", Num(s.dry), 0.8, 0.8, 0.8, 1, 1, 1)
				if since > 0 and p > 0 then
					tt:AddDoubleLine("Chance of current dry streak", Pct(St.Drought(p, since)), 0.8, 0.8, 0.8, 1, 1, 1)
				end
				tt:AddDoubleLine("Last drop", s.it.lastT and MJ.Ago(s.it.lastT) or "-", 0.8, 0.8, 0.8, 1, 1, 1)
				tt:AddLine("Click to open in the monster journal.", 0.5, 0.5, 0.5)
			end,
			onClick = function() UI:Navigate(UI.TAB_MONSTERS, s.npc) end,
		}
	end
	c:Table({
		{ "Monster", 190 }, { "Drops", 44, "RIGHT" }, { "Qty", 44, "RIGHT" }, { "Corpses", 54, "RIGHT" },
		{ "Rate", 56, "RIGHT" }, { "1 in", 44, "RIGHT" }, { "Since", 44, "RIGHT", "Corpses since the last drop from this monster." },
		{ "90%", 44, "RIGHT", "Corpses for a 90% chance of at least one." }, { "Luck", 44, "RIGHT" },
	}, rows, { empty = "No monster drops recorded." })

	if #gsources > 0 then
		c:Section("Gathered from monsters")
		local grows = {}
		for _, s in ipairs(gsources) do
			grows[#grows + 1] = {
				cells = { UI.NPCLabel(s.npc), UI.GATHER_LABEL[s.kind] or s.kind, Num(s.it.drops), Num(s.it.qty), Num(s.count), UI.RateText(s.rate, s.count) },
				onClick = function() UI:Navigate(UI.TAB_MONSTERS, s.npc) end,
			}
		end
		c:Table({ { "Monster", 190 }, { "Method", 90 }, { "Times", 50, "RIGHT" }, { "Qty", 50, "RIGHT" }, { "Attempts", 60, "RIGHT" }, { "Rate", 60, "RIGHT" } }, grows)
	end

	local other = g.other
	if other then
		if other.fishing then
			c:Section("Fishing")
			local frows = {}
			for zone, o in pairs(other.fishing) do
				local f = MJ.db.fishing[zone]
				local catches = f and f.catches or 0
				local p = catches > 0 and o.d / catches or nil
				frows[#frows + 1] = { k = o.d, cells = { zone, Num(o.d), Num(o.q), Num(catches), UI.RateText(p, catches), UI.OneIn(p) } }
			end
			table.sort(frows, function(a, b) return a.k > b.k end)
			c:Table({ { "Zone", 190 }, { "Caught", 54, "RIGHT" }, { "Qty", 50, "RIGHT" }, { "Casts", 54, "RIGHT", "Total loot windows while fishing in this zone." }, { "Rate", 60, "RIGHT" }, { "1 in", 50, "RIGHT" } }, frows)
		end
		local orows = {}
		for kind, o in pairs(other) do
			if kind ~= "fishing" then
				orows[#orows + 1] = { cells = { OTHER_LABEL[kind] or kind, Num(o.d), Num(o.q) } }
			end
		end
		if #orows > 0 then
			c:Section("Other sources")
			c:Table({ { "Source", 190 }, { "Times", 54, "RIGHT" }, { "Qty", 54, "RIGHT" } }, orows)
		end
	end

	c:Space(6)
	if g.link then
		c:Button("Link in chat", 12, 120, function() UI.InsertLink(g.link) end)
		c:Space(28)
	end
end

UI.views[3] = UI.views.loot
