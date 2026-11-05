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
-- Shared text helpers for views
---------------------------------------------------------------------------
UI.CLASS_LABEL = {
	normal = "", elite = "Elite", rare = "Rare", rareelite = "Rare Elite",
	worldboss = "Boss", trivial = "Trivial", minus = "Minion",
}

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

function UI.SpellLabel(spellID)
	if not spellID or spellID == 0 or spellID == 6603 then return "Melee" end
	local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID))
	return name or ("Spell " .. spellID)
end

function UI.InsertLink(link)
	if ChatEdit_InsertLink then
		ChatEdit_InsertLink(link)
	elseif ChatFrameUtil and ChatFrameUtil.InsertLink then
		ChatFrameUtil.InsertLink(link)
	end
end

function UI.OneIn(p)
	if not p or p <= 0 then return "-" end
	local v = 1 / p
	if v < 10 then return ("%.1f"):format(v) end
	return MJ.Num(v)
end
