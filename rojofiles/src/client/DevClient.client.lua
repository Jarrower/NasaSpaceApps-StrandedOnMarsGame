--[[
	DevClient  (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > DevClient

	Dev / testing panel. Hidden until you type Config.Dev.ChatCode in chat
	("The Key To Wellness"). Type it again or press F8 to show/hide.
	The panel can be dragged by its header.
	All commands are verified on the server (DevService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("BaseShared"):WaitForChild("Config"))
if not (Config.Dev and Config.Dev.Enabled) then
	return
end
local remotes = ReplicatedStorage:WaitForChild("BaseRemotes")
local DevCommand = remotes:WaitForChild("DevCommand", 15)
local DevState = remotes:WaitForChild("DevState", 15)
local DevChat = remotes:WaitForChild("DevChat", 15)
if not DevCommand then
	return
end

local THEME = {
	Panel = Color3.fromRGB(18, 19, 25), Card = Color3.fromRGB(30, 32, 41), Hover = Color3.fromRGB(42, 45, 57),
	Inset = Color3.fromRGB(12, 13, 17), Text = Color3.fromRGB(240, 241, 246), Sub = Color3.fromRGB(145, 150, 168),
	Accent = Color3.fromRGB(170, 120, 255), -- purple = dev
	Good = Color3.fromRGB(92, 222, 140), Bad = Color3.fromRGB(255, 88, 88), Warn = Color3.fromRGB(255, 190, 70),
	Font = Enum.Font.GothamMedium, Bold = Enum.Font.GothamBold, Black = Enum.Font.GothamBlack,
}
local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad)

------------------------------------------------------------------ helpers
local function create(class, props)
	local inst = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end
local function corner(p, r)
	create("UICorner", { CornerRadius = UDim.new(0, r or 8), Parent = p })
end
local function stroke(p, t, c)
	return create("UIStroke", { Transparency = t or 0.88, Color = c or Color3.new(1, 1, 1), ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p })
end
local function label(parent, props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or THEME.Text
	props.Font = props.Font or THEME.Font
	props.TextSize = props.TextSize or 13
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.Parent = parent
	return create("TextLabel", props)
end

------------------------------------------------------------------ window
local gui = create("ScreenGui", {
	Name = "DevPanel", ResetOnSpawn = false, DisplayOrder = 50, Enabled = false,
	Parent = player:WaitForChild("PlayerGui"),
})

local win = create("Frame", {
	Size = UDim2.fromOffset(400, 520), Position = UDim2.new(1, -420, 0.5, -260),
	BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.03, Parent = gui,
})
corner(win, 14)
stroke(win, 0.5, THEME.Accent)

-- header (drag handle)
local header = create("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = win })
label(header, { Text = "DEV TOOLS", Font = THEME.Black, TextSize = 18, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -60, 0, 20) })
label(header, {
	Text = "Testing only  •  " .. Config.Dev.ToggleKey.Name .. " to hide", TextSize = 11, TextColor3 = THEME.Sub,
	Position = UDim2.fromOffset(16, 30), Size = UDim2.new(1, -60, 0, 14),
})
local close = create("TextButton", {
	Text = "✕", Font = THEME.Bold, TextSize = 13, TextColor3 = THEME.Sub, AutoButtonColor = false,
	Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -42, 0, 12), BackgroundColor3 = THEME.Card, Parent = header,
})
corner(close, 7)
close.MouseButton1Click:Connect(function()
	gui.Enabled = false
end)

do -- dragging
	local dragging, startPos, startMouse
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, startPos, startMouse = true, win.Position, input.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - startMouse
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- target player selector
local target = player
local targetBar = create("Frame", {
	Position = UDim2.fromOffset(14, 56), Size = UDim2.new(1, -28, 0, 34), BackgroundColor3 = THEME.Inset, Parent = win,
})
corner(targetBar, 9)
label(targetBar, { Text = "TARGET", Font = THEME.Bold, TextSize = 10, TextColor3 = THEME.Sub, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 60, 1, 0) })
local targetName = label(targetBar, {
	Text = player.Name, Font = THEME.Bold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.new(0, 70, 0, 0), Size = UDim2.new(1, -140, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd,
})
local function arrow(text, x)
	local b = create("TextButton", {
		Text = text, Font = THEME.Bold, TextSize = 14, TextColor3 = THEME.Text, AutoButtonColor = true,
		Size = UDim2.fromOffset(28, 26), Position = UDim2.new(1, x, 0, 4), BackgroundColor3 = THEME.Card, Parent = targetBar,
	})
	corner(b, 6)
	return b
end
local prevBtn, nextBtn = arrow("<", -64), arrow(">", -32)

-- tabs
local tabBar = create("Frame", {
	Position = UDim2.fromOffset(14, 98), Size = UDim2.new(1, -28, 0, 32), BackgroundColor3 = THEME.Inset, Parent = win,
})
corner(tabBar, 9)
create("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), Parent = tabBar })
create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabBar })

-- status line
local status = label(win, {
	Text = "Ready", TextSize = 12, TextColor3 = THEME.Sub, TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.new(0, 16, 1, -30), Size = UDim2.new(1, -32, 0, 20),
})

local pages, tabs = {}, {}
local MISSION = Config.GameMode == "Mission"
local TAB_NAMES = MISSION and { "Mission", "Player", "World" } or { "Items", "Base", "Player", "Survival", "World" }
local function showTab(name)
	for n, page in pairs(pages) do
		page.Visible = n == name
		TweenService:Create(tabs[n], FAST, {
			BackgroundTransparency = n == name and 0 or 1,
			TextColor3 = n == name and Color3.new(1, 1, 1) or THEME.Sub,
		}):Play()
	end
end
for i, name in ipairs(TAB_NAMES) do
	local t = create("TextButton", {
		Text = name, Font = THEME.Bold, TextSize = 12, TextColor3 = THEME.Sub, AutoButtonColor = false,
		Size = UDim2.new(1 / #TAB_NAMES, -3, 1, 0), BackgroundColor3 = THEME.Accent, BackgroundTransparency = 1,
		LayoutOrder = i, Parent = tabBar,
	})
	corner(t, 7)
	t.MouseButton1Click:Connect(function()
		showTab(name)
	end)
	tabs[name] = t
	local page = create("ScrollingFrame", {
		Position = UDim2.fromOffset(14, 140), Size = UDim2.new(1, -28, 1, -140 - 38), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.Sub,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Visible = false, Parent = win,
	})
	create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
	create("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = page })
	pages[name] = page
end

------------------------------------------------------------------ widgets
local refreshInventory = function() end -- replaced by the Items tab (Sandbox mode)

local function run(cmd, ...)
	local ok, msg = DevCommand:InvokeServer(cmd, target, ...)
	if typeof(msg) == "string" then
		status.Text = msg
		status.TextColor3 = ok and THEME.Good or THEME.Bad
	end
	task.delay(0.2, function()
		if refreshInventory then
			refreshInventory()
		end
	end)
	return ok, msg
end

local orderCounter = 0
local function nextOrder()
	orderCounter += 1
	return orderCounter
end

local function section(page, text)
	label(page, {
		Text = string.upper(text), Font = THEME.Bold, TextSize = 10, TextColor3 = THEME.Accent,
		Size = UDim2.new(1, 0, 0, 18), LayoutOrder = nextOrder(),
	})
end

local function button(parent, text, color, onClick, size)
	local b = create("TextButton", {
		Text = text, Font = THEME.Bold, TextSize = 12, TextColor3 = THEME.Text, AutoButtonColor = false,
		Size = size or UDim2.new(1, 0, 0, 34), BackgroundColor3 = color or THEME.Card,
		LayoutOrder = nextOrder(), Parent = parent,
	})
	corner(b, 8)
	local base = b.BackgroundColor3
	b.MouseEnter:Connect(function()
		TweenService:Create(b, FAST, { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.08) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, FAST, { BackgroundColor3 = base }):Play()
	end)
	b.MouseButton1Click:Connect(function()
		onClick(b)
	end)
	return b
end

-- A row of buttons side by side
local function buttonRow(page, list)
	local row = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nextOrder(), Parent = page })
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	for _, item in ipairs(list) do
		button(row, item[1], item[3], item[2], UDim2.new(1 / #list, -6 + 6 / #list, 1, 0))
	end
	return row
end

-- Text box + button: "WalkSpeed [ 16 ] [Set]"
local function inputRow(page, title, default, buttonText, onClick)
	local row = create("Frame", { BackgroundColor3 = THEME.Card, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = nextOrder(), Parent = page })
	corner(row, 8)
	label(row, { Text = title, TextSize = 12, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.45, -12, 1, 0) })
	local box = create("TextBox", {
		Text = tostring(default), PlaceholderText = tostring(default), Font = THEME.Bold, TextSize = 13,
		TextColor3 = THEME.Text, BackgroundColor3 = THEME.Inset, ClearTextOnFocus = false,
		Position = UDim2.new(0.45, 0, 0, 5), Size = UDim2.new(0.3, -6, 1, -10), Parent = row,
	})
	corner(box, 6)
	local b = create("TextButton", {
		Text = buttonText, Font = THEME.Bold, TextSize = 12, TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = THEME.Accent, Position = UDim2.new(0.75, 0, 0, 5), Size = UDim2.new(0.25, -6, 1, -10), Parent = row,
	})
	corner(b, 6)
	b.MouseButton1Click:Connect(function()
		onClick(box.Text)
	end)
	return box
end

-- Button that needs a second click within 3s (for destructive actions)
local function confirmButton(page, text, onConfirm)
	local armed = false
	button(page, text, Color3.fromRGB(70, 26, 30), function(b)
		if armed then
			armed = false
			b.Text = text
			onConfirm()
		else
			armed = true
			b.Text = "Click again to confirm"
			task.delay(3, function()
				if armed then
					armed = false
					b.Text = text
				end
			end)
		end
	end)
end

------------------------------------------------------------------ ITEMS tab
if not MISSION then
local itemsPage = pages.Items
local amount = 10

section(itemsPage, "Amount")
local amountBox
amountBox = inputRow(itemsPage, "Amount per click", amount, "OK", function(text)
	amount = math.max(1, math.floor(tonumber(text) or 10))
	amountBox.Text = tostring(amount)
end)
buttonRow(itemsPage, {
	{ "1", function() amount = 1; amountBox.Text = "1" end },
	{ "10", function() amount = 10; amountBox.Text = "10" end },
	{ "100", function() amount = 100; amountBox.Text = "100" end },
	{ "1000", function() amount = 1000; amountBox.Text = "1000" end },
})

section(itemsPage, "Quick")
buttonRow(itemsPage, {
	{ "Give ALL items", function() run("GiveAll", amount) end, Color3.fromRGB(34, 70, 48) },
})
confirmButton(itemsPage, "Clear inventory", function()
	run("ClearInventory")
end)

section(itemsPage, "Items  (+ add / − remove)")
local itemIds = {}
for id in pairs(Config.Items) do
	table.insert(itemIds, id)
end
table.sort(itemIds, function(a, b)
	return Config.ItemName(a) < Config.ItemName(b)
end)
local countLabels = {}
for _, id in ipairs(itemIds) do
	local row = create("Frame", { BackgroundColor3 = THEME.Card, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = nextOrder(), Parent = itemsPage })
	corner(row, 8)
	label(row, { Text = Config.ItemName(id), Font = THEME.Bold, TextSize = 12, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.5, -12, 1, 0) })
	countLabels[id] = label(row, {
		Text = "0", TextSize = 12, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.2, -8, 1, 0),
	})
	local function small(text, x, color, cmd)
		local b = create("TextButton", {
			Text = text, Font = THEME.Black, TextSize = 16, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = true,
			BackgroundColor3 = color, Position = UDim2.new(x, 0, 0, 5), Size = UDim2.new(0.15, -6, 1, -10), Parent = row,
		})
		corner(b, 6)
		b.MouseButton1Click:Connect(function()
			run(cmd, id, amount)
		end)
	end
	small("+", 0.7, Color3.fromRGB(40, 110, 70), "GiveItem")
	small("−", 0.85, Color3.fromRGB(120, 40, 45), "RemoveItem")
end

function refreshInventory()
	if not gui.Enabled then
		return
	end
	local ok, inv = DevCommand:InvokeServer("GetInventory", target)
	if ok and type(inv) == "table" then
		for id, l in pairs(countLabels) do
			local n = inv[id] or 0
			l.Text = tostring(n)
			l.TextColor3 = n > 0 and THEME.Text or THEME.Sub
		end
	end
end

------------------------------------------------------------------ BASE tab
local basePage = pages.Base
section(basePage, "Building")
local freeBuild = false
button(basePage, "Free build: OFF", nil, function(b)
	freeBuild = not freeBuild
	local ok = run("SetFreeBuild", freeBuild)
	if not ok then
		freeBuild = not freeBuild
	end
	b.Text = "Free build: " .. (freeBuild and "ON (outlines build instantly)" or "OFF")
	b.TextColor3 = freeBuild and THEME.Good or THEME.Text
end)
button(basePage, "Finish all my outlines now", nil, function()
	run("FinishOutlines")
end)

section(basePage, "Power & machines")
button(basePage, "Refuel all generators", nil, function()
	run("RefuelAll")
end)
button(basePage, "Recalculate power / oxygen / roofs", nil, function()
	run("RecomputeNetwork")
end)
local speeds = { 1, 10, 100 }
local speedIndex = 1
button(basePage, "Processing speed: x1", nil, function(b)
	speedIndex = speedIndex % #speeds + 1
	if run("SetProcessingSpeed", speeds[speedIndex]) then
		b.Text = "Processing speed: x" .. speeds[speedIndex]
	end
end)

section(basePage, "World resources")
button(basePage, "Respawn all mined ores", nil, function()
	run("RespawnOres")
end)

section(basePage, "Danger")
confirmButton(basePage, "Delete target's ENTIRE base", function()
	run("DeleteBase")
end)

end -- not MISSION (Items + Base tabs)

------------------------------------------------------------------ PLAYER tab
local playerPage = pages.Player
section(playerPage, "Movement")
inputRow(playerPage, "WalkSpeed", 16, "Set", function(v)
	run("SetWalkSpeed", v)
end)
inputRow(playerPage, "JumpPower", 50, "Set", function(v)
	run("SetJumpPower", v)
end)
buttonRow(playerPage, {
	{ "Fast (60)", function() run("SetWalkSpeed", 60) end },
	{ "Normal (16)", function() run("SetWalkSpeed", 16); run("SetJumpPower", 50) end },
})
section(playerPage, "Character")
buttonRow(playerPage, {
	{ "Heal", function() run("Heal") end, Color3.fromRGB(34, 70, 48) },
	{ "Respawn", function() run("Respawn") end },
})
section(playerPage, "Teleport (you go to the target)")
button(playerPage, "Teleport to target's base", nil, function()
	run("TeleportToBase")
end)
button(playerPage, "Teleport to target player", nil, function()
	run("TeleportToPlayer")
end)

------------------------------------------------------------------ SURVIVAL tab
if not MISSION then
local survivalPage = pages.Survival
section(survivalPage, "Oxygen")
local infO2 = false
button(survivalPage, "Infinite oxygen: OFF", nil, function(b)
	infO2 = not infO2
	if not run("SetInfiniteO2", infO2) then
		infO2 = not infO2
	end
	b.Text = "Infinite oxygen: " .. (infO2 and "ON" or "OFF")
	b.TextColor3 = infO2 and THEME.Good or THEME.Text
end)
buttonRow(survivalPage, {
	{ "Refill tank", function() run("RefillO2") end, Color3.fromRGB(34, 70, 48) },
	{ "Set to 10s", function() run("SetO2", 10) end },
	{ "Empty", function() run("SetO2", 0) end, Color3.fromRGB(70, 26, 30) },
})
inputRow(survivalPage, "Tank seconds", 30, "Set", function(v)
	run("SetO2", v)
end)

section(survivalPage, "Hunger")
local infFood = false
button(survivalPage, "Infinite food: OFF", nil, function(b)
	infFood = not infFood
	if not run("SetInfiniteHunger", infFood) then
		infFood = not infFood
	end
	b.Text = "Infinite food: " .. (infFood and "ON" or "OFF")
	b.TextColor3 = infFood and THEME.Good or THEME.Text
end)
buttonRow(survivalPage, {
	{ "Full", function() run("SetHunger", 100) end, Color3.fromRGB(34, 70, 48) },
	{ "20", function() run("SetHunger", 20) end },
	{ "Starving", function() run("SetHunger", 0) end, Color3.fromRGB(70, 26, 30) },
})

section(survivalPage, "Drill tier")
buttonRow(survivalPage, {
	{ "T0", function() run("SetDrillTier", 0) end },
	{ "T1", function() run("SetDrillTier", 1) end },
	{ "T2", function() run("SetDrillTier", 2) end },
	{ "T3", function() run("SetDrillTier", 3) end },
})

section(survivalPage, "Farming & water")
button(survivalPage, "Grow all crops instantly", nil, function()
	run("GrowAllCrops")
end)
buttonRow(survivalPage, {
	{ "Fill water tanks", function() run("FillWater", false) end, Color3.fromRGB(30, 60, 90) },
	{ "Empty tanks", function() run("FillWater", true) end },
})

section(survivalPage, "Spawn ore at your feet")
local oreIds = {}
for id in pairs(Config.Ores) do
	table.insert(oreIds, id)
end
table.sort(oreIds, function(a, b)
	return (Config.Ores[a].Tier or 0) < (Config.Ores[b].Tier or 0)
end)
for i = 1, #oreIds, 3 do
	local row = {}
	for j = i, math.min(i + 2, #oreIds) do
		local id = oreIds[j]
		table.insert(row, { Config.ItemName(Config.Ores[id].Item), function() run("SpawnOre", id) end })
	end
	buttonRow(survivalPage, row)
end

section(survivalPage, "Suits (gives + equips)")
local suitIds = {}
for id in pairs(Config.Suits) do
	table.insert(suitIds, id)
end
table.sort(suitIds, function(a, b)
	return (Config.Suits[a].Order or 99) < (Config.Suits[b].Order or 99)
end)
for _, id in ipairs(suitIds) do
	button(survivalPage, Config.Suits[id].DisplayName, nil, function()
		run("GiveSuit", id)
	end)
end

section(survivalPage, "Weather")
local eventIds = {}
for id in pairs(Config.Weather.Events) do
	table.insert(eventIds, id)
end
table.sort(eventIds)
for _, id in ipairs(eventIds) do
	local name = Config.Weather.Events[id].DisplayName
	buttonRow(survivalPage, {
		{ "Start " .. name, function() run("StartWeather", id) end, Color3.fromRGB(90, 52, 28) },
		{ "Warn (60s)", function() run("WarnWeather", id) end },
	})
end
button(survivalPage, "Clear weather", nil, function()
	run("ClearWeather")
end)

end -- not MISSION (Survival tab)

------------------------------------------------------------------ MISSION tab
if MISSION then
	local page = pages.Mission
	section(page, "Mission")
	buttonRow(page, {
		{ "Start", function() run("MissionStart") end, Color3.fromRGB(34, 70, 48) },
		{ "Skip phase", function() run("MissionSkip") end },
	})
	local paused = false
	button(page, "Pause timer: OFF", nil, function(b)
		paused = not paused
		run("MissionPause", paused)
		b.Text = "Pause timer: " .. (paused and "ON" or "OFF")
		b.TextColor3 = paused and THEME.Warn or THEME.Text
	end)
	confirmButton(page, "Restart mission now", function()
		run("MissionRestart", false)
	end)
	confirmButton(page, "Back to title screen", function()
		run("MissionRestart", true)
	end)

	section(page, "Sols")
	buttonRow(page, {
		{ "Sol 60s", function() run("MissionSolLength", 60) end },
		{ "20s", function() run("MissionSolLength", 20) end },
		{ "10s", function() run("MissionSolLength", 10) end },
	})
	inputRow(page, "Jump to sol", 7, "Go", function(v)
		run("MissionJumpToSol", v)
	end)

	section(page, "Meters")
	for _, m in ipairs({ "Oxygen", "Food", "Health" }) do
		buttonRow(page, {
			{ m .. " 100", function() run("MissionSetMeter", m, 100) end, Color3.fromRGB(34, 70, 48) },
			{ "30", function() run("MissionSetMeter", m, 30) end },
			{ "5", function() run("MissionSetMeter", m, 5) end, Color3.fromRGB(90, 52, 28) },
		})
	end
	buttonRow(page, {
		{ "Fuel 0", function() run("MissionSetMeter", "Fuel", 0) end },
		{ "Fuel 3", function() run("MissionSetMeter", "Fuel", 3) end },
		{ "Fuel full", function() run("MissionSetMeter", "Fuel", Config.Mission.FuelNeeded) end, Color3.fromRGB(34, 70, 48) },
	})
	button(page, "+1 power cell (this sol)", nil, function()
		run("MissionAddCell")
	end)

	section(page, "Events (during a sol)")
	buttonRow(page, {
		{ "Dust storm", function() run("MissionEvent", "DustStorm") end, Color3.fromRGB(90, 52, 28) },
		{ "Solar storm", function() run("MissionEvent", "SolarStorm") end, Color3.fromRGB(90, 28, 40) },
		{ "Meteorite", function() run("MissionEvent", "Micrometeorite") end, Color3.fromRGB(70, 60, 24) },
	})

	section(page, "End the mission")
	button(page, "WIN now (rocket launch)", Color3.fromRGB(34, 70, 48), function()
		run("MissionWin")
	end)
	buttonRow(page, {
		{ "Lose: Oxygen", function() run("MissionLose", "Oxygen") end, Color3.fromRGB(70, 26, 30) },
		{ "Food", function() run("MissionLose", "Food") end, Color3.fromRGB(70, 26, 30) },
	})
	buttonRow(page, {
		{ "Lose: Health", function() run("MissionLose", "Health") end, Color3.fromRGB(70, 26, 30) },
		{ "Fuel", function() run("MissionLose", "Fuel") end, Color3.fromRGB(70, 26, 30) },
	})

	section(page, "Fact cards")
	inputRow(page, "Show fact #", 1, "Show", function(v)
		run("MissionShowFact", v)
	end)

	section(page, "Teleport (you)")
	local spots = { { "Hub", "Hub" }, { "Bunker", "Bunker" }, { "Rocket", "Pad" } }
	for _, d in ipairs(Config.Mission.Stations) do
		table.insert(spots, { d.Icon .. " " .. d.Id, d.Id })
	end
	for i = 1, #spots, 3 do
		local row = {}
		for j = i, math.min(i + 2, #spots) do
			local where = spots[j][2]
			table.insert(row, { spots[j][1], function() run("MissionTeleport", where) end })
		end
		buttonRow(page, row)
	end
end

------------------------------------------------------------------ WORLD tab
local worldPage = pages.World
section(worldPage, "Time of day (solar panels)")
buttonRow(worldPage, {
	{ "Dawn", function() run("SetTime", 6) end },
	{ "Noon", function() run("SetTime", 12) end },
	{ "Dusk", function() run("SetTime", 18) end },
	{ "Night", function() run("SetTime", 0) end },
})
inputRow(worldPage, "Clock time (0-24)", 12, "Set", function(v)
	run("SetTime", v)
end)
if not MISSION then
	section(worldPage, "Saving")
	button(worldPage, "Save target's inventory now", nil, function()
		run("SaveInventory")
	end)
end

------------------------------------------------------------------ target cycling
local function setTarget(p)
	target = p
	targetName.Text = p == player and (p.Name .. "  (you)") or p.Name
	refreshInventory()
end
local function cycle(dir)
	local list = Players:GetPlayers()
	local i = table.find(list, target) or 1
	setTarget(list[(i - 1 + dir) % #list + 1])
end
prevBtn.MouseButton1Click:Connect(function()
	cycle(-1)
end)
nextBtn.MouseButton1Click:Connect(function()
	cycle(1)
end)
Players.PlayerRemoving:Connect(function(p)
	if p == target then
		setTarget(player)
	end
end)

------------------------------------------------------------------ open / close
local unlocked = false
local function setVisible(v)
	gui.Enabled = v
	if v then
		refreshInventory()
	end
end

DevState.OnClientEvent:Connect(function(action)
	if action == "Toggle" then
		if not unlocked then
			unlocked = true
			status.Text = "Dev panel unlocked"
			status.TextColor3 = THEME.Good
		end
		setVisible(not gui.Enabled)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not unlocked then
		return
	end
	if input.KeyCode == Config.Dev.ToggleKey then
		setVisible(not gui.Enabled)
	end
end)

-- Backup chat detection for TextChatService (server also listens to Player.Chatted)
if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
	local function norm(t)
		t = tostring(t or ""):gsub("^%s+", ""):gsub("%s+$", "")
		return Config.Dev.CaseSensitive and t or string.lower(t)
	end
	TextChatService.SendingMessage:Connect(function(message)
		if norm(message.Text) == norm(Config.Dev.ChatCode) then
			DevChat:FireServer(message.Text)
		end
	end)
end

-- Keep counts fresh while open
task.spawn(function()
	while true do
		task.wait(2)
		refreshInventory()
	end
end)

setTarget(player)
showTab(TAB_NAMES[1])
