-- Tracker/Loot.lua: reads the loot window and attributes every slot to its source corpse.
local _, MJ = ...
local S, issecret, ParseGUID = MJ.S, MJ.issecret, MJ.ParseGUID
local GetTime = GetTime

local SLOT_ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or LOOT_SLOT_ITEM or 1
local SLOT_MONEY = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or LOOT_SLOT_MONEY or 2

---------------------------------------------------------------------------
-- Gathering / pick pocket detection (all ranks of the classic spells)
---------------------------------------------------------------------------
local GATHER_SPELLS = {
	[8613] = "skin", [8617] = "skin", [8618] = "skin", [10768] = "skin",
	[2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
	[2575] = "mine", [2576] = "mine", [3564] = "mine", [10248] = "mine",
	[921] = "pick",
}

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	if GetSpellInfo then return (GetSpellInfo(id)) end
end

local gatherNames
local function GatherKind(spellID)
	if not spellID then return nil end
	if GATHER_SPELLS[spellID] then return GATHER_SPELLS[spellID] end
	if not gatherNames or not next(gatherNames) then
		gatherNames = {}
		for id, kind in pairs(GATHER_SPELLS) do
			local nm = SpellName(id)
			if nm then gatherNames[nm] = kind end
		end
	end
	local nm = SpellName(spellID)
	return nm and gatherNames[nm]
end

local lastGather -- { kind, t }

local function playerSpell(unit, spellID)
	if issecret(unit) or unit ~= "player" then return nil end
	return GatherKind(S(spellID))
end

MJ:On("UNIT_SPELLCAST_SENT", function(unit, _, _, spellID)
	local kind = playerSpell(unit, spellID)
	if kind then lastGather = { kind = kind, t = GetTime() } end
end)

MJ:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	local kind = playerSpell(unit, spellID)
	if not kind then return end
	lastGather = { kind = kind, t = GetTime() }
	if kind == "pick" and MJ.db then
		local npcId = MJ.UnitNPC("target")
		if npcId then
			MJ.CaptureMeta("target", npcId)
			MJ:RecordPickAttempt(npcId)
		end
	end
end)

local function castStopped(unit, _, spellID)
	if playerSpell(unit, spellID) then lastGather = nil end
end
MJ:On("UNIT_SPELLCAST_FAILED", castStopped)
MJ:On("UNIT_SPELLCAST_INTERRUPTED", castStopped)

---------------------------------------------------------------------------
-- Loot window
---------------------------------------------------------------------------
local handled = false

local function unitInfoFor(guid)
	for _, u in ipairs({ "target", "mouseover", "softinteract" }) do
		if MJ.SafeGUID(u) == guid then
			local npcId = ParseGUID(guid)
			if npcId then MJ.CaptureMeta(u, npcId) end
			return S(UnitName(u)), S(UnitLevel(u))
		end
	end
end

local function OnLoot()
	if handled or not MJ.db then return end
	local num = S(GetNumLootItems())
	if not num then return end
	handled = true

	local gather = lastGather and (GetTime() - lastGather.t) < 10 and lastGather.kind or nil
	local fishing = IsFishingLoot and S(IsFishingLoot()) or false

	if num == 0 then
		-- An empty loot window has no slots to name a source, so use the corpse you opened.
		if gather or fishing then return end
		for _, u in ipairs({ "target", "mouseover", "softinteract" }) do
			if S(UnitIsDead(u)) then
				local guid = MJ.SafeGUID(u)
				local npcId = guid and ParseGUID(guid)
				if npcId then
					local name, level = unitInfoFor(guid)
					MJ:RecordCorpseLoot(guid, npcId, { items = {}, money = 0, name = name, level = level })
					return
				end
			end
		end
		return
	end

	-- fallback when the client does not tell us the source of a slot
	local fallbackGUID
	if S(UnitIsDead("target")) then fallbackGUID = MJ.SafeGUID("target") end

	local sources, order = {}, {}
	local function source(guid)
		local s = sources[guid]
		if not s then
			s = { items = {}, money = 0 }
			sources[guid] = s
			order[#order + 1] = guid
		end
		return s
	end

	for slot = 1, num do
		local slotType = S(GetLootSlotType(slot))
		local _, slotName, slotQty, _, quality, _, isQuest, questID = GetLootSlotInfo(slot)
		slotName, slotQty, quality, isQuest, questID = S(slotName), S(slotQty), S(quality), S(isQuest), S(questID)
		local starter = (questID and questID ~= 0) and true or nil
		local link = S(GetLootSlotLink(slot))
		local itemId = link and tonumber(link:match("item:(%d+)"))
		local isMoney = slotType == SLOT_MONEY
		if isMoney or (slotType == SLOT_ITEM and itemId) then
			local srcs = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
			local found = 0
			for i = 1, #srcs, 2 do
				local g, q = srcs[i], srcs[i + 1]
				if g ~= nil and not issecret(g) then
					q = S(q)
					found = found + 1
					local s = source(g)
					if isMoney then
						s.money = s.money + (q or MJ.ParseMoney(slotName) or 0)
					else
						local e = s.items[itemId]
						if not e then
							e = { q = 0, link = link, quality = quality, quest = isQuest or nil, starter = starter, name = slotName }
							s.items[itemId] = e
						end
						e.q = e.q + ((q and q > 0) and q or slotQty or 1)
					end
				end
			end
			if found == 0 and (fallbackGUID or fishing) then
				local s = source(fallbackGUID or "fishing")
				if isMoney then
					s.money = s.money + (MJ.ParseMoney(slotName) or 0)
				else
					local e = s.items[itemId]
					if not e then
						e = { q = 0, link = link, quality = quality, quest = isQuest or nil, starter = starter, name = slotName }
						s.items[itemId] = e
					end
					e.q = e.q + (slotQty or 1)
				end
			end
		end
	end

	local zone = MJ.ZoneInfo()

	if fishing then
		local merged = { items = {}, money = 0 }
		for _, guid in ipairs(order) do
			local s = sources[guid]
			merged.money = merged.money + s.money
			for id, e in pairs(s.items) do
				local m = merged.items[id]
				if m then m.q = m.q + e.q else merged.items[id] = e end
			end
		end
		MJ:RecordOther("fishing", merged, zone)
		return
	end

	local usedGather = false
	for _, guid in ipairs(order) do
		local s = sources[guid]
		local npcId, kind = ParseGUID(guid)
		if npcId then
			s.name, s.level = unitInfoFor(guid)
			if gather then
				MJ:RecordGather(guid, npcId, gather, s)
				usedGather = true
			else
				MJ:RecordCorpseLoot(guid, npcId, s)
			end
		elseif kind == "Item" then
			MJ:RecordOther("container", s, zone)
		elseif kind == "GameObject" then
			if not MJ.db.recent.loot[guid] then
				MJ.db.recent.loot[guid] = time()
				local okind = (gather == "herb" or gather == "mine") and gather or "object"
				MJ:RecordOther(okind, s, zone)
				usedGather = usedGather or okind ~= "object"
			end
		end
	end
	if usedGather then lastGather = nil end
end

MJ:On("LOOT_READY", OnLoot)
MJ:On("LOOT_OPENED", OnLoot)
MJ:On("LOOT_CLOSED", function() handled = false end)

MJ:On("UNIT_LOOT", function(guid, hasLoot)
	if MJ.db then MJ:OnUnitLoot(guid, hasLoot) end
end)
