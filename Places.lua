-- Places near you that are not tracked quests: quest givers with a quest you
-- could pick up (from QuestieDB) and flight masters (from the game). Each kind
-- shows within its own range. A quest giver, or a flight master you have not
-- discovered, coming into range is announced; the compass draws that.

local _, ns = ...

-- In range now: {place, point, since}. since: when it came into range and was
-- announced, else 0. The player's own map pin is there too, whatever the range.
ns.nearby = {}

local pin = { key = "pin", kind = "pin", title = "Map pin", always = true, points = { {} } }
ns.pin = pin

local available    -- the last scan: quests you could pick up, or nil
local givers = {}  -- "npc:<id>" or "object:<id>" -> {key, kind = "giver", title, points, quests, shown, tier}
local flights = {} -- "taxi:<node>" -> {key, kind = "flight", title, atlas, undiscovered, points}

local notes = {}   -- "note:<map>:<coord>" -> {key, kind = "note", title, desc, icon, points}

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

-- Notes the player put on the map with HandyNotes (Alt+right-click), read
-- from its own store: map ID -> coordinate -> {title, desc, icon}.
local function HandyNotesModule()
	local addons = LibStub and LibStub("AceAddon-3.0", true)
	local handyNotes = addons and addons:GetAddon("HandyNotes", true)
	return handyNotes and handyNotes:GetModule("HandyNotes", true)
end

local function RefreshNotes()
	wipe(notes)
	local module = HandyNotesModule()
	local maps = module and module.db and module.db.global
	if type(maps) ~= "table" then
		return
	end
	for mapID, list in pairs(maps) do
		if type(mapID) == "number" and type(list) == "table" then
			for coord, note in pairs(list) do
				if type(coord) == "number" and type(note) == "table" then
					-- HandyNotes packs a spot as XXXXYYYY, in ten-thousandths.
					local x, y = math.floor(coord / 10000) / 10000, (coord % 10000) / 10000
					local north, west, instance = ns.ToWorld(mapID, x, y)
					if north then
						local key = "note:" .. mapID .. ":" .. coord
						notes[key] = { key = key, kind = "note",
							title = (note.title and note.title ~= "") and note.title or "Note",
							desc = (note.desc and note.desc ~= "") and note.desc or nil,
							icon = module.icons and module.icons[note.icon],
							points = { { north = north, west = west, instance = instance, mapID = mapID, x = x, y = y } } }
					end
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
		if ns.PlayersPin() then
			local waypoint = C_Map.GetUserWaypoint()
			local pos = waypoint and waypoint.position
			local pinNorth, pinWest, instance
			if pos then
				pinNorth, pinWest, instance = ns.ToWorld(waypoint.uiMapID, pos.x, pos.y)
			end
			if pinNorth and instance == here then
				local point = pin.points[1]
				point.north, point.west, point.instance = pinNorth, pinWest, instance
				point.mapID, point.x, point.y = waypoint.uiMapID, pos.x, pos.y
				seen[pin.key] = true
				ns.nearby[#ns.nearby + 1] = { place = pin, point = point, since = 0 }
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
		if settings.notes then
			for _, note in pairs(notes) do
				Consider(note, settings.noteRange, false)
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
	-- Notes added, edited or deleted: HandyNotes tells only its own kind, so look again now and then.
	RefreshNotes()
	C_Timer.NewTicker(2, RefreshNotes)
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
