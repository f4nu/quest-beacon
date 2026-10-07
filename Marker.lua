-- The marker in the world. The game places one point on screen where its
-- navigation target is (C_Navigation.GetFrame); the marker hangs on it and
-- shows the quest, its next objective and the distance, in place of the
-- game's own diamond. Core decides which quest that is.

local _, ns = ...

local TEX_TURNIN = "Interface\\GossipFrame\\ActiveQuestIcon"
local TEX_PROGRESS = "Interface\\GossipFrame\\IncompleteQuestIcon"

local marker = CreateFrame("Frame", "QuestBeaconMarker", UIParent)
marker:SetSize(28, 28)
marker:SetFrameStrata("LOW")
marker:SetClampedToScreen(true)
marker:EnableMouse(false)
marker:Hide()

local disc = marker:CreateTexture(nil, "BACKGROUND")
disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
disc:SetVertexColor(0, 0, 0, 0.55)
disc:SetSize(36, 36)
disc:SetPoint("CENTER")

local icon = marker:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()

local detail = marker:CreateFontString(nil, "OVERLAY")
detail:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
detail:SetTextColor(0.85, 0.85, 0.85)
detail:SetPoint("BOTTOM", marker, "TOP", 0, 4)

local title = marker:CreateFontString(nil, "OVERLAY")
title:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
title:SetTextColor(1, 0.82, 0)
title:SetPoint("BOTTOM", detail, "TOP", 0, 2)

local distance = marker:CreateFontString(nil, "OVERLAY")
distance:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
distance:SetTextColor(1, 1, 1)
distance:SetPoint("TOP", marker, "BOTTOM", 0, -3)

-- The game's own marker stays hidden while ours shows. Its frame shows itself
-- again whenever the game creates a navigation frame, so it is hidden each time.
local hideGame = false
local hooked = false

local function SetGameMarkerHidden(hidden)
	local frame = SuperTrackedFrame
	if not frame or hidden == hideGame then
		return
	end
	hideGame = hidden
	if not hooked then
		hooked = true
		local function Keep(self)
			if hideGame and self:IsShown() then
				self:Hide()
			end
		end
		hooksecurefunc(frame, "Show", Keep)
		hooksecurefunc(frame, "SetShown", Keep)
	end
	if hidden then
		frame:Hide()
	elseif frame.navFrame then
		frame:Show()
	end
end

local function Off()
	marker:Hide()
	SetGameMarkerHidden(false)
end

local anchoredTo
local updater = CreateFrame("Frame")
local elapsed = 0
updater:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.03 then
		return
	end
	elapsed = 0

	if not ns.Settings().marker then
		return Off()
	end
	local nav = C_Navigation.GetFrame()
	local questID = C_SuperTrack.GetSuperTrackedQuestID()
	if not nav or not questID or questID == 0 then
		return Off()
	end

	-- A quest in another instance: the game still navigates to it, but draws the
	-- point in this instance's space, where it means nothing (the Deeprun Tram,
	-- quest in Stormwind: 8.6k yd). Same where the game has no map for where you
	-- are and the quest's place is unknown. Show neither marker.
	local target = ns.byQuest[questID]
	local elsewhere
	if target and target.instance then
		elsewhere = target.instance ~= ns.Instance()
	else
		elsewhere = C_Map.GetBestMapForUnit("player") == nil
	end
	if elsewhere then
		marker:Hide()
		SetGameMarkerHidden(true)
		return
	end

	if anchoredTo ~= nav then
		marker:ClearAllPoints()
		marker:SetPoint("CENTER", nav, "CENTER")
		anchoredTo = nav
	end

	local questTitle, complete, objective
	if target then
		questTitle, complete, objective = target.title, target.complete, target.detail
	else
		questTitle, complete, objective = ns.Describe(questID)
	end

	local clamped = C_Navigation.WasClampedToScreen()
	icon:SetTexture(complete and TEX_TURNIN or TEX_PROGRESS)
	title:SetText(questTitle)
	detail:SetText(objective or "")
	title:SetShown(not clamped)
	detail:SetShown(not clamped)

	local yards = C_Navigation.GetDistance()
	distance:SetText(yards and yards > 0 and ("%d yd"):format(math.floor(yards)) or "")
	-- Fade out on arrival rather than sit on top of the target.
	marker:SetAlpha(yards and yards < 15 and math.max(0.25, yards / 15) or 1)

	marker:Show()
	SetGameMarkerHidden(true)
end)

local previous = ns.OnSettingsChanged
function ns.OnSettingsChanged()
	if previous then
		previous()
	end
	if not ns.Settings().marker then
		Off()
	end
end
