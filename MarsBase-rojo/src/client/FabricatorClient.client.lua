--[[
	FabricatorClient  (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > FabricatorClient

	Opens when you press [E] on your Fabricator. Shows suits (craft / equip)
	and item recipes (O2 Canisters). The server (SuitService) checks every
	craft. Closes when you walk away, press Q/Esc or click X.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("BaseShared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("BaseRemotes")
local OpenEvent = remotes:WaitForChild("FabricatorOpen")
local Action = remotes:WaitForChild("FabricatorAction")

local THEME = {
	Panel = Color3.fromRGB(18, 19, 25), Card = Color3.fromRGB(30, 32, 41), Inset = Color3.fromRGB(12, 13, 17),
	Text = Color3.fromRGB(240, 241, 246), Sub = Color3.fromRGB(145, 150, 168),
	Accent = Color3.fromRGB(90, 200, 230), Good = Color3.fromRGB(92, 222, 140), Bad = Color3.fromRGB(255, 88, 88),
	Font = Enum.Font.GothamMedium, Bold = Enum.Font.GothamBold, Black = Enum.Font.GothamBlack,
}

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
local function label(parent, props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or THEME.Text
	props.Font = props.Font or THEME.Font
	props.TextSize = props.TextSize or 13
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.Parent = parent
	return create("TextLabel", props)
end
local function counts()
	local c = {}
	for _, bag in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		for _, t in ipairs(bag and bag:GetChildren() or {}) do
			local id = t:IsA("Tool") and t:GetAttribute("ItemId")
			if id then
				c[id] = (c[id] or 0) + (t:GetAttribute("Count") or 0)
			end
		end
	end
	return c
end

------------------------------------------------------------------ window
local gui = create("ScreenGui", { Name = "FabricatorUI", ResetOnSpawn = false, Enabled = false, DisplayOrder = 20, Parent = player:WaitForChild("PlayerGui") })
local win = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 440),
	BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.03, Parent = gui,
})
corner(win, 16)
create("UIStroke", { Color = THEME.Accent, Transparency = 0.5, Thickness = 1.5, Parent = win })
local scale = create("UIScale", { Scale = 1, Parent = win })

label(win, { Text = "FABRICATOR", Font = THEME.Black, TextSize = 20, Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -80, 0, 24) })
label(win, { Text = "Craft suits and survival gear", TextSize = 12, TextColor3 = THEME.Sub, Position = UDim2.fromOffset(20, 40), Size = UDim2.new(1, -80, 0, 16) })
local closeBtn = create("TextButton", {
	Text = "✕", Font = THEME.Bold, TextSize = 14, TextColor3 = THEME.Sub, Size = UDim2.fromOffset(30, 30),
	Position = UDim2.new(1, -48, 0, 16), BackgroundColor3 = THEME.Card, Parent = win,
})
corner(closeBtn, 8)

local list = create("ScrollingFrame", {
	Position = UDim2.fromOffset(16, 70), Size = UDim2.new(1, -32, 1, -112), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = win,
})
create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
create("UIPadding", { PaddingRight = UDim.new(0, 6), Parent = list })

local status = label(win, { Text = "", TextSize = 12, TextColor3 = THEME.Sub, Position = UDim2.new(0, 20, 1, -34), Size = UDim2.new(1, -40, 0, 20) })

------------------------------------------------------------------ content
local currentModel, entries
local rows = {}

local function close()
	if not gui.Enabled then
		return
	end
	gui.Enabled = false
	currentModel = nil
end
closeBtn.MouseButton1Click:Connect(close)

local function render()
	for _, r in ipairs(rows) do
		r:Destroy()
	end
	rows = {}
	local have = counts()
	local currentSuit = player:GetAttribute("Suit")
	local ownedList = string.split(player:GetAttribute("OwnedSuits") or "", ",")

	for i, e in ipairs(entries or {}) do
		local row = create("Frame", { BackgroundColor3 = THEME.Card, Size = UDim2.new(1, 0, 0, 92), LayoutOrder = i, Parent = list })
		corner(row, 12)
		table.insert(rows, row)

		local title = e.Kind == "Item" and string.format("%s  x%d", e.Name, e.Amount) or e.Name
		label(row, { Text = title, Font = THEME.Bold, TextSize = 15, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(0.6, 0, 0, 20) })
		local info
		if e.Kind == "Suit" then
			info = string.format("Air: %s  •  Storm protection: %d%%", string.format("%d:%02d", e.TankSeconds // 60, e.TankSeconds % 60), math.floor((e.StormProtection or 0) * 100))
		else
			info = string.format("Restores %ds of air when used outside", Config.Breathing.Canister.Seconds)
		end
		label(row, { Text = info, TextSize = 12, TextColor3 = THEME.Sub, Position = UDim2.fromOffset(14, 32), Size = UDim2.new(0.62, 0, 0, 16) })

		-- cost chips
		local chips = create("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 56), Size = UDim2.new(0.68, 0, 0, 24), Parent = row })
		create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = chips })
		local affordable = true
		local items = {}
		for item in pairs(e.Cost or {}) do
			table.insert(items, item)
		end
		table.sort(items)
		for _, item in ipairs(items) do
			local need, got = e.Cost[item], have[item] or 0
			if got < need then
				affordable = false
			end
			local chip = label(chips, {
				Text = string.format("%s %d/%d", Config.ItemName(item), got, need), Font = THEME.Bold, TextSize = 11,
				TextColor3 = got >= need and THEME.Good or THEME.Bad, AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 22), BackgroundTransparency = 0, BackgroundColor3 = THEME.Inset,
			})
			corner(chip, 6)
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = chip })
		end
		if #items == 0 then
			label(chips, { Text = "Free starter suit", TextSize = 11, TextColor3 = THEME.Sub, Size = UDim2.fromOffset(140, 22) })
		end

		-- action button
		local text, color, action, enabled
		if e.Kind == "Suit" then
			local owns = e.Id == Config.Breathing.StartingSuit or table.find(ownedList, e.Id) ~= nil
			if e.Id == currentSuit then
				text, color, enabled = "Equipped", THEME.Inset, false
			elseif owns then
				text, color, action, enabled = "Equip", THEME.Accent, "EquipSuit", true
			else
				text, color, action, enabled = "Craft", affordable and THEME.Good or THEME.Inset, "CraftSuit", affordable
			end
		else
			text, color, action, enabled = "Craft", affordable and THEME.Good or THEME.Inset, "CraftItem", affordable
		end
		local btn = create("TextButton", {
			Text = text, Font = THEME.Bold, TextSize = 14, AutoButtonColor = enabled,
			TextColor3 = enabled and Color3.fromRGB(15, 20, 25) or THEME.Sub, BackgroundColor3 = color,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(110, 40), Parent = row,
		})
		corner(btn, 10)
		if enabled then
			btn.MouseButton1Click:Connect(function()
				btn.Text = "..."
				local ok, msg = Action:InvokeServer(action, currentModel, e.Id)
				status.Text = msg or ""
				status.TextColor3 = ok and THEME.Good or THEME.Bad
				task.wait(0.15)
				render()
			end)
		end
	end
end

OpenEvent.OnClientEvent:Connect(function(model, list_)
	currentModel, entries = model, list_
	status.Text = ""
	render()
	gui.Enabled = true
	scale.Scale = 0.9
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end)

-- live cost refresh + auto close when walking away
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	if not gui.Enabled then
		return
	end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local center = currentModel and currentModel.Parent and currentModel:GetAttribute("Center")
	if not hrp or not center or (hrp.Position - center.Position).Magnitude > 25 then
		close()
		return
	end
	acc += dt
	if acc > 1 then
		acc = 0
		render()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Config.Build.Keys.Cancel then
		close()
	end
end)
