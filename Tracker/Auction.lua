-- Tracker/Auction.lua: auction house prices for the things you loot.
--
-- Two sources, both C_AuctionHouse:
--   full scan   - ReplicateItems returns every auction at once. The server allows it about every
--                 15 minutes. Started from the "MJurnal scan" button under the auction house
--                 (or automatically when you open it, see the settings).
--   your search - the lowest price in the browse and search results you look at anyway.
-- Prices are per realm and faction (MJ.AHKey): db.prices[key][itemID] = { p = lowest buyout
-- per unit in copper, t = when it was seen, h = { [dayKey] = lowest price that day } for the
-- last HISTORY_DAYS days }. Only items in the journal get a price (the rest of
-- the auction house is not stored), and a full scan drops prices of items no longer in it.
-- They are only shown next to the vendor value; every value in the journal is still calculated
-- with vendor prices.
local _, MJ = ...
local S = MJ.S
local AH = C_AuctionHouse
if not AH then
	MJ.auctionMissing = true
	return
end

local SCAN_COOLDOWN = 15 * 60 -- seconds between full scans the server allows
local HISTORY_DAYS = 90       -- days of daily prices kept per item
local BATCH = 500             -- auctions read per frame, so a big auction house doesn't freeze the game

local isOpen = false
local scan       -- { reading } while a full scan runs
local button

local function store()
	local key = MJ.AHKey()
	MJ.db.prices[key] = MJ.db.prices[key] or {}
	return MJ.db.prices[key]
end

-- Sets an item's current price and keeps the day's lowest price in its history.
local function record(prices, itemID, price, now)
	price = math.floor(price + 0.5)
	local e = prices[itemID]
	if not e then
		e = {}
		prices[itemID] = e
	end
	e.h = e.h or {}
	-- a price from before the history was kept becomes its first point
	if e.p and e.t and not next(e.h) then e.h[MJ.DayKey(e.t)] = e.p end
	e.p, e.t = price, now
	local dk = MJ.DayKey(now)
	e.h[dk] = math.min(e.h[dk] or price, price)
	local cutoff = MJ.DayKey(now - HISTORY_DAYS * 86400)
	for k in pairs(e.h) do
		if k < cutoff then e.h[k] = nil end
	end
end

local function secondsUntilScan()
	local last = MJ.db.ahScans[MJ.AHKey()] or 0
	return math.max(0, SCAN_COOLDOWN - (time() - last))
end

local function updateButton()
	if not button then return end
	button:SetText(scan and "Scanning..." or "MJurnal scan")
	if scan then button:Disable() else button:Enable() end
end

---------------------------------------------------------------------------
-- Full scan
---------------------------------------------------------------------------
function MJ:ScanAuctionHouse(quiet)
	if not AH.ReplicateItems then
		if not quiet then self:Print("This client has no full auction house scan.") end
		return
	end
	if not isOpen then
		if not quiet then self:Print("Open the auction house first.") end
		return
	end
	if scan then return end
	local wait = secondsUntilScan()
	if wait > 0 then
		if not quiet then
			self:Print(("The server allows a full scan about every 15 minutes. Next one in %s."):format(MJ.Dur(wait)))
		end
		return
	end
	scan = {}
	self.db.ahScans[MJ.AHKey()] = time()
	self:Print("Scanning the auction house...")
	updateButton()
	local ok = pcall(AH.ReplicateItems)
	if not ok then
		scan = nil
		updateButton()
		self:Print("The auction house did not accept the scan.")
		return
	end
	-- give up when nothing comes back
	local this = scan
	C_Timer.After(60, function()
		if scan == this and not scan.reading then
			scan = nil
			updateButton()
			MJ:Print("The auction house scan got no answer. Try again later.")
		end
	end)
end

local function finishScan(lowest, auctions)
	local prices, now, journal = store(), time(), MJ.db.items
	-- forget items that left the journal (deleted monsters, characters...)
	for itemID in pairs(prices) do
		if not journal[itemID] then prices[itemID] = nil end
	end
	local found, listed = 0, 0
	for itemID, unit in pairs(lowest) do
		listed = listed + 1
		if journal[itemID] then
			record(prices, itemID, unit, now)
			found = found + 1
		end
	end
	scan = nil
	updateButton()
	MJ:Print(("Auction house scanned: %s auctions of %s items. Prices for %s items in your journal.")
		:format(MJ.Num(auctions), MJ.Num(listed), MJ.Num(found)))
	MJ:Fire("DATA_CHANGED")
end

MJ:On("REPLICATE_ITEM_LIST_UPDATE", function()
	if not scan or scan.reading or not MJ.db then return end
	scan.reading = true
	local n = S(AH.GetNumReplicateItems()) or 0
	local lowest, i = {}, 0
	local function step()
		local stop = math.min(i + BATCH, n)
		for idx = i, stop - 1 do -- replicate indices start at 0
			local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = pcall(AH.GetReplicateItemInfo, idx)
			if ok then
				count, buyout, itemID = S(count), S(buyout), S(itemID)
				-- bid-only auctions have no buyout
				if itemID and count and count > 0 and buyout and buyout > 0 then
					local unit = buyout / count
					if not lowest[itemID] or unit < lowest[itemID] then lowest[itemID] = unit end
				end
			end
		end
		i = stop
		if i < n then
			C_Timer.After(0, step)
		else
			finishScan(lowest, n)
		end
	end
	step()
end)

---------------------------------------------------------------------------
-- Your own searches
---------------------------------------------------------------------------
local function learn(itemID, price, quantity)
	itemID, price = S(itemID), S(price)
	if not itemID or not price or price <= 0 or not MJ.db.items[itemID] then return false end
	quantity = S(quantity)
	if quantity and quantity > 1 then price = price / quantity end
	record(store(), itemID, price, time())
	return true
end

local function learnBrowse(results)
	local any = false
	for _, r in ipairs(type(results) == "table" and results or {}) do
		if learn(r.itemKey and r.itemKey.itemID, r.minPrice) then any = true end
	end
	if any then MJ:Fire("DATA_CHANGED") end
end

MJ:On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
	if not MJ.db or not AH.GetBrowseResults then return end
	local ok, results = pcall(AH.GetBrowseResults)
	if ok then learnBrowse(results) end
end)

MJ:On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added)
	if MJ.db then learnBrowse(added) end
end)

-- the cheapest offer is the first result
MJ:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	if not MJ.db or not AH.GetCommoditySearchResultInfo then return end
	local ok, r = pcall(AH.GetCommoditySearchResultInfo, itemID, 1)
	if ok and type(r) == "table" and learn(itemID, r.unitPrice) then MJ:Fire("DATA_CHANGED") end
end)

MJ:On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
	if not MJ.db or not AH.GetItemSearchResultInfo or type(itemKey) ~= "table" then return end
	local ok, r = pcall(AH.GetItemSearchResultInfo, itemKey, 1)
	if ok and type(r) == "table" and learn(itemKey.itemID, r.buyoutAmount, r.quantity) then MJ:Fire("DATA_CHANGED") end
end)

---------------------------------------------------------------------------
-- The button under the auction house
---------------------------------------------------------------------------
local function createButton()
	if button or not AuctionHouseFrame then return end
	button = CreateFrame("Button", "MJurnalAHScanButton", AuctionHouseFrame, "UIPanelButtonTemplate")
	button:SetSize(120, 22)
	button:SetPoint("TOPRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", 0, -2)
	button:SetScript("OnClick", function() MJ:ScanAuctionHouse() end)
	button:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetText("MJurnal: scan prices", 1, 1, 1)
		GameTooltip:AddLine("Reads every auction and keeps the prices of the items in your journal, shown next to their vendor prices. Prices from your own searches are picked up automatically.", nil, nil, nil, true)
		local last = MJ.db.ahScans[MJ.AHKey()]
		GameTooltip:AddDoubleLine("Last full scan", last and MJ.Ago(last) or "never", 0.8, 0.8, 0.8, 1, 1, 1)
		local wait = secondsUntilScan()
		if wait > 0 then GameTooltip:AddDoubleLine("Next possible in", MJ.Dur(wait), 0.8, 0.8, 0.8, 1, 1, 1) end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	updateButton()
end

MJ:On("AUCTION_HOUSE_SHOW", function()
	if not MJ.db then return end
	isOpen = true
	createButton()
	if MJ.db.settings.ahAutoScan then MJ:ScanAuctionHouse(true) end
end)

MJ:On("AUCTION_HOUSE_CLOSED", function()
	isOpen = false
	-- a scan that has not answered yet will not answer once the auction house is closed
	if scan and not scan.reading then
		scan = nil
		updateButton()
	end
end)
