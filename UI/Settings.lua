-- UI/Settings.lua: options panel (Esc > Options > AddOns > MJurnal).
local _, MJ = ...
local UI = MJ.UI

-- { setting, label, tooltip }
local OPTIONS = {
	{ "minimapButton", "Show minimap button" },
	{ "fadeMoving", "Fade the journal while moving", "Fully visible while the mouse is over it." },
	{ "fadeCombat", "Fade the journal in combat", "Fully visible while the mouse is over it." },
	{ "unitTooltip", "MJurnal line on NPC tooltips", "Kills, corpses looted and value per corpse." },
	{ "itemTooltip", "MJurnal line on item tooltips", "Times looted and the best source." },
	{ "dropAlerts", "Chat alert on rare drops", "Drops with a rate at or below %s, or epic and better." },
	{ "milestones", "Chat message on kill milestones" },
	{ "newEntries", "Chat message on new entries", "New monsters and first-time uncommon+ loot." },
	{ "rareAlerts", "Chat message when a rare is spotted" },
	{ "ahAutoScan", "Scan the auction house when you open it", "A full scan of every auction for prices, at most every 15 minutes (the server's limit). You can always scan with the MJurnal button under the auction house." },
	{ "debug", "Debug: print every kill / loot" },
}

-- Quest drop stats on NPC tooltips: the switch, then what to show.
local QUEST_OPTIONS = {
	{ "qtRate", "Drop rate", "Chance per corpse (on-quest corpses for quest-only items)." },
	{ "qtLeft", "Kills left for the quest", "Estimate from the items still needed and the average per kill." },
	{ "qtOneIn", "1 in X", "Corpses per drop." },
	{ "qtPerCorpse", "Average per kill", "Units of the item per corpse, stacks counted." },
	{ "qtSample", "Drops / corpses", "The numbers the rate is built from." },
	{ "qtSince", "Corpses since last drop" },
}

local panel

local function build()
	panel = CreateFrame("Frame")
	panel.name = "MJurnal"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("MJurnal")
	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetText("Monster & loot journal. Key bindings are under Key Bindings > AddOns > MJurnal.")

	panel.checks = {}
	local function check(opt, x, y, onClick)
		local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", x, y)
		local label = cb.Text or cb.text
		if not label then
			label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
		end
		cb.label = label
		label:SetText(opt[2])
		cb.key = opt[1]
		-- "%s" in a tooltip is the current rare-drop threshold
		local tip = opt[3] and opt[3]:format(("%g%%"):format(MJ.db.settings.alertRate * 100))
		if tip then
			cb:SetScript("OnEnter", function(s)
				GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
				GameTooltip:SetText(opt[2], 1, 1, 1)
				GameTooltip:AddLine(tip, nil, nil, nil, true)
				GameTooltip:Show()
			end)
			cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		cb:SetScript("OnClick", function(s)
			MJ.db.settings[s.key] = s:GetChecked() and true or false
			MJ:Fire("SETTING_CHANGED", s.key)
			if onClick then onClick() end
		end)
		panel.checks[#panel.checks + 1] = cb
		return cb
	end

	local y = -64
	for _, opt in ipairs(OPTIONS) do
		check(opt, 16, y)
		y = y - 30
	end

	-- right column: quest drop stats on NPC tooltips
	local qx, qy = 340, -64
	local qTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	qTitle:SetPoint("TOPLEFT", qx + 4, qy)
	qTitle:SetText("Quest drops on NPC tooltips")
	local qNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	qNote:SetPoint("TOPLEFT", qTitle, "BOTTOMLEFT", 0, -4)
	qNote:SetWidth(300)
	qNote:SetJustifyH("LEFT")
	qNote:SetText("Shown next to the quest objective (\"Murloc Fin: 3/6\") when you mouse over a monster that has dropped the item.")
	local subChecks = {}
	local function updateSub()
		local on = MJ.db.settings.questTooltip
		for _, cb in ipairs(subChecks) do
			if on then cb:Enable() else cb:Disable() end
			cb.label:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
		end
	end
	qy = qy - 46
	check({ "questTooltip", "Show quest drop stats" }, qx, qy, updateSub)
	for _, opt in ipairs(QUEST_OPTIONS) do
		qy = qy - 26
		subChecks[#subChecks + 1] = check(opt, qx + 24, qy)
	end
	panel.updateSub = updateSub

	local qLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	qLabel:SetPoint("TOPLEFT", 20, y - 10)
	local qBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	qBtn:SetSize(140, 22)
	qBtn:SetPoint("LEFT", qLabel, "RIGHT", 10, 0)
	local function updateQ()
		local q = MJ.db.settings.logQuality
		qLabel:SetText("Log drops of quality:")
		qBtn:SetText(MJ.QualityHex(q) .. MJ.QualityName(q) .. "|r+")
	end
	qBtn:SetScript("OnClick", function()
		MJ.db.settings.logQuality = MJ.db.settings.logQuality % 5 + 1
		updateQ()
	end)
	panel.updateQ = updateQ

	local FADE_STEPS = { 0.2, 0.35, 0.5, 0.65, 0.8 }
	local fLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fLabel:SetPoint("TOPLEFT", 20, y - 44)
	fLabel:SetText("Opacity while faded:")
	local fBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	fBtn:SetSize(80, 22)
	fBtn:SetPoint("LEFT", fLabel, "RIGHT", 10, 0)
	local function updateF()
		fBtn:SetText(math.floor((MJ.db.settings.fadeAlpha or 0.35) * 100 + 0.5) .. "%")
	end
	fBtn:SetScript("OnClick", function()
		local cur, nextA = MJ.db.settings.fadeAlpha or 0.35, FADE_STEPS[1]
		for _, a in ipairs(FADE_STEPS) do
			if a > cur + 0.001 then
				nextA = a
				break
			end
		end
		MJ.db.settings.fadeAlpha = nextA
		updateF()
	end)

	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(180, 22)
	reset:SetPoint("TOPLEFT", 16, y - 90)
	reset:SetText("Reset ALL journal data")
	reset:SetScript("OnClick", function()
		StaticPopupDialogs.MJURNAL_RESET_ALL = StaticPopupDialogs.MJURNAL_RESET_ALL or {
			text = "Delete ALL MJurnal data on this account? This cannot be undone.",
			button1 = YES or "Yes",
			button2 = NO or "No",
			OnAccept = function() MJ:ResetAll() MJ:Print("All journal data deleted.") end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			showAlert = true,
		}
		StaticPopup_Show("MJURNAL_RESET_ALL")
	end)

	-- delete one character: pick it from a menu, then confirm
	StaticPopupDialogs.MJURNAL_DELETE_CHAR = {
		text = "Delete all MJurnal data for %s?\n\nIts kills, loot, deaths and history are removed. Monsters and items only this character has seen disappear from the journal. This cannot be undone.",
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function(_, ck)
			local name = MJ:CharName(ck)
			MJ:DeleteCharacter(ck)
			MJ:Print("Deleted the journal data of " .. name .. ".")
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		showAlert = true,
	}
	local function charMenu()
		local chars = {}
		for ck, c in pairs(MJ.db.chars) do chars[#chars + 1] = { ck = ck, kills = c.kills or 0 } end
		table.sort(chars, function(a, b)
			if a.kills ~= b.kills then return a.kills > b.kills end
			return a.ck < b.ck
		end)
		local entries = { { text = "Delete the data of:", title = true } }
		for _, ch in ipairs(chars) do
			local ck = ch.ck
			entries[#entries + 1] = {
				text = MJ:CharName(ck) .. UI.Grey(" - " .. (ck:match("%-(.+)$") or ck) .. ", " .. MJ.Num(ch.kills) .. " kills"),
				onClick = function() StaticPopup_Show("MJURNAL_DELETE_CHAR", ck, nil, ck) end,
			}
		end
		if #chars == 0 then entries[2] = { text = UI.Grey("No characters recorded yet.") } end
		return entries
	end
	local deleteChar = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	deleteChar:SetSize(200, 22)
	deleteChar:SetPoint("LEFT", reset, "RIGHT", 10, 0)
	deleteChar:SetText("Delete a character's data...")
	deleteChar:SetScript("OnClick", function(b) UI.ToggleMenu(b, charMenu) end)
	panel:SetScript("OnHide", function() UI.HideMenu() end)

	panel:SetScript("OnShow", function()
		for _, cb in ipairs(panel.checks) do cb:SetChecked(MJ.db.settings[cb.key]) end
		panel.updateSub()
		updateQ()
		updateF()
	end)

	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, "MJurnal")
		Settings.RegisterAddOnCategory(category)
		UI.settingsCategory = category
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

MJ:Listen("DB_READY", build)

function UI:OpenSettings()
	if self.settingsCategory and Settings and Settings.OpenToCategory then
		local id = self.settingsCategory.GetID and self.settingsCategory:GetID() or self.settingsCategory.ID
		Settings.OpenToCategory(id)
	elseif InterfaceOptionsFrame_OpenToCategory and panel then
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end
