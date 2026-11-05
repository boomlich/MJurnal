-- Tracker/Progress.lua: experience and reputation from kills (via chat messages).
local _, MJ = ...
local S = MJ.S

local XP_PATTERN = MJ.FormatToPattern(COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience.")
local REP_PATTERN = MJ.FormatToPattern(FACTION_STANDING_INCREASED or "Reputation with %s increased by %d.")

local function toNumber(s)
	if not s then return nil end
	return tonumber((s:gsub("[^%d]", "")))
end

MJ:On("CHAT_MSG_COMBAT_XP_GAIN", function(msg)
	msg = S(msg)
	if not msg or not MJ.db or not XP_PATTERN then return end
	local name, xp = msg:match(XP_PATTERN)
	xp = toNumber(xp)
	if name and xp then MJ:OnXPGain(name, xp) end
end)

MJ:On("CHAT_MSG_COMBAT_FACTION_CHANGE", function(msg)
	msg = S(msg)
	if not msg or not MJ.db or not REP_PATTERN then return end
	local faction, amount = msg:match(REP_PATTERN)
	amount = toNumber(amount)
	if faction and amount then MJ:OnRepGain(faction, amount) end
end)
