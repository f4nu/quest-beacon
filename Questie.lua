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

-- A quest giver's name, spawn points {mapID, x, y}, and the factions it is
-- friendly to ("A", "H", "AH"; nil: unknown).
function Q.Npc(id)
	local points = {}
	AddNpc(points, id)
	return Get(db.Npc, id, "name"), points, Get(db.Npc, id, "friendlyToFaction")
end

function Q.Object(id)
	local points = {}
	AddObject(points, id)
	return Get(db.Object, id, "name"), points
end

-- Quests you could pick up now: QuestieDB's requirements, checked the way
-- Questie checks them (its QuestieDB.IsDoable), against the game's record of
-- completed quests and your quest log. Questie's own code is not a contract
-- between addons; QuestieDB's data is.

local EVENT = 2   -- specialFlags: only during a world event

-- Holiday and world-event quests, by their quest category (zoneOrSort).
-- QuestieDB flags few of them; Questie keeps its own lists. Left out, even
-- while the holiday is on.
local EVENTS = {}
for _, sort in ipairs({ -404, -402, -378, -376, -375, -374, -370, -369, -366, -364, -41, -22, -21, -368, -365 }) do
	EVENTS[sort] = true
end

-- Skyborne races carry bits 32 and 33, not race ID - 1, and only the
-- faction-wide masks (77 Alliance, 178 Horde) include them. As Questie.
local SKYBORNE = { [95] = 4294967296, [96] = 8589934592 }

-- Arithmetic, not bit.band: race masks go past 32 bits.
local function HasFlag(mask, flag)
	return (mask % (2 * flag)) >= flag
end

-- What the checks read about you, taken once per scan.
local function Player()
	local p = { level = UnitLevel("player"), faction = UnitFactionGroup("player"), completed = {}, log = {},
		skills = {} }
	local race = select(3, UnitRace("player"))
	p.skyborne = SKYBORNE[race] ~= nil
	p.race = SKYBORNE[race] or 2 ^ (race - 1)
	p.class = 2 ^ (select(3, UnitClass("player")) - 1)
	if C_QuestLog.GetAllCompletedQuestIDs then
		for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do
			p.completed[id] = true
		end
	elseif GetQuestsCompleted then
		for id in pairs(GetQuestsCompleted() or {}) do
			p.completed[id] = true
		end
	end
	-- In the log: asked per quest. Walking the log misses the quests under a
	-- collapsed header.
	setmetatable(p.log, { __index = function(log, id)
		local inLog = C_QuestLog.GetLogIndexForQuestID(id) ~= nil
		rawset(log, id, inLog)
		return inLog
	end })
	if GetProfessions then
		for _, index in pairs({ GetProfessions() }) do
			local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
			if skillLine then
				p.skills[skillLine] = rank
			end
		end
	end
	return p
end

-- Reputation with a faction; one not met yet counts as 0.
local function Standing(factionID)
	local data = C_Reputation and C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(factionID)
	if data then
		return data.currentStanding or 0
	end
	return GetFactionInfoByID and select(6, GetFactionInfoByID(factionID)) or 0
end

local function KnowsSpell(spellID)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		return C_SpellBook.IsSpellKnown(spellID)
	end
	return IsPlayerSpell(spellID)
end

local function AnyIn(ids, set)
	for _, id in ipairs(ids or {}) do
		if set[id] then
			return true
		end
	end
	return false
end

local function Doable(p, id)
	local q = db.Quest
	if p.completed[id] or p.log[id] then
		return false
	end
	local flags = Get(q, id, "specialFlags")
	if flags and HasFlag(flags, EVENT) or EVENTS[Get(q, id, "zoneOrSort")] then
		return false
	end
	local races = Get(q, id, "requiredRaces")
	if races and races ~= 0 then
		if p.skyborne and (races == 77 or races == 178) then
			if (races == 77) ~= (p.faction == "Alliance") then
				return false
			end
		elseif not HasFlag(races, p.race) then
			return false
		end
	end
	local classes = Get(q, id, "requiredClasses")
	if classes and classes ~= 0 and not HasFlag(classes, p.class) then
		return false
	end
	if (Get(q, id, "requiredLevel") or 0) > p.level then
		return false
	end
	local maxLevel = Get(q, id, "requiredMaxLevel")
	if maxLevel and maxLevel ~= 0 and p.level > maxLevel then
		return false
	end
	-- One of preQuestSingle done; else all of preQuestGroup, where a quest
	-- also counts as done when one exclusive to it is (unless negative).
	local single = Get(q, id, "preQuestSingle")
	if single then
		if not AnyIn(single, p.completed) then
			return false
		end
	else
		for _, pre in ipairs(Get(q, id, "preQuestGroup") or {}) do
			if pre < 0 then
				if not p.completed[-pre] then
					return false
				end
			elseif not p.completed[pre] and not AnyIn(Get(q, pre, "exclusiveTo"), p.completed) then
				return false
			end
		end
	end
	local minRep = Get(q, id, "requiredMinRep")
	if minRep and Standing(minRep[1]) < minRep[2] then
		return false
	end
	local maxRep = Get(q, id, "requiredMaxRep")
	if maxRep and Standing(maxRep[1]) >= maxRep[2] then
		return false
	end
	local skill = Get(q, id, "requiredSkill")
	if skill and (p.skills[skill[1]] or -1) < (skill[2] or 0) then
		return false
	end
	-- Profession ranks and specialisations are not checked: such quests are left out.
	if Get(q, id, "requiredRanks") then
		return false
	end
	local specialization = Get(q, id, "requiredSpecialization")
	if specialization and specialization > 0 then
		return false
	end
	local parent = Get(q, id, "parentQuest")
	if parent and parent ~= 0 and not p.log[parent] then
		return false
	end
	local nextQuest = Get(q, id, "nextQuestInChain")
	if nextQuest and nextQuest ~= 0 and (p.completed[nextQuest] or p.log[nextQuest]) then
		return false
	end
	local exclusive = Get(q, id, "exclusiveTo")
	if AnyIn(exclusive, p.completed) or AnyIn(exclusive, p.log) then
		return false
	end
	-- A positive spell must be known, a negative one must not.
	local spell = Get(q, id, "requiredSpell")
	if spell and spell ~= 0 and (spell > 0) ~= KnowsSpell(math.abs(spell)) then
		return false
	end
	local breadcrumbFor = Get(q, id, "breadcrumbForQuestId")
	if breadcrumbFor and breadcrumbFor ~= 0 and (p.completed[breadcrumbFor] or p.log[breadcrumbFor]) then
		return false
	end
	if AnyIn(Get(q, id, "breadcrumbs"), p.log) then
		return false
	end
	local disabledBy = Get(q, id, "disabledByQuest")
	if disabledBy and disabledBy ~= 0 and p.log[disabledBy] then
		return false
	end
	local untilDone = Get(q, id, "availableUntilCompleted")
	if untilDone and untilDone ~= 0 and p.completed[untilDone] then
		return false
	end
	local startingWith = Get(q, id, "availableStartingWith")
	if startingWith and startingWith ~= 0 and not (p.completed[startingWith] or p.log[startingWith]) then
		return false
	end
	return true
end

-- Every quest you could pick up now, with who starts it:
-- {questID, name, level, npcs, objects}. Quests started only by an item are
-- left out, having no place. Scanned a slice per frame, then done(list);
-- done(nil) without QuestieDB. A new scan cancels one still running.
local scan = 0
local SLICE = 200

function Q.ScanAvailable(done)
	if not Load() then
		return done(nil)
	end
	scan = scan + 1
	local run = scan
	local ok, ids = pcall(db.Quest.GetAllIds)
	if not ok or type(ids) ~= "table" then
		return done(nil)
	end
	local p = Player()
	local list = {}
	local i = 1
	local function Step()
		if run ~= scan then
			return
		end
		local last = math.min(i + SLICE - 1, #ids)
		for n = i, last do
			local id = ids[n]
			local fine, doable = pcall(Doable, p, id)
			if fine and doable then
				local starters = Get(db.Quest, id, "startedBy")
				local npcs, objects = starters and starters[1], starters and starters[2]
				if npcs or objects then
					local level = Get(db.Quest, id, "questLevel") or 0
					if level == -1 then
						level = math.max(p.level, Get(db.Quest, id, "requiredLevel") or 0)
					end
					list[#list + 1] = { questID = id, name = Get(db.Quest, id, "name") or ("Quest " .. id),
						level = level, npcs = npcs, objects = objects }
				end
			end
		end
		i = last + 1
		if i <= #ids then
			C_Timer.After(0, Step)
		else
			done(list)
		end
	end
	Step()
end
