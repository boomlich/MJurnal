-- UI/Frame.lua: main journal window with Overview / Monsters / Loot / History tabs.
local _, MJ = ...
local UI, St = MJ.UI, MJ.Stats

local W, H = 1080, 680
local LIST_W = 290
local TABS = { "Overview", "Monsters", "Loot", "History" }
local TAB_OVERVIEW, TAB_MONSTERS, TAB_LOOT, TAB_HISTORY = 1, 2, 3, 4

UI.views = {}
UI.state = {
	tab = TAB_MONSTERS,
	selected = {},
	search = { [TAB_MONSTERS] = "", [TAB_LOOT] = "" },
	sort = { [TAB_MONSTERS] = 1, [TAB_LOOT] = 1 },
}

local function hasList(tab) return tab == TAB_MONSTERS or tab == TAB_LOOT end

function UI.FadeTarget(frame)
	local s = MJ.db.settings
	if not s.fadeMoving or not IsPlayerMoving() then return 1 end
	if frame:IsMouseOver() then return 1 end
	return s.fadeAlpha or 0.35
end

---------------------------------------------------------------------------
-- List (left side)
---------------------------------------------------------------------------
local function InitListButton(btn, data)
	if not btn.text then
		btn:SetHeight(20)
		btn.sel = btn:CreateTexture(nil, "BACKGROUND")
		btn.sel:SetAllPoints()
		btn.sel:SetColorTexture(1, 0.82, 0, 0.2)
		local hl = btn:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.08)
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetSize(16, 16)
		btn.icon:SetPoint("LEFT", 4, 0)
		btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		btn.count:SetPoint("RIGHT", -6, 0)
		btn.count:SetJustifyH("RIGHT")
		btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		btn.text:SetJustifyH("LEFT")
		btn.text:SetWordWrap(false)
		btn.text:SetPoint("RIGHT", btn.count, "LEFT", -6, 0)
		btn:SetScript("OnClick", function(s) UI:Select(s.data.id) end)
		btn:SetScript("OnEnter", function(s)
			if s.data.tab == TAB_LOOT then
				GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
				GameTooltip:SetItemByID(s.data.id)
				GameTooltip:Show()
			end
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	btn.data = data
	if data.icon then
		btn.icon:SetTexture(data.icon)
		btn.icon:Show()
		btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 4, 0)
	else
		btn.icon:Hide()
		btn.text:SetPoint("LEFT", btn, "LEFT", 6, 0)
	end
	btn.text:SetText(data.label)
	btn.count:SetText(data.count)
	btn.sel:SetShown(UI.state.selected[UI.state.tab] == data.id)
end

local function MonsterElements()
	local sortKey = St.MONSTER_SORTS[UI.state.sort[TAB_MONSTERS]].key
	local out = {}
	for _, e in ipairs(St.MonsterList(UI.state.search[TAB_MONSTERS], sortKey)) do
		local count
		if sortKey == "value" then
			count = MJ.Money(e.v)
		elseif sortKey == "items" then
			count = MJ.Num(e.v)
		elseif sortKey == "last" then
			count = MJ.Ago(e.n.lastKill and e.n.lastKill.t)
		elseif sortKey == "deaths" then
			local d = e.n.deathsTo or 0
			count = d > 0 and UI.Red(MJ.Num(d)) or UI.Grey("0")
		else
			count = MJ.Num(e.n.kills)
		end
		local label = UI.NPCLabel(e.id)
		local cl = UI.CLASS_LABEL[e.n.class or "normal"]
		if cl and cl ~= "" then label = label .. UI.Grey(" (" .. cl .. ")") end
		out[#out + 1] = { tab = TAB_MONSTERS, id = e.id, label = label, count = count }
	end
	return out
end

local function LootElements()
	local sortKey = St.LOOT_SORTS[UI.state.sort[TAB_LOOT]].key
	local out = {}
	for _, e in ipairs(St.ItemList(UI.state.search[TAB_LOOT], sortKey)) do
		local count
		if sortKey == "value" then
			count = MJ.Money(e.v)
		elseif sortKey == "last" then
			count = MJ.Ago(e.g.last and e.g.last.t)
		else
			count = MJ.Num(e.g.drops)
		end
		out[#out + 1] = {
			tab = TAB_LOOT, id = e.id, count = count, icon = MJ:ItemIcon(e.id),
			label = MJ.QualityHex(e.g.quality) .. e.name .. "|r",
		}
	end
	return out
end

function UI:RefreshList(keepScroll)
	if not self.frame or not hasList(self.state.tab) then return end
	local elements = self.state.tab == TAB_MONSTERS and MonsterElements() or LootElements()
	self.listElements = elements
	local dp = CreateDataProvider(elements)
	if keepScroll and ScrollBoxConstants then
		self.scrollBox:SetDataProvider(dp, ScrollBoxConstants.RetainScrollPosition)
	else
		self.scrollBox:SetDataProvider(dp)
	end
	local sorts = self.state.tab == TAB_MONSTERS and St.MONSTER_SORTS or St.LOOT_SORTS
	self.sortButton:SetText("Sort: " .. sorts[self.state.sort[self.state.tab]].label)
	self.countText:SetText(MJ.Num(#elements) .. (self.state.tab == TAB_MONSTERS and " monsters" or " items"))
end

function UI:CycleSort()
	local tab = self.state.tab
	local sorts = tab == TAB_MONSTERS and St.MONSTER_SORTS or St.LOOT_SORTS
	self.state.sort[tab] = self.state.sort[tab] % #sorts + 1
	self:RefreshList()
end

---------------------------------------------------------------------------
-- Detail (right side)
---------------------------------------------------------------------------
function UI:DetailWidth()
	if hasList(self.state.tab) then
		return W - 20 - LIST_W - 6 - 34
	end
	return W - 20 - 34
end

function UI:RenderDetail(resetScroll)
	if not self.frame then return end
	local c = self.canvas
	local width = self:DetailWidth()
	self.child:SetWidth(width)
	c:Reset(width)
	local view = self.views[self.state.tab]
	if view then view(c, self.state.selected[self.state.tab]) end
	self.child:SetHeight(math.max(c.y + 16, 50))
	if resetScroll then self.detailScroll:SetVerticalScroll(0) end
end

function UI:Select(id)
	local tab = self.state.tab
	self.state.selected[tab] = id
	if self.scrollBox then
		self.scrollBox:ForEachFrame(function(btn)
			if btn.sel and btn.data then btn.sel:SetShown(btn.data.id == id) end
		end)
	end
	self:RenderDetail(true)
end

function UI:Navigate(tab, id)
	self:Open(tab, id)
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
function UI:SelectTab(tab)
	self.state.tab = tab
	local f = self.frame
	PanelTemplates_SetTab(f, tab)
	local list = hasList(tab)
	self.listPanel:SetShown(list)
	self.search:SetShown(list)
	self.sortButton:SetShown(list)
	self.countText:SetShown(list)
	self.headerText:SetShown(not list)
	self.headerText:SetText(tab == TAB_OVERVIEW and "Account-wide totals, records and trends"
		or "Notable drops, milestones, rares and deaths - newest first")
	self.detailPanel:ClearAllPoints()
	if list then
		self.detailPanel:SetPoint("TOPLEFT", self.listPanel, "TOPRIGHT", 6, 0)
	else
		self.detailPanel:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -62)
	end
	self.detailPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
	if list then
		self.search:SetText(self.state.search[tab] or "")
		self:RefreshList()
		if not self.state.selected[tab] and self.listElements and self.listElements[1] then
			self.state.selected[tab] = self.listElements[1].id
			local id = self.state.selected[tab]
			self.scrollBox:ForEachFrame(function(btn)
				if btn.sel and btn.data then btn.sel:SetShown(btn.data.id == id) end
			end)
		end
	end
	self:RenderDetail(true)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function SavePosition(f)
	local point, _, relPoint, x, y = f:GetPoint(1)
	MJ.db.ui.point = { point, relPoint, x, y }
end

function UI:Build()
	if self.frame then return end
	local f = CreateFrame("Frame", "MJurnalFrame", UIParent, "PortraitFrameTemplate")
	self.frame = f
	f:SetSize(W, H)
	local p = MJ.db.ui.point
	if p then
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint("CENTER")
	end
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(s)
		s:StopMovingOrSizing()
		SavePosition(s)
	end)
	f:Hide()
	tinsert(UISpecialFrames, "MJurnalFrame")

	if f.SetTitle then
		f:SetTitle("MJurnal - Monster & Loot Journal")
	elseif f.TitleText then
		f.TitleText:SetText("MJurnal - Monster & Loot Journal")
	end
	if f.SetPortraitToAsset then
		f:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09")
	elseif f.PortraitContainer and f.PortraitContainer.portrait then
		f.PortraitContainer.portrait:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
	end

	-- list panel
	local list = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	list:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -62)
	list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 30)
	list:SetWidth(LIST_W)
	self.listPanel = list

	local search = CreateFrame("EditBox", "MJurnalSearchBox", f, "SearchBoxTemplate")
	search:SetSize(LIST_W - 108, 20)
	search:SetPoint("TOPLEFT", f, "TOPLEFT", 68, -34)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function(s)
		local tab = UI.state.tab
		if not hasList(tab) then return end
		local text = s:GetText() or ""
		if text == UI.state.search[tab] then return end
		UI.state.search[tab] = text
		UI:RefreshList()
	end)
	self.search = search

	local sortButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	sortButton:SetSize(104, 22)
	sortButton:SetPoint("LEFT", search, "RIGHT", 6, 0)
	sortButton:SetScript("OnClick", function() UI:CycleSort() end)
	self.sortButton = sortButton

	local countText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	countText:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 6, -6)
	self.countText = countText

	local headerText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	headerText:SetPoint("TOPLEFT", f, "TOPLEFT", 70, -38)
	self.headerText = headerText

	local sb = CreateFrame("Frame", nil, list, "WowScrollBoxList")
	sb:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4)
	sb:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -18, 4)
	local bar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", sb, "TOPRIGHT", 4, 0)
	bar:SetPoint("BOTTOMLEFT", sb, "BOTTOMRIGHT", 4, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(20)
	view:SetElementInitializer("Button", InitListButton)
	ScrollUtil.InitScrollBoxListWithScrollBar(sb, bar, view)
	self.scrollBox = sb

	-- detail panel
	local detail = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	self.detailPanel = detail
	local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, detail, "ScrollFrameTemplate")
	if not ok then sf = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate") end
	sf:SetPoint("TOPLEFT", detail, "TOPLEFT", 4, -4)
	sf:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -26, 4)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(self:DetailWidth(), 100)
	sf:SetScrollChild(child)
	self.detailScroll, self.child = sf, child
	self.canvas = UI.CreateCanvas(child, self:DetailWidth())

	-- settings button
	local gear = CreateFrame("Button", nil, f)
	gear:SetSize(20, 20)
	gear:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -34)
	gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	gear:SetScript("OnClick", function() UI:OpenSettings() end)
	gear:SetScript("OnEnter", function(s)
		GameTooltip:SetOwner(s, "ANCHOR_LEFT")
		GameTooltip:SetText("Settings")
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- tabs
	f.Tabs = {}
	for i, name in ipairs(TABS) do
		local tab = CreateFrame("Button", "MJurnalFrameTab" .. i, f, "PanelTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(name)
		if i == 1 then
			tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
		else
			tab:SetPoint("LEFT", f.Tabs[i - 1], "RIGHT", 3, 0)
		end
		tab:SetScript("OnClick", function(s)
			UI:SelectTab(s:GetID())
			if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
		end)
		if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 15, nil, 70) end
		f.Tabs[i] = tab
	end
	PanelTemplates_SetNumTabs(f, #TABS)

	-- Fade while the player moves (like the world map), but stay fully visible under the mouse.
	f:SetScript("OnUpdate", function(s, elapsed)
		local target = UI.FadeTarget(s)
		local a = s:GetAlpha()
		if math.abs(a - target) > 0.005 then
			s:SetAlpha(a + (target - a) * math.min(1, elapsed * 8))
		elseif a ~= target then
			s:SetAlpha(target)
		end
	end)

	f:SetScript("OnShow", function()
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
		UI:SelectTab(UI.state.tab)
	end)
	f:SetScript("OnHide", function()
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
	end)

	-- live refresh while open (throttled)
	local pending = false
	MJ:Listen("DATA_CHANGED", function()
		if not f:IsShown() or pending then return end
		pending = true
		C_Timer.After(0.75, function()
			pending = false
			if f:IsShown() then
				UI:RefreshList(true)
				UI:RenderDetail(false)
			end
		end)
	end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function UI:Toggle()
	if not MJ.db then return end
	self:Build()
	self.frame:SetShown(not self.frame:IsShown())
end

function UI:Open(tab, id)
	if not MJ.db then return end
	self:Build()
	tab = tab or self.state.tab
	if id and hasList(tab) then
		-- make sure the entry is visible in the list
		self.state.search[tab] = ""
	end
	if id then self.state.selected[tab] = id end
	self.state.tab = tab
	if self.frame:IsShown() then
		self:SelectTab(tab)
	else
		self.frame:Show()
	end
	if id and hasList(tab) and self.scrollBox.ScrollToElementDataByPredicate then
		pcall(self.scrollBox.ScrollToElementDataByPredicate, self.scrollBox, function(d) return d.id == id end)
	end
end

function UI:Search(tab, text)
	if not MJ.db then return end
	self:Build()
	self.state.search[tab] = text or ""
	local list = St[tab == TAB_MONSTERS and "MonsterList" or "ItemList"](text, "kills")
	if tab == TAB_MONSTERS and #list == 0 and #St.ItemList(text, "drops") > 0 then
		tab = TAB_LOOT
		self.state.search[tab] = text or ""
		list = St.ItemList(text, "drops")
	end
	self.state.selected[tab] = list[1] and list[1].id or nil
	self.state.tab = tab
	if self.frame:IsShown() then self:SelectTab(tab) else self.frame:Show() end
end

UI.TAB_OVERVIEW, UI.TAB_MONSTERS, UI.TAB_LOOT, UI.TAB_HISTORY = TAB_OVERVIEW, TAB_MONSTERS, TAB_LOOT, TAB_HISTORY
