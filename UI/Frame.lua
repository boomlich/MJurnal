-- UI/Frame.lua: main journal window with Overview / Monsters / Loot / Gathering / History tabs.
local _, MJ = ...
local UI, St = MJ.UI, MJ.Stats

local W, H = 1080, 680
local LIST_W = 290
local TABS = { "Overview", "Monsters", "Loot", "Gathering", "History" }
local TAB_OVERVIEW, TAB_MONSTERS, TAB_LOOT, TAB_GATHER, TAB_HISTORY =
	UI.TAB_OVERVIEW, UI.TAB_MONSTERS, UI.TAB_LOOT, UI.TAB_GATHER, UI.TAB_HISTORY

local DEFAULT_SORT = "last" -- both journals open sorted by most recent

local SORTS = { [TAB_MONSTERS] = St.MONSTER_SORTS, [TAB_LOOT] = St.LOOT_SORTS, [TAB_GATHER] = St.NODE_SORTS }
local function sortsFor(tab)
	return SORTS[tab]
end

local function sortIndex(tab, key)
	for i, s in ipairs(sortsFor(tab)) do
		if s.key == key then return i end
	end
	return 1
end

UI.views = {}
UI.state = {
	tab = TAB_MONSTERS,
	selected = {},
	search = { [TAB_MONSTERS] = "", [TAB_LOOT] = "", [TAB_GATHER] = "" },
	sort = {
		[TAB_MONSTERS] = sortIndex(TAB_MONSTERS, DEFAULT_SORT), [TAB_LOOT] = sortIndex(TAB_LOOT, DEFAULT_SORT),
		[TAB_GATHER] = sortIndex(TAB_GATHER, DEFAULT_SORT),
	},
	category = {}, -- [tab] = category key (see Stats.lua), nil = the full list
}

local function hasList(tab) return SORTS[tab] ~= nil end

local function currentSortKey(tab)
	return sortsFor(tab)[UI.state.sort[tab]].key
end

local function inCombat()
	return InCombatLockdown() or MJ.S(UnitAffectingCombat("player")) and true or false
end

-- Faded while moving or in combat (each can be turned off), fully visible under the mouse.
function UI.FadeTarget(frame)
	local s = MJ.db.settings
	local fade = (s.fadeMoving and IsPlayerMoving()) or (s.fadeCombat and inCombat())
	if not fade or frame:IsMouseOver() then return 1 end
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
	local sortKey = currentSortKey(TAB_MONSTERS)
	local out = {}
	for _, e in ipairs(St.MonsterList(UI.state.search[TAB_MONSTERS], sortKey, UI.state.category[TAB_MONSTERS])) do
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
	local sortKey = currentSortKey(TAB_LOOT)
	local out = {}
	for _, e in ipairs(St.ItemList(UI.state.search[TAB_LOOT], sortKey, UI.state.category[TAB_LOOT])) do
		local count
		if sortKey == "value" or sortKey == "ah" then
			count = e.v > 0 and MJ.Money(e.v) or UI.Grey("-")
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

local function GatherElements()
	local sortKey = currentSortKey(TAB_GATHER)
	local out = {}
	for _, e in ipairs(St.NodeList(UI.state.search[TAB_GATHER], sortKey, UI.state.category[TAB_GATHER])) do
		local nd, count = e.nd, nil
		if sortKey == "value" then
			count = nd.count and MJ.Money(e.v) or UI.Grey("-")
		elseif sortKey == "last" then
			count = MJ.Ago(nd.last and nd.last.t)
		else
			count = nd.count and MJ.Num(nd.count) or UI.Grey("-")
		end
		out[#out + 1] = {
			tab = TAB_GATHER, id = e.id, count = count, icon = UI.NodeIcon(nd.kind),
			label = nd.legacy and UI.Grey(e.name) or e.name,
		}
	end
	return out
end

local ELEMENTS = { [TAB_MONSTERS] = MonsterElements, [TAB_LOOT] = LootElements, [TAB_GATHER] = GatherElements }
local COUNT_NOUN = { [TAB_MONSTERS] = " monsters", [TAB_LOOT] = " items", [TAB_GATHER] = " sources" }

function UI:RefreshList(keepScroll)
	if not self.frame or not hasList(self.state.tab) then return end
	local elements = ELEMENTS[self.state.tab]()
	self.listElements = elements
	local dp = CreateDataProvider(elements)
	if keepScroll and ScrollBoxConstants then
		self.scrollBox:SetDataProvider(dp, ScrollBoxConstants.RetainScrollPosition)
	else
		self.scrollBox:SetDataProvider(dp)
	end
	local sorts = sortsFor(self.state.tab)
	self.sortButton:SetText("Sort: " .. sorts[self.state.sort[self.state.tab]].label)
	self.categoryButton:SetText(UI.CategoryLabel(self.state.tab, self.state.category[self.state.tab]))
	self.countText:SetText(MJ.Num(#elements) .. COUNT_NOUN[self.state.tab])
end

-- Keeps the selection on a row that is still in the list (after a filter changed it).
function UI:EnsureSelection()
	local tab = self.state.tab
	if not hasList(tab) or not self.listElements then return end
	local sel = self.state.selected[tab]
	for _, e in ipairs(self.listElements) do
		if e.id == sel then return end
	end
	self.state.selected[tab] = self.listElements[1] and self.listElements[1].id or nil
	local id = self.state.selected[tab]
	self.scrollBox:ForEachFrame(function(btn)
		if btn.sel and btn.data then btn.sel:SetShown(btn.data.id == id) end
	end)
end

-- Rebuilds the list and the detail after the character filter or the category changed.
function UI:Reload()
	if not self.frame or not self.frame:IsShown() then return end
	self:RefreshList()
	self:EnsureSelection()
	self:UpdateHeader()
	self:RenderDetail(true)
end

function UI:CycleSort()
	local tab = self.state.tab
	local sorts = sortsFor(tab)
	self.state.sort[tab] = self.state.sort[tab] % #sorts + 1
	self:RefreshList()
end

---------------------------------------------------------------------------
-- Filters: characters (all tabs) and category (list tabs)
---------------------------------------------------------------------------
-- "All characters" / "Thrall" / "3 characters"
function UI.CharFilterLabel()
	local filter = MJ:CharFilter()
	if not filter then return "All characters" end
	local keys = {}
	for ck in pairs(filter) do keys[#keys + 1] = ck end
	if #keys == 1 then return MJ:CharName(keys[1]) end
	return #keys .. " characters"
end

local function setChar(ck, on)
	local filter = MJ:CharFilter()
	local set = {}
	if filter then
		for k in pairs(filter) do set[k] = true end
	end
	set[ck] = on or nil
	-- every character selected is the same as no filter
	local all = true
	for k in pairs(MJ.db.chars) do
		if not set[k] then all = false end
	end
	MJ:SetCharFilter((not all) and set or nil)
end

local function charMenu()
	local filter = MJ:CharFilter()
	local entries = {
		{ text = "All characters", checked = filter == nil, keepOpen = true, onClick = function() MJ:SetCharFilter(nil) end },
		{ separator = true },
	}
	local chars = {}
	for ck, c in pairs(MJ.db.chars) do chars[#chars + 1] = { ck = ck, kills = c.kills or 0 } end
	table.sort(chars, function(a, b)
		if a.kills ~= b.kills then return a.kills > b.kills end
		return a.ck < b.ck
	end)
	for _, ch in ipairs(chars) do
		local ck = ch.ck
		local on = filter ~= nil and filter[ck] == true
		local you = ck == MJ.charKey and UI.Grey(" (you)") or ""
		entries[#entries + 1] = {
			text = MJ:CharName(ck) .. you .. UI.Grey("  " .. MJ.Num(ch.kills) .. " kills"),
			checked = on, keepOpen = true,
			-- from "All", a click shows only that character; after that, clicks add or remove
			onClick = function()
				if filter == nil then MJ:SetCharFilter({ [ck] = true }) else setChar(ck, not on) end
			end,
		}
	end
	return entries
end

local CATEGORY_TITLES = {
	type = "Creature type", class = "Classification", zone = "Zone (where it was killed)",
	itype = "Item type", quest = "Quest", gkind = "Source",
}
-- Category sections that fold in and out in the menu (kept between sessions): [kind] = true when closed
local function collapsedKinds()
	MJ.db.ui.collapsedKinds = MJ.db.ui.collapsedKinds or {}
	return MJ.db.ui.collapsedKinds
end
local FOLDING_KINDS = { zone = true }

-- Button text for a category: "Beast", "Elite", "Weapon", "Cloth (Armor)", "Quest items"
function UI.CategoryLabel(tab, key)
	if not key then return "Category: All" end
	local kind, value = key:match("^(%a+):(.*)$")
	if kind == "class" then value = UI.CLASS_LABEL[value] or value end
	if kind == "gkind" then value = UI.NODE_KIND[value] or value end
	if kind == "zone" then value = value .. " (zone)" end
	if kind == "isub" then
		local itype, sub = value:match("^([^:]*):(.*)$")
		value = sub .. " (" .. itype .. ")"
	end
	if key == "quest" then value = "Quest items" end
	return value or key
end

local ALL_LABEL = { [TAB_MONSTERS] = "All monsters", [TAB_LOOT] = "All items", [TAB_GATHER] = "All sources" }
local CATEGORIES = {
	[TAB_MONSTERS] = function() return St.MonsterCategories() end,
	[TAB_LOOT] = function() return St.ItemCategories() end,
	[TAB_GATHER] = function() return St.NodeCategories() end,
}

-- Item types whose subtypes are shown in the loot category menu (kept between sessions).
local function expandedTypes()
	MJ.db.ui.lootExpanded = MJ.db.ui.lootExpanded or {}
	return MJ.db.ui.lootExpanded
end

local function categoryMenu()
	local tab = UI.state.tab
	local current = UI.state.category[tab]
	local expanded = expandedTypes()
	local function pick(cat)
		return function()
			UI.state.category[tab] = cat and cat.key
			-- keep the picked subtype visible next time the menu opens
			if cat and cat.parent then expanded[cat.parent] = true end
			UI:Reload()
		end
	end
	local entries = {
		{ text = ALL_LABEL[tab], checked = current == nil, onClick = pick(nil) },
	}
	local cats = CATEGORIES[tab]()

	local parents = {}
	for _, cat in ipairs(cats) do
		if cat.hasSubs then parents[#parents + 1] = cat.value end
	end
	if #parents > 0 then
		entries[#entries + 1] = { actions = {
			{ text = "Expand all", onClick = function() for _, t in ipairs(parents) do expanded[t] = true end end },
			{ text = "Collapse all", onClick = function() wipe(expanded) end },
		} }
	end

	local lastKind
	local closed = collapsedKinds()
	for _, cat in ipairs(cats) do
		if cat.kind ~= lastKind then
			entries[#entries + 1] = { separator = true }
			local kind = cat.kind
			entries[#entries + 1] = {
				text = CATEGORY_TITLES[kind] or kind, title = true,
				toggle = FOLDING_KINDS[kind] and {
					expanded = not closed[kind],
					onClick = function() closed[kind] = not closed[kind] or nil end,
				} or nil,
			}
			lastKind = kind
		end
		-- subtypes are listed indented under their item type, while it is expanded;
		-- a folded section (zones) lists only its current pick
		local folded = closed[cat.kind] and current ~= cat.key
		if not folded and (not cat.sub or expanded[cat.parent]) then
			local value = cat.value
			entries[#entries + 1] = {
				text = ((cat.sub or cat.kind == "zone") and cat.value or UI.CategoryLabel(tab, cat.key)) .. UI.Grey("  " .. MJ.Num(cat.count)),
				indent = cat.sub and 14 or nil,
				checked = current == cat.key, onClick = pick(cat),
				toggle = cat.hasSubs and {
					expanded = expanded[value] == true,
					onClick = function() expanded[value] = not expanded[value] or nil end,
				} or nil,
			}
		end
	end
	return entries
end

function UI:UpdateHeader()
	if not self.frame then return end
	self.charButton:SetText(UI.CharFilterLabel())
	local who = MJ:CharFilter() and UI.CharFilterLabel() or "the whole account"
	self.headerText:SetText(self.state.tab == TAB_OVERVIEW and ("Totals, records and trends for " .. who)
		or "Notable drops, milestones, rares and deaths - newest first")
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

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
function UI:SelectTab(tab)
	self.state.tab = tab
	local f = self.frame
	PanelTemplates_SetTab(f, tab)
	UI.HideMenu()
	local list = hasList(tab)
	self.listPanel:SetShown(list)
	self.search:SetShown(list)
	self.sortButton:SetShown(list)
	self.categoryButton:SetShown(list)
	self.countText:SetShown(list)
	self.headerText:SetShown(not list)
	self:UpdateHeader()
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
		self:EnsureSelection()
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

	local categoryButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	categoryButton:SetSize(150, 22)
	categoryButton:SetPoint("LEFT", sortButton, "RIGHT", 6, 0)
	categoryButton:SetScript("OnClick", function(b) UI.ToggleMenu(b, categoryMenu) end)
	self.categoryButton = categoryButton

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

	-- character filter (every tab)
	local charButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	charButton:SetSize(180, 22)
	charButton:SetPoint("RIGHT", gear, "LEFT", -8, 0)
	charButton:SetScript("OnClick", function(b) UI.ToggleMenu(b, charMenu) end)
	charButton:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Characters")
		GameTooltip:AddLine("Show the journal for every character, one character or a few of them.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	charButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.charButton = charButton
	MJ:Listen("FILTER_CHANGED", function() UI:Reload() end)

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

	-- Fade while the player moves (like the world map) or fights, but stay fully visible under the mouse.
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
		UI.HideMenu()
		if SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
	end)

	-- live refresh while open (throttled). The overview and the history rebuild a lot on every
	-- render, so they refresh less often than the journals while you farm.
	local REFRESH_DELAY = { [TAB_OVERVIEW] = 5, [TAB_HISTORY] = 3 }
	local pending = false
	MJ:Listen("DATA_CHANGED", function()
		if not f:IsShown() or pending then return end
		pending = true
		C_Timer.After(REFRESH_DELAY[UI.state.tab] or 0.75, function()
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
		self.state.category[tab] = nil
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
	text = text or ""
	-- a search looks through the full list; select the first row in the current sort order
	self.state.category[TAB_MONSTERS], self.state.category[TAB_LOOT] = nil, nil
	if tab == TAB_GATHER then
		self.state.category[TAB_GATHER] = nil
		self.state.search[TAB_GATHER] = text
		local list = St.NodeList(text, currentSortKey(TAB_GATHER))
		self.state.selected[tab] = list[1] and list[1].id or nil
		self.state.tab = tab
		if self.frame:IsShown() then self:SelectTab(tab) else self.frame:Show() end
		return
	end
	local list = tab == TAB_MONSTERS and St.MonsterList(text, currentSortKey(TAB_MONSTERS)) or St.ItemList(text, currentSortKey(TAB_LOOT))
	if tab == TAB_MONSTERS and #list == 0 then
		-- no monster matches: fall back to the loot journal
		local items = St.ItemList(text, currentSortKey(TAB_LOOT))
		if #items > 0 then tab, list = TAB_LOOT, items end
	end
	self.state.search[tab] = text
	self.state.selected[tab] = list[1] and list[1].id or nil
	self.state.tab = tab
	if self.frame:IsShown() then self:SelectTab(tab) else self.frame:Show() end
end

