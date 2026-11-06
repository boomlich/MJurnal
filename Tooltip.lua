-- Tooltip.lua: MJurnal lines on NPC and item tooltips (always the whole account).
--   NPC tooltips: kills / loot / value, and quest drop stats next to the quest objective
--   lines ("Murloc Fin: 3/6") for the quest items that monster has dropped.
local _, MJ = ...
local St = MJ.Stats
local format = string.format

local PREFIX = "|cffd4a017MJurnal:|r "

local function npcLine(tooltip, n)
	local corpses = St.Corpses(n)
	local text = format("Killed %s · Looted %s", MJ.Num(n.kills), MJ.Num(n.looted))
	local v = St.NPCValuePerCorpse(n)
	if v and corpses >= 5 then text = text .. " · " .. MJ.Money(v) .. "/corpse" end
	tooltip:AddLine(PREFIX .. text, 1, 1, 1)
end

---------------------------------------------------------------------------
-- Quest drops (settings qt*: which numbers to show)
---------------------------------------------------------------------------
-- "32% drop · ~9 kills left" for one quest item this monster drops, or nil.
-- want = { have, need } from the quest log.
local function questStats(n, itemId, it, want, s)
	local d, corpses, _, since, _, qty = St.ItemBase(n, itemId, it)
	if not corpses or corpses <= 0 then return nil end
	local p = St.Rate(d, corpses)
	local per = St.PerCorpse(qty, corpses)
	local parts = {}
	if s.qtRate then parts[#parts + 1] = MJ.Pct(p) .. " drop" end
	if s.qtOneIn then parts[#parts + 1] = "1 in " .. MJ.UI.OneIn(p) end
	if s.qtPerCorpse and per then parts[#parts + 1] = format("%.2f per kill", per) end
	if s.qtLeft and want.have and want.need and per and per > 0 then
		local left = want.need - want.have
		if left > 0 then parts[#parts + 1] = "~" .. MJ.Num(math.ceil(left / per)) .. " kills left" end
	end
	if s.qtSample then parts[#parts + 1] = MJ.Num(d) .. "/" .. MJ.Num(corpses) .. " corpses" end
	if s.qtSince then parts[#parts + 1] = MJ.Num(since) .. " since last drop" end
	if #parts == 0 then return nil end
	-- grey until the sample is decent, like the journal
	local color = St.Confident(corpses) and "|cffd4a017" or "|cff9d9d9d"
	return color .. table.concat(parts, " · ") .. "|r"
end

-- The tooltip line that mentions name (the quest objective line), if any.
local function findLine(tooltip, name)
	local tname = tooltip.GetName and tooltip:GetName()
	if not tname or not tooltip.NumLines then return nil end
	for i = 2, tooltip:NumLines() do
		local fs = _G[tname .. "TextLeft" .. i]
		local text = fs and MJ.S(fs:GetText())
		if type(text) == "string" and text:find(name, 1, true) then return fs, text end
	end
end

-- Adds the stats to each quest objective line of a quest item this monster has dropped, or
-- as a line of its own when the tooltip has no objective line for it.
local function questLines(tooltip, n)
	local s = MJ.db.settings
	local wanted = MJ.WantedQuestItems()
	local changed = false
	for itemId, it in pairs(n.items) do
		local g = MJ.db.items[itemId]
		local name = g and g.name
		local want = name and wanted[name]
		if want and (it.quest or g.quest) and not g.questStarter then
			local stats = questStats(n, itemId, it, want, s)
			if stats then
				local fs, text = findLine(tooltip, name)
				if fs then
					fs:SetText(text .. "  " .. stats)
					changed = true
				else
					tooltip:AddLine(PREFIX .. name .. ": " .. stats, 1, 1, 1)
				end
			end
		end
	end
	-- a longer line needs the tooltip to resize
	if changed then tooltip:Show() end
end

local function unitLines(tooltip, guid)
	if not guid or MJ.issecret(guid) then return end
	local npcId = MJ.ParseGUID(guid)
	local n = npcId and St.AccountView().npcs[npcId]
	if not n then return end
	local s = MJ.db.settings
	if s.unitTooltip then npcLine(tooltip, n) end
	if s.questTooltip then questLines(tooltip, n) end
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local function itemLine(tooltip, itemId)
	local V = St.AccountView()
	local g = itemId and V.items[itemId]
	if not g then return end
	local text = format("Looted %sx", MJ.Num(g.drops))
	local best = St.ItemSources(itemId, V)[1]
	if best then text = text .. format(" · best: %s (%s)", MJ:NPCName(best.npc), MJ.Pct(best.rate)) end
	local ah = St.AHPrice(itemId)
	if ah then text = text .. " · AH " .. MJ.Money(ah) end
	tooltip:AddLine(PREFIX .. text, 1, 1, 1)
end

local function setup()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
			if tooltip ~= GameTooltip or not MJ.db then return end
			local guid = data and data.guid
			if guid == nil or MJ.issecret(guid) then
				local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
				guid = ok and MJ.SafeGUID(unit) or nil
			end
			unitLines(tooltip, guid)
		end)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			if not MJ.db or not MJ.db.settings.itemTooltip then return end
			if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
			local id = data and MJ.S(data.id)
			itemLine(tooltip, id)
		end)
	elseif GameTooltip.HookScript then
		GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
			if not MJ.db then return end
			local _, unit = tooltip:GetUnit()
			unitLines(tooltip, MJ.SafeGUID(unit))
		end)
		GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
			if not MJ.db or not MJ.db.settings.itemTooltip then return end
			local _, link = tooltip:GetItem()
			local id = link and tonumber(link:match("item:(%d+)"))
			itemLine(tooltip, id)
		end)
	end
end

MJ:Listen("DB_READY", setup)
