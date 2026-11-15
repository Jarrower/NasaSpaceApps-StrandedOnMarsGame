--[[
	MissionUI  (ModuleScript)
	Location: StarterPlayer > StarterPlayerScripts > MissionClient > MissionUI

	Small UI kit for Mars Base 7: the same dark theme + Mars-orange accent as
	BuildUI / SurvivalClient, with bigger text for young players.
	Change colours and fonts in UI.THEME.
]]

local TweenService = game:GetService("TweenService")

local UI = {}

UI.THEME = {
	Panel = Color3.fromRGB(18, 19, 25),
	Card = Color3.fromRGB(30, 32, 41),
	Inset = Color3.fromRGB(12, 13, 17),
	Text = Color3.fromRGB(240, 241, 246),
	Sub = Color3.fromRGB(160, 165, 182),
	Accent = Color3.fromRGB(255, 122, 61), -- Mars orange
	AccentDark = Color3.fromRGB(120, 52, 24),
	Good = Color3.fromRGB(92, 222, 140),
	Bad = Color3.fromRGB(255, 88, 88),
	Warn = Color3.fromRGB(255, 196, 70),
	Info = Color3.fromRGB(110, 170, 255),
	Storm = Color3.fromRGB(230, 140, 70),
	Font = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Black = Enum.Font.GothamBlack,
}
local THEME = UI.THEME

UI.FAST = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
UI.SLIDE = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

function UI.create(class, props)
	local inst = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end
local create = UI.create

function UI.corner(p, r)
	return create("UICorner", { CornerRadius = UDim.new(0, r or 10), Parent = p })
end

function UI.stroke(p, color, transparency, thickness)
	return create("UIStroke", {
		Color = color or Color3.new(1, 1, 1), Transparency = transparency or 0.85, Thickness = thickness or 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p,
	})
end

function UI.pad(p, l, t, r, b)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, l or 12), PaddingTop = UDim.new(0, t or l or 12),
		PaddingRight = UDim.new(0, r or l or 12), PaddingBottom = UDim.new(0, b or t or l or 12), Parent = p,
	})
end

function UI.list(p, gap, horizontal, align)
	return create("UIListLayout", {
		Padding = UDim.new(0, gap or 8), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left, Parent = p,
	})
end

function UI.label(parent, props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or THEME.Text
	props.Font = props.Font or THEME.Font
	props.TextSize = props.TextSize or 18
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextWrapped = props.TextWrapped ~= false
	props.Parent = parent
	return create("TextLabel", props)
end

-- Panel with rounded corners and a soft border
function UI.panel(parent, props)
	props.BackgroundColor3 = props.BackgroundColor3 or THEME.Panel
	props.BackgroundTransparency = props.BackgroundTransparency or 0.06
	props.Parent = parent
	local f = create("Frame", props)
	UI.corner(f, 14)
	UI.stroke(f, Color3.new(1, 1, 1), 0.88)
	return f
end

-- Big friendly button
function UI.button(parent, text, color, onClick, props)
	props = props or {}
	props.Text = text
	props.Font = props.Font or THEME.Black
	props.TextSize = props.TextSize or 22
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.AutoButtonColor = false
	props.BackgroundColor3 = color or THEME.Accent
	props.Size = props.Size or UDim2.fromOffset(260, 56)
	props.Parent = parent
	local b = create("TextButton", props)
	UI.corner(b, 12)
	local base = b.BackgroundColor3
	b.MouseEnter:Connect(function()
		TweenService:Create(b, UI.FAST, { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12) }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, UI.FAST, { BackgroundColor3 = base }):Play()
	end)
	b.Activated:Connect(function()
		onClick(b)
	end)
	return b
end

-- Meter row: icon + name + value + bar. Returns a setter(value, max).
function UI.meter(parent, icon, name, color, order)
	local row = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = order, Parent = parent })
	UI.label(row, { Text = icon .. " " .. name, Font = THEME.Bold, TextSize = 18, Size = UDim2.new(1, -60, 0, 22) })
	local value = UI.label(row, {
		Text = "100", Font = THEME.Black, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -60, 0, 0), Size = UDim2.new(0, 60, 0, 22),
	})
	local back = create("Frame", { BackgroundColor3 = THEME.Inset, Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 14), Parent = row })
	UI.corner(back, 7)
	local fill = create("Frame", { BackgroundColor3 = color, Size = UDim2.fromScale(1, 1), Parent = back })
	UI.corner(fill, 7)
	local lastV
	return function(v, max)
		v = math.max(0, math.floor(v or 0))
		local frac = math.clamp(v / (max or 100), 0, 1)
		if v ~= lastV then
			TweenService:Create(fill, UI.SLIDE, { Size = UDim2.fromScale(frac, 1) }):Play()
			lastV = v
		end
		value.Text = tostring(v)
		local low = frac <= 0.3
		fill.BackgroundColor3 = low and THEME.Bad or color
		value.TextColor3 = low and THEME.Bad or THEME.Text
	end, row
end

function UI.fmt(sec)
	sec = math.max(0, math.ceil(sec or 0))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

function UI.tween(inst, props, info)
	local t = TweenService:Create(inst, info or UI.FAST, props)
	t:Play()
	return t
end

return UI
