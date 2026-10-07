-- The settings page (Options > AddOns > Quest Beacon) and the minimap button.
--
-- The button is a LibDataBroker launcher shown through LibDBIcon, which is
-- what minimap button collectors (Leatrix Plus, MinimapButtonButton, MBB and
-- the like) gather, and what Broker displays show.

local ADDON, ns = ...

local category

-- Where the minimap icon's centre goes, from the button's centre.
local MINIMAP_ICON_OFFSET_X, MINIMAP_ICON_OFFSET_Y = 1.5, -1

function ns.OpenSettings()
	if category then
		Settings.OpenToCategory(category:GetID())
	end
end

local function Checkbox(key, name, tooltip)
	local setting = Settings.RegisterAddOnSetting(category, "QuestBeacon_" .. key, key, QuestBeaconDB,
		type(ns.DEFAULTS[key]), name, ns.DEFAULTS[key])
	setting:SetValueChangedCallback(ns.OnSettingsChanged)
	Settings.CreateCheckbox(category, setting, tooltip)
end

local function Slider(key, name, tooltip, low, high, step)
	local setting = Settings.RegisterAddOnSetting(category, "QuestBeacon_" .. key, key, QuestBeaconDB,
		type(ns.DEFAULTS[key]), name, ns.DEFAULTS[key])
	setting:SetValueChangedCallback(ns.OnSettingsChanged)
	local options = Settings.CreateSliderOptions(low, high, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return ("%d px"):format(math.floor(value))
	end)
	Settings.CreateSlider(category, setting, options, tooltip)
end

local icon = LibStub("LibDBIcon-1.0")

local function CreateSettings()
	category = Settings.RegisterVerticalLayoutCategory("Quest Beacon")

	Checkbox("compass", "Compass", "A bar at the top of the screen with a pin for every tracked quest.")
	Checkbox("marker", "World marker",
		"A marker in the world on the quest the game navigates to, with its next objective and the distance.")
	Checkbox("auto", "Navigate to the nearest quest",
		"Navigation switches to the nearest tracked quest as you move. A quest you pick yourself is kept until it leaves your log.")
	Checkbox("questie", "Use QuestieDB locations",
		"Point at the nearest spawn of what a quest still needs, or of whoever takes it in, instead of the game's quest area. "
		.. (ns.Questie.Available() and "QuestieDB is installed." or "Needs the QuestieDB addon, which is not installed."))
	Checkbox("cameraFade", "Fade the compass while turning the camera",
		"The compass follows your character. While you swing the camera with the left mouse button it no longer matches the view, so it fades.")
	Checkbox("taxiFade", "Hide the compass on flight paths",
		"The compass fades out while you fly a flight path, and comes back when you land.")
	Slider("compassWidth", "Compass width", "Width of the compass bar.", 300, 1200, 20)
	Slider("merge", "Group quests closer than",
		"Quests closer than this on the compass share one pin, with a count.", 10, 60, 2)

	local minimap = Settings.RegisterProxySetting(category, "QuestBeacon_minimap", "boolean", "Minimap button", true,
		function()
			return not QuestBeaconDB.minimap.hide
		end,
		function(value)
			QuestBeaconDB.minimap.hide = not value
			if value then
				icon:Show(ADDON)
			else
				icon:Hide(ADDON)
			end
		end)
	Settings.CreateCheckbox(category, minimap, "Show the Quest Beacon button on the minimap.")

	Settings.RegisterAddOnCategory(category)
end

local function CreateMinimapButton()
	local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON, {
		type = "launcher",
		label = "Quest Beacon",
		icon = ns.ICON,
		OnClick = function(_, button)
			if button == "RightButton" then
				QuestBeaconDB.compass = not QuestBeaconDB.compass
				ns.OnSettingsChanged()
			else
				ns.OpenSettings()
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("Quest Beacon")
			tooltip:AddLine("Left-click: settings", 1, 1, 1)
			tooltip:AddLine("Right-click: compass on/off", 1, 1, 1)
		end,
	})
	icon:Register(ADDON, launcher, QuestBeaconDB.minimap)

	-- Outside the retail client LibDBIcon lays a square icon out at (7,-6),
	-- left of and above the ring's centre; a round icon shows it. Centre ours
	-- on the ring (measured in game).
	local button = icon:GetMinimapButton(ADDON)
	if button and button.icon and WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then
		button.icon:ClearAllPoints()
		button.icon:SetPoint("CENTER", button, "CENTER", MINIMAP_ICON_OFFSET_X, MINIMAP_ICON_OFFSET_Y)
	end
end

table.insert(ns.onLoad, function()
	CreateSettings()
	CreateMinimapButton()
end)
