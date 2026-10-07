-- Optional quest locations from QuestieDB: where the NPCs, objects and items a
-- quest still needs are found, and who takes it in. Only when QuestieDB is
-- loaded and speaks the contract this was written against; otherwise every
-- call here returns nil and the game's own quest areas are used.
--
-- QuestieDB spawns are 0-100 coordinates per zone area ID; its support data
-- maps area IDs to the game's map IDs.

local _, ns = ...

local CONTRACT = 2

local Q = {}
ns.Questie = Q

local db           -- LibQuestieDB, false once found unusable
local areaToMap    -- area ID -> map ID

local function Table(source)
	if type(source) == "table" then
		return source
	end
	if type(source) == "string" then
		local chunk = loadstring(source)
		local ok, result = pcall(chunk or error)
		if ok and type(result) == "table" then
			return result
		end
	end
	return {}
end

local function Load()
	if db ~= nil then
		return db or nil
	end
	db = false
	local lib = _G.LibQuestieDB
	if not (lib and lib.RequireContract and lib.RequireContract(CONTRACT)) then
		return nil
	end
	if not (lib.Quest and lib.Npc and lib.Object and lib.Item and lib.Support and lib.Support.Get) then
		return nil
	end
	local zones = lib.Support.Get("ZoneDB")
	if not (zones and zones.private) then
		return nil
	end
	areaToMap = Table(zones.private.areaIdToUiMapId)
	for areaID, mapID in pairs(Table(zones.private.areaIdToUiMapIdOverride)) do
		areaToMap[areaID] = mapID > 0 and mapID or nil
	end
	db = lib
	return db
end

function Q.Available()
	return Load() ~= nil
end

local function Get(entity, id, key)
	local ok, value = pcall(entity.Get, id, key)
	if ok then
		return value
	end
end

local function AddSpawns(points, spawns)
	if type(spawns) ~= "table" then
		return
	end
	for areaID, list in pairs(spawns) do
		local mapID = areaToMap[areaID]
		if mapID and type(list) == "table" then
			for _, spawn in ipairs(list) do
				local x, y = spawn[1], spawn[2]
				-- Negative coordinates mark spawns inside instances, with no place on the map.
				if x and y and x >= 0 and y >= 0 then
					points[#points + 1] = { mapID, x / 100, y / 100 }
				end
			end
		end
	end
end

local function AddNpc(points, id)
	AddSpawns(points, Get(db.Npc, id, "spawns"))
end

local function AddObject(points, id)
	AddSpawns(points, Get(db.Object, id, "spawns"))
end

local function AddItem(points, id)
	for _, npc in ipairs(Get(db.Item, id, "npcDrops") or {}) do
		AddNpc(points, npc)
	end
	for _, object in ipairs(Get(db.Item, id, "objectDrops") or {}) do
		AddObject(points, object)
	end
end

-- Does the quest still need what is called name? The game's objective texts
-- carry the name ("Defias Thug slain: 3/10"); a finished one is skipped. When
-- no text names it, it may still be needed.
local function Wanted(name, objectives)
	if type(name) ~= "string" or name == "" then
		return true
	end
	name = name:lower()
	local seen = false
	for _, objective in ipairs(objectives) do
		if objective.text and objective.text:lower():find(name, 1, true) then
			if not objective.finished then
				return true
			end
			seen = true
		end
	end
	return not seen
end

-- Points {mapID, x, y} where the quest can be advanced (or turned in), or nil.
function Q.Points(questID, complete)
	if not Load() then
		return nil
	end
	local points = {}
	if complete then
		local finishers = Get(db.Quest, questID, "finishedBy")
		if type(finishers) == "table" then
			for _, npc in ipairs(finishers[1] or {}) do
				AddNpc(points, npc)
			end
			for _, object in ipairs(finishers[2] or {}) do
				AddObject(points, object)
			end
		end
	else
		local objectives = C_QuestLog.GetQuestObjectives(questID) or {}
		local wanted = Get(db.Quest, questID, "objectives")
		if type(wanted) == "table" then
			for _, entry in ipairs(wanted[1] or {}) do
				if Wanted(Get(db.Npc, entry[1], "name"), objectives) then
					AddNpc(points, entry[1])
				end
			end
			for _, entry in ipairs(wanted[2] or {}) do
				if Wanted(Get(db.Object, entry[1], "name"), objectives) then
					AddObject(points, entry[1])
				end
			end
			for _, entry in ipairs(wanted[3] or {}) do
				if Wanted(Get(db.Item, entry[1], "name"), objectives) then
					AddItem(points, entry[1])
				end
			end
			-- Kill credits: { {npc IDs that count}, credited npc, text }.
			for _, entry in ipairs(wanted[5] or {}) do
				if Wanted(entry[2] and Get(db.Npc, entry[2], "name"), objectives) then
					for _, npc in ipairs(entry[1] or {}) do
						AddNpc(points, npc)
					end
				end
			end
		end
		-- Places to reach: { text, spawns }.
		local trigger = Get(db.Quest, questID, "triggerEnd")
		if type(trigger) == "table" then
			AddSpawns(points, trigger[2])
		end
	end
	return #points > 0 and points or nil
end
