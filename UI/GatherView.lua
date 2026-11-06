-- UI/GatherView.lua: one gathering source - a herb or mining node, a chest or other object,
-- an opened container, or fishing in one zone - and everything it gave.
local _, MJ = ...
local UI, St = MJ.UI, MJ.Stats
local Num, Pct, Money = MJ.Num, MJ.Pct, MJ.Money
local Grey = UI.Grey
local format, max = string.format, math.max

local function confirmDelete(key, name)
	StaticPopupDialogs.MJURNAL_DELETE_NODE = StaticPopupDialogs.MJURNAL_DELETE_NODE or {
		text = "Delete the journal entry for %s?\n\nIts loot is removed for every character. Character totals and daily counts keep counting it.",
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function(_, data)
			MJ:DeleteNode(data)
			UI.state.selected[UI.TAB_GATHER] = nil
			UI:SelectTab(UI.TAB_GATHER)
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
	StaticPopup_Show("MJURNAL_DELETE_NODE", name, nil, key)
end

local function itemTooltip(tt, nd, itemId, it)
	local g = MJ.db.items[itemId]
	if g and g.link then tt:SetHyperlink(g.link) else tt:SetItemByID(itemId) end
	local function line(l, r) tt:AddDoubleLine(l, r, 0.8, 0.8, 0.8, 1, 1, 1) end
	tt:AddLine(" ")
	tt:AddLine("MJurnal - from " .. nd.name, 1, 0.82, 0)
	local p = St.Rate(it.drops, nd.count)
	if p then
		tt:AddDoubleLine("Drop rate", Pct(p), 1, 1, 1, 1, 1, 1)
		local lo, hi = St.Wilson(it.drops, nd.count)
		if lo then tt:AddDoubleLine("95% confidence", Pct(lo) .. " - " .. Pct(hi), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8) end
		line("Looted / times", Num(it.drops) .. " / " .. Num(nd.count))
		line("Avg per loot", format("%.3f", it.qty / nd.count))
		line("Loots for 50% / 90%", format("%s / %s", Num(St.KillsFor(p, 0.5)), Num(St.KillsFor(p, 0.9))))
	else
		line("Looted", Num(it.drops) .. " times")
	end
	line("Total quantity", Num(it.qty))
	UI.AddAHLines(tt, itemId, nd.count and nd.count > 0 and it.qty / nd.count, "AH value per loot")
	if it.sMin then line("Per loot min / avg / max", format("%d / %.2f / %d", it.sMin, it.qty / max(it.drops, 1), it.sMax)) end
	local stacks = St.StackText(it)
	if stacks then line("Amounts", stacks) end
	tt:AddLine("Click: open in loot journal · Shift-click: link in chat", 0.5, 0.5, 0.5)
end

local function renderLoot(c, nd)
	local rows = {}
	for itemId, it in pairs(nd.items) do
		local p = St.Rate(it.drops, nd.count)
		rows[#rows + 1] = {
			sortv = p or it.qty,
			icon = MJ:ItemIcon(itemId),
			cells = {
				MJ:ItemText(itemId), Num(it.drops), Num(it.qty),
				UI.PerCorpseText(St.PerCorpse(it.qty, nd.count), nd.count), UI.RateText(p, nd.count), UI.OneIn(p),
			},
			onEnter = function(_, tt) itemTooltip(tt, nd, itemId, it) end,
			onClick = function()
				local g = MJ.db.items[itemId]
				if IsModifiedClick("CHATLINK") and g and g.link then
					UI.InsertLink(g.link)
				else
					UI:Open(UI.TAB_LOOT, itemId)
				end
			end,
		}
	end
	table.sort(rows, function(a, b) return a.sortv > b.sortv end)
	c:Table({
		{ "Item", 220 },
		{ "Times", 50, "RIGHT", "Number of loots that had this item." },
		{ "Qty", 50, "RIGHT", "Total quantity (stacks summed)." },
		{ "Per loot", 60, "RIGHT", "Average number of this item per loot, counting every unit." },
		{ "Rate", 60, "RIGHT", "Chance that a loot has at least one. Grey until 20 loots." },
		{ "1 in", 50, "RIGHT", "Expected loots per drop (1 / rate)." },
	}, rows, { empty = "No items." })
end

function UI.views.gather(c, key)
	local V = St.View()
	local nd = key and V.nodes[key]
	if not nd then
		if key and MJ.db.nodeNames[key] then
			c:Title(MJ.db.nodeNames[key], UI.CharFilterLabel())
			c:Text("None of the selected characters has looted this. Pick other characters in the character filter (top right) to see it.")
			return
		end
		c:Title("Gathering", "Select a source from the list.")
		if not next(V.nodes) then
			c:Text("Nothing gathered yet. Herb and mining nodes, chests and other objects, opened containers and fishing are recorded here, each with its own loot table.")
		end
		return
	end

	-- header
	local sub = { UI.NODE_KIND[nd.kind] or nd.kind }
	local topZone, topZoneN
	for zone, k in pairs(nd.zones) do
		if not topZoneN or k > topZoneN then topZone, topZoneN = zone, k end
	end
	if topZone and nd.kind ~= "fishing" then sub[#sub + 1] = topZone end
	local id = key:match("^%a+:(%d+)$")
	if id then sub[#sub + 1] = Grey("ID " .. id) end
	c:Title(nd.legacy and Grey(nd.name) or nd.name, table.concat(sub, "  ·  "), UI.NodeIcon(nd.kind))
	if nd.legacy then
		c:Text(Grey("Looted before MJurnal kept track of each source. The items are known, but not how many times you looted, so there are no rates."))
	end

	-- summary
	local qty = 0
	for _, it in pairs(nd.items) do qty = qty + it.qty end
	local count = nd.count
	local per = St.NodeValuePer(nd)
	local ahValue, ahPriced, ahTotal = St.AHValue(nd.items)
	c:Section("Summary")
	c:Grid({
		{ nd.kind == "fishing" and "Catches" or "Times looted", count and Num(count) or "-" },
		{ "Distinct items", Num(MJ.Count(nd.items)) },
		{ "Items (qty)", Num(qty) },
		{ "Items per loot", count and count > 0 and format("%.2f", qty / count) or "-" },
		{ "Money", Money(nd.money) },
		{ "Vendor value", Money(St.NodeVendor(nd)), "Sum of vendor sell price x quantity for everything it gave." },
		{ "Value per loot", per and Money(per) or "-", "Money + vendor value per loot. Use it to compare sources." },
		{ "AH value", ahPriced > 0 and Money(ahValue) or "-", function(tt)
			tt:AddLine(("Everything it gave at today's auction price. %d of %d items have a price."):format(ahPriced, ahTotal), nil, nil, nil, true)
			tt:AddLine(UI.AH_NOTE, 0.7, 0.7, 0.7, true)
		end },
		{ "Value per loot (AH)", ahPriced > 0 and count and count > 0 and Money((nd.money + St.MarketValue(nd.items)) / count) or "-",
			"Money + items at their auction price (vendor price for items without one), per loot." },
		{ "First", nd.first and MJ.Date(nd.first.t) or "-" },
		{ "Last", nd.last and MJ.Ago(nd.last.t) or "-", nd.last and MJ.Date(nd.last.t) },
	}, 3)

	c:Section("Loot", count and "rates per loot · hover for full stats" or nil)
	renderLoot(c, nd)

	if next(nd.zones) then
		c:Section("Where")
		local rows = {}
		local total = 0
		for _, k in pairs(nd.zones) do total = total + k end
		for zone, k in pairs(nd.zones) do
			rows[#rows + 1] = { k = k, cells = { zone, Num(k), Pct(k / max(total, 1)) } }
		end
		table.sort(rows, function(a, b) return a.k > b.k end)
		c:Table({ { "Zone", 220 }, { "Times", 60, "RIGHT" }, { "Share", 60, "RIGHT" } }, rows)
	end

	-- characters (only worth a table with more than one)
	local chars = {}
	for ck, ch in pairs(V.chars) do
		local cn = ch.nodes and ch.nodes[key]
		if cn then chars[#chars + 1] = { ck = ck, n = cn.count or 0 } end
	end
	if #chars > 1 then
		table.sort(chars, function(a, b) return a.n > b.n end)
		c:Section("Characters")
		local rows = {}
		for _, ch in ipairs(chars) do
			rows[#rows + 1] = { cells = { MJ:CharName(ch.ck), Num(ch.n), Pct(ch.n / max(count or 0, 1)) } }
		end
		c:Table({ { "Character", 200 }, { "Times", 60, "RIGHT" }, { "Share", 60, "RIGHT" } }, rows)
	end

	c:Space(6)
	c:Button("Delete entry", 12, 120, function() confirmDelete(key, nd.name) end)
	c:Space(28)
end

UI.views[UI.TAB_GATHER] = UI.views.gather
