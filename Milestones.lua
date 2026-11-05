-- Milestones.lua: history log, milestones and chat alerts.
local _, MJ = ...
local St = MJ.Stats
local format = string.format

local NPC_MILESTONES = { 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000 }
local TOTAL_MILESTONES = { 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000 }

local function isIn(list, v)
	for i = 1, #list do
		if list[i] == v then return true end
	end
	return false
end

-- Log entry kinds: drop, ms (npc milestone), total, rare, rarekill, death, newnpc, newitem
function MJ:Log(e)
	e.t = e.t or time()
	e.c = e.c or self.charKey
	local log = self.db.log
	log[#log + 1] = e
	if #log > 5500 then
		local trimmed = {}
		for i = #log - 4999, #log do trimmed[#trimmed + 1] = log[i] end
		self.db.log = trimmed
	end
	self:Fire("LOG_ADDED", e)
end

function MJ:CheckKillMilestones(npcId, n)
	local s = self.db.settings
	if isIn(NPC_MILESTONES, n.kills) then
		self:Log({ k = "ms", npc = npcId, v = n.kills })
		if s.milestones then
			self:Print(format("Milestone! |cffffffff%s|r kills of |cffffd200%s|r.", MJ.Num(n.kills), self:NPCName(npcId)))
		end
	end
	local total = self.db.totals.kills or 0
	if isIn(TOTAL_MILESTONES, total) then
		self:Log({ k = "total", v = total })
		if s.milestones then
			self:Print(format("Milestone! |cffffffff%s|r total kills in your journal.", MJ.Num(total)))
		end
	end
end

function MJ:OnNewNPC(npcId, n)
	self:Log({ k = "newnpc", npc = npcId, z = (MJ.ZoneInfo()) })
	if self.db.settings.newEntries and self.charKey then
		self:Print("New journal entry: |cffffd200" .. self:NPCName(npcId) .. "|r")
	end
end

function MJ:OnNewItem(itemId, g, npcId)
	local q = g.quality or 1
	if q >= (self.db.settings.logQuality or 2) then
		self:Log({ k = "newitem", item = itemId, npc = npcId })
	end
end

function MJ:OnRareSeen(npcId, m)
	local zone = MJ.ZoneInfo()
	self.db.rares[npcId] = { t = time(), z = zone, name = m.name, c = self.charKey }
	self:Log({ k = "rare", npc = npcId, z = zone })
	if self.db.settings.rareAlerts then
		self:Print(format("Rare spotted: |cffc0c0ff%s|r%s", m.name or ("NPC #" .. npcId), zone ~= "" and (" in " .. zone) or ""))
	end
end

function MJ:OnItemDrop(npcId, n, itemId, it, gap, e)
	local s = self.db.settings
	local g = self.db.items[itemId]
	local q = e.quality or (g and g.quality) or 1
	local corpses = St.Corpses(n)
	local rate = it.drops / math.max(corpses, 1)
	-- quest-only drops are measured on on-quest corpses only; never call them "rare" by the normal rate
	local rare = corpses >= 20 and rate <= (s.alertRate or 0.05) and not St.IsQuestOnly(itemId, it)
	if q >= (s.logQuality or 2) or rare then
		self.session.notable = (self.session.notable or 0) + 1
		self:Log({ k = "drop", npc = npcId, item = itemId, q = e.q, gap = gap, cn = corpses, d = it.drops })
	end
	if not s.dropAlerts then return end
	if rare or q >= 4 then
		local text = format("%s dropped from |cffffd200%s|r", self:ItemText(itemId), self:NPCName(npcId))
		if it.drops > 1 and corpses > gap then
			local expected = (corpses - gap) / (it.drops - 1)
			text = text .. format(" after %d corpses (expected ~%d). Rate now %s.", gap, math.floor(expected + 0.5), MJ.Pct(rate))
		else
			text = text .. format(" - first time, after %d corpses.", gap)
		end
		self:Print(text)
	elseif it.drops == 1 and s.newEntries and q >= 2 then
		self:Print(format("New loot: %s from |cffffd200%s|r", self:ItemText(itemId), self:NPCName(npcId)))
	end
end
