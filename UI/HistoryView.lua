-- UI/HistoryView.lua: the event log (notable drops, milestones, rares, deaths, new entries).
local _, MJ = ...
local UI = MJ.UI
local Num = MJ.Num
local format = string.format

local FILTERS = {
	{ key = "all", label = "All" },
	{ key = "drop", label = "Drops", kinds = { drop = true, newitem = true } },
	{ key = "ms", label = "Milestones", kinds = { ms = true, total = true } },
	{ key = "rare", label = "Rares", kinds = { rare = true, rarekill = true } },
	{ key = "death", label = "Deaths", kinds = { death = true } },
	{ key = "new", label = "New entries", kinds = { newnpc = true, newitem = true } },
}
local filter = 1
local limit = 200

local KIND_LABEL = {
	drop = "|cff20ff20Drop|r", newitem = "|cff20ff20New item|r", ms = "|cffffd200Milestone|r",
	total = "|cffffd200Milestone|r", rare = "|cffc0c0ffRare|r", rarekill = "|cffc0c0ffRare kill|r",
	death = "|cffff4040Death|r", newnpc = "|cff80c0ffNew monster|r",
}

function UI.LogText(e)
	local npc = e.npc and UI.NPCLabel(e.npc)
	if e.k == "drop" then
		local qty = (e.q and e.q > 1) and (" x" .. e.q) or ""
		return format("%s%s from %s - corpse #%s, after %s corpses (drop #%s)", MJ:ItemText(e.item), qty, npc or "?", Num(e.cn), Num(e.gap), Num(e.d))
	elseif e.k == "newitem" then
		return format("First %s%s", MJ:ItemText(e.item), npc and (" from " .. npc) or "")
	elseif e.k == "ms" then
		return format("%s kills of %s", Num(e.v), npc or "?")
	elseif e.k == "total" then
		return format("%s total kills", Num(e.v))
	elseif e.k == "rare" then
		return format("Spotted %s%s", npc or "?", (e.z and e.z ~= "") and (" in " .. e.z) or "")
	elseif e.k == "rarekill" then
		return format("Killed %s%s", npc or "?", (e.z and e.z ~= "") and (" in " .. e.z) or "")
	elseif e.k == "death" then
		local cause = e.kb and (" - " .. UI.DeathCause(e)) or ""
		local adds = (e.adds and e.adds > 1) and UI.Grey(format(" (%d enemies)", e.adds)) or ""
		return format("Killed by %s%s%s%s", UI.DeathKiller(e), cause, adds, (e.z and e.z ~= "") and (" in " .. e.z) or "")
	elseif e.k == "newnpc" then
		return format("%s%s", npc or "?", (e.z and e.z ~= "") and (" in " .. e.z) or "")
	end
	return e.k or "?"
end

function UI.views.history(c)
	local x = 12
	for i, f in ipairs(FILTERS) do
		local b = c:Button(f.label, x, 96, function()
			filter = i
			limit = 200
			UI:RenderDetail(true)
		end)
		if i == filter then b:Disable() end
		x = x + 100
	end
	c:Space(30)

	local log = MJ.db.log
	local V = MJ.Stats.View()
	local kinds = FILTERS[filter].kinds
	local rows, total = {}, 0
	for i = #log, 1, -1 do
		local e = log[i]
		if (not kinds or kinds[e.k]) and V.Includes(e.c) then
			total = total + 1
			if #rows < limit then
				rows[#rows + 1] = {
					icon = e.item and MJ:ItemIcon(e.item) or nil,
					cells = { MJ.Date(e.t), KIND_LABEL[e.k] or e.k, UI.LogText(e), MJ:CharName(e.c) },
					onEnter = (e.item and function(_, tt) tt:SetItemByID(e.item) end)
						or (e.k == "death" and function(_, tt) UI.DeathTooltip(tt, e) end) or nil,
					onClick = function()
						if e.item then
							UI:Open(UI.TAB_LOOT, e.item)
						elseif e.npc and V.npcs[e.npc] then
							UI:Open(UI.TAB_MONSTERS, e.npc)
						end
					end,
				}
			end
		end
	end
	c:Table({ { "When", 110 }, { "Event", 80 }, { "Details", 560 }, { "Character", 100 } }, rows,
		{ empty = "Nothing here yet. Drops of " .. MJ.QualityName(MJ.db.settings.logQuality) .. " quality or better, rare drops, milestones, rares and deaths show up here." })
	if total > limit then
		c:Button(format("Show more (%d of %d)", limit, total), 12, 200, function()
			limit = limit + 300
			UI:RenderDetail(false)
		end)
		c:Space(28)
	end
end

UI.views[UI.TAB_HISTORY] = UI.views.history
