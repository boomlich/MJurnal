-- Tracker/Damage.lua: damage dealt to / taken from each monster type.
--
-- The combat log is not available to addons on WoW Forever, but the built-in damage meter
-- (C_DamageMeter, the same source Details! uses there) keeps per-fight aggregates.
-- Its values are secret while in combat, so each fight is read shortly after it ends:
--   EnemyDamageTaken -> damage each enemy type took, and who dealt it (you / your pet / group)
--   DamageTaken      -> damage you took, per ability, with the name of the enemy that dealt it
local _, MJ = ...
local S, issecret = MJ.S, MJ.issecret

local DM = C_DamageMeter
local T = Enum and Enum.DamageMeterType
if not DM or not T or not DM.GetAvailableCombatSessions or not DM.GetCombatSessionFromID then
	MJ.damageMeterMissing = true
	return
end

local processed = {}     -- [sessionID] = true
local fightKills = {}    -- [npcId] = kills since the last processed fight
local fightNames = {}    -- [name] = npcId seen since the last processed fight
local NO_KILLS = {}

MJ:Listen("KILL", function(npcId, name)
	fightKills[npcId] = (fightKills[npcId] or 0) + 1
	if name then fightNames[name] = npcId end
end)

local function sessions()
	local ok, list = pcall(DM.GetAvailableCombatSessions)
	if not ok or type(list) ~= "table" then return {} end
	return list
end

local function nameToNPC(name)
	return (name and fightNames[name]) or MJ.NPCIdByName(name)
end

local function sourceDetails(sessionID, meterType, guid, creatureID)
	if not DM.GetCombatSessionSourceFromID then return nil end
	local ok, det = pcall(DM.GetCombatSessionSourceFromID, sessionID, meterType, guid, creatureID)
	if ok and type(det) == "table" then return det end
end

-- kills = [npcId] = kills to credit to this session (only the newest session gets them).
-- Returns false when the data is still secret (try again later).
local function readSession(sessionID, kills)
	local ok, enemy = pcall(DM.GetCombatSessionFromID, sessionID, T.EnemyDamageTaken)
	if not ok then return true end
	local result = {}   -- [npcId] = { done, mine, taken, spells = { [spellID] = amount } }
	local idByName = {}
	local myName = S(UnitName("player"))
	local petName = S(UnitName("pet"))
	local myGUID = MJ.SafeGUID("player")

	local function entry(npcId)
		local r = result[npcId]
		if not r then
			r = { done = 0, mine = 0, taken = 0, spells = {} }
			result[npcId] = r
		end
		return r
	end

	if type(enemy) == "table" and type(enemy.combatSources) == "table" then
		for _, src in ipairs(enemy.combatSources) do
			if issecret(src.sourceCreatureID) or issecret(src.totalAmount) or issecret(src.name) then return false end
			local cid, total = src.sourceCreatureID, src.totalAmount
			if cid and cid > 0 and total then
				if src.name then idByName[src.name] = cid end
				local r = entry(cid)
				r.done = r.done + total
				local det = sourceDetails(sessionID, T.EnemyDamageTaken, src.sourceGUID, cid)
				if det and type(det.combatSpells) == "table" then
					for _, sp in ipairs(det.combatSpells) do
						local d = sp.combatSpellDetails
						local who = d and S(d.unitName)
						local amt = S(sp.totalAmount)
						if amt and who and (who == myName or (petName and who == petName)) then
							r.mine = r.mine + amt
						end
					end
				end
			end
		end
	end

	if myGUID and T.DamageTaken then
		local det = sourceDetails(sessionID, T.DamageTaken, myGUID, nil)
		if det and type(det.combatSpells) == "table" then
			for _, sp in ipairs(det.combatSpells) do
				local d = sp.combatSpellDetails
				local who = d and S(d.unitName) or S(sp.creatureName)
				local amt, spellID = S(sp.totalAmount), S(sp.spellID)
				if amt == nil and sp.totalAmount ~= nil then return false end
				local npcId = who and (idByName[who] or nameToNPC(who))
				if npcId and amt then
					local r = entry(npcId)
					r.taken = r.taken + amt
					local key = spellID or 0
					r.spells[key] = (r.spells[key] or 0) + amt
				end
			end
		end
	end

	local any = false
	for npcId, r in pairs(result) do
		local k = kills[npcId] or 0
		if MJ.db.npcs[npcId] or k > 0 then
			local n = MJ:NPCStats(MJ:GetNPC(npcId, true))
			n.dmgFights = (n.dmgFights or 0) + 1
			n.dmgDone = (n.dmgDone or 0) + r.done
			n.dmgMine = (n.dmgMine or 0) + r.mine
			n.dmgTaken = (n.dmgTaken or 0) + r.taken
			if k > 0 then
				-- only fights where it died count towards "damage per kill" (~ its health)
				n.dmgKills = (n.dmgKills or 0) + k
				n.dmgKillDone = (n.dmgKillDone or 0) + r.done
				n.dmgKillTaken = (n.dmgKillTaken or 0) + r.taken
			end
			if next(r.spells) then
				n.spells = n.spells or {}
				for spellID, amt in pairs(r.spells) do
					local s = n.spells[spellID]
					if not s then
						s = { amt = 0, fights = 0 }
						n.spells[spellID] = s
					end
					s.amt = s.amt + amt
					s.fights = s.fights + 1
					s.max = math.max(s.max or 0, amt)
				end
			end
			if r.mine > 0 then MJ:Bump("dmgDone", r.mine) end
			if r.taken > 0 then MJ:Bump("dmgTaken", r.taken) end
			any = true
		end
	end
	MJ:Debug("damage meter session %s: %d monster types", tostring(sessionID), MJ.Count(result))
	if any then MJ:Changed() end
	return true
end

local tries = 0
local function processAll()
	if not MJ.db then return end
	if InCombatLockdown() or UnitAffectingCombat("player") then return end
	local todo = {}
	for _, s in ipairs(sessions()) do
		local id = S(s.sessionID)
		if id and not processed[id] then todo[#todo + 1] = id end
	end
	table.sort(todo)
	-- The kills seen since the last run belong to the newest fight. Crediting them to every
	-- unread session would count each kill once per session.
	local pending = false
	for i, id in ipairs(todo) do
		if readSession(id, i == #todo and fightKills or NO_KILLS) then
			processed[id] = true
		else
			pending = true
			break
		end
	end
	if pending and tries < 8 then
		tries = tries + 1
		C_Timer.After(3, processAll)
		return
	end
	tries = 0
	wipe(fightKills)
	wipe(fightNames)
end

MJ:Listen("LOGIN", function()
	-- sessions that existed before we loaded were not seen by us; skip them
	for _, s in ipairs(sessions()) do
		local id = S(s.sessionID)
		if id then processed[id] = true end
	end
end)

MJ:On("PLAYER_REGEN_ENABLED", function()
	tries = 0
	C_Timer.After(4, processAll)
end)

MJ:On("DAMAGE_METER_RESET", function()
	wipe(processed)
end)
