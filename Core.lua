-- Tracked quests, where they are, and which one the game navigates to.
--
-- Locations are the game's own: the quest's spot on the player's map (or a
-- parent map), else the game's next waypoint for it (a zone exit, a dungeon
-- entrance). With QuestieDB installed (and enabled in the settings), the
-- nearest spawn of whatever the quest still needs, or of whoever takes it in,
-- is used instead. Positions are world yards: north and west, as the game's
-- GetWorldPosFromMapPos and UnitPosition give them.

local ADDON, ns = ...

local DEFAULTS = {
	compass = true,
	marker = true,
	auto = true,
	questie = true,
	cameraFade = true,
	compassWidth = 560,
	merge = 26,
}
ns.DEFAULTS = DEFAULTS

-- A filled circle centred in its texture; the game's portrait mask is not, and
-- numbers on it looked off centre.
ns.CIRCLE = "Interface\\AddOns\\" .. ADDON .. "\\Media\\circle"
ns.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon"

ns.targets = {}  -- tracked quests in watch order: {questID, title, complete, detail, north, west, instance, ...}
ns.byQuest = {}

function ns.Settings()
	return QuestBeaconDB or DEFAULTS
end

local vec = CreateVector2D(0, 0)

local function ToWorld(mapID, x, y)
	vec:SetXY(x, y)
	local instance, pos = C_Map.GetWorldPosFromMapPos(mapID, vec)
	if pos then
		local north, west = pos:GetXY()
		return north, west, instance
	end
end

-- The instance the player is in; known even where the position is hidden.
function ns.Instance()
	return (select(8, GetInstanceInfo()))
end

-- The player in world yards: north, west, instance. Nil where the game hides it (instances).
function ns.PlayerPosition()
	local north, west, _, instance = UnitPosition("player")
	if north and west then
		return north, west, instance
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if pos then
		return ToWorld(mapID, pos:GetXY())
	end
end

-- Distance in yards and bearing in radians (0 = north, counter-clockwise, like GetPlayerFacing).
function ns.Measure(target, north, west)
	local dNorth, dWest = target.north - north, target.west - west
	return math.sqrt(dNorth * dNorth + dWest * dWest), math.atan2(dWest, dNorth)
end

-- Short distance for labels: 673, 1.2k, 3k, 12k.
function ns.Yards(yards)
	if yards < 1000 then
		return tostring(math.floor(yards))
	elseif yards < 10000 then
		return (("%.1f"):format(yards / 1000):gsub("%.0$", "")) .. "k"
	end
	return math.floor(yards / 1000) .. "k"
end

function ns.Describe(questID)
	local title = C_QuestLog.GetTitleForQuestID(questID) or ("Quest " .. questID)
	local complete = C_QuestLog.ReadyForTurnIn(questID) or C_QuestLog.IsComplete(questID)
	local detail
	if complete then
		detail = "Ready for turn-in"
	else
		for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
			if not objective.finished then
				detail = objective.text
				break
			end
		end
	end
	return title, complete, detail
end

-- "dungeon" or "raid" for quests the game tags so, else nil.
local KINDS = {}
for name, kind in pairs({ Dungeon = "dungeon", Raid = "raid", Raid10 = "raid", Raid25 = "raid" }) do
	local tag = Enum.QuestTag and Enum.QuestTag[name]
	if tag then
		KINDS[tag] = kind
	end
end

function ns.Kind(questID)
	local tag = C_QuestLog.GetQuestTagInfo(questID)
	return tag and KINDS[tag.tagID]
end

-- Hard: the quests the game's tracker shows in orange or red, by the same
-- call. Returns the tier's name in QuestDifficultyColors, else nil.
local HARD = {}
if Enum.RelativeContentDifficulty then
	HARD[Enum.RelativeContentDifficulty.Difficult] = "verydifficult"
	HARD[Enum.RelativeContentDifficulty.Impossible] = "impossible"
end

function ns.Hard(questID)
	return HARD[C_PlayerInfo.GetContentDifficultyQuestForPlayer(questID)]
end

-- A quest's icon: ready for turn-in, the map-pin "?"; a dungeon or raid quest
-- still to do, its entrance icon in colour; any other quest still to do, the
-- "?" in grey, or in the tracker's orange or red when hard and the caller asks.
-- The old gossip icon if a client lacks the art. The entrance art is mostly
-- glow, so it is drawn larger than the "?", by entranceScale.
local ATLAS = { dungeon = "Dungeon", raid = "Raid" }

function ns.SetQuestIcon(texture, complete, kind, size, entranceScale, hard)
	kind = not complete and kind or nil
	hard = not complete and not kind and hard or nil
	if texture.questComplete ~= complete or texture.questKind ~= kind or texture.questHard ~= hard then
		texture.questComplete, texture.questKind, texture.questHard = complete, kind, hard
		texture.entrance = kind ~= nil and texture:SetAtlas(ATLAS[kind])
		if texture.entrance then
			texture:SetDesaturated(false)
		else
			if not texture:SetAtlas("UI-QuestIcon-TurnIn-Normal") then
				texture:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
			end
			texture:SetDesaturated(not complete)
		end
		-- The grey "?" tinted takes the tint's colour cleanly.
		local tint = hard and QuestDifficultyColors[hard]
		if tint then
			texture:SetVertexColor(tint.r, tint.g, tint.b)
		else
			texture:SetVertexColor(1, 1, 1)
		end
	end
	size = size * (texture.entrance and entranceScale or 1)
	texture:SetSize(size, size)
end

-- The player's map and its parents up to the continent.
local function MapChain(mapID)
	local chain = {}
	while mapID and #chain < 5 do
		chain[#chain + 1] = mapID
		local info = C_Map.GetMapInfo(mapID)
		if not info or info.mapType <= Enum.UIMapType.Continent then
			break
		end
		mapID = info.parentMapID
	end
	return chain
end

-- QuestieDB points in world yards, per quest, rebuilt when the quest's
-- progress changes.
local spawnCache = {}

local function Progress(questID, complete)
	local key = complete and "done" or ""
	for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
		key = key .. (objective.finished and "1" or "0")
	end
	return key
end

local function SpawnPoints(questID, complete)
	local key = Progress(questID, complete)
	local cached = spawnCache[questID]
	if cached and cached.key == key then
		return cached.points
	end
	local points = {}
	for _, point in ipairs(ns.Questie.Points(questID, complete) or {}) do
		local north, west, instance = ToWorld(point[1], point[2], point[3])
		if north then
			points[#points + 1] = { north = north, west = west, instance = instance,
				mapID = point[1], x = point[2], y = point[3] }
		end
	end
	spawnCache[questID] = { key = key, points = points }
	return points
end

-- The game's location for a quest: its area on a map, or its next waypoint.
local function GameLocation(target, onMap, here)
	local questID = target.questID
	local spot = onMap[questID]
	-- Not on your map (or you have none, as in the Deeprun Tram): the quest's own map, where the client says.
	if not spot and GetQuestUiMapID then
		local questMap = GetQuestUiMapID(questID)
		if questMap and questMap > 0 then
			for _, poi in ipairs(C_QuestLog.GetQuestsOnMap(questMap) or {}) do
				if poi.questID == questID then
					spot = { questMap, poi.x, poi.y }
					break
				end
			end
		end
	end
	if spot then
		target.north, target.west, target.instance = ToWorld(spot[1], spot[2], spot[3])
		target.source = ("quest area on map %d (%.3f, %.3f)"):format(spot[1], spot[2], spot[3])
	end
	-- No spot, or one in another instance (you are in the Deeprun Tram, it is
	-- outside): the game's next waypoint, which may be the way out.
	if target.instance ~= here then
		local mapID, x, y = C_QuestLog.GetNextWaypoint(questID)
		if mapID and x and y then
			local north, west, instance = ToWorld(mapID, x, y)
			if instance == here or not target.instance then
				target.north, target.west, target.instance = north, west, instance
				target.source = ("next waypoint on map %d (%.3f, %.3f)"):format(mapID, x, y)
			end
		end
	end
end

-- The nearest QuestieDB spawn in this instance. Spawns elsewhere still give
-- the quest a place (another instance) when the game has none.
local function SpawnLocation(target, north, west, here)
	local points = SpawnPoints(target.questID, target.complete)
	local best, bestYards
	if north then
		for _, point in ipairs(points) do
			if point.instance == here then
				local yards = ns.Measure(point, north, west)
				if not bestYards or yards < bestYards then
					best, bestYards = point, yards
				end
			end
		end
	end
	if not best and not target.north then
		best = points[1]
	end
	if best then
		target.north, target.west, target.instance = best.north, best.west, best.instance
		target.mapID, target.x, target.y = best.mapID, best.x, best.y
		target.spawn = true
		target.source = ("QuestieDB spawn on map %d (%.3f, %.3f), %d known"):format(best.mapID, best.x, best.y, #points)
	end
end

function ns.Refresh()
	local onMap = {}
	local playerMap = C_Map.GetBestMapForUnit("player")
	if playerMap then
		for _, mapID in ipairs(MapChain(playerMap)) do
			for _, poi in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
				if not onMap[poi.questID] then
					onMap[poi.questID] = { mapID, poi.x, poi.y }
				end
			end
		end
	end

	local here = ns.Instance()
	local north, west = ns.PlayerPosition()
	local useQuestie = ns.Settings().questie and ns.Questie.Available()
	wipe(ns.targets)
	wipe(ns.byQuest)
	for i = 1, C_QuestLog.GetNumQuestWatches() do
		local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
		if questID then
			local target = { questID = questID }
			target.title, target.complete, target.detail = ns.Describe(questID)
			target.kind = ns.Kind(questID)
			target.hard = ns.Hard(questID)
			if useQuestie then
				SpawnLocation(target, north, west, here)
			end
			if not target.spawn or target.instance ~= here then
				local spawn = target.spawn and { target.north, target.west, target.instance, target.source }
				target.north, target.west, target.instance, target.spawn = nil, nil, nil, nil
				GameLocation(target, onMap, here)
				-- The game knows nothing at all: keep the spawn, even in another
				-- instance, so the marker knows the quest is not here.
				if spawn and not target.north then
					target.north, target.west, target.instance, target.source = spawn[1], spawn[2], spawn[3], spawn[4]
					target.spawn = true
				end
			end
			ns.targets[#ns.targets + 1] = target
			ns.byQuest[questID] = target
		end
	end
end

-- Located tracked quests in this instance, nearest first: {target, distance}.
function ns.ByDistance()
	local north, west, instance = ns.PlayerPosition()
	local list = {}
	if not north then
		return list
	end
	for _, target in ipairs(ns.targets) do
		if target.north and target.instance == instance then
			list[#list + 1] = { target = target, distance = (ns.Measure(target, north, west)) }
		end
	end
	table.sort(list, function(a, b) return a.distance < b.distance end)
	return list
end

-- Navigation: the game navigates to the nearest tracked quest, unless the
-- player picked one (in the game's tracker, on the compass, or with Next).
-- A quest located by a QuestieDB spawn is navigated to through a map
-- waypoint on that spawn, since the game only knows its own quest areas.

local ourPick      -- quest we last navigated to
local manual       -- quest the player picked; held while it is in the log
local placed       -- our map waypoint: {questID, mapID, x, y, north, west}
local quietUntil = 0

local function SuperTracked()
	local questID = C_SuperTrack.GetSuperTrackedQuestID()
	if questID and questID > 0 then
		return questID
	end
end

-- Is the game navigating to the waypoint we put down (and not one the player moved)?
local function OnOurWaypoint()
	if not (placed and C_SuperTrack.IsSuperTrackingUserWaypoint()) then
		return false
	end
	local point = C_Map.GetUserWaypoint()
	local pos = point and point.position
	return pos ~= nil and point.uiMapID == placed.mapID
		and math.abs(pos.x - placed.x) < 0.002 and math.abs(pos.y - placed.y) < 0.002
end

-- The quest the game is navigating to, by quest or by our waypoint.
function ns.CurrentQuest()
	if OnOurWaypoint() then
		return placed.questID
	end
	return SuperTracked()
end

local function ClearOurWaypoint()
	if not placed then
		return
	end
	if OnOurWaypoint() then
		C_SuperTrack.SetSuperTrackedUserWaypoint(false)
		C_Map.ClearUserWaypoint()
	end
	placed = nil
end

local function Navigate(questID)
	ourPick = questID
	local target = ns.byQuest[questID]
	if target and target.spawn and target.mapID and C_Map.CanSetUserWaypointOnMap(target.mapID) then
		-- Move the waypoint only when the nearest spawn moved, not on every tick.
		local same = placed and placed.questID == questID and OnOurWaypoint()
			and ns.Measure(target, placed.north, placed.west) < 20
		if not same then
			placed = { questID = questID, mapID = target.mapID, x = target.x, y = target.y,
				north = target.north, west = target.west }
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(target.mapID, target.x, target.y))
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
		return
	end
	ClearOurWaypoint()
	if SuperTracked() ~= questID then
		C_SuperTrack.SetSuperTrackedQuestID(questID)
	end
end

function ns.Choose()
	if not ns.Settings().auto then
		return
	end
	-- Navigating to a map pin, a corpse or the like: the player's business.
	if C_SuperTrack.IsSuperTrackingAnything() and not C_SuperTrack.IsSuperTrackingQuest() and not OnOurWaypoint() then
		return
	end
	if manual then
		if C_QuestLog.GetLogIndexForQuestID(manual) then
			return Navigate(manual)
		end
		manual = nil
	end
	local list = ns.ByDistance()
	local nearest = list[1]
	if not nearest then
		return
	end
	-- Hold the current quest unless the nearest is clearly closer, so two
	-- quests about as far away don't swap back and forth.
	local current = ns.CurrentQuest()
	for _, entry in ipairs(list) do
		if entry.target.questID == current then
			if nearest.distance > entry.distance * 0.85 then
				return Navigate(current)
			end
			break
		end
	end
	Navigate(nearest.target.questID)
end

function ns.Pick(questID)
	manual = questID
	Navigate(questID)
end

function QuestBeacon_Next()
	local list = ns.ByDistance()
	if #list == 0 then
		return
	end
	local current = ns.CurrentQuest()
	local index = 0
	for i, entry in ipairs(list) do
		if entry.target.questID == current then
			index = i
			break
		end
	end
	ns.Pick(list[index % #list + 1].target.questID)
end

local function OnSuperTrackingChanged()
	if GetTime() < quietUntil then
		return
	end
	local questID = SuperTracked()
	if questID and questID ~= ourPick then
		manual = questID
	end
end

local pending = false
local function Update()
	pending = false
	ns.Refresh()
	ns.Choose()
end

function ns.Soon()
	if not pending then
		pending = true
		C_Timer.After(0.2, Update)
	end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "SUPER_TRACKING_CHANGED" then
		OnSuperTrackingChanged()
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		-- The game restores its last super-tracked quest after a login or reload; that is not a pick.
		quietUntil = GetTime() + 5
	end
	ns.Soon()
end)

-- Settings.lua and the display files add their own setup here.
ns.onLoad = {}

EventUtil.ContinueOnAddOnLoaded(ADDON, function()
	QuestBeaconDB = QuestBeaconDB or {}
	for key, value in pairs(DEFAULTS) do
		if QuestBeaconDB[key] == nil then
			QuestBeaconDB[key] = value
		end
	end
	QuestBeaconDB.minimap = QuestBeaconDB.minimap or {}
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED",
		"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "SUPER_TRACKING_CHANGED" }) do
		events:RegisterEvent(event)
	end
	-- Quest spots move as objectives progress, and the nearest changes as you move.
	C_Timer.NewTicker(1, Update)
	for _, setup in ipairs(ns.onLoad) do
		setup()
	end
	ns.OnSettingsChanged()
end)

-- A setting changed: Choose again with it, and let the displays follow.
local displays = {}
function ns.OnSettingsChanged()
	if not ns.Settings().auto then
		manual = nil
	end
	for _, apply in ipairs(displays) do
		apply()
	end
	ns.Soon()
end

function ns.AddDisplay(apply)
	displays[#displays + 1] = apply
end

BINDING_HEADER_QUESTBEACON = "Quest Beacon"
BINDING_NAME_QUESTBEACON_NEXT = "Navigate to next tracked quest"

local function Toggle(key, label)
	QuestBeaconDB[key] = not QuestBeaconDB[key]
	print(("Quest Beacon: %s %s"):format(label, QuestBeaconDB[key] and "on" or "off"))
	ns.OnSettingsChanged()
end

SLASH_QUESTBEACON1 = "/qb"
SlashCmdList.QUESTBEACON = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "" then
		ns.OpenSettings()
	elseif msg == "compass" then
		Toggle("compass", "compass")
	elseif msg == "marker" then
		Toggle("marker", "world marker")
	elseif msg == "auto" then
		Toggle("auto", "navigate to nearest")
	elseif msg == "next" then
		QuestBeacon_Next()
	elseif msg == "why" then
		ns.Diagnose()
	elseif msg == "move" then
		ns.ToggleMove()
	else
		print("Quest Beacon: /qb (settings) | compass | marker | auto | next | move | why")
	end
end

-- /qb why: where the player is, and where each tracked quest is believed to be.
function ns.Diagnose()
	local function S(v)
		return v == nil and "nil" or tostring(v)
	end
	local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	local uNorth, uWest, _, uInstance = UnitPosition("player")
	local mapID = C_Map.GetBestMapForUnit("player")
	local mapInfo = mapID and C_Map.GetMapInfo(mapID)
	print("Quest Beacon: you")
	print(("  instance %s (%s, %s), map %s %s"):format(S(instanceID), S(name), S(instanceType), S(mapID),
		mapInfo and ("(" .. mapInfo.name .. ", parent " .. S(mapInfo.parentMapID) .. ")") or ""))
	print(("  UnitPosition north %s west %s instance %s"):format(S(uNorth and math.floor(uNorth)),
		S(uWest and math.floor(uWest)), S(uInstance)))
	print(("  QuestieDB %s"):format(ns.Questie.Available() and (ns.Settings().questie and "in use" or "off in settings")
		or "not installed or incompatible"))
	local north, west = ns.PlayerPosition()
	local current = ns.CurrentQuest()
	print(("  navigating to quest %s%s, %s yd away"):format(S(current), OnOurWaypoint() and " (by waypoint)" or "",
		S(C_Navigation.GetFrame() and math.floor(C_Navigation.GetDistance()))))
	for _, target in ipairs(ns.targets) do
		local yards = target.north and north and math.floor((ns.Measure(target, north, west)))
		print(("  %s%d %s: %s, instance %s, %s yd"):format(target.questID == current and "> " or "",
			target.questID, target.title, S(target.source), S(target.instance), S(yards)))
	end
end
