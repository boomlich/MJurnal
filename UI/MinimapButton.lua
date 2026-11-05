-- UI/MinimapButton.lua: draggable minimap button (+ LibDataBroker launcher when available).
local _, MJ = ...
local UI = MJ.UI

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local button

-- Which quadrants of each minimap shape are round (true) or square (false).
-- Quadrants: 1 = bottom-right, 2 = bottom-left, 3 = top-right, 4 = top-left.
local SHAPES = {
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function updatePosition()
	if not button then return end
	local angle = math.rad(MJ.db.settings.minimapAngle or 215)
	local x, y = math.cos(angle), math.sin(angle)
	local q = 1
	if x < 0 then q = q + 1 end
	if y > 0 then q = q + 2 end
	local shape = (GetMinimapShape and GetMinimapShape()) or "ROUND"
	local round = (SHAPES[shape] or SHAPES.ROUND)[q]
	local w = Minimap:GetWidth() / 2 + 5
	local h = Minimap:GetHeight() / 2 + 5
	if round then
		x, y = x * w, y * h
	else
		local dw = math.sqrt(2 * w * w) - 10
		local dh = math.sqrt(2 * h * h) - 10
		x = math.max(-w, math.min(x * dw, w))
		y = math.max(-h, math.min(y * dh, h))
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local atan2 = math.atan2 or math.atan
local function onDragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale
	MJ.db.settings.minimapAngle = math.deg(atan2(py - my, px - mx)) % 360
	updatePosition()
end

-- Shared tooltip for the minimap button, addon compartment and broker displays.
function UI.FillLauncherTooltip(tt)
	tt:AddLine("MJurnal")
	local t = MJ.db and MJ.db.totals or {}
	local s = MJ.session
	tt:AddDoubleLine("Kills (all time)", MJ.Num(t.kills or 0), 0.8, 0.8, 0.8, 1, 1, 1)
	tt:AddDoubleLine("Corpses looted", MJ.Num(t.corpses or 0), 0.8, 0.8, 0.8, 1, 1, 1)
	tt:AddDoubleLine("This session", MJ.Num(s.kills or 0) .. " kills · " .. MJ.Money((s.money or 0) + (s.vendor or 0)), 0.8, 0.8, 0.8, 1, 1, 1)
	tt:AddLine(" ")
	tt:AddLine("Left-click: open / close journal", 0.6, 0.6, 0.6)
	tt:AddLine("Right-click: settings", 0.6, 0.6, 0.6)
	tt:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
end

local function onClick(_, mouse)
	if mouse == "RightButton" then
		UI:OpenSettings()
	else
		UI:Toggle()
	end
end

local function create()
	button = CreateFrame("Button", "MJurnalMinimapButton", Minimap)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetSize(31, 31)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = button:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	button.icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", onClick)
	button:SetScript("OnMouseDown", function() icon:SetTexCoord(0, 1, 0, 1) end)
	button:SetScript("OnMouseUp", function() icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) end)
	button:SetScript("OnDragStart", function(self)
		self:LockHighlight()
		self:SetScript("OnUpdate", onDragUpdate)
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		UI.FillLauncherTooltip(GameTooltip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI:UpdateMinimapButton()
	if not MJ.db then return end
	if MJ.db.settings.minimapButton then
		if not button then create() end
		updatePosition()
		button:Show()
	elseif button then
		button:Hide()
	end
end

-- Optional LibDataBroker launcher (Titan Panel, ChocolateBar, ElvUI datatexts...).
local function registerBroker()
	local LibStub = _G.LibStub
	local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
	if not ldb or ldb:GetDataObjectByName("MJurnal") then return end
	ldb:NewDataObject("MJurnal", {
		type = "launcher",
		label = "MJurnal",
		icon = ICON,
		OnClick = onClick,
		OnTooltipShow = function(tt) UI.FillLauncherTooltip(tt) end,
	})
end

MJ:Listen("LOGIN", function()
	UI:UpdateMinimapButton()
	registerBroker()
end)

MJ:Listen("SETTING_CHANGED", function(key)
	if key == "minimapButton" then UI:UpdateMinimapButton() end
end)
