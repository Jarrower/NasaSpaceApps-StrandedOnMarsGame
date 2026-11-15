--[[
	BuildUI  (ModuleScript)
	Location: StarterPlayer > StarterPlayerScripts > BuildClient > BuildUI

	All the visuals for building. BuildClient handles input/placement and
	tells this module what to show. Change colours/fonts in THEME.

	API:
	  local ui = BuildUI.new(Config, Placement, { OnSelect = fn(typeName), OnDelete = fn(), OnClose = fn() })
	  ui:SetOpen(bool)  ui:IsOpen()  ui:Toggle()
	  ui:SetMode(typeName | "Delete" | nil)
	  ui:SetStatus(text, valid)       -- line under the mode bar
	  ui:Toast(text, kind?)           -- kind: "good" | "bad" | "info" (auto-detected if nil)
	  ui:SetInspect(piece | nil)      -- tooltip that follows the mouse
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local THEME = {
	Panel = Color3.fromRGB(18, 19, 25),
	Card = Color3.fromRGB(30, 32, 41),
	CardHover = Color3.fromRGB(40, 43, 55),
	Inset = Color3.fromRGB(12, 13, 17),
	Text = Color3.fromRGB(240, 241, 246),
	Sub = Color3.fromRGB(145, 150, 168),
	Accent = Color3.fromRGB(255, 122, 61),    -- Mars orange
	AccentDark = Color3.fromRGB(120, 52, 24),
	Good = Color3.fromRGB(92, 222, 140),
	Bad = Color3.fromRGB(255, 88, 88),
	Info = Color3.fromRGB(110, 170, 255),
	Font = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Black = Enum.Font.GothamBlack,
}

local FAST = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

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
	return create("UICorner", { CornerRadius = UDim.new(0, r or 10), Parent = p })
end

local function stroke(p, transparency, color, thickness)
	return create("UIStroke", {
		Color = color or Color3.new(1, 1, 1),
		Transparency = transparency or 0.9,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = p,
	})
end

local function padding(p, all)
	local u = UDim.new(0, all)
	return create("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u, Parent = p })
end

local function label(parent, props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or THEME.Text
	props.Font = props.Font or THEME.Font
	props.TextSize = props.TextSize or 14
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.Parent = parent
	return create("TextLabel", props)
end

local function tween(inst, props, info)
	local t = TweenService:Create(inst, info or FAST, props)
	t:Play()
	return t
end

-- Small keyboard key graphic: [R] Rotate
local function keycap(parent, key, text, order)
	local holder = create("Frame", {
		BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0), LayoutOrder = order or 0, Parent = parent,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder,
	})
	local cap = label(holder, {
		Text = key, Font = THEME.Bold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(12, 22), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0, BackgroundColor3 = THEME.Card, LayoutOrder = 1,
	})
	create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = cap })
	corner(cap, 5)
	stroke(cap, 0.75)
	label(holder, {
		Text = text, TextColor3 = THEME.Sub, TextSize = 13, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 2,
	})
	return holder
end

local function getCounts(player)
	local counts = {}
	local function scan(container)
		if not container then
			return
		end
		for _, t in ipairs(container:GetChildren()) do
			local id = t:IsA("Tool") and t:GetAttribute("ItemId")
			if id then
				counts[id] = (counts[id] or 0) + (t:GetAttribute("Count") or 0)
			end
		end
	end
	scan(player:FindFirstChildOfClass("Backpack"))
	scan(player.Character)
	return counts
end

local function fmtTime(sec)
	sec = math.max(0, math.floor(sec or 0))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

------------------------------------------------------------------ module
local BuildUI = {}
BuildUI.__index = BuildUI
BuildUI.Theme = THEME

function BuildUI.new(Config, Placement, callbacks)
	local self = setmetatable({}, BuildUI)
	self.Config, self.Placement, self.Callbacks = Config, Placement, callbacks or {}
	self.Player = Players.LocalPlayer
	self.Open = false
	self.Category = Config.Build.Categories[1]
	self.Cards = {}
	self.Previews = {}
	self:_build()
	return self
end

function BuildUI:_build()
	local Config = self.Config
	local Keys = Config.Build.Keys

	local gui = create("ScreenGui", {
		Name = "BuildUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = self.Player:WaitForChild("PlayerGui"),
	})
	self.Gui = gui

	---------------------------------------------------------- open button
	local openBtn = create("TextButton", {
		Name = "OpenButton", Text = "", AutoButtonColor = false,
		Size = UDim2.fromOffset(132, 46), Position = UDim2.new(0, 16, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.08, Parent = gui,
	})
	corner(openBtn, 12)
	local openStroke = stroke(openBtn, 0.4, THEME.Accent, 1.5)
	local dot = create("Frame", {
		Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 14, 0.5, -4),
		BackgroundColor3 = THEME.Accent, Parent = openBtn,
	})
	corner(dot, 4)
	label(openBtn, {
		Text = "BUILD", Font = THEME.Black, TextSize = 15,
		Position = UDim2.fromOffset(30, 0), Size = UDim2.new(0, 60, 1, 0),
	})
	local openKey = label(openBtn, {
		Text = Keys.Menu.Name, Font = THEME.Bold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(24, 22), Position = UDim2.new(1, -36, 0.5, -11),
		BackgroundTransparency = 0, BackgroundColor3 = THEME.Card,
	})
	corner(openKey, 5)
	stroke(openKey, 0.75)
	openBtn.MouseEnter:Connect(function()
		tween(openStroke, { Transparency = 0 })
	end)
	openBtn.MouseLeave:Connect(function()
		tween(openStroke, { Transparency = 0.4 })
	end)
	openBtn.MouseButton1Click:Connect(function()
		self:Toggle()
	end)
	self.OpenButton = openBtn

	---------------------------------------------------------- panel
	-- (plain Frame, not CanvasGroup, so the 3D ViewportFrame previews render crisply)
	local panel = create("Frame", {
		Name = "Panel", Size = UDim2.new(0, 330, 0.78, 0), AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -360, 0.5, 0), BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.04,
		ClipsDescendants = true, Visible = false, Parent = gui,
	})
	corner(panel, 16)
	stroke(panel, 0.88)
	create("UISizeConstraint", { MaxSize = Vector2.new(330, 720), MinSize = Vector2.new(300, 360), Parent = panel })
	self.Panel = panel

	-- accent strip
	local strip = create("Frame", {
		Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0, Parent = panel,
	})
	create("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.85) }),
		Parent = strip,
	})

	-- header
	label(panel, {
		Text = "CONSTRUCTION", Font = THEME.Black, TextSize = 20,
		Position = UDim2.fromOffset(18, 16), Size = UDim2.new(1, -70, 0, 24),
	})
	label(panel, {
		Text = "Mars Outpost  •  pick a structure to place", TextColor3 = THEME.Sub, TextSize = 12,
		Position = UDim2.fromOffset(18, 40), Size = UDim2.new(1, -70, 0, 16),
	})
	local closeBtn = create("TextButton", {
		Text = "✕", Font = THEME.Bold, TextSize = 14, TextColor3 = THEME.Sub, AutoButtonColor = false,
		Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -46, 0, 16),
		BackgroundColor3 = THEME.Card, Parent = panel,
	})
	corner(closeBtn, 8)
	closeBtn.MouseEnter:Connect(function()
		tween(closeBtn, { TextColor3 = THEME.Text, BackgroundColor3 = THEME.CardHover })
	end)
	closeBtn.MouseLeave:Connect(function()
		tween(closeBtn, { TextColor3 = THEME.Sub, BackgroundColor3 = THEME.Card })
	end)
	closeBtn.MouseButton1Click:Connect(function()
		self:SetOpen(false)
	end)

	-- tabs
	local tabs = create("Frame", {
		BackgroundColor3 = THEME.Inset, Position = UDim2.fromOffset(14, 70), Size = UDim2.new(1, -28, 0, 36),
		Parent = panel,
	})
	corner(tabs, 10)
	padding(tabs, 3)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = tabs,
	})
	self.Tabs = {}
	local cats = Config.Build.Categories
	for i, cat in ipairs(cats) do
		local tab = create("TextButton", {
			Text = cat, Font = THEME.Bold, TextSize = 12, TextColor3 = THEME.Sub, AutoButtonColor = false,
			Size = UDim2.new(1 / #cats, -3, 1, 0), BackgroundColor3 = THEME.Accent, BackgroundTransparency = 1,
			LayoutOrder = i, Parent = tabs,
		})
		corner(tab, 8)
		tab.MouseButton1Click:Connect(function()
			self:SetCategory(cat)
		end)
		self.Tabs[cat] = tab
	end

	-- cards grid
	local grid = create("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(14, 116),
		Size = UDim2.new(1, -28, 1, -116 - 70), ScrollBarThickness = 3, ScrollBarImageColor3 = THEME.Sub,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = panel,
	})
	create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -5, 0, 192), CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid,
	})
	create("UIPadding", { PaddingBottom = UDim.new(0, 6), PaddingRight = UDim.new(0, 4), Parent = grid })
	self.Grid = grid

	-- footer: delete
	local del = create("TextButton", {
		Text = "", AutoButtonColor = false, Size = UDim2.new(1, -28, 0, 44), Position = UDim2.new(0, 14, 1, -58),
		BackgroundColor3 = Color3.fromRGB(58, 24, 26), Parent = panel,
	})
	corner(del, 10)
	local delStroke = stroke(del, 0.6, THEME.Bad)
	label(del, {
		Text = "Delete mode", Font = THEME.Bold, TextSize = 14, TextColor3 = Color3.fromRGB(255, 190, 190),
		Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -60, 0.6, 0),
	})
	label(del, {
		Text = "Outline = full refund  •  Building = no refund", TextSize = 11, TextColor3 = Color3.fromRGB(200, 140, 140),
		Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.new(1, -60, 0.4, 0),
	})
	local delKey = label(del, {
		Text = Keys.Delete.Name, Font = THEME.Bold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(24, 22), Position = UDim2.new(1, -36, 0.5, -11),
		BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(80, 34, 36),
	})
	corner(delKey, 5)
	del.MouseEnter:Connect(function()
		tween(delStroke, { Transparency = 0 })
	end)
	del.MouseLeave:Connect(function()
		tween(delStroke, { Transparency = 0.6 })
	end)
	del.MouseButton1Click:Connect(function()
		if self.Callbacks.OnDelete then
			self.Callbacks.OnDelete()
		end
	end)
	self.DeleteButton, self.DeleteStroke = del, delStroke

	self:_buildCards()
	self:_buildModeBar()
	self:_buildToasts()
	self:_buildInspect()
	self:SetCategory(self.Category)

	-- spin previews + refresh costs while open
	local angle, acc = 0, 0
	RunService.RenderStepped:Connect(function(dt)
		if not self.Open then
			return
		end
		angle += dt * 0.6
		for _, pv in ipairs(self.Previews) do
			if pv.Card.Visible then
				pv.Camera.CFrame = CFrame.new(pv.Center) * CFrame.Angles(0, angle, 0) * CFrame.Angles(-0.42, 0, 0)
					* CFrame.new(0, 0, pv.Distance)
			end
		end
		acc += dt
		if acc > 0.4 then
			acc = 0
			self:_refreshCosts()
		end
	end)
end

function BuildUI:_buildCards()
	local Config, Placement = self.Config, self.Placement
	local entries = {}
	for name, def in pairs(Config.Buildables) do
		table.insert(entries, { Name = name, Def = def })
	end
	table.sort(entries, function(a, b)
		return (a.Def.Order or 99) < (b.Def.Order or 99)
	end)

	for i, e in ipairs(entries) do
		local def = e.Def
		local card = create("TextButton", {
			Name = e.Name, Text = "", AutoButtonColor = false, BackgroundColor3 = THEME.Card,
			LayoutOrder = i, Parent = self.Grid,
		})
		corner(card, 12)
		local cardStroke = stroke(card, 0.92)

		-- 3D preview
		local vp = create("ViewportFrame", {
			Size = UDim2.new(1, -12, 0, 88), Position = UDim2.fromOffset(6, 6),
			BackgroundColor3 = THEME.Inset, Ambient = Color3.fromRGB(170, 160, 150),
			LightColor = Color3.fromRGB(255, 240, 225), LightDirection = Vector3.new(-1, -1.5, -0.6), Parent = card,
		})
		corner(vp, 9)
		local template = Placement.GetTemplate(e.Name)
		if template then
			local model = template:Clone()
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BaseScript") or d:IsA("ProximityPrompt") or d:IsA("Sound") or d:IsA("ParticleEmitter") then
					d:Destroy()
				end
			end
			model.Parent = vp
			local cam = create("Camera", { FieldOfView = 35, Parent = vp })
			vp.CurrentCamera = cam
			local cf, size = model:GetBoundingBox()
			local radius = size.Magnitude / 2
			table.insert(self.Previews, {
				Card = card, Camera = cam, Center = cf.Position,
				Distance = radius / math.tan(math.rad(17.5)) * 1.05,
			})
		end

		-- size badge
		local badgeText = def.Kind == "Component" and string.upper(def.Size or "") or string.upper(def.Kind)
		local badge = label(vp, {
			Text = badgeText, Font = THEME.Bold, TextSize = 10, TextColor3 = THEME.Sub,
			TextXAlignment = Enum.TextXAlignment.Center, AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 16), Position = UDim2.fromOffset(6, 6),
			BackgroundTransparency = 0.2, BackgroundColor3 = THEME.Panel,
		})
		corner(badge, 5)
		create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = badge })

		label(card, {
			Text = def.DisplayName, Font = THEME.Bold, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(10, 100), Size = UDim2.new(1, -20, 0, 18),
		})
		label(card, {
			Text = def.Description or "", TextSize = 11, TextColor3 = THEME.Sub, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(10, 118), Size = UDim2.new(1, -20, 0, 28),
		})

		-- cost rows
		local costs = create("Frame", {
			BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 148), Size = UDim2.new(1, -20, 0, 38), Parent = card,
		})
		create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = costs })
		local rows = {}
		local items = {}
		for item in pairs(def.Cost or {}) do
			table.insert(items, item)
		end
		table.sort(items)
		for j, item in ipairs(items) do
			local row = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = j, Parent = costs })
			label(row, { Text = Config.ItemName(item), TextSize = 11, TextColor3 = THEME.Sub, Size = UDim2.new(0.65, 0, 1, 0) })
			local amount = label(row, {
				Text = "", Font = THEME.Bold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.new(0.65, 0, 0, 0), Size = UDim2.new(0.35, 0, 1, 0),
			})
			rows[item] = { Label = amount, Need = def.Cost[item] }
		end

		card.MouseEnter:Connect(function()
			tween(card, { BackgroundColor3 = THEME.CardHover })
		end)
		card.MouseLeave:Connect(function()
			tween(card, { BackgroundColor3 = THEME.Card })
		end)
		card.MouseButton1Click:Connect(function()
			if self.Callbacks.OnSelect then
				self.Callbacks.OnSelect(e.Name)
			end
		end)

		self.Cards[e.Name] = { Card = card, Stroke = cardStroke, Rows = rows, Def = def }
	end
	self:_refreshCosts()
end

function BuildUI:_refreshCosts()
	local counts = getCounts(self.Player)
	for _, c in pairs(self.Cards) do
		for item, row in pairs(c.Rows) do
			local have = counts[item] or 0
			row.Label.Text = string.format("%d / %d", have, row.Need)
			row.Label.TextColor3 = have >= row.Need and THEME.Good or THEME.Bad
		end
	end
end

function BuildUI:_buildModeBar()
	local Keys = self.Config.Build.Keys
	local bar = create("Frame", {
		Name = "ModeBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 40),
		Size = UDim2.fromOffset(600, 62), BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.06,
		Visible = false, Parent = self.Gui,
	})
	corner(bar, 14)
	self.ModeStroke = stroke(bar, 0.5, THEME.Accent, 1.5)
	self.ModeBar = bar

	self.ModeTag = label(bar, {
		Text = "PLACING", Font = THEME.Bold, TextSize = 10, TextColor3 = THEME.Accent,
		Position = UDim2.fromOffset(16, 9), Size = UDim2.new(0, 200, 0, 12),
	})
	self.ModeName = label(bar, {
		Text = "", Font = THEME.Black, TextSize = 17,
		Position = UDim2.fromOffset(16, 21), Size = UDim2.new(0, 230, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	self.StatusLabel = label(bar, {
		Text = "", TextSize = 12, TextColor3 = THEME.Sub,
		Position = UDim2.fromOffset(16, 41), Size = UDim2.new(1, -32, 0, 14),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local keys = create("Frame", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 10), Size = UDim2.fromOffset(330, 26), Parent = bar,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = keys,
	})
	self.RotateKey = keycap(keys, Keys.Rotate.Name, "Rotate", 1)
	keycap(keys, "LMB", "Place", 2)
	keycap(keys, Keys.Cancel.Name, "Cancel", 3)
	self.KeysFrame = keys
end

function BuildUI:_buildToasts()
	local holder = create("Frame", {
		Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(320, 400), Parent = self.Gui,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder,
	})
	self.ToastHolder = holder
	self.ToastCount = 0
end

function BuildUI:_buildInspect()
	local box = create("Frame", {
		Name = "Inspect", Size = UDim2.fromOffset(220, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.05, Visible = false, Parent = self.Gui,
	})
	corner(box, 10)
	stroke(box, 0.85)
	padding(box, 10)
	create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = box })
	self.InspectTitle = label(box, { Text = "", Font = THEME.Bold, TextSize = 14, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1 })
	self.InspectBody = label(box, {
		Text = "", TextSize = 12, TextColor3 = THEME.Sub, RichText = true, TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	self.InspectBox = box

	RunService.RenderStepped:Connect(function()
		if box.Visible then
			local m = UserInputService:GetMouseLocation()
			local inset = game:GetService("GuiService"):GetGuiInset()
			box.Position = UDim2.fromOffset(m.X + 18, m.Y - inset.Y + 18)
		end
	end)
end

------------------------------------------------------------------ public
function BuildUI:IsOpen()
	return self.Open
end

function BuildUI:SetOpen(open)
	if self.Open == open then
		return
	end
	self.Open = open
	local panel = self.Panel
	if open then
		self:_refreshCosts()
		panel.Visible = true
		tween(panel, { Position = UDim2.new(0, 16, 0.5, 0) }, SLIDE)
		tween(self.OpenButton, { Position = UDim2.new(0, -160, 0.5, 0) }, SLIDE)
	else
		local t = tween(panel, { Position = UDim2.new(0, -360, 0.5, 0) }, SLIDE)
		t.Completed:Connect(function()
			if not self.Open then
				panel.Visible = false
			end
		end)
		tween(self.OpenButton, { Position = UDim2.new(0, 16, 0.5, 0) }, SLIDE)
		if self.Callbacks.OnClose then
			self.Callbacks.OnClose()
		end
	end
end

function BuildUI:Toggle()
	self:SetOpen(not self.Open)
end

function BuildUI:SetCategory(cat)
	self.Category = cat
	for name, tab in pairs(self.Tabs) do
		local on = name == cat
		tween(tab, { BackgroundTransparency = on and 0 or 1, TextColor3 = on and Color3.fromRGB(25, 15, 10) or THEME.Sub })
	end
	for _, c in pairs(self.Cards) do
		c.Card.Visible = (c.Def.Category or self.Config.Build.Categories[1]) == cat
	end
	self.Grid.CanvasPosition = Vector2.zero
end

function BuildUI:SetMode(mode)
	-- highlight selected card
	for name, c in pairs(self.Cards) do
		local on = name == mode
		c.Stroke.Color = on and THEME.Accent or Color3.new(1, 1, 1)
		c.Stroke.Transparency = on and 0 or 0.92
		c.Stroke.Thickness = on and 2 or 1
	end
	self.DeleteStroke.Transparency = mode == "Delete" and 0 or 0.6

	local bar = self.ModeBar
	if mode == nil then
		local t = tween(bar, { Position = UDim2.new(0.5, 0, 1, 40) }, SLIDE)
		t.Completed:Connect(function()
			if self.CurrentMode == nil then
				bar.Visible = false
			end
		end)
	else
		bar.Visible = true
		-- sits above the default hotbar
		tween(bar, { Position = UDim2.new(0.5, 0, 1, -84) }, SLIDE)
		if mode == "Delete" then
			self.ModeTag.Text = "DELETE MODE"
			self.ModeTag.TextColor3 = THEME.Bad
			self.ModeStroke.Color = THEME.Bad
			self.ModeName.Text = "Click to remove"
			self.RotateKey.Visible = false
		else
			local def = self.Config.Buildables[mode]
			self.ModeTag.Text = "PLACING  •  " .. string.upper(def.Category or "")
			self.ModeTag.TextColor3 = THEME.Accent
			self.ModeStroke.Color = THEME.Accent
			self.ModeName.Text = def.DisplayName
			self.RotateKey.Visible = def.Kind == "Tile" or def.Kind == "Component"
		end
	end
	self.CurrentMode = mode
end

function BuildUI:SetStatus(text, valid)
	self.StatusLabel.Text = text or ""
	if valid == true then
		self.StatusLabel.TextColor3 = THEME.Good
	elseif valid == false then
		self.StatusLabel.TextColor3 = THEME.Bad
	else
		self.StatusLabel.TextColor3 = THEME.Sub
	end
end

local function guessKind(msg)
	local lower = string.lower(msg)
	if string.sub(msg, 1, 1) == "+" or lower:find("built") or lower:find("refunded") or lower:find("added")
		or lower:find("inserted") or lower:find("placed") then
		return "good"
	end
	if lower:find("n't") or lower:find("need") or lower:find("too far") or lower:find("full")
		or lower:find("no ") or lower:find("not ") or lower:find("hold") or lower:find("busy") then
		return "bad"
	end
	return "info"
end

function BuildUI:Toast(msg, kind)
	if not msg or msg == "" then
		return
	end
	kind = kind or guessKind(msg)
	local color = (kind == "good" and THEME.Good) or (kind == "bad" and THEME.Bad) or THEME.Info
	self.ToastCount += 1

	local slot = create("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(320, 48), LayoutOrder = -self.ToastCount,
		Parent = self.ToastHolder,
	})
	local card = create("CanvasGroup", {
		Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(340, 0), BackgroundColor3 = THEME.Panel,
		BackgroundTransparency = 0.04, GroupTransparency = 0, Parent = slot,
	})
	corner(card, 10)
	stroke(card, 0.85)
	create("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0, Parent = card })
	label(card, {
		Text = msg, TextSize = 13, TextWrapped = true, Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -26, 1, 0),
	})
	tween(card, { Position = UDim2.fromOffset(0, 0) }, SLIDE)

	-- keep at most 4 toasts
	local slots = {}
	for _, c in ipairs(self.ToastHolder:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(slots, c)
		end
	end
	table.sort(slots, function(a, b)
		return a.LayoutOrder > b.LayoutOrder
	end)
	for i = 5, #slots do
		slots[i]:Destroy()
	end

	task.delay(3.2, function()
		if slot.Parent then
			local t = tween(card, { GroupTransparency = 1, Position = UDim2.fromOffset(40, 0) }, SLIDE)
			t.Completed:Connect(function()
				slot:Destroy()
			end)
		end
	end)
end

function BuildUI:SetInspect(piece)
	if not piece then
		self.InspectBox.Visible = false
		return
	end
	local Config, Placement = self.Config, self.Placement
	local def = Placement.Def(piece)
	if not def then
		self.InspectBox.Visible = false
		return
	end
	local function yes(b)
		return b and '<font color="#5CDE8C">Yes</font>' or '<font color="#FF5858">No</font>'
	end
	local lines = {}
	if piece:GetAttribute("State") == "Blueprint" then
		table.insert(lines, '<font color="#6EAAFF">Outline</font> - hold materials and press E')
		for item, need in pairs(def.Cost or {}) do
			local have = piece:GetAttribute("Dep_" .. item) or 0
			table.insert(lines, string.format("%s  %d / %d", Config.ItemName(item), have, need))
		end
	else
		if def.Kind ~= "Wall" then
			table.insert(lines, "Powered: " .. yes(piece:GetAttribute("Powered")) .. string.format(
				"  (%d / %d)", piece:GetAttribute("PowerDemand") or 0, piece:GetAttribute("PowerSupply") or 0))
		end
		if def.Kind == "Tile" then
			table.insert(lines, "Enclosed: " .. yes(piece:GetAttribute("Enclosed")))
			table.insert(lines, "Oxygen: " .. yes(piece:GetAttribute("Oxygenated")))
			local why = piece:GetAttribute("OxygenReason")
			if why and not piece:GetAttribute("Oxygenated") then
				table.insert(lines, '<font color="#FFB04A">' .. why .. "</font>")
			end
		end
		-- water
		if def.Kind == "Tile" or def.Kind == "Linear" then
			local cap = piece:GetAttribute("WaterCapacity") or 0
			local wIn, wOut = piece:GetAttribute("WaterIn") or 0, piece:GetAttribute("WaterOut") or 0
			if cap > 0 or wIn > 0 or wOut > 0 then
				table.insert(lines, string.format("Water: %d / %d stored  (+%g/s, -%g/s)",
					piece:GetAttribute("WaterStored") or 0, cap, wIn, wOut))
			end
		end
		if def.WaterCapacity then
			table.insert(lines, string.format("Tank: %d / %d water", piece:GetAttribute("Water") or 0, def.WaterCapacity))
		end
		if def.WaterOutput then
			table.insert(lines, string.format("Pumps: +%g water/s %s", def.WaterOutput, piece:GetAttribute("Powered") and "" or "(no power)"))
		end
		if def.WaterUse or def.Plots then
			table.insert(lines, "Water supply: " .. yes(piece:GetAttribute("Watered") ~= false))
		end
		if def.Plots then
			table.insert(lines, string.format("Growing plots: %d / %d", piece:GetAttribute("GrowingPlots") or 0, def.Plots))
		end
		if def.OxygenCapacity then
			table.insert(lines, "Fills: " .. def.OxygenCapacity .. " oxygen units (small tile = 1, large = 2)")
		end
		if def.Fuel then
			table.insert(lines, "Fuel: " .. fmtTime(piece:GetAttribute("FuelTime")))
		end
		if def.PowerOutput then
			table.insert(lines, "Output: " .. def.PowerOutput .. " power")
		elseif def.PowerDraw then
			table.insert(lines, "Uses: " .. def.PowerDraw .. " power")
		end
	end
	self.InspectTitle.Text = def.DisplayName
	self.InspectBody.Text = table.concat(lines, "\n")
	self.InspectBox.Visible = true
end

return BuildUI
