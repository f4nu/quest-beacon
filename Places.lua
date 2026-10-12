-- Places near you that are not tracked quests: quest givers with a quest you
-- could pick up (from QuestieDB) and flight masters (from the game). Each kind
-- shows within its own range. A quest giver, or a flight master you have not
-- discovered, coming into range is announced; the compass draws that.

local _, ns = ...

-- In range now: {place, point, since}. since: when it came into range and was
-- announced, else 0.
ns.nearby = {}

local available    -- the last scan: quests you could pick up, or nil
local givers = {}  -- "npc:<id>" or "object:<id>" -> {key, kind = "giver", title, points, quests, shown, tier}
local flights = {} -- "taxi:<node>" -> {key, kind = "flight", title, atlas, undiscovered, points}

local LETTER = { Alliance = "A", Horde = "H" }

-- A starter's spawns in world yards. Spawns do not move: kept for good.
local spots = {}

local function Spot(kind, id)
	local key = kind .. ":" .. id
	local spot = spots[key]
	if spot then
		return spot
	end
	local name, points, faction
	if kind == "npc" then
		name, points, faction = ns.Questie.Npc(id)
	else
		name, points = ns.Questie.Object(id)
	end
	spot = { key = key, name = name, faction = faction, points = {} }
	for _, point in ipairs(points) do
		local north, west, instance = ns.ToWorld(point[1], point[2], point[3])
		if north then
			spot.points[#spot.points + 1] = { north = north, west = west, instance = instance,
				mapID = point[1], x = point[2], y = point[3] }
		end
	end
	spots[key] = spot
	return spot
end

-- An NPC with no faction listed is taken as friendly.
local function Friendly(faction)
	local mine = LETTER[UnitFactionGroup("player")]
	return not faction or not mine or faction:find(mine, 1, true) ~= nil
end

-- Givers from the last scan, each with the quests it offers that are shown
-- (grey ones left out when asked), lowest level first. The pin takes the
-- colour of the lowest.
local function BuildGivers()
	wipe(givers)
	if not available then
		return
	end
	local hideTrivial = ns.Settings().hideTrivial
	for _, quest in ipairs(available) do
		quest.tier = ns.TierByLevel(quest.level)
		if not (hideTrivial and quest.tier == "trivial") then
			local function Add(kind, id)
				local spot = Spot(kind, id)
				if #spot.points > 0 and Friendly(spot.faction) then
					local giver = givers[spot.key]
					if not giver then
						giver = { key = spot.key, kind = "giver", title = spot.name or "?", points = spot.points,
							quests = {} }
						givers[spot.key] = giver
					end
					giver.quests[#giver.quests + 1] = quest
				end
			end
			for _, id in ipairs(quest.npcs or {}) do
				Add("npc", id)
			end
			for _, id in ipairs(quest.objects or {}) do
				Add("object", id)
			end
		end
	end
	for _, giver in pairs(givers) do
		table.sort(giver.quests, function(a, b) return a.level < b.level end)
		giver.tier = giver.quests[1].tier
	end
end

local scanPending = false
local function Scan()
	scanPending = false
	if not ns.Settings().givers then
		available = nil
		return BuildGivers()
	end
	ns.Questie.ScanAvailable(function(list)
		available = list
		BuildGivers()
	end)
end

-- Quests turned in, taken, dropped, a level gained: scan again, once things settle.
local function ScanSoon()
	if not scanPending then
		scanPending = true
		C_Timer.After(1, Scan)
	end
end

-- Flight masters on your map and the maps above it, of your faction or neutral.
local function Ours(faction)
	local factions = Enum.FlightPathFaction
	if not factions or not faction or faction == factions.Neutral then
		return true
	end
	local mine = UnitFactionGroup("player")
	return (faction == factions.Horde and mine == "Horde") or (faction == factions.Alliance and mine == "Alliance")
end

local function RefreshFlights()
	wipe(flights)
	local mapID = C_Map.GetBestMapForUnit("player")
	if not (mapID and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then
		return
	end
	for _, map in ipairs(ns.MapChain(mapID)) do
		for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(map) or {}) do
			local key = "taxi:" .. node.nodeID
			if not flights[key] and node.position and Ours(node.faction) then
				local x, y = node.position:GetXY()
				local north, west, instance = ns.ToWorld(map, x, y)
				if north then
					flights[key] = { key = key, kind = "flight", title = node.name, atlas = node.atlasName,
						undiscovered = node.isUndiscovered,
						points = { { north = north, west = west, instance = instance, mapID = map, x = x, y = y } } }
				end
			end
		end
	end
end

-- What is in range, and when each came into range. Nothing is announced for
-- a while after a loading screen: what is around you then was already there.
local since = {}
local quietUntil = 0

local function Nearest(place, north, west, here)
	local best, bestYards
	for _, point in ipairs(place.points) do
		if point.instance == here then
			local yards = ns.Measure(point, north, west)
			if not bestYards or yards < bestYards then
				best, bestYards = point, yards
			end
		end
	end
	return best, bestYards
end

local seen = {}
local function Tick()
	wipe(ns.nearby)
	wipe(seen)
	local north, west, here = ns.PlayerPosition()
	if north then
		local settings = ns.Settings()
		local now = GetTime()
		local function Consider(place, range, announce)
			local point, yards = Nearest(place, north, west, here)
			if point and yards <= range then
				seen[place.key] = true
				if not since[place.key] then
					since[place.key] = announce and now >= quietUntil and now or 0
				end
				ns.nearby[#ns.nearby + 1] = { place = place, point = point, since = since[place.key] }
			end
		end
		if settings.givers then
			for _, giver in pairs(givers) do
				Consider(giver, settings.giverRange, true)
			end
		end
		if settings.flights then
			for _, flight in pairs(flights) do
				Consider(flight, settings.flightRange, flight.undiscovered)
			end
		end
	end
	for key in pairs(since) do
		if not seen[key] then
			since[key] = nil
		end
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		quietUntil = GetTime() + 3
		wipe(since)
		RefreshFlights()
		ScanSoon()
	elseif event == "ZONE_CHANGED_NEW_AREA" or event == "TAXIMAP_CLOSED" or event == "TAXI_NODE_STATUS_CHANGED" then
		RefreshFlights()
	else
		ScanSoon()
	end
end)

table.insert(ns.onLoad, function()
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "TAXIMAP_CLOSED",
		"QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED" }) do
		events:RegisterEvent(event)
	end
	-- Not every client has it.
	pcall(events.RegisterEvent, events, "TAXI_NODE_STATUS_CHANGED")
	C_Timer.NewTicker(0.25, Tick)
	-- A flight path learned without opening the map, a node crossed into: a slow sweep.
	C_Timer.NewTicker(10, RefreshFlights)
end)

-- Settings: givers switched on want a scan; hiding grey quests, a rebuild.
local wanted, hiding
ns.AddDisplay(function()
	local settings = ns.Settings()
	if settings.givers ~= wanted then
		wanted = settings.givers
		ScanSoon()
	elseif settings.hideTrivial ~= hiding then
		BuildGivers()
	end
	hiding = settings.hideTrivial
end)
