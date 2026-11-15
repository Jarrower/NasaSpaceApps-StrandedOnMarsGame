--[[
	MissionClient  (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > MissionClient
	Child:    MissionUI (ModuleScript) - theme + widgets

	Everything the player sees in Mars Base 7 (Config.GameMode = "Mission").
	The server decides everything; this script only draws:
	  - Title screen (Start Mission) with 3 how-to cards
	  - HUD: sol + timer, Oxygen / Food / Health / Fuel, power cells, station list
	  - Sol banner, solar storm + micrometeorite alerts, toasts
	  - End-of-sol report, "Did you know?" card
	  - Victory and failure screens
	  - Camera shots of the lander touching down and the rocket launching
	It reads ReplicatedStorage > MissionState attributes and listens to
	BaseRemotes > MissionEvent.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("BaseShared"):WaitForChild("Config"))
if Config.GameMode ~= "Mission" then
	return
end
local MC = Config.Mission
local UI = require(script:WaitForChild("MissionUI"))
local THEME, create, label = UI.THEME, UI.create, UI.label

local state = ReplicatedStorage:WaitForChild("MissionState")
local remotes = ReplicatedStorage:WaitForChild("BaseRemotes")
local MissionEvent = remotes:WaitForChild("MissionEvent")
local MissionAction = remotes:WaitForChild("MissionAction")
local Notify = remotes:WaitForChild("Notify")
local camera = workspace.CurrentCamera

task.spawn(function()
	for _ = 1, 10 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
			break
		end
		task.wait(1)
	end
end)

local function attr(name, default)
	local v = state:GetAttribute(name)
	if v == nil then
		return default
	end
	return v
end
local function now()
	return workspace:GetServerTimeNow()
end
local function act(action)
	local ok, a, b = pcall(MissionAction.InvokeServer, MissionAction, action)
	return ok and a, b
end

------------------------------------------------------------------ sounds
local sounds = {}
for key, id in pairs(MC.Sounds or {}) do
	if id then
		sounds[key] = create("Sound", { SoundId = id, Volume = 0.6, Parent = SoundService })
	end
end
local function play(key, pitch)
	local s = sounds[key]
	if s then
		s.PlaybackSpeed = pitch or 1
		SoundService:PlayLocalSound(s)
	end
end

------------------------------------------------------------------ root gui
local gui = create("ScreenGui", {
	Name = "MissionHUD", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui"),
})
-- Everything is laid out for a 1366x768 screen. The root frame is sized to
-- (screen / scale) and a UIScale inside it shrinks or grows it back to fill the
-- screen, so the UI looks the same on a laptop, a big monitor or a phone.
local root = create("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(1366, 768), ZIndex = 2, Parent = gui,
})
local scale = create("UIScale", { Parent = root })
local function rescale()
	local vp = camera.ViewportSize
	scale.Scale = math.clamp(math.min(vp.X / 1366, vp.Y / 768), 0.5, 1.25)
	root.Size = UDim2.fromOffset(vp.X / scale.Scale, vp.Y / scale.Scale)
end
rescale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

------------------------------------------------------------------ red edges (solar storm)
local edges = {}
local function edge(size, pos, rotation)
	local f = create("Frame", { Size = size, Position = pos, BackgroundColor3 = THEME.Bad, BorderSizePixel = 0, BackgroundTransparency = 1, ZIndex = 1, Parent = gui })
	create("UIGradient", { Rotation = rotation, Transparency = NumberSequence.new(0, 1), Parent = f })
	table.insert(edges, f)
end
edge(UDim2.new(1, 0, 0.2, 0), UDim2.new(0, 0, 0, 0), 90)
edge(UDim2.new(1, 0, 0.2, 0), UDim2.new(0, 0, 0.8, 0), -90)
edge(UDim2.new(0.14, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0)
edge(UDim2.new(0.14, 0, 1, 0), UDim2.new(0.86, 0, 0, 0), 180)

------------------------------------------------------------------ HUD
local hud = create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = root })

-- top: sol + timer
local top = UI.panel(hud, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(440, 78) })
local solText = label(top, { Text = "SOL 1 / 7", Font = THEME.Black, TextSize = 28, TextColor3 = THEME.Accent, Position = UDim2.fromOffset(18, 8), Size = UDim2.fromOffset(220, 34) })
local timerText = label(top, { Text = "1:00", Font = THEME.Black, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -138, 0, 8), Size = UDim2.fromOffset(120, 34) })
local phaseText = label(top, { Text = "", TextSize = 15, TextColor3 = THEME.Sub, Position = UDim2.fromOffset(18, 42), Size = UDim2.new(1, -36, 0, 18) })
local timeBack = create("Frame", { BackgroundColor3 = THEME.Inset, Position = UDim2.new(0, 18, 1, -14), Size = UDim2.new(1, -36, 0, 6), Parent = top })
UI.corner(timeBack, 3)
local timeFill = create("Frame", { BackgroundColor3 = THEME.Accent, Size = UDim2.fromScale(1, 1), Parent = timeBack })
UI.corner(timeFill, 3)

-- left: meters
local meterPanel = UI.panel(hud, { Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(300, 262) })
UI.pad(meterPanel, 16, 12)
UI.list(meterPanel, 6)
label(meterPanel, { Text = "CREW STATUS", Font = THEME.Bold, TextSize = 14, TextColor3 = THEME.Sub, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 0 })
local setMeter = {}
for i, key in ipairs({ "Oxygen", "Food", "Health" }) do
	local m = MC.Meters[key]
	setMeter[key] = UI.meter(meterPanel, m.Icon, m.Name, m.Color, i)
end
local fuelRow = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 9, Parent = meterPanel })
local fuelLabel = label(fuelRow, { Text = "⛽ Rocket fuel  0 / " .. MC.FuelNeeded, Font = THEME.Bold, TextSize = 18, Size = UDim2.new(1, 0, 0, 22) })
local fuelSegs = create("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 14), Parent = fuelRow })
UI.list(fuelSegs, 4, true)
local segs = {}
for i = 1, MC.FuelNeeded do
	local s = create("Frame", { BackgroundColor3 = THEME.Inset, Size = UDim2.new(1 / MC.FuelNeeded, -4, 1, 0), LayoutOrder = i, Parent = fuelSegs })
	UI.corner(s, 5)
	segs[i] = s
end

-- right: stations
local stationPanel = UI.panel(hud, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(300, 46 + 52 * #MC.Stations) })
UI.pad(stationPanel, 14, 12)
UI.list(stationPanel, 6)
label(stationPanel, { Text = "STATIONS", Font = THEME.Bold, TextSize = 14, TextColor3 = THEME.Sub, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 0 })
local stationRows = {}
for i, d in ipairs(MC.Stations) do
	local row = create("Frame", { BackgroundColor3 = THEME.Card, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = i, Parent = stationPanel })
	UI.corner(row, 10)
	label(row, { Text = d.Icon .. " " .. d.Name, Font = THEME.Bold, TextSize = 17, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -90, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
	local by = label(row, { Text = "", TextSize = 13, TextColor3 = THEME.Sub, Position = UDim2.fromOffset(10, 25), Size = UDim2.new(1, -90, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
	local chip = create("TextLabel", {
		Text = "OFF", Font = THEME.Black, TextSize = 15, TextColor3 = THEME.Bad, BackgroundColor3 = THEME.Inset,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(64, 28), Parent = row,
	})
	UI.corner(chip, 8)
	local rs = UI.stroke(row, d.Color, 1, 2)
	stationRows[d.Id] = { Chip = chip, By = by, Stroke = rs }
end

-- bottom: power cells
local cellPanel = UI.panel(hud, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(470, 98) })
label(cellPanel, { Text = "POWER CELLS", Font = THEME.Bold, TextSize = 14, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 18) })
local cellRow = create("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 34), Parent = cellPanel })
UI.list(cellRow, 10, true, Enum.HorizontalAlignment.Center)
local cellHint = label(cellPanel, { Text = "", TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(10, 66), Size = UDim2.new(1, -20, 0, 22) })
local cellIcons = {}
local function setCells(total, usedN)
	while #cellIcons < total do
		local c = create("Frame", { Size = UDim2.fromOffset(26, 34), LayoutOrder = #cellIcons + 1, Parent = cellRow })
		UI.corner(c, 6)
		create("UIStroke", { Color = THEME.Accent, Thickness = 2, Parent = c })
		create("Frame", { Name = "Cap", BackgroundColor3 = THEME.Accent, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -1), Size = UDim2.fromOffset(10, 4), Parent = c })
		table.insert(cellIcons, c)
	end
	for i, c in ipairs(cellIcons) do
		c.Visible = i <= total
		local free = i <= total - usedN
		c.BackgroundColor3 = free and THEME.Accent or THEME.Inset
		c.BackgroundTransparency = free and 0 or 0.2
	end
	local free = total - usedN
	if attr("StationsLocked", true) then
		cellHint.Text = "Cells reset at the start of each sol"
		cellHint.TextColor3 = THEME.Sub
	elseif free > 0 then
		cellHint.Text = string.format("%d of %d free: walk to a station and press E", free, total)
		cellHint.TextColor3 = THEME.Text
	else
		cellHint.Text = "All cells in use. Press E at a station to unplug one."
		cellHint.TextColor3 = THEME.Warn
	end
end

------------------------------------------------------------------ banner
local banner = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(700, 100), Visible = false, ZIndex = 5 })
local bannerStroke = banner:FindFirstChildOfClass("UIStroke")
local bannerTitle = label(banner, { Text = "", Font = THEME.Black, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 38) })
local bannerSub = label(banner, { Text = "", TextSize = 19, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(16, 52), Size = UDim2.new(1, -32, 0, 40) })
local bannerToken = 0
local function showBanner(title, sub, color, seconds)
	bannerToken += 1
	local my = bannerToken
	bannerTitle.Text, bannerSub.Text = title or "", sub or ""
	bannerTitle.TextColor3 = color or THEME.Accent
	bannerStroke.Color, bannerStroke.Transparency = color or THEME.Accent, 0.2
	banner.Visible = true
	banner.Position = UDim2.new(0.5, 0, 0, 70)
	UI.tween(banner, { Position = UDim2.new(0.5, 0, 0, 104) }, UI.SLIDE)
	task.delay(seconds or MC.BannerTime, function()
		if my == bannerToken then
			banner.Visible = false
		end
	end)
end

------------------------------------------------------------------ alert card (storm / leak)
local alert = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 216), Size = UDim2.fromOffset(620, 150), Visible = false, ZIndex = 6 })
local alertStroke = alert:FindFirstChildOfClass("UIStroke")
local alertTitle = label(alert, { Text = "", Font = THEME.Black, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 36) })
local alertSub = label(alert, { Text = "", TextSize = 19, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(16, 48), Size = UDim2.new(1, -32, 0, 26) })
local alertCount = label(alert, { Text = "", Font = THEME.Black, TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(16, 76), Size = UDim2.new(1, -32, 0, 44) })
local alertInfo = label(alert, { Text = "", Font = THEME.Bold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(16, 120), Size = UDim2.new(1, -32, 0, 22) })
local alertMode = nil -- "SolarStorm" | "Micrometeorite" | "Result"
local alertToken = 0
local function hideAlert()
	alertMode = nil
	alert.Visible = false
end
local function showResult(text, good)
	alertToken += 1
	local my = alertToken
	alertMode = "Result"
	alert.Visible = true
	alertStroke.Color = good and THEME.Good or THEME.Bad
	alertTitle.Text = good and "Great job, crew!" or "Ouch!"
	alertTitle.TextColor3 = good and THEME.Good or THEME.Bad
	alertSub.Text = text
	alertCount.Text, alertInfo.Text = "", ""
	task.delay(5, function()
		if my == alertToken and alertMode == "Result" then
			hideAlert()
		end
	end)
end

-- world marker (bunker / leak) that shows through walls
local markerPart = create("Part", { Name = "MissionMarker", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.one, Parent = workspace.CurrentCamera })
local marker = create("BillboardGui", { Name = "MissionMarker", Size = UDim2.fromOffset(220, 60), AlwaysOnTop = true, LightInfluence = 0, Enabled = false, ResetOnSpawn = false, Adornee = markerPart, Parent = player:WaitForChild("PlayerGui") })
local markerFrame = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.1, Parent = marker })
UI.corner(markerFrame, 10)
local markerStroke = UI.stroke(markerFrame, THEME.Bad, 0, 2)
local markerText = label(markerFrame, { Text = "", Font = THEME.Black, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 2) })
local markerDist = label(markerFrame, { Text = "", Font = THEME.Bold, TextSize = 15, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 34) })
local function showMarker(pos, text, color)
	if not pos then
		marker.Enabled = false
		return
	end
	markerPart.CFrame = CFrame.new(pos + Vector3.new(0, 6, 0))
	markerText.Text = text
	markerText.TextColor3 = color
	markerStroke.Color = color
	marker.Enabled = true
end

------------------------------------------------------------------ toasts
local toastHolder = create("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(380, 300), ZIndex = 8, Parent = root })
create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Parent = toastHolder })
local toastN = 0
local function toast(text, kind)
	if not text or text == "" then
		return
	end
	toastN += 1
	local color = (kind == "good" and THEME.Good) or (kind == "bad" and THEME.Bad) or THEME.Info
	local card = create("Frame", { BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.05, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = toastN, Parent = toastHolder })
	UI.corner(card, 10)
	create("Frame", { BackgroundColor3 = color, Size = UDim2.new(0, 5, 1, 0), BorderSizePixel = 0, Parent = card })
	local l = label(card, { Text = text, TextSize = 16, AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -26, 0, 0) })
	UI.pad(l, 0, 10, 0, 10)
	local cards = {}
	for _, c in ipairs(toastHolder:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(cards, c)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder > b.LayoutOrder
	end)
	for i = 5, #cards do
		cards[i]:Destroy()
	end
	task.delay(4, function()
		if card.Parent then
			card:Destroy()
		end
	end)
end
Notify.OnClientEvent:Connect(function(msg)
	local lower = string.lower(tostring(msg))
	toast(msg, (lower:find("no ") or lower:find("locked") or lower:find("wait")) and "bad" or "info")
end)

------------------------------------------------------------------ modal cards
local dim = create("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1.2, 1.2), Visible = false, ZIndex = 9, Parent = root })
local modals = {}
local lastPhase -- last mission phase the screens were updated for
local function modal(w, h)
	local f = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, h), Visible = false, ZIndex = 10 })
	table.insert(modals, f)
	return f
end
local function showModal(f, dimmed)
	for _, m in ipairs(modals) do
		m.Visible = m == f
	end
	dim.Visible = f ~= nil and dimmed ~= false
	if f then
		f.Position = UDim2.new(0.5, 0, 0.5, 30)
		UI.tween(f, { Position = UDim2.fromScale(0.5, 0.5) }, UI.SLIDE)
	end
end
local function clear(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if not c:IsA("UICorner") and not c:IsA("UIStroke") then -- padding/layout are re-added by each screen
			c:Destroy()
		end
	end
end
local function readyButton(parent, text)
	local b
	b = UI.button(parent, text or "Next  ▶", THEME.Accent, function()
		act("Ready")
		b.Text = "Waiting for crew..."
		b.BackgroundColor3 = THEME.Card
	end, { Size = UDim2.fromOffset(240, 50), TextSize = 20, LayoutOrder = 99 })
	return b
end

-- TITLE SCREEN
local lobby = modal(1000, 670)
do
	UI.pad(lobby, 30, 24)
	UI.list(lobby, 12, false, Enum.HorizontalAlignment.Center)
	label(lobby, { Text = "MARS BASE 7", Font = THEME.Black, TextSize = 72, TextColor3 = THEME.Accent, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 80), LayoutOrder = 1 })
	label(lobby, { Text = "Junior Astronaut Mission Trainer", Font = THEME.Bold, TextSize = 22, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 2 })
	label(lobby, {
		Text = string.format("Keep the outpost alive for %d sols (Mars days), make %d rocket fuel, and fly home!", MC.Sols, MC.FuelNeeded),
		TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 3,
	})
	local cards = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 190), LayoutOrder = 4, Parent = lobby })
	UI.list(cards, 16, true, Enum.HorizontalAlignment.Center)
	local how = {
		{ "🔋  Power", string.format("Each sol the crew gets %d power cells. But %d stations need power!", MC.StartCells, #MC.Stations) },
		{ "⚡  Plug in", "Walk to a station's Power Port and press E to plug in a cell. Press E again to unplug it." },
		{ "🚀  Survive", "Keep Oxygen, Food and Health above 0. Watch out for dust storms, solar storms and space rocks!" },
	}
	for i, h in ipairs(how) do
		local c = create("Frame", { BackgroundColor3 = THEME.Card, Size = UDim2.fromOffset(292, 190), LayoutOrder = i, Parent = cards })
		UI.corner(c, 12)
		UI.pad(c, 16, 14)
		label(c, { Text = h[1], Font = THEME.Black, TextSize = 24, TextColor3 = THEME.Accent, Size = UDim2.new(1, 0, 0, 32) })
		label(c, { Text = h[2], TextSize = 19, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40), TextYAlignment = Enum.TextYAlignment.Top })
	end
	local crew = label(lobby, { Name = "Crew", Text = "", TextSize = 18, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 5 })
	local function updateCrew()
		local names = {}
		for _, p in ipairs(Players:GetPlayers()) do
			table.insert(names, p.DisplayName)
		end
		crew.Text = "Crew: " .. table.concat(names, ", ")
	end
	updateCrew()
	Players.PlayerAdded:Connect(updateCrew)
	Players.PlayerRemoving:Connect(function()
		task.defer(updateCrew)
	end)
	UI.button(lobby, "START MISSION  🚀", THEME.Accent, function(b)
		b.Text = "Starting..."
		local ok, msg = act("Start")
		if not ok then
			toast(msg or "Couldn't start", "bad")
		end
		task.delay(1, function()
			b.Text = "START MISSION  🚀"
		end)
	end, { Size = UDim2.fromOffset(340, 64), TextSize = 26, LayoutOrder = 6 })
	label(lobby, { Text = "Project Michaelians Ad Astra  •  NASA Space Apps Challenge", TextSize = 14, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 9 })
end

-- REPORT
local report = modal(640, 560)
local function showReport(data)
	clear(report)
	UI.pad(report, 24, 18)
	UI.list(report, 8, false, Enum.HorizontalAlignment.Center)
	label(report, { Text = string.format("SOL %d REPORT", data.Sol), Font = THEME.Black, TextSize = 30, TextColor3 = THEME.Accent, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1 })
	for i, line in ipairs(data.Lines) do
		local row = create("Frame", { BackgroundColor3 = THEME.Card, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 1 + i, Parent = report })
		UI.corner(row, 10)
		label(row, { Text = line.Icon .. " " .. line.Name, Font = THEME.Bold, TextSize = 18, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 220, 1, 0) })
		local chip = create("TextLabel", {
			Text = line.On and "ON" or "OFF", Font = THEME.Black, TextSize = 15, BackgroundColor3 = THEME.Inset,
			TextColor3 = line.On and THEME.Good or THEME.Bad, Position = UDim2.new(0, 232, 0.5, -13), Size = UDim2.fromOffset(52, 26), Parent = row,
		})
		UI.corner(chip, 7)
		label(row, { Text = "→  " .. line.Text, Font = THEME.Bold, TextSize = 18, TextColor3 = line.Good and THEME.Good or THEME.Bad, Position = UDim2.fromOffset(296, 0), Size = UDim2.new(1, -306, 1, 0) })
	end
	for i, n in ipairs(data.Notes or {}) do
		label(report, { Text = n.Text, Font = THEME.Bold, TextSize = 17, TextColor3 = n.Good and THEME.Good or THEME.Bad, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 20 + i })
	end
	local nextText = data.Last and "Last sol done! Time to check the rocket..."
		or string.format("Next sol: %d power cells%s", data.NextCells, data.NextCells > MC.StartCells and "  (Solar bonus!)" or "")
	label(report, { Text = nextText, Font = THEME.Bold, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 40 })
	readyButton(report)
	local rows = #data.Lines + #(data.Notes or {})
	report.Size = UDim2.fromOffset(640, 190 + rows * 54)
	showModal(report, false)
end

-- FACT
local factCard = modal(680, 380)
local function showFact(data)
	clear(factCard)
	UI.pad(factCard, 28, 22)
	UI.list(factCard, 10, false, Enum.HorizontalAlignment.Center)
	label(factCard, { Text = "💡 DID YOU KNOW?", Font = THEME.Black, TextSize = 28, TextColor3 = THEME.Warn, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1 })
	label(factCard, { Text = data.Title, Font = THEME.Black, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 2 })
	label(factCard, { Text = data.Text, TextSize = 21, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 130), LayoutOrder = 3 })
	label(factCard, { Text = "Source: " .. data.Source, TextSize = 14, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 4 })
	if data.Preview then
		UI.button(factCard, "Close", THEME.Card, function()
			showModal(nil)
		end, { Size = UDim2.fromOffset(200, 48), TextSize = 20, LayoutOrder = 5 })
	else
		readyButton(factCard)
	end
	showModal(factCard, false)
end

-- END SCREENS
local endCard = modal(820, 620)
local function endButton(text)
	UI.button(endCard, text, THEME.Accent, function(b)
		b.Text = "Starting..."
		local ok, msg = act("Again")
		if not ok then
			toast(msg or "Couldn't start", "bad")
			b.Text = text
		end
	end, { Size = UDim2.fromOffset(300, 60), TextSize = 24, LayoutOrder = 99 })
end

local function showVictory(data)
	clear(endCard)
	UI.pad(endCard, 30, 24)
	UI.list(endCard, 10, false, Enum.HorizontalAlignment.Center)
	label(endCard, { Text = "🚀 MISSION COMPLETE!", Font = THEME.Black, TextSize = 46, TextColor3 = THEME.Good, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 1 })
	label(endCard, { Text = string.format("Your crew kept Mars Base 7 alive for %d sols and flew home safely!", data.Sols), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 2 })
	local m = data.Meters
	label(endCard, {
		Text = string.format("🫁 Oxygen %d    🍎 Food %d    ❤️ Health %d    ⛽ Fuel %d/%d", math.max(0, m.Oxygen), math.max(0, m.Food), math.max(0, m.Health), data.Fuel, data.FuelNeeded),
		Font = THEME.Bold, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 3,
	})
	label(endCard, { Text = "HOW OFTEN EACH STATION HAD POWER", Font = THEME.Bold, TextSize = 14, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 4 })
	for i, s in ipairs(data.Stations) do
		label(endCard, { Text = string.format("%s %s: %d of %d sols", s.Icon, s.Name, s.Count, data.Sols), TextSize = 19, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 4 + i })
	end
	if data.Storms > 0 then
		label(endCard, { Text = string.format("☢️ Solar storms with everyone safe: %d of %d", data.StormsSafe, data.Storms), TextSize = 19, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 20 })
	end
	label(endCard, { Text = "Crew: " .. table.concat(data.Crew, ", "), TextSize = 16, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 21 })
	endButton("PLAY AGAIN")
	showModal(endCard)
end

local function showFailure(data)
	clear(endCard)
	UI.pad(endCard, 30, 22)
	UI.list(endCard, 8, false, Enum.HorizontalAlignment.Center)
	label(endCard, { Text = string.format("MISSION FAILED  •  SOL %d", data.Sol), Font = THEME.Bold, TextSize = 18, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1 })
	label(endCard, { Text = data.Title, Font = THEME.Black, TextSize = 44, TextColor3 = THEME.Bad, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 2 })
	label(endCard, { Text = "WHAT HAPPENED", Font = THEME.Bold, TextSize = 14, TextColor3 = THEME.Sub, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 3 })
	for i, l in ipairs(data.Lines) do
		label(endCard, { Text = "• " .. l, TextSize = 18, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 3 + i })
	end
	label(endCard, { Text = "WHY", Font = THEME.Bold, TextSize = 14, TextColor3 = THEME.Sub, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 20 })
	label(endCard, { Text = data.Why, TextSize = 19, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 21 })
	local tip = create("Frame", { BackgroundColor3 = THEME.Card, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 22, Parent = endCard })
	UI.corner(tip, 10)
	label(tip, { Text = "💡 Next time: " .. data.Tip, Font = THEME.Bold, TextSize = 18, TextColor3 = THEME.Warn, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0) })
	if data.Fact then
		label(endCard, { Text = "Did you know? " .. data.Fact.Text, TextSize = 16, TextColor3 = THEME.Sub, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 23 })
	end
	endButton("TRY AGAIN")
	showModal(endCard)
end

------------------------------------------------------------------ camera shots
local shotToken = 0
local function rocketShot(rocket, seconds, fromAbove)
	if not rocket or not rocket.Parent then
		return
	end
	shotToken += 1
	local my = shotToken
	camera.CameraType = Enum.CameraType.Scriptable
	local base = rocket:GetPivot().Position
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if my ~= shotToken or not rocket.Parent then
			conn:Disconnect()
			return
		end
		local p = rocket:GetPivot().Position
		local t = os.clock() - t0
		local eye = Vector3.new(base.X + 70 * math.cos(t * 0.15), base.Y + (fromAbove and 25 or 12), base.Z + 70 * math.sin(t * 0.15))
		camera.CFrame = CFrame.lookAt(eye, p)
		if t >= seconds then
			conn:Disconnect()
			if my == shotToken then
				camera.CameraType = Enum.CameraType.Custom
			end
		end
	end)
end
local function endShot()
	shotToken += 1
	camera.CameraType = Enum.CameraType.Custom
end

------------------------------------------------------------------ tutorial (camera tour, skippable)
-- Shown once when you first spawn (Config.Mission.Tutorial). "How to play" on
-- the title screen shows it again. Each step moves the camera to a station.
local tutorialActive = false
local runTutorial -- forward
do
	local tut = UI.panel(root, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(760, 210), Visible = false, ZIndex = 20 })
	local tutStroke = tut:FindFirstChildOfClass("UIStroke")
	tutStroke.Color, tutStroke.Transparency, tutStroke.Thickness = THEME.Accent, 0.2, 2
	local stepText = label(tut, { Text = "", Font = THEME.Bold, TextSize = 15, TextColor3 = THEME.Sub, Position = UDim2.fromOffset(24, 14), Size = UDim2.fromOffset(200, 20) })
	local titleText = label(tut, { Text = "", Font = THEME.Black, TextSize = 30, TextColor3 = THEME.Accent, Position = UDim2.fromOffset(24, 34), Size = UDim2.new(1, -48, 0, 38) })
	local bodyText = label(tut, { Text = "", TextSize = 21, Position = UDim2.fromOffset(24, 76), Size = UDim2.new(1, -48, 0, 66), TextYAlignment = Enum.TextYAlignment.Top })
	local skipBtn, backBtn, nextBtn
	local step, steps = 1, {}
	local myRun = 0

	-- where things are (read from Workspace.MissionBase made by setup/MissionSetup.lua)
	local function hubPos()
		local base = workspace:FindFirstChild("MissionBase")
		local sp = base and base:FindFirstChild("MissionSpawn", true)
		return sp and sp.Position or Vector3.new(33, 3, 3)
	end
	local function stationPos(id, wantModel)
		local base = workspace:FindFirstChild("MissionBase")
		local st = base and base:FindFirstChild("Stations")
		local m = st and st:FindFirstChild(id)
		if not m then
			return nil
		end
		if wantModel then
			local ok, cf = pcall(m.GetBoundingBox, m)
			return ok and cf.Position or nil
		end
		local port = m:FindFirstChild("PowerPort", true)
		return port and port.Position
	end
	local function bunkerPos()
		local base = workspace:FindFirstChild("MissionBase")
		local b = base and base:FindFirstChild("Bunker")
		if b and b:IsA("Model") then
			return b:GetBoundingBox().Position
		end
		return nil
	end
	local function padPos()
		local base = workspace:FindFirstChild("MissionBase")
		local f = base and base:FindFirstChild("RocketPad")
		local pad = f and f:FindFirstChild("Pad")
		return pad and pad.Position
	end
	-- camera stands on the hub side of a target, looking at it
	local function shotAt(focus, dist, height)
		local hub = hubPos()
		local d = Vector3.new(hub.X - focus.X, 0, hub.Z - focus.Z)
		d = d.Magnitude > 1 and d.Unit or Vector3.new(0, 0, 1)
		return CFrame.lookAt(focus + d * dist + Vector3.new(0, height, 0), focus)
	end

	local function build()
		local hub = hubPos()
		local list = {}
		local function add(title, text, cf, markerPos, markerText)
			table.insert(list, { Title = title, Text = text, CFrame = cf, Marker = markerPos, MarkerText = markerText })
		end
		add("Welcome to Mars Base 7!",
			string.format("Your crew must keep this outpost alive for %d sols (Mars days), then fly home in a rocket.", MC.Sols),
			CFrame.lookAt(hub + Vector3.new(70, 120, 110), hub))
		local o2 = stationPos("Oxygen")
		if o2 then
			add("Power Ports",
				"Every station has a Power Port ⚡. Walk up to it and press E to plug in a power cell. Press E again to unplug it.",
				shotAt(o2, 18, 8), o2, "⚡ POWER PORT")
		end
		local solar = stationPos("Solar", true)
		if solar then
			add("Only " .. MC.StartCells .. " power cells",
				string.format("You get %d cells each sol, but there are %d stations. Power the Solar Panels to get an extra cell next sol!", MC.StartCells, #MC.Stations),
				shotAt(solar, 34, 16), solar, "☀️ SOLAR PANELS")
		end
		local gh = stationPos("Greenhouse", true)
		if gh then
			add("Air and food",
				"Stations without power make meters drop. The Oxygen Generator keeps your air up, the Greenhouse grows food. Don't let any meter hit 0!",
				shotAt(gh, 70, 30), gh, "🌱 GREENHOUSE")
		end
		local bunker = bunkerPos()
		if bunker then
			add("Solar storms!",
				"When the alarm rings, run into the Shield Bunker. Its door only opens if the bunker has power!",
				shotAt(bunker, 60, 30), bunker, "🛡️ SHIELD BUNKER")
		end
		local pad = padPos() or stationPos("Fuel", true)
		if pad then
			add("Fly home",
				string.format("Power the Rocket Fuel Plant to make %d fuel. Then the rocket can take your crew home!", MC.FuelNeeded),
				shotAt(pad, 75, 32), pad, "🚀 ROCKET")
		end
		add("You're ready, astronaut!",
			"Watch out for dust storms and space rocks too. Press START MISSION when your crew is ready.",
			nil)
		return list
	end

	local function finish()
		myRun += 1
		tutorialActive = false
		tut.Visible = false
		showMarker(nil)
		camera.CameraType = Enum.CameraType.Custom
		lastPhase = nil -- let the main loop show the right screen again
	end

	local function show(i)
		step = i
		local s = steps[i]
		stepText.Text = string.format("HOW TO PLAY  •  %d / %d", i, #steps)
		titleText.Text = s.Title
		bodyText.Text = s.Text
		backBtn.Visible = i > 1
		nextBtn.Text = i == #steps and "Let's go!  ✓" or "Next  ▶"
		if s.CFrame then
			camera.CameraType = Enum.CameraType.Scriptable
			UI.tween(camera, { CFrame = s.CFrame }, TweenInfo.new(1.4, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut))
		else
			camera.CameraType = Enum.CameraType.Custom
		end
		if s.Marker then
			showMarker(s.Marker, s.MarkerText, THEME.Accent)
		else
			showMarker(nil)
		end
	end

	local row = create("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 24, 1, -14), Size = UDim2.new(1, -48, 0, 48), Parent = tut })
	skipBtn = UI.button(row, "Skip tutorial", THEME.Card, function()
		finish()
	end, { Size = UDim2.fromOffset(190, 46), TextSize = 18, TextColor3 = THEME.Sub })
	backBtn = UI.button(row, "◀  Back", THEME.Card, function()
		show(math.max(1, step - 1))
	end, { Size = UDim2.fromOffset(140, 46), TextSize = 18, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -216, 0, 0) })
	nextBtn = UI.button(row, "Next  ▶", THEME.Accent, function()
		if step >= #steps then
			finish()
		else
			show(step + 1)
		end
	end, { Size = UDim2.fromOffset(200, 46), TextSize = 20, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0) })

	runTutorial = function()
		steps = build()
		myRun += 1
		tutorialActive = true
		showModal(nil)
		tut.Visible = true
		show(1)
	end
	-- a mission starting (someone pressed Start) ends the tour
	state:GetAttributeChangedSignal("Phase"):Connect(function()
		local p = state:GetAttribute("Phase")
		if tutorialActive and (p == "Intro" or p == "Launch") then
			finish()
		end
	end)
end

-- "How to play" button on the title screen
UI.button(lobby, "How to play", THEME.Card, function()
	runTutorial()
end, { Size = UDim2.fromOffset(220, 46), TextSize = 19, LayoutOrder = 7 })

------------------------------------------------------------------ server messages
MissionEvent.OnClientEvent:Connect(function(kind, data)
	data = data or {}
	if kind == "Banner" then
		showModal(nil)
		local color = data.Kind == "dust" and THEME.Storm or THEME.Accent
		showBanner(data.Title, data.Sub, color, MC.BannerTime + 1)
	elseif kind == "Intro" then
		showModal(nil)
		showBanner("Touchdown!", "Welcome to Mars, crew. Your outpost is waiting.", THEME.Accent, data.Duration or 6)
		rocketShot(data.Rocket, (data.Duration or 6) - 0.5, true)
	elseif kind == "Toast" then
		toast(data.Text, data.Kind)
	elseif kind == "Plug" then
		play("Plug", data.On and 1.2 or 0.8)
	elseif kind == "Report" then
		hideAlert()
		showReport(data)
	elseif kind == "Fact" then
		showFact(data)
	elseif kind == "SolarStorm" then
		if data.Phase == "Warning" then
			alertToken += 1
			alertMode = "SolarStorm"
			alert.Visible = true
			alertStroke.Color = THEME.Bad
			alertTitle.Text = "☢️ SOLAR STORM!"
			alertTitle.TextColor3 = THEME.Bad
			alertSub.Text = "The Sun is blasting radiation. Get inside the Shield Bunker!"
			showMarker(data.BunkerPos, "🛡️ BUNKER", THEME.Bad)
			task.spawn(function()
				local my = alertToken
				while my == alertToken and alertMode == "SolarStorm" do
					play("Alarm", 0.7)
					task.wait(0.9)
				end
			end)
		else
			showMarker(nil)
			showResult(data.Text, data.Safe)
			for _, e in ipairs(edges) do
				e.BackgroundTransparency = data.Safe and 1 or 0.2
				UI.tween(e, { BackgroundTransparency = 1 }, TweenInfo.new(1.5))
			end
		end
	elseif kind == "Micrometeorite" then
		if data.Phase == "Start" then
			alertToken += 1
			alertMode = "Micrometeorite"
			alert.Visible = true
			alertStroke.Color = THEME.Warn
			alertTitle.Text = "☄️ MICROMETEORITE HIT!"
			alertTitle.TextColor3 = THEME.Warn
			alertSub.Text = string.format("An air pipe near the %s is leaking! Click the sparks (or press E) %d times.", data.Where or "base", data.Clicks or 5)
			showMarker(data.Position, "💨 LEAK!", THEME.Warn)
			play("Alarm", 1.3)
		else
			showMarker(nil)
			showResult(data.Text, data.Phase == "Fixed")
			if data.Phase == "Fixed" then
				play("Fixed", 1.5)
			end
		end
	elseif kind == "Launch" then
		showModal(nil)
		hideAlert()
		showBanner("3... 2... 1... LIFTOFF!", "The rocket is fuelled. The crew is heading home!", THEME.Good, data.Duration or 8)
		rocketShot(data.Rocket, data.Duration or 8, false)
	elseif kind == "Victory" then
		endShot()
		showVictory(data)
	elseif kind == "Failed" then
		endShot()
		hideAlert()
		showMarker(nil)
		showFailure(data)
	elseif kind == "Lobby" then
		endShot()
		hideAlert()
		showMarker(nil)
	end
end)

------------------------------------------------------------------ every frame
local PHASE_TEXT = {
	Sol = "Plug in power cells, then keep the crew safe!",
	Wrapup = "Finishing up...",
	Report = "Sol report",
	Fact = "Did you know?",
	Intro = "Landing...",
	Launch = "Liftoff!",
}
local pulse = 0
RunService.RenderStepped:Connect(function(dt)
	pulse += dt
	local phase = attr("Phase", "Lobby")

	-- which big screen?
	if tutorialActive then
		hud.Visible = false
		return
	end
	if phase ~= lastPhase then
		if phase == "Lobby" then
			showModal(lobby)
		elseif phase == "Sol" or phase == "Intro" or phase == "Launch" then
			if lobby.Visible or endCard.Visible then
				showModal(nil)
			end
		end
		lastPhase = phase
	end
	hud.Visible = phase == "Sol" or phase == "Wrapup" or phase == "Report" or phase == "Fact"

	if hud.Visible then
		local sol, sols = attr("Sol", 1), attr("Sols", MC.Sols)
		solText.Text = string.format("SOL %d / %d", sol, sols)
		local ends, length = attr("PhaseEnds", 0), attr("PhaseLength", 0)
		local left = math.max(0, ends - now())
		timerText.Text = UI.fmt(left)
		timeFill.Size = UDim2.fromScale(length > 0 and math.clamp(left / length, 0, 1) or 0, 1)
		timerText.TextColor3 = (phase == "Sol" and left <= 10) and THEME.Warn or THEME.Text
		if attr("Paused", false) then
			phaseText.Text = "⏸ PAUSED (dev panel)"
		elseif attr("Dust", false) and phase == "Sol" then
			phaseText.Text = "🌪️ Dust storm: Solar Panels can't make a bonus cell"
		else
			phaseText.Text = PHASE_TEXT[phase] or ""
		end

		for key, set in pairs(setMeter) do
			set(attr(key, 100), MC.MaxMeter)
		end
		local fuel = attr("Fuel", 0)
		fuelLabel.Text = string.format("⛽ Rocket fuel  %d / %d", fuel, MC.FuelNeeded)
		for i, s in ipairs(segs) do
			s.BackgroundColor3 = i <= fuel and THEME.Accent or THEME.Inset
		end

		for id, row in pairs(stationRows) do
			local on = attr("On_" .. id, false)
			row.Chip.Text = on and "ON" or "OFF"
			row.Chip.TextColor3 = on and THEME.Good or THEME.Bad
			row.Stroke.Transparency = on and 0.1 or 1
			local by = attr("By_" .. id, "")
			row.By.Text = on and ("plugged in by " .. by) or ""
		end
		setCells(attr("CellsTotal", 0), attr("CellsUsed", 0))
	end

	-- alert countdowns
	local alertId = attr("Alert", "")
	if alertMode == "SolarStorm" and alertId == "SolarStorm" then
		local left = math.max(0, attr("AlertEnds", 0) - now())
		alertCount.Text = tostring(math.ceil(left))
		local powered = attr("On_Shield", false)
		local inside = player:GetAttribute("InBunker") == true
		alertInfo.Text = (powered and "Bunker: OPEN" or "Bunker: LOCKED (plug a cell into the Shield Bunker!)")
			.. "   •   You: " .. (inside and "SAFE inside ✓" or "OUTSIDE")
		alertInfo.TextColor3 = (powered and inside) and THEME.Good or THEME.Bad
		local t = 0.55 + 0.3 * math.sin(pulse * 6)
		for _, e in ipairs(edges) do
			e.BackgroundTransparency = inside and 0.85 or t
		end
	elseif alertMode == "Micrometeorite" and alertId == "Micrometeorite" then
		local left = math.max(0, attr("AlertEnds", 0) - now())
		alertCount.Text = string.format("%d / %d", attr("AlertProgress", 0), attr("AlertGoal", 5))
		alertInfo.Text = string.format("%d seconds before air is lost", math.ceil(left))
		alertInfo.TextColor3 = left < 6 and THEME.Bad or THEME.Warn
	elseif alertMode == "SolarStorm" or alertMode == "Micrometeorite" then
		if alertId == "" then
			hideAlert()
			showMarker(nil)
		end
	end
	if marker.Enabled then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			markerDist.Text = string.format("%d studs", (hrp.Position - markerPart.Position).Magnitude)
		end
	end
end)

------------------------------------------------------------------ first spawn: tutorial
local tutCfg = MC.Tutorial or {}
if tutCfg.Enabled ~= false then
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		char:WaitForChild("HumanoidRootPart", 10)
		task.wait(tutCfg.Delay or 1.5)
		local phase = attr("Phase", "Lobby")
		if phase == "Lobby" or tutCfg.EvenDuringMission then
			runTutorial()
		end
	end)
end

------------------------------------------------------------------ late join
task.defer(function()
	local phase = attr("Phase", "Lobby")
	if phase == "Victory" or phase == "Failed" then
		local last = act("GetEnd")
		if type(last) == "table" then
			if last.Kind == "Victory" then
				showVictory(last.Data)
			else
				showFailure(last.Data)
			end
		end
	end
end)
