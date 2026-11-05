-- Tracker/Units.lua: kill detection without the combat log.
--
-- WoW Forever runs with the Midnight addon restrictions, so COMBAT_LOG_EVENT_UNFILTERED
-- is not available. Kills are detected from unit tokens instead:
--   1. A hostile NPC is "engaged" when it is in combat with you/your group (threat or target)
--      and not tapped by someone else.
--   2. When an engaged unit (or a unit whose health just changed while you are in combat)
--      is seen dead and not tap-denied, it is a kill for you/your group.
--   3. "X dies, you gain N experience" and looting a corpse are fallbacks (see Progress/Loot).
local _, MJ = ...
local S, SafeGUID, ParseGUID = MJ.S, MJ.SafeGUID, MJ.ParseGUID
local GetTime, pairs = GetTime, pairs

local engaged = {}  -- [guid] = { npc, start, last, level, name }
MJ.engaged = engaged

local inCombat, combatEnd = false, 0
local RARE = { rare = true, rareelite = true }

local scanTokens = { "target", "focus", "mouseover", "softenemy", "pettarget" }
for i = 1, 40 do scanTokens[#scanTokens + 1] = "nameplate" .. i end
for i = 1, 4 do scanTokens[#scanTokens + 1] = "party" .. i .. "target" end
MJ.scanTokens = scanTokens

local function Exists(u)
	return S(UnitExists(u)) and true or false
end

local function CaptureMeta(unit, npcId)
	local m = MJ.meta[npcId]
	if not m then
		m = {}
		MJ.meta[npcId] = m
	end
	local name = S(UnitName(unit))
	if name and name ~= "" and name ~= UNKNOWNOBJECT then m.name = name end
	m.class = S(UnitClassification(unit)) or m.class
	m.type = S(UnitCreatureType(unit)) or m.type
	m.family = S(UnitCreatureFamily(unit)) or m.family
	if MJ.db.npcs[npcId] then MJ:ApplyMeta(npcId) end
	if m.class and RARE[m.class] and m.name and not MJ.db.rares[npcId] then
		MJ:OnRareSeen(npcId, m)
	end
	return m
end
MJ.CaptureMeta = CaptureMeta

local function IsGroupUnit(u)
	if not Exists(u) then return false end
	if S(UnitIsUnit(u, "player")) or S(UnitIsUnit(u, "pet")) then return true end
	if S(UnitPlayerOrPetInParty(u)) or S(UnitPlayerOrPetInRaid(u)) then return true end
	return false
end

local function EngagedWithGroup(unit)
	if S(UnitThreatSituation("player", unit)) then return true end
	if Exists("pet") and S(UnitThreatSituation("pet", unit)) then return true end
	if IsGroupUnit(unit .. "target") then return true end
	if IsInGroup() and not IsInRaid() then
		for i = 1, GetNumSubgroupMembers() do
			if S(UnitThreatSituation("party" .. i, unit)) then return true end
		end
	end
	return false
end

function MJ:InCombatWindow()
	return inCombat or (GetTime() - combatEnd) < 4
end

local ticker

-- live = true when called from an event that means "this unit just changed" (UNIT_HEALTH):
-- a dead unit there died just now.
local function CheckUnit(unit, live)
	local guid = SafeGUID(unit)
	if not guid then return end
	local npcId = ParseGUID(guid)
	if not npcId then return end
	if S(UnitPlayerControlled(unit)) then return end
	local e = engaged[guid]

	if S(UnitIsDead(unit)) then
		if MJ.db.recent.kills[guid] then
			engaged[guid] = nil
			return
		end
		local denied = S(UnitIsTapDenied(unit))
		if denied then
			engaged[guid] = nil
			return
		end
		if e or (live and denied == false and MJ:InCombatWindow() and S(UnitCanAttack("player", unit))) then
			local m = CaptureMeta(unit, npcId)
			local lvl = (e and e.level) or S(UnitLevel(unit))
			MJ:RecordKill(guid, npcId, { source = "unit", start = e and e.start, level = lvl, name = m.name })
			engaged[guid] = nil
		end
		return
	end

	if not S(UnitCanAttack("player", unit)) then return end
	local m = CaptureMeta(unit, npcId)
	local now = GetTime()
	if S(UnitAffectingCombat(unit)) and S(UnitIsTapDenied(unit)) == false and EngagedWithGroup(unit) then
		if not e then
			e = { npc = npcId, start = now, name = m.name }
			engaged[guid] = e
			MJ:EnsureTicker()
		end
		e.last = now
		local lvl = S(UnitLevel(unit))
		if lvl and lvl > 0 then e.level = lvl end
	elseif e and S(UnitIsTapDenied(unit)) then
		engaged[guid] = nil
	end
end
MJ.CheckUnit = CheckUnit

local function Scan()
	for i = 1, #scanTokens do
		local u = scanTokens[i]
		if Exists(u) then CheckUnit(u, false) end
	end
	local now = GetTime()
	for guid, e in pairs(engaged) do
		if now - (e.last or e.start) > 120 then engaged[guid] = nil end
	end
end

function MJ:EnsureTicker()
	if ticker or not C_Timer then return end
	ticker = C_Timer.NewTicker(0.5, function()
		Scan()
		if not inCombat and next(engaged) == nil then
			ticker:Cancel()
			ticker = nil
		end
	end)
end

-- Used by the XP fallback: a fresh, uncounted, not-tapped corpse with this name.
function MJ.FindDeadUnitByName(name)
	for i = 1, #scanTokens do
		local u = scanTokens[i]
		if Exists(u) and S(UnitIsDead(u)) and S(UnitName(u)) == name and S(UnitIsTapDenied(u)) == false then
			local guid = SafeGUID(u)
			local npcId = guid and ParseGUID(guid)
			if npcId and not MJ.db.recent.kills[guid] then
				CaptureMeta(u, npcId)
				local e = engaged[guid]
				return guid, npcId, (e and e.level) or S(UnitLevel(u))
			end
		end
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function IsEnemyToken(unit)
	if unit == nil or MJ.issecret(unit) or type(unit) ~= "string" then return false end
	return unit == "target" or unit == "focus" or unit == "mouseover" or unit == "softenemy"
		or unit:sub(1, 9) == "nameplate" or unit:sub(1, 4) == "boss"
end

local function ready() return MJ.db ~= nil end

MJ:On("UNIT_HEALTH", function(unit)
	if ready() and IsEnemyToken(unit) then CheckUnit(unit, true) end
end)

local function passive(unit)
	if ready() and IsEnemyToken(unit) then CheckUnit(unit, false) end
end
MJ:On("UNIT_FLAGS", passive)
MJ:On("UNIT_THREAT_LIST_UPDATE", passive)
MJ:On("NAME_PLATE_UNIT_ADDED", passive)
MJ:On("NAME_PLATE_UNIT_REMOVED", passive)

MJ:On("PLAYER_TARGET_CHANGED", function() if ready() then CheckUnit("target", false) end end)
MJ:On("UPDATE_MOUSEOVER_UNIT", function() if ready() then CheckUnit("mouseover", false) end end)
MJ:On("PLAYER_FOCUS_CHANGED", function() if ready() then CheckUnit("focus", false) end end)
MJ:On("PLAYER_SOFT_ENEMY_CHANGED", function() if ready() then CheckUnit("softenemy", false) end end)

MJ:On("PLAYER_REGEN_DISABLED", function()
	inCombat = true
	if ready() then
		MJ:EnsureTicker()
		Scan()
	end
end)

MJ:On("PLAYER_REGEN_ENABLED", function()
	inCombat = false
	combatEnd = GetTime()
	if ready() then Scan() end
end)

-- Who killed us? Mobs targeting the player, else the most recently engaged mob.
MJ:On("PLAYER_DEAD", function()
	if not ready() then return end
	local killers = {}
	for i = 1, #scanTokens do
		local u = scanTokens[i]
		if Exists(u) and not S(UnitIsDead(u)) and S(UnitCanAttack("player", u)) and S(UnitIsUnit(u .. "target", "player")) then
			local npcId = MJ.UnitNPC(u)
			if npcId then
				CaptureMeta(u, npcId)
				killers[npcId] = true
			end
		end
	end
	if not next(killers) then
		local best, bestT
		for _, e in pairs(engaged) do
			if not bestT or e.last > bestT then best, bestT = e.npc, e.last end
		end
		if best and GetTime() - bestT < 10 then killers[best] = true end
	end
	MJ:RecordDeath(killers)
end)
