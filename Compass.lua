-- A compass bar at the top of the screen: cardinal points, and a pin for each
-- tracked quest at its bearing. Quests behind you sit at the nearer edge.
-- It follows the way your character faces, not the camera.

local _, ns = ...

local WIDTH, HEIGHT = 560, 24
local SPAN = math.pi / 2          -- radians from the centre to either end of the bar
local TWO_PI = 2 * math.pi

-- Bearings counter-clockwise from north, as GetPlayerFacing measures them.
local CARDINALS = {
	{ "N", 0 }, { "NW", math.pi / 4 }, { "W", math.pi / 2 }, { "SW", 3 * math.pi / 4 },
	{ "S", math.pi }, { "SE", 5 * math.pi / 4 }, { "E", 3 * math.pi / 2 }, { "NE", 7 * math.pi / 4 },
}

-- Horizontal offset from the bar's centre, and whether it lies within the bar.
local function Offset(bearing, facing)
	local relative = (bearing - facing + math.pi) % TWO_PI - math.pi   -- positive: to the left
	local within = math.abs(relative) <= SPAN
	if not within then
		relative = relative > 0 and SPAN or -SPAN
	end
	return -relative / SPAN * (WIDTH / 2), within
end

local bar = CreateFrame("Frame", "QuestBeaconCompass", UIParent)
bar:SetSize(WIDTH, HEIGHT)
bar:SetPoint("TOP", UIParent, "TOP", 0, -14)
bar:SetFrameStrata("LOW")
bar:SetClampedToScreen(true)
bar:SetMovable(true)
bar:Hide()

-- Dark band fading out at both ends.
local third = WIDTH / 3
for i, spec in ipairs({ { "LEFT", 0, 0, 0.5 }, { "CENTER", 0, 0.5, 0.5 }, { "RIGHT", 0, 0.5, 0 } }) do
	local band = bar:CreateTexture(nil, "BACKGROUND")
	band:SetSize(third, HEIGHT)
	band:SetPoint(spec[1], bar, spec[1], spec[2], 0)
	band:SetColorTexture(1, 1, 1, 1)
	band:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, spec[3]), CreateColor(0, 0, 0, spec[4]))
end

local centre = bar:CreateTexture(nil, "ARTWORK")
centre:SetColorTexture(1, 0.82, 0, 0.9)
centre:SetSize(2, HEIGHT)
centre:SetPoint("CENTER")

local cardinals = {}
for _, spec in ipairs(CARDINALS) do
	local label = bar:CreateFontString(nil, "ARTWORK")
	label:SetFont(STANDARD_TEXT_FONT, #spec[1] == 1 and 13 or 10, "OUTLINE")
	label:SetText(spec[1])
	label:SetTextColor(#spec[1] == 1 and 1 or 0.7, #spec[1] == 1 and 0.82 or 0.7, #spec[1] == 1 and 0 or 0.7)
	label.bearing = spec[2]
	cardinals[#cardinals + 1] = label
end

local MERGE = 26   -- px: quests closer than this on the bar share one pin
local pins = {}
local tips = {}

local function Tip(i)
	if not tips[i] then
		tips[i] = CreateFrame("GameTooltip", "QuestBeaconTooltip" .. i, UIParent, "GameTooltipTemplate")
	end
	return tips[i]
end

local function HideTips()
	for _, tip in ipairs(tips) do
		tip:Hide()
	end
end

-- One tooltip per quest, nearest first, stacked under the pin.
local function ShowTips(pin)
	HideTips()
	for i, member in ipairs(pin.members) do
		local tip = Tip(i)
		tip:SetOwner(pin, "ANCHOR_NONE")
		tip:ClearAllPoints()
		if i == 1 then
			tip:SetPoint("TOP", pin, "BOTTOM", 0, -16)
		else
			tip:SetPoint("TOP", tips[i - 1], "BOTTOM", 0, -4)
		end
		local target = member.target
		tip:AddLine(target.title, 1, 0.82, 0)
		if target.detail then
			tip:AddLine(target.detail, 1, 1, 1, true)
		end
		tip:AddLine(("%d yd"):format(math.floor(member.yards)), 0.7, 0.7, 0.7)
		if i == #pin.members then
			tip:AddLine(#pin.members > 1 and "Click to navigate to the nearest" or "Click to navigate here", 0.5, 0.5, 0.5)
		end
		tip:Show()
	end
end

local function Pin(i)
	local pin = pins[i]
	if pin then
		return pin
	end
	pin = CreateFrame("Button", nil, bar)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetAllPoints()
	pin.distance = pin:CreateFontString(nil, "OVERLAY")
	pin.distance:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	pin.distance:SetPoint("TOP", pin, "BOTTOM", 0, -2)
	pin.badge = pin:CreateTexture(nil, "ARTWORK", nil, 1)
	pin.badge:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	pin.badge:SetVertexColor(0, 0, 0, 0.85)
	pin.badge:SetSize(14, 14)
	pin.badge:SetPoint("CENTER", pin, "BOTTOMRIGHT", -1, 3)
	-- The number fills the badge and is centred in it both ways; a free-floating
	-- string sits off centre by its own rounding.
	pin.count = pin:CreateFontString(nil, "OVERLAY")
	pin.count:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
	pin.count:SetAllPoints(pin.badge)
	pin.count:SetJustifyH("CENTER")
	pin.count:SetJustifyV("MIDDLE")
	pin:SetScript("OnClick", function(self)
		ns.Pick(self.members[1].target.questID)
	end)
	pin:SetScript("OnEnter", ShowTips)
	pin:SetScript("OnLeave", HideTips)
	pins[i] = pin
	return pin
end

local entries, groups = {}, {}

local function Draw()
	local facing = GetPlayerFacing()
	local north, west, instance = ns.PlayerPosition()
	if not facing or not north then
		bar:SetAlpha(0)
		return
	end
	bar:SetAlpha(1)

	for _, label in ipairs(cardinals) do
		local x, within = Offset(label.bearing, facing)
		label:SetShown(within)
		label:SetPoint("CENTER", bar, "CENTER", x, 0)
	end

	-- Every located quest, left to right on the bar.
	wipe(entries)
	for _, target in ipairs(ns.targets) do
		if target.north and target.instance == instance then
			local yards, bearing = ns.Measure(target, north, west)
			local x, within = Offset(bearing, facing)
			entries[#entries + 1] = { target = target, yards = yards, x = x, within = within }
		end
	end
	table.sort(entries, function(a, b) return a.x < b.x end)

	-- Neighbours within MERGE px of a group's first quest join it.
	wipe(groups)
	local group
	for _, entry in ipairs(entries) do
		if group and entry.x - group[1].x <= MERGE and entry.within == group[1].within then
			group[#group + 1] = entry
		else
			group = { entry }
			groups[#groups + 1] = group
		end
	end

	local superTracked = C_SuperTrack.GetSuperTrackedQuestID()
	for i, members in ipairs(groups) do
		table.sort(members, function(a, b) return a.yards < b.yards end)
		local x, complete, current = 0, false, false
		for _, member in ipairs(members) do
			x = x + member.x
			complete = complete or member.target.complete
			current = current or member.target.questID == superTracked
		end
		x = x / #members
		local many = #members > 1
		local within = members[1].within

		local pin = Pin(i)
		pin.members = members
		ns.SetQuestIcon(pin.icon, complete)
		local size = (many and 24 or 18) + (current and 6 or 0)
		pin:SetSize(size, size)
		pin:SetFrameLevel(bar:GetFrameLevel() + (current and 3 or 2))
		pin:SetAlpha(within and 1 or 0.45)
		pin.badge:SetShown(many)
		pin.count:SetShown(many)
		pin.count:SetText(#members)
		local badge = #members >= 10 and 17 or 14
		pin.badge:SetSize(badge, badge)
		local near, far = math.floor(members[1].yards), math.floor(members[#members].yards)
		pin.distance:SetText(not within and "" or (many and near ~= far) and ("%d-%d"):format(near, far) or near)
		pin.distance:SetTextColor(current and 1 or 0.8, current and 0.82 or 0.8, current and 0 or 0.8)
		pin:SetPoint("CENTER", bar, "CENTER", x, 0)
		pin:Show()
	end
	for i = #groups + 1, #pins do
		pins[i]:Hide()
	end
end

local elapsed = 0
bar:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed >= 0.02 then
		elapsed = 0
		Draw()
	end
end)

local function Apply()
	local settings = ns.Settings()
	if settings.compassPoint then
		local p = settings.compassPoint
		bar:ClearAllPoints()
		bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	end
	bar:SetShown(settings.compass)
end

-- Drag mode: /qb move to unlock, again to lock.
local moving = false
bar:SetScript("OnDragStart", bar.StartMoving)
bar:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, relativePoint, x, y = self:GetPoint()
	QuestBeaconDB.compassPoint = { point, relativePoint, x, y }
end)

function ns.ToggleMove()
	moving = not moving
	bar:EnableMouse(moving)
	if moving then
		bar:RegisterForDrag("LeftButton")
	else
		bar:RegisterForDrag()
	end
	print("Quest Beacon: compass " .. (moving and "unlocked, drag it" or "locked"))
end

local previous = ns.OnSettingsChanged
function ns.OnSettingsChanged()
	if previous then
		previous()
	end
	Apply()
end
