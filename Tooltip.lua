-- Tooltip.lua: a short MJurnal line on NPC and item tooltips (always the whole account).
local _, MJ = ...
local St = MJ.Stats
local format = string.format

local function npcLine(tooltip, guid)
	if not guid or MJ.issecret(guid) then return end
	local npcId = MJ.ParseGUID(guid)
	local n = npcId and St.AccountView().npcs[npcId]
	if not n then return end
	local corpses = St.Corpses(n)
	local text = format("Killed %s · Looted %s", MJ.Num(n.kills), MJ.Num(n.looted))
	local v = St.NPCValuePerCorpse(n)
	if v and corpses >= 5 then text = text .. " · " .. MJ.Money(v) .. "/corpse" end
	tooltip:AddLine("|cffd4a017MJurnal:|r " .. text, 1, 1, 1)
end

local function itemLine(tooltip, itemId)
	local V = St.AccountView()
	local g = itemId and V.items[itemId]
	if not g then return end
	local text = format("Looted %sx", MJ.Num(g.drops))
	local best = St.ItemSources(itemId, V)[1]
	if best then text = text .. format(" · best: %s (%s)", MJ:NPCName(best.npc), MJ.Pct(best.rate)) end
	tooltip:AddLine("|cffd4a017MJurnal:|r " .. text, 1, 1, 1)
end

local function setup()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
			if tooltip ~= GameTooltip or not MJ.db or not MJ.db.settings.unitTooltip then return end
			local guid = data and data.guid
			if guid == nil or MJ.issecret(guid) then
				local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
				guid = ok and MJ.SafeGUID(unit) or nil
			end
			npcLine(tooltip, guid)
		end)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			if not MJ.db or not MJ.db.settings.itemTooltip then return end
			if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
			local id = data and MJ.S(data.id)
			itemLine(tooltip, id)
		end)
	elseif GameTooltip.HookScript then
		GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
			if not MJ.db or not MJ.db.settings.unitTooltip then return end
			local _, unit = tooltip:GetUnit()
			npcLine(tooltip, MJ.SafeGUID(unit))
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
