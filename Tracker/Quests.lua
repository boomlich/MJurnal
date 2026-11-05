-- Tracker/Quests.lua: which quest items are wanted right now.
--
-- Quest-only drops (isQuestItem, not a quest starter) only show up while you have an
-- unfinished quest objective for them. Their drop rate is therefore counted only over
-- corpses looted while the item was wanted. The wanted set comes from the quest log's
-- item objectives ("Murloc Fin: 3/10"), matched by item name.
local _, MJ = ...
local S = MJ.S

local wanted, dirty = {}, true

-- "Murloc Fin: 3/10", "3/10 Murloc Fin", "Murloc Fin: 3/10 (Complete)" -> "Murloc Fin"
function MJ.ObjectiveItemName(text)
	if type(text) ~= "string" then return nil end
	local name = text:gsub("%s*%(.-%)%s*$", "")
	name = name:gsub("%s*%d+%s*/%s*%d+%s*", " ")
	name = name:gsub("^%s*:%s*", ""):gsub("%s*:%s*$", "")
	name = strtrim and strtrim(name) or name:match("^%s*(.-)%s*$")
	return name ~= "" and name or nil
end

-- Set of item names that are unfinished item objectives in your quest log: [name] = questID
function MJ.WantedQuestItems()
	if not dirty then return wanted end
	dirty = false
	wipe(wanted)
	local QL = C_QuestLog
	if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo and QL.GetQuestObjectives) then return wanted end
	local ok, num = pcall(QL.GetNumQuestLogEntries)
	num = ok and S(num) or 0
	for i = 1, num do
		local okInfo, info = pcall(QL.GetInfo, i)
		if okInfo and type(info) == "table" and not info.isHeader and info.questID then
			local okObj, objectives = pcall(QL.GetQuestObjectives, info.questID)
			if okObj and type(objectives) == "table" then
				for _, o in ipairs(objectives) do
					if o.type == "item" and not S(o.finished) then
						local name = MJ.ObjectiveItemName(S(o.text))
						if name then wanted[name] = info.questID end
					end
				end
			end
		end
	end
	return wanted
end

local function markDirty() dirty = true end
for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "UNIT_QUEST_LOG_CHANGED", "PLAYER_ENTERING_WORLD" }) do
	MJ:On(event, markDirty)
end

-- Counts one corpse of npc n for every quest item that is wanted right now (sign = 1),
-- or undoes such a count (sign = -1, names = what was counted). Returns the names counted.
function MJ:CountQuestCorpse(n, sign, names)
	if sign and sign < 0 then
		for _, name in ipairs(names or {}) do
			if n.qNeed and n.qNeed[name] then n.qNeed[name] = math.max(0, n.qNeed[name] - 1) end
		end
		return nil
	end
	local counted
	for name in pairs(MJ.WantedQuestItems()) do
		n.qNeed = n.qNeed or {}
		n.qNeed[name] = (n.qNeed[name] or 0) + 1
		counted = counted or {}
		counted[#counted + 1] = name
	end
	return counted
end
