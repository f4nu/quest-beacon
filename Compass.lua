-- A compass bar at the top of the screen: cardinal points, and a pin for each
-- tracked quest at its bearing. Quests behind you sit at the nearer edge.
-- It follows the way your character faces, not the camera: while the camera
-- swings on its own (left button held), it fades.

local _, ns = ...

local WIDTH, HEIGHT = ns.DEFAULTS.compassWidth, 24   -- width follows the settings
local CAMERA_ALPHA = 0.2   -- the compass while the camera swings away from your facing
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
local bands = {}
for _, spec in ipairs({ { "LEFT", 0, 0.5 }, { "CENTER", 0.5, 0.5 }, { "RIGHT", 0.5, 0 } }) do
	local band = bar:CreateTexture(nil, "BACKGROUND")
	band:SetPoint(spec[1], bar, spec[1], 0, 0)
	band:SetColorTexture(1, 1, 1, 1)
	band:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, spec[2]), CreateColor(0, 0, 0, spec[3]))
	bands[#bands + 1] = band
end

local function Resize(width)
	WIDTH = width
	bar:SetSize(WIDTH, HEIGHT)
	for _, band in ipairs(bands) do
		band:SetSize(WIDTH / 3, HEIGHT)
	end
end
Resize(WIDTH)

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

-- MERGE (px: quests closer than this on the bar share one pin) is a setting.
local LABEL_TOP = 14   -- px from the bar's middle line down to the first row of distances
local LABEL_ROW = 11   -- px between the two rows
local LABEL_GAP = 4    -- px kept clear between labels on one row
-- A distance fades out a quarter of the bar's width from its centre.
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
	pin.icon:SetPoint("CENTER")
	-- Badge and distance hang off the pin's centre, which sits on the bar's
	-- middle line: they stay at one height whatever size the icon is.
	pin.distance = pin:CreateFontString(nil, "OVERLAY")
	pin.distance:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	pin.badge = pin:CreateTexture(nil, "ARTWORK", nil, 1)
	pin.badge:SetTexture(ns.CIRCLE)
	pin.badge:SetVertexColor(0, 0, 0, 0.85)
	pin.badge:SetSize(14, 14)
	pin.badge:SetPoint("CENTER", pin, "CENTER", 11, -9)
	-- The number fills the badge, centred both ways, 1px right: centred
	-- digits still read a touch left in game.
	pin.count = pin:CreateFontString(nil, "OVERLAY")
	pin.count:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
	pin.count:SetPoint("TOPLEFT", pin.badge, "TOPLEFT", 1, 0)
	pin.count:SetPoint("BOTTOMRIGHT", pin.badge, "BOTTOMRIGHT", 1, 0)
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
local alpha = 1

-- Left button held over the world: the camera turns, your character does not.
-- (With the right button, or both, the character turns too.) IsMouselooking()
-- did not report a left-button camera drag in game, so the buttons and what
-- the mouse is over tell instead.
local function OverWorld()
	local focus = GetMouseFoci()[1]
	return focus == nil or focus == WorldFrame
end

local function CameraSwinging()
	return ns.Settings().cameraFade and IsMouseButtonDown("LeftButton") and not IsMouseButtonDown("RightButton")
		and OverWorld()
end

local function Draw(dt)
	local facing = GetPlayerFacing()
	local north, west, instance = ns.PlayerPosition()
	if not facing or not north then
		alpha = 0
		bar:SetAlpha(0)
		return
	end
	-- Ease towards the wanted alpha rather than blink.
	local want = CameraSwinging() and CAMERA_ALPHA or 1
	alpha = alpha + (want - alpha) * math.min(1, dt * 12)
	bar:SetAlpha(alpha)
	local merge = ns.Settings().merge

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

	-- Neighbours within merge px of a group's first quest join it.
	wipe(groups)
	local group
	for _, entry in ipairs(entries) do
		if group and entry.x - group[1].x <= merge and entry.within == group[1].within then
			group[#group + 1] = entry
		else
			group = { entry }
			groups[#groups + 1] = group
		end
	end

	local superTracked = ns.CurrentQuest()
	for i, members in ipairs(groups) do
		table.sort(members, function(a, b) return a.yards < b.yards end)
		-- The pin looks like its nearest quest.
		local nearest = members[1].target
		local x, current = 0, false
		for _, member in ipairs(members) do
			x = x + member.x
			current = current or member.target.questID == superTracked
		end
		x = x / #members
		local many = #members > 1
		local within = members[1].within

		local pin = Pin(i)
		pin.members = members
		local size = (many and 24 or 18) + (current and 6 or 0)
		pin:SetSize(size, size)
		ns.SetQuestIcon(pin.icon, nearest.complete, nearest.kind, size, 1.4, nearest.hard)
		pin:SetFrameLevel(bar:GetFrameLevel() + (current and 3 or 2))
		pin:SetAlpha(within and 1 or 0.45)
		pin.badge:SetShown(many)
		pin.count:SetShown(many)
		pin.count:SetText(#members)
		local badge = #members >= 10 and 17 or 14
		pin.badge:SetSize(badge, badge)
		-- The nearest distance, clear at the centre and fading out towards the
		-- sides: gone with a quarter of the bar left.
		local fade = 1 - math.abs(x) / (WIDTH / 4)
		pin.distance:SetText(within and fade > 0 and ns.Yards(members[1].yards) or "")
		pin.distance:SetAlpha(math.max(fade, 0))
		pin.distance:SetTextColor(current and 1 or 0.8, current and 0.82 or 0.8, current and 0 or 0.8)
		pin.x = x
		-- Whole pixels only: text snaps to the pixel grid while textures glide
		-- between pixels, and the count jittered inside its badge.
		PixelUtil.SetPoint(pin, "CENTER", bar, "CENTER", x, 0)
		pin:Show()
	end
	for i = #groups + 1, #pins do
		pins[i]:Hide()
	end

	-- Labels left to right: one that would touch its left neighbour takes the
	-- other row, so colliding labels alternate upper, lower, upper.
	local previousRight, previousRow
	for i = 1, #groups do
		local pin = pins[i]
		local width = pin.distance:GetStringWidth() or 0
		local row = 0
		if width > 0 then
			if previousRight and pin.x - width / 2 < previousRight + LABEL_GAP then
				row = 1 - previousRow
			end
			previousRight, previousRow = pin.x + width / 2, row
		end
		pin.distance:ClearAllPoints()
		pin.distance:SetPoint("TOP", pin, "CENTER", 0, -(LABEL_TOP + row * LABEL_ROW))
	end
end

local elapsed = 0
bar:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed >= 0.02 then
		Draw(elapsed)
		elapsed = 0
	end
end)

local function Apply()
	local settings = ns.Settings()
	if settings.compassPoint then
		local p = settings.compassPoint
		bar:ClearAllPoints()
		bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	end
	Resize(settings.compassWidth)
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

ns.AddDisplay(Apply)
