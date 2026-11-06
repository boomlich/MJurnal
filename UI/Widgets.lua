-- UI/Widgets.lua: a tiny immediate-mode "canvas" that lays out headings, stat grids,
-- tables and bar charts top-to-bottom inside a scroll child, reusing pooled regions.
local _, MJ = ...
local UI = MJ.UI
local floor, ceil, max = math.floor, math.ceil, math.max

local Canvas = {}
Canvas.__index = Canvas

function UI.CreateCanvas(frame, width)
	local c = setmetatable({}, Canvas)
	c.frame = frame
	c.width = width
	c.fs, c.fsN = {}, 0
	c.tex, c.texN = {}, 0
	c.hot, c.hotN = {}, 0
	c.btn, c.btnN = {}, 0
	c.y = 0
	return c
end

function Canvas:Reset(width)
	if width then self.width = width end
	for _, r in ipairs(self.fs) do r:Hide() end
	for _, r in ipairs(self.tex) do r:Hide() end
	for _, r in ipairs(self.hot) do r:Hide() end
	for _, r in ipairs(self.btn) do r:Hide() end
	self.fsN, self.texN, self.hotN, self.btnN = 0, 0, 0, 0
	self.y = 10
end

function Canvas:FS(font)
	self.fsN = self.fsN + 1
	local fs = self.fs[self.fsN]
	if not fs then
		fs = self.frame:CreateFontString(nil, "OVERLAY")
		self.fs[self.fsN] = fs
	end
	font = font or GameFontHighlight
	fs:SetFontObject(font)
	fs:SetTextColor(font:GetTextColor())
	fs:ClearAllPoints()
	fs:SetWidth(0)
	fs:SetHeight(0)
	fs:SetWordWrap(false)
	fs:SetJustifyH("LEFT")
	fs:SetText("")
	fs:Show()
	return fs
end

function Canvas:Tex(layer)
	self.texN = self.texN + 1
	local t = self.tex[self.texN]
	if not t then
		t = self.frame:CreateTexture(nil, "ARTWORK")
		self.tex[self.texN] = t
	end
	t:SetDrawLayer(layer or "ARTWORK")
	t:ClearAllPoints()
	t:SetTexture(nil)
	t:SetTexCoord(0, 1, 0, 1)
	t:SetVertexColor(1, 1, 1, 1)
	t:Show()
	return t
end

local function hotEnter(self)
	if self.onEnter then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		self.onEnter(self, GameTooltip)
		GameTooltip:Show()
	end
end
local function hotLeave()
	GameTooltip:Hide()
end
local function hotClick(self, button)
	if self.onClick then self.onClick(self, button) end
end

-- Invisible hover/click area at canvas coordinates.
function Canvas:Hot(x, y, w, h, onEnter, onClick, highlight)
	if not onEnter and not onClick then return end
	self.hotN = self.hotN + 1
	local b = self.hot[self.hotN]
	if not b then
		b = CreateFrame("Button", nil, self.frame)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnEnter", hotEnter)
		b:SetScript("OnLeave", hotLeave)
		b:SetScript("OnClick", hotClick)
		b.hl = b:CreateTexture(nil, "HIGHLIGHT")
		b.hl:SetAllPoints()
		b.hl:SetColorTexture(1, 1, 1, 0.08)
		self.hot[self.hotN] = b
	end
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
	b:SetSize(max(w, 1), max(h, 1))
	b.onEnter, b.onClick = onEnter, onClick
	b.hl:SetShown(highlight and true or false)
	b:Show()
	return b
end

function Canvas:Button(text, x, w, onClick)
	self.btnN = self.btnN + 1
	local b = self.btn[self.btnN]
	if not b then
		b = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
		b:SetScript("OnClick", function(s) if s.cb then s.cb(s) end end)
		self.btn[self.btnN] = b
	end
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -self.y)
	b:SetSize(w, 22)
	b:SetText(text)
	b.cb = onClick
	b:Enable()
	b:Show()
	return b
end

---------------------------------------------------------------------------
-- Layout blocks
---------------------------------------------------------------------------
function Canvas:Title(text, sub, icon, onEnter)
	local x = 12
	if icon then
		local t = self:Tex()
		t:SetTexture(icon)
		t:SetSize(42, 42)
		t:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 12, -self.y)
		x = 62
		self:Hot(12, self.y, 42, 42, onEnter)
	end
	local fs = self:FS(GameFontNormalHuge or GameFontNormalLarge)
	fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -self.y)
	fs:SetWidth(self.width - x - 12)
	fs:SetText(text)
	local h = 30
	if sub and sub ~= "" then
		local s = self:FS(GameFontHighlight)
		s:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -self.y - 26)
		s:SetWidth(self.width - x - 12)
		s:SetText(sub)
		h = 46
	end
	self.y = self.y + max(h, icon and 48 or 0)
end

function Canvas:Section(text, right)
	self.y = self.y + 10
	local fs = self:FS(GameFontNormalLarge)
	fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 12, -self.y)
	fs:SetText(text)
	if right then
		local r = self:FS(GameFontDisableSmall)
		r:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", self.width - 12, -self.y - 4)
		r:SetJustifyH("RIGHT")
		r:SetText(right)
	end
	local line = self:Tex("BORDER")
	line:SetColorTexture(1, 0.82, 0, 0.3)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 12, -self.y - 20)
	line:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", self.width - 12, -self.y - 20)
	self.y = self.y + 26
end

function Canvas:Text(text, font, indent)
	indent = indent or 12
	local fs = self:FS(font or GameFontHighlightSmall)
	fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", indent, -self.y)
	fs:SetWidth(self.width - indent - 12)
	fs:SetWordWrap(true)
	fs:SetText(text)
	self.y = self.y + ceil(fs:GetStringHeight()) + 6
	return fs
end

function Canvas:Space(h)
	self.y = self.y + (h or 8)
end

-- items = { { label, value, tooltipText or function(tooltip) }, ... }
function Canvas:Grid(items, cols)
	cols = cols or 3
	local colW = (self.width - 24) / cols
	local rowH = 18
	for i, it in ipairs(items) do
		local col = (i - 1) % cols
		local row = floor((i - 1) / cols)
		local x = 12 + col * colW
		local y = self.y + row * rowH
		local l = self:FS(GameFontNormalSmall)
		l:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -y)
		l:SetText(it[1])
		local v = self:FS(GameFontHighlightSmall)
		v:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", x + colW - 14, -y)
		v:SetJustifyH("RIGHT")
		v:SetText(it[2] == nil and "-" or tostring(it[2]))
		local tip = it[3]
		if tip then
			self:Hot(x - 2, y - 2, colW - 8, rowH, function(_, tt)
				tt:SetText(it[1], 1, 1, 1)
				if type(tip) == "function" then
					tip(tt)
				else
					tt:AddLine(tip, nil, nil, nil, true)
				end
			end, nil, true)
		end
	end
	self.y = self.y + ceil(#items / cols) * rowH + 4
end

-- cols = { { title, width, align, tip } }
-- rows = { { cells = {...}, icon, onEnter(btn, tooltip), onClick(btn, mouseButton) } }
-- opts = { sortCol, sortDesc, onSort(colIndex), empty = "text", max = n }
function Canvas:Table(cols, rows, opts)
	opts = opts or {}
	local x0 = 12
	local x = x0
	for i, c in ipairs(cols) do
		local fs = self:FS(GameFontNormalSmall)
		fs:SetWidth(c[2])
		fs:SetJustifyH(c[3] or "LEFT")
		fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, -self.y)
		local mark = ""
		if opts.sortCol == i then mark = opts.sortDesc and " |TInterface\\Buttons\\Arrow-Down-Up:10:10|t" or " |TInterface\\Buttons\\Arrow-Up-Up:10:10|t" end
		fs:SetText(c[1] .. mark)
		local tip = c[4]
		self:Hot(x, self.y - 2, c[2], 16,
			tip and function(_, tt)
				tt:SetText(c[1], 1, 1, 1)
				tt:AddLine(tip, nil, nil, nil, true)
				if opts.onSort then tt:AddLine("Click to sort.", 0.6, 0.6, 0.6) end
			end or nil,
			opts.onSort and function() opts.onSort(i) end or nil,
			opts.onSort ~= nil)
		x = x + c[2] + 6
	end
	local totalW = x - x0 - 6
	self.y = self.y + 18
	local line = self:Tex("BORDER")
	line:SetColorTexture(1, 1, 1, 0.15)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x0, -self.y + 2)
	line:SetWidth(totalW)

	local limit = opts.max or #rows
	for r = 1, math.min(#rows, limit) do
		local row = rows[r]
		local y = self.y
		if r % 2 == 0 then
			local stripe = self:Tex("BACKGROUND")
			stripe:SetColorTexture(1, 1, 1, 0.03)
			stripe:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x0 - 4, -y)
			stripe:SetSize(totalW + 8, 18)
		end
		local rx = x0
		if row.icon then
			local ic = self:Tex()
			ic:SetTexture(row.icon)
			ic:SetSize(16, 16)
			ic:SetPoint("TOPLEFT", self.frame, "TOPLEFT", rx, -y - 1)
		end
		for i, c in ipairs(cols) do
			local off = (i == 1 and row.icon) and 20 or 0
			local fs = self:FS(GameFontHighlightSmall)
			fs:SetWidth(c[2] - off)
			fs:SetJustifyH(c[3] or "LEFT")
			fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", rx + off, -y - 3)
			local cell = row.cells[i]
			fs:SetText(cell == nil and "" or tostring(cell))
			rx = rx + c[2] + 6
		end
		self:Hot(x0 - 4, y, totalW + 8, 18, row.onEnter, row.onClick, true)
		self.y = self.y + 18
	end
	if #rows == 0 and opts.empty then
		local fs = self:FS(GameFontDisableSmall)
		fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x0, -self.y - 2)
		fs:SetText(opts.empty)
		self.y = self.y + 18
	elseif #rows > limit then
		local fs = self:FS(GameFontDisableSmall)
		fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x0, -self.y - 2)
		fs:SetText(("... and %d more"):format(#rows - limit))
		self.y = self.y + 18
	end
	self.y = self.y + 6
end

-- Simple bar chart. tipFn(index, tooltip)
function Canvas:Bars(values, height, tipFn, firstLabel, lastLabel)
	height = height or 70
	local n = #values
	if n == 0 then return end
	local maxV = 1
	for _, v in ipairs(values) do maxV = max(maxV, v) end
	local w = self.width - 24
	local bw = w / n
	local base = self.y + height
	for i, v in ipairs(values) do
		local h = v > 0 and max(2, v / maxV * height) or 1
		local t = self:Tex()
		if v > 0 then t:SetColorTexture(0.85, 0.65, 0.12, 0.85) else t:SetColorTexture(1, 1, 1, 0.12) end
		t:SetSize(max(1, bw - 2), h)
		t:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", 12 + (i - 1) * bw, -base)
		if tipFn then
			self:Hot(12 + (i - 1) * bw, self.y, bw, height, function(_, tt) tipFn(i, tt) end, nil, true)
		end
	end
	local maxFs = self:FS(GameFontDisableSmall)
	maxFs:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", self.width - 12, -self.y + 12)
	maxFs:SetJustifyH("RIGHT")
	maxFs:SetText("max " .. MJ.Num(maxV))
	if firstLabel then
		local a = self:FS(GameFontDisableSmall)
		a:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 12, -base - 3)
		a:SetText(firstLabel)
	end
	if lastLabel then
		local b = self:FS(GameFontDisableSmall)
		b:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", self.width - 12, -base - 3)
		b:SetJustifyH("RIGHT")
		b:SetText(lastLabel)
	end
	self.y = base + 20
end

---------------------------------------------------------------------------
-- Popup menu (character and category filters)
--   UI.ToggleMenu(anchor, build): build() returns the entries, rebuilt after every click so
--   check marks stay current. Entry: { text, checked, onClick, keepOpen, title, separator, indent,
--   toggle = { expanded, onClick } (a +/- button on the right that keeps the menu open),
--   actions = { { text, onClick }, ... } (small text buttons in one row, keep the menu open) }
---------------------------------------------------------------------------
local menu
local ROW_H = 18

local function hideMenu()
	if menu then menu:Hide() end
end
UI.HideMenu = hideMenu

local function menuRow(i)
	local row = menu.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, menu)
	row:SetHeight(ROW_H)
	row.check = row:CreateTexture(nil, "ARTWORK")
	row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	row.check:SetSize(14, 14)
	row.check:SetPoint("LEFT", 6, 0)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 24, 0)
	row.text:SetJustifyH("LEFT")
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 1, 1, 0.1)
	row.line = row:CreateTexture(nil, "ARTWORK")
	row.line:SetColorTexture(1, 0.82, 0, 0.25)
	row.line:SetHeight(1)
	row.line:SetPoint("LEFT", 6, 0)
	row.line:SetPoint("RIGHT", -6, 0)
	row:SetScript("OnClick", function(self)
		local e = self.entry
		if not e or not e.onClick then return end
		e.onClick()
		if e.keepOpen and menu:IsShown() then
			UI.FillMenu()
		else
			hideMenu()
		end
	end)
	row.toggle = CreateFrame("Button", nil, row)
	row.toggle:SetSize(14, 14)
	row.toggle:SetPoint("RIGHT", -6, 0)
	row.toggle:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
	row.toggle:SetScript("OnClick", function(self)
		local t = self:GetParent().entry.toggle
		t.onClick()
		UI.FillMenu()
	end)
	row.actions = {}
	menu.rows[i] = row
	return row
end

local function actionButton(row, i)
	local b = row.actions[i]
	if b then return b end
	b = CreateFrame("Button", nil, row)
	b:SetHeight(ROW_H)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.label:SetPoint("CENTER")
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.1)
	b:SetScript("OnClick", function(self)
		self.action.onClick()
		UI.FillMenu()
	end)
	row.actions[i] = b
	return b
end

-- Lays out an entry's action buttons from the left; returns the width they take.
local function layoutActions(row, actions)
	local x = 6
	for i, a in ipairs(actions or {}) do
		local b = actionButton(row, i)
		b.action = a
		b.label:SetText(a.text)
		b:SetWidth(b.label:GetStringWidth() + 14)
		b:ClearAllPoints()
		b:SetPoint("LEFT", x, 0)
		b:Show()
		x = x + b:GetWidth() + 6
	end
	for i = #(actions or {}) + 1, #row.actions do row.actions[i]:Hide() end
	return x
end

function UI.FillMenu()
	local entries = menu.build()
	local width = 160
	for i, e in ipairs(entries) do
		local row = menuRow(i)
		row.entry = e
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)
		row:SetPoint("RIGHT", -4, 0)
		row.line:SetShown(e.separator == true)
		row.text:SetShown(not e.separator and not e.actions)
		row.check:SetShown(e.checked == true)
		local actionsW = layoutActions(row, e.actions)
		row.toggle:SetShown(e.toggle ~= nil)
		if e.toggle then
			row.toggle:SetNormalTexture(e.toggle.expanded and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
		end
		local indent = e.indent or 0
		row.check:SetPoint("LEFT", 6 + indent, 0)
		row.text:SetPoint("LEFT", 24 + indent, 0)
		row.text:SetText(e.text or "")
		row.text:SetFontObject(e.title and GameFontNormalSmall or GameFontHighlightSmall)
		row:EnableMouse(e.onClick ~= nil)
		row.hl:SetShown(e.onClick ~= nil)
		row:Show()
		width = math.max(width, row.text:GetStringWidth() + 40 + indent + (e.toggle and 20 or 0), actionsW + 4)
	end
	for i = #entries + 1, #menu.rows do menu.rows[i]:Hide() end
	menu:SetSize(width, #entries * ROW_H + 8)
end

function UI.ToggleMenu(anchor, build)
	if menu and menu:IsShown() and menu.anchor == anchor then
		hideMenu()
		return
	end
	if not menu then
		menu = CreateFrame("Frame", "MJurnalMenu", UIParent)
		menu:SetFrameStrata("FULLSCREEN_DIALOG")
		menu:SetClampedToScreen(true)
		menu:EnableMouse(true)
		-- a 1px gold edge behind a dark background that covers all but the edge
		local edge = menu:CreateTexture(nil, "BACKGROUND", nil, -8)
		edge:SetPoint("TOPLEFT", -1, 1)
		edge:SetPoint("BOTTOMRIGHT", 1, -1)
		edge:SetColorTexture(1, 0.82, 0, 0.35)
		local bg = menu:CreateTexture(nil, "BACKGROUND", nil, 0)
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.05, 0.05, 0.97)
		menu.rows = {}
		tinsert(UISpecialFrames, "MJurnalMenu")
	end
	menu.anchor, menu.build = anchor, build
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	UI.FillMenu()
	menu:Show()
end

---------------------------------------------------------------------------
-- Shared text helpers for views
---------------------------------------------------------------------------
UI.CLASS_LABEL = {
	normal = "", elite = "Elite", rare = "Rare", rareelite = "Rare Elite",
	worldboss = "Boss", trivial = "Trivial", minus = "Minion",
}

-- Gathering sources (see MJ:RecordNode)
UI.NODE_KIND = {
	herb = "Herbalism", mine = "Mining", fishing = "Fishing", object = "Chests & objects", container = "Containers",
}
local NODE_ICON = {
	herb = "Interface\\Icons\\Trade_Herbalism", mine = "Interface\\Icons\\Trade_Mining",
	fishing = "Interface\\Icons\\Trade_Fishing", object = "Interface\\Icons\\INV_Box_01",
	container = "Interface\\Icons\\INV_Misc_Bag_10",
}
function UI.NodeIcon(kind) return NODE_ICON[kind] or 134400 end

function UI.Grey(text) return "|cff808080" .. tostring(text) .. "|r" end
function UI.Gold(text) return "|cffffd200" .. tostring(text) .. "|r" end
function UI.Green(text) return "|cff20ff20" .. tostring(text) .. "|r" end
function UI.Red(text) return "|cffff4040" .. tostring(text) .. "|r" end
function UI.Orange(text) return "|cffff9020" .. tostring(text) .. "|r" end

function UI.NPCLabel(npcId)
	local n = MJ.db.npcs[npcId]
	local name = MJ:NPCName(npcId)
	local cl = n and n.class
	if cl == "rare" or cl == "rareelite" then return "|cffc0c0ff" .. name .. "|r" end
	if cl == "elite" or cl == "worldboss" then return "|cffffa040" .. name .. "|r" end
	return name
end

function UI.LuckText(luck)
	if not luck then return UI.Grey("-") end
	local s = ("%.2fx"):format(luck)
	if luck >= 1.15 then return UI.Green(s) end
	if luck <= 0.85 then return UI.Red(s) end
	return s
end

function UI.RateText(p, corpses)
	if not p then return UI.Grey("-") end
	local s = MJ.Pct(p)
	if not MJ.Stats.Confident(corpses) then return UI.Grey(s) end
	return s
end

-- "1.35" / "0.042": average units of an item per corpse, grey until the sample is decent
function UI.PerCorpseText(v, corpses)
	if not v then return UI.Grey("-") end
	local s = v >= 10 and MJ.Num(v) or v >= 0.1 and ("%.2f"):format(v) or ("%.3f"):format(v)
	if not MJ.Stats.Confident(corpses) then return UI.Grey(s) end
	return s
end

function UI.SpellLabel(spellID)
	if not spellID or spellID == 0 or spellID == 6603 then return "Melee" end
	local name = MJ.SpellName(spellID)
	return name or ("Spell " .. spellID)
end

local ENV_LABEL = {
	FALLING = "Falling", DROWNING = "Drowning", FATIGUE = "Fatigue", FIRE = "Fire", LAVA = "Lava", SLIME = "Slime",
}

-- "Shadow Bolt (245, 32 overkill)" / "Falling" / "-" for a death record.
function UI.DeathCause(e)
	local kb = e.kb
	if not kb then return UI.Grey("-") end
	if kb.env then return ENV_LABEL[kb.env:upper()] or kb.env end
	local name = kb.sn or UI.SpellLabel(kb.s)
	if kb.s == 0 then name = "Melee" end
	if kb.a then
		local extra = (kb.o and kb.o > 0) and (", " .. MJ.Num(kb.o) .. " overkill") or ""
		name = name .. UI.Grey(" (" .. MJ.Num(kb.a) .. extra .. ")")
	end
	return name
end

function UI.DeathKiller(e)
	if e.kb and e.kb.env then return UI.Grey("environment") end
	if e.npc then return UI.NPCLabel(e.npc) end
	if e.kb and e.kb.src then return e.kb.src end
	return UI.Grey("unknown")
end

-- Tooltip lines with everything recorded about one death.
function UI.DeathTooltip(tt, e)
	tt:SetText("Death · " .. MJ.Date(e.t), 1, 0.3, 0.3)
	local function line(l, r) tt:AddDoubleLine(l, r, 0.8, 0.8, 0.8, 1, 1, 1) end
	line("Killed by", UI.DeathKiller(e))
	line("Killing blow", UI.DeathCause(e))
	if e.o and #e.o > 0 then
		local names = {}
		for _, id in ipairs(e.o) do names[#names + 1] = MJ:NPCName(id) end
		line("Also attacking", table.concat(names, ", "))
	end
	if e.adds then line("Enemies on you", MJ.Num(e.adds)) end
	if e.lvl then line("Your level", e.lvl .. (e.mlvl and ("  vs  " .. e.mlvl) or "")) end
	if e.dur then line("Fight length", MJ.Dur(e.dur)) end
	if e.dmg then
		line("Damage in recap", MJ.Num(e.dmg) .. (e.hits and (" in " .. e.hits .. " hits") or "")
			.. (e.win and (" over " .. MJ.Dur(e.win)) or ""))
	end
	if e.hp and e.hp > 0 then line("Your max health", MJ.Num(e.hp)) end
	line("Where", (e.z or "?") .. (e.sz and (" / " .. e.sz) or ""))
	line("Character", MJ:CharName(e.c))
	if e.g then line("Group", "yes") end
end

-- Puts an item link in chat: into the chat box you are typing in, or else opens the chat box
-- with the link in it (ChatEdit_InsertLink does nothing when no chat box is open).
function UI.InsertLink(link)
	if not link then return end
	local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
	if insert and insert(link) then return end
	local open = ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
	if open then open(link) end
end

function UI.OneIn(p)
	if not p or p <= 0 then return "-" end
	local v = 1 / p
	if v < 10 then return ("%.1f"):format(v) end
	return MJ.Num(v)
end
