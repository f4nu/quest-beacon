-- Tracked quests, where they are, and which one the game navigates to.
--
-- Locations are the game's own: the quest's spot on the player's map (or a
-- parent map), else the game's next waypoint for it (a zone exit, a dungeon
-- entrance). Positions are world yards: north and west, as the game's
-- GetWorldPosFromMapPos and UnitPosition give them.

local ADDON, ns = ...

local DEFAULTS = { compass = true, marker = true, auto = true }

-- A filled circle centred in its texture; the game's portrait mask is not, and
-- numbers on it looked off centre.
ns.CIRCLE = "Interface\\AddOns\\" .. ADDON .. "\\Media\\circle"

ns.targets = {}  -- tracked quests in watch order: {questID, title, complete, detail, north, west, instance}
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

-- The game's map-pin "?" for a quest, grey while in progress; the old gossip
-- icon if a client lacks the atlas.
function ns.SetQuestIcon(texture, complete)
	if texture.questComplete == complete then
		return
	end
	texture.questComplete = complete
	if not texture:SetAtlas("UI-QuestIcon-TurnIn-Normal") then
		texture:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
	end
	texture:SetDesaturated(not complete)
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
	wipe(ns.targets)
	wipe(ns.byQuest)
	for i = 1, C_QuestLog.GetNumQuestWatches() do
		local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
		if questID then
			local target = { questID = questID }
			target.title, target.complete, target.detail = ns.Describe(questID)
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

-- Super-tracking: the game navigates to the nearest tracked quest, unless the
-- player picked one (in the game's tracker, on the compass, or with Next).

local ourPick      -- quest we last super-tracked
local manual       -- quest the player picked; held while it is tracked
local quietUntil = 0

local function SuperTracked()
	local questID = C_SuperTrack.GetSuperTrackedQuestID()
	if questID and questID > 0 then
		return questID
	end
end

local function SuperTrack(questID)
	ourPick = questID
	if SuperTracked() ~= questID then
		C_SuperTrack.SetSuperTrackedQuestID(questID)
	end
end

function ns.Choose()
	if not ns.Settings().auto then
		return
	end
	-- Navigating to a map pin, a corpse or the like: the player's business.
	if C_SuperTrack.IsSuperTrackingAnything() and not C_SuperTrack.IsSuperTrackingQuest() then
		return
	end
	if manual then
		if C_QuestLog.GetLogIndexForQuestID(manual) then
			return SuperTrack(manual)
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
	local current = SuperTracked()
	for _, entry in ipairs(list) do
		if entry.target.questID == current then
			if nearest.distance > entry.distance * 0.85 then
				return
			end
			break
		end
	end
	SuperTrack(nearest.target.questID)
end

function ns.Pick(questID)
	manual = questID
	SuperTrack(questID)
end

function QuestBeacon_Next()
	local list = ns.ByDistance()
	if #list == 0 then
		return
	end
	local current = SuperTracked()
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

local function Soon()
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
	Soon()
end)

EventUtil.ContinueOnAddOnLoaded(ADDON, function()
	QuestBeaconDB = QuestBeaconDB or {}
	for key, value in pairs(DEFAULTS) do
		if QuestBeaconDB[key] == nil then
			QuestBeaconDB[key] = value
		end
	end
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED",
		"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "SUPER_TRACKING_CHANGED" }) do
		events:RegisterEvent(event)
	end
	-- Quest spots move as objectives progress, and the nearest changes as you move.
	C_Timer.NewTicker(1, Update)
	ns.OnSettingsChanged()
end)

BINDING_HEADER_QUESTBEACON = "Quest Beacon"
BINDING_NAME_QUESTBEACON_NEXT = "Navigate to next tracked quest"

local function Toggle(key, label)
	QuestBeaconDB[key] = not QuestBeaconDB[key]
	print(("Quest Beacon: %s %s"):format(label, QuestBeaconDB[key] and "on" or "off"))
	if ns.OnSettingsChanged then
		ns.OnSettingsChanged()
	end
end

SLASH_QUESTBEACON1 = "/qb"
SlashCmdList.QUESTBEACON = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "compass" then
		Toggle("compass", "compass")
	elseif msg == "marker" then
		Toggle("marker", "world marker")
	elseif msg == "auto" then
		manual = nil
		Toggle("auto", "navigate to nearest")
		Soon()
	elseif msg == "next" then
		QuestBeacon_Next()
	elseif msg == "why" then
		ns.Diagnose()
	elseif msg == "move" then
		if ns.ToggleMove then
			ns.ToggleMove()
		end
	else
		print("Quest Beacon: /qb compass | marker | auto | next | move | why")
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
	local north, west = ns.PlayerPosition()
	local superTracked = C_SuperTrack.GetSuperTrackedQuestID()
	print(("  game navigates to quest %s, %s yd away"):format(S(superTracked),
		S(C_Navigation.GetFrame() and math.floor(C_Navigation.GetDistance()))))
	for _, target in ipairs(ns.targets) do
		local yards = target.north and north and math.floor((ns.Measure(target, north, west)))
		print(("  %s%d %s: %s, instance %s, north %s west %s, %s yd"):format(
			target.questID == superTracked and "> " or "", target.questID, target.title, S(target.source),
			S(target.instance), S(target.north and math.floor(target.north)), S(target.west and math.floor(target.west)),
			S(yards)))
	end
end
