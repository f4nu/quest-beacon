-- A compass bar at the top of the screen: cardinal points, and a pin for each
-- tracked quest at its bearing. Quests behind you sit at the nearer edge.
-- It follows the way your character faces, not the camera.

local _, ns = ...

local WIDTH, HEIGHT = 560, 24
local SPAN = math.pi / 2          -- radians from the centre to either end of the bar
local TWO_PI = 2 * math.pi
local TEX_TURNIN = "Interface\\GossipFrame\\ActiveQuestIcon"
local TEX_PROGRESS = "Interface\\GossipFrame\\IncompleteQuestIcon"

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

local pins = {}

local function Pin(i)
	local pin = pins[i]
	if pin then
		return pin
	end
	pin = CreateFrame("Button", nil, bar)
	pin:SetSize(18, 18)
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.icon:SetAllPoints()
	pin.distance = pin:CreateFontString(nil, "OVERLAY")
	pin.distance:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	pin.distance:SetPoint("TOP", pin, "BOTTOM", 0, -2)
	pin:SetScript("OnClick", function(self)
		ns.Pick(self.target.questID)
	end)
	pin:SetScript("OnEnter", function(self)
		local target = self.target
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(target.title, 1, 0.82, 0)
		if target.detail then
			GameTooltip:AddLine(target.detail, 1, 1, 1, true)
		end
		if self.yards then
			GameTooltip:AddLine(("%d yd"):format(math.floor(self.yards)), 0.7, 0.7, 0.7)
		end
		GameTooltip:AddLine("Click to navigate here", 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pins[i] = pin
	return pin
end

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

	local superTracked = C_SuperTrack.GetSuperTrackedQuestID()
	local used = 0
	for _, target in ipairs(ns.targets) do
		if target.north and target.instance == instance then
			used = used + 1
			local pin = Pin(used)
			local yards, bearing = ns.Measure(target, north, west)
			local x, within = Offset(bearing, facing)
			local current = target.questID == superTracked
			pin.target, pin.yards = target, yards
			pin.icon:SetTexture(target.complete and TEX_TURNIN or TEX_PROGRESS)
			pin:SetSize(current and 24 or 18, current and 24 or 18)
			pin:SetFrameLevel(bar:GetFrameLevel() + (current and 3 or 2))
			pin:SetAlpha(within and 1 or 0.45)
			pin.distance:SetText(within and ("%d"):format(math.floor(yards)) or "")
			pin.distance:SetTextColor(current and 1 or 0.8, current and 0.82 or 0.8, current and 0 or 0.8)
			pin:SetPoint("CENTER", bar, "CENTER", x, 0)
			pin:Show()
		end
	end
	for i = used + 1, #pins do
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
