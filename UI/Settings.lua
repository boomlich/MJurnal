-- UI/Settings.lua: options panel (Esc > Options > AddOns > MJurnal).
local _, MJ = ...
local UI = MJ.UI

local OPTIONS = {
	{ "minimapButton", "Show minimap button" },
	{ "fadeMoving", "Fade the journal while moving (fully visible while the mouse is over it)" },
	{ "unitTooltip", "Show MJurnal line on NPC tooltips" },
	{ "itemTooltip", "Show MJurnal line on item tooltips" },
	{ "dropAlerts", "Chat alert on rare drops (rate at or below %s, or epic+)" },
	{ "milestones", "Chat message on kill milestones" },
	{ "newEntries", "Chat message on new monsters and first-time uncommon+ loot" },
	{ "rareAlerts", "Chat message when a rare monster is spotted" },
	{ "debug", "Debug: print every detected kill / loot" },
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

	local y = -64
	panel.checks = {}
	for _, opt in ipairs(OPTIONS) do
		local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", 16, y)
		local label = cb.Text or cb.text
		if not label then
			label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
			label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
		end
		-- "%s" in a label is the current rare-drop threshold
		label:SetText(opt[2]:format(("%g%%"):format(MJ.db.settings.alertRate * 100)))
		cb.key = opt[1]
		cb:SetScript("OnClick", function(s)
			MJ.db.settings[s.key] = s:GetChecked() and true or false
			MJ:Fire("SETTING_CHANGED", s.key)
		end)
		panel.checks[#panel.checks + 1] = cb
		y = y - 30
	end

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
	fLabel:SetText("Opacity while moving:")
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

	panel:SetScript("OnShow", function()
		for _, cb in ipairs(panel.checks) do cb:SetChecked(MJ.db.settings[cb.key]) end
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
