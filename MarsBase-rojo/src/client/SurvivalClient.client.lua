--[[
	SurvivalClient  (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > SurvivalClient

	Client side of oxygen + weather (all local visuals, the server decides
	everything that matters):
	  - O2 HUD (bottom left): suit, seconds of air, bar, status
	  - Low-air warnings: red screen edges, blur, optional sounds
	  - Weather banner (top centre): warning countdown / storm timer
	  - Dust storm visuals: Atmosphere, colour tint, blowing dust particles
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("BaseShared"):WaitForChild("Config"))
local camera = workspace.CurrentCamera

local THEME = {
	Panel = Color3.fromRGB(18, 19, 25), Inset = Color3.fromRGB(12, 13, 17),
	Text = Color3.fromRGB(240, 241, 246), Sub = Color3.fromRGB(145, 150, 168),
	O2 = Color3.fromRGB(90, 190, 255), Warn = Color3.fromRGB(255, 160, 60), Bad = Color3.fromRGB(255, 80, 80),
	Good = Color3.fromRGB(92, 222, 140), Storm = Color3.fromRGB(230, 140, 70),
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
local function fmt(sec)
	sec = math.max(0, math.floor(sec or 0))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local gui = create("ScreenGui", { Name = "SurvivalHUD", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = player:WaitForChild("PlayerGui") })

------------------------------------------------------------------ warning edges
local edges = {}
local function edge(size, pos, rotation)
	local f = create("Frame", {
		Size = size, Position = pos, BackgroundColor3 = THEME.Bad, BorderSizePixel = 0,
		BackgroundTransparency = 1, Parent = gui,
	})
	create("UIGradient", {
		Rotation = rotation,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Parent = f,
	})
	table.insert(edges, f)
end
edge(UDim2.new(1, 0, 0.18, 0), UDim2.new(0, 0, 0, 0), 90)
edge(UDim2.new(1, 0, 0.18, 0), UDim2.new(0, 0, 0.82, 0), -90)
edge(UDim2.new(0.12, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0)
edge(UDim2.new(0.12, 0, 1, 0), UDim2.new(0.88, 0, 0, 0), 180)

------------------------------------------------------------------ O2 panel
local panel = create("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(270, 82),
	BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.06, Parent = gui,
})
corner(panel, 14)
local panelStroke = create("UIStroke", { Color = THEME.O2, Transparency = 0.6, Thickness = 1.5, Parent = panel })

label(panel, { Text = "O₂", Font = THEME.Black, TextSize = 18, TextColor3 = THEME.O2, Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(30, 22) })
local suitLabel = label(panel, { Text = "", TextSize = 11, TextColor3 = THEME.Sub, Position = UDim2.fromOffset(46, 14), Size = UDim2.new(1, -130, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd })
local timeLabel = label(panel, {
	Text = "0:00", Font = THEME.Black, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right,
	Position = UDim2.new(1, -94, 0, 8), Size = UDim2.fromOffset(80, 24),
})
local barBack = create("Frame", { BackgroundColor3 = THEME.Inset, Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 10), Parent = panel })
corner(barBack, 5)
local barFill = create("Frame", { BackgroundColor3 = THEME.O2, Size = UDim2.fromScale(1, 1), Parent = barBack })
corner(barFill, 5)
local dot = create("Frame", { BackgroundColor3 = THEME.Good, Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(14, 60), Parent = panel })
corner(dot, 4)
local statusLabel = label(panel, { Text = "", TextSize = 12, Position = UDim2.fromOffset(28, 55), Size = UDim2.new(1, -40, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })

------------------------------------------------------------------ weather banner
local banner = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(420, 56),
	BackgroundColor3 = THEME.Panel, BackgroundTransparency = 0.06, Visible = false, Parent = gui,
})
corner(banner, 14)
local bannerStroke = create("UIStroke", { Color = THEME.Storm, Transparency = 0.3, Thickness = 1.5, Parent = banner })
local bannerTitle = label(banner, { Text = "", Font = THEME.Black, TextSize = 16, TextColor3 = THEME.Storm, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 20) })
local bannerSub = label(banner, { Text = "", TextSize = 12, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 16) })

------------------------------------------------------------------ effects
local blur = Instance.new("BlurEffect")
blur.Size = 0
blur.Parent = camera
local tint = Instance.new("ColorCorrectionEffect")
tint.Parent = camera

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
	atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0
	atmosphere.Parent = Lighting
end
local baseAtmo = {
	Density = atmosphere.Density, Haze = atmosphere.Haze,
	Color = atmosphere.Color, Decay = atmosphere.Decay,
}

-- dust particles: an invisible box that follows the camera
local dustBox = create("Part", {
	Name = "DustBox", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
	Transparency = 1, Size = Vector3.new(120, 50, 120), Parent = camera,
})
local dust = create("ParticleEmitter", {
	Rate = 0, Lifetime = NumberRange.new(1.5, 3), Speed = NumberRange.new(30, 55),
	Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	EmissionDirection = Enum.NormalId.Right, SpreadAngle = Vector2.new(15, 15),
	Acceleration = Vector3.new(10, -2, 4),
	Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.55), NumberSequenceKeypoint.new(1, 1) }),
	Texture = "rbxasset://textures/particles/smoke_main.dds", LightInfluence = 0.6,
	Parent = dustBox,
})

local windSound = Instance.new("Sound")
windSound.Looped = true
windSound.Volume = 0
windSound.Parent = gui
local warnSound, breathSound
if Config.Breathing.Sounds.Warning then
	warnSound = create("Sound", { SoundId = Config.Breathing.Sounds.Warning, Parent = gui })
end
if Config.Breathing.Sounds.Breathing then
	breathSound = create("Sound", { SoundId = Config.Breathing.Sounds.Breathing, Looped = true, Volume = 0, Parent = gui })
	breathSound:Play()
end

------------------------------------------------------------------ update loop
local intensity = 0          -- smoothed storm intensity (0..1)
local lastVis                -- keeps fading the last storm's look after it ends
local lastWarnLevel = 0
local pulse = 0

local function lerp(a, b, t)
	return a + (b - a) * t
end

RunService.RenderStepped:Connect(function(dt)
	pulse += dt
	-------------------------------------------------- oxygen
	local o2 = player:GetAttribute("O2")
	local max = player:GetAttribute("O2Max") or 90
	local status = player:GetAttribute("AirStatus") or "Outside"
	local infinite = player:GetAttribute("InfiniteO2")
	local suitId = player:GetAttribute("Suit")
	local suitDef = suitId and Config.Suits[suitId]
	panel.Visible = Config.Breathing.Enabled and o2 ~= nil

	local frac = o2 and math.clamp(o2 / max, 0, 1) or 1
	suitLabel.Text = (suitDef and suitDef.DisplayName or "Suit") .. (infinite and "  •  INFINITE" or "")
	timeLabel.Text = fmt(o2)
	barFill.Size = UDim2.fromScale(frac, 1)

	local color = THEME.O2
	if status ~= "Pressurized" and frac <= Config.Breathing.CriticalAt then
		color = THEME.Bad
	elseif status ~= "Pressurized" and frac <= Config.Breathing.WarnAt then
		color = THEME.Warn
	end
	barFill.BackgroundColor3 = color
	panelStroke.Color = color
	timeLabel.TextColor3 = color == THEME.O2 and THEME.Text or color

	if status == "Pressurized" then
		statusLabel.Text, dot.BackgroundColor3 = "Pressurized - breathing room air", THEME.Good
	elseif status == "Leaking" then
		statusLabel.Text, dot.BackgroundColor3 = "Room losing pressure! Air running out", THEME.Warn
	elseif status == "Suffocating" then
		statusLabel.Text, dot.BackgroundColor3 = "NO AIR - get inside or use an O2 Canister!", THEME.Bad
	else
		local extra = player:GetAttribute("Exerted") and "  •  working hard" or ""
		statusLabel.Text, dot.BackgroundColor3 = "Mars atmosphere - using suit air" .. extra, THEME.Warn
	end

	-- warning effects
	local level = 0
	if status ~= "Pressurized" and not infinite then
		if status == "Suffocating" or frac <= Config.Breathing.CriticalAt then
			level = 2
		elseif frac <= Config.Breathing.WarnAt then
			level = 1
		end
	end
	local edgeT = 1
	if level == 2 then
		edgeT = 0.45 + 0.25 * math.sin(pulse * 6)
	elseif level == 1 then
		edgeT = 0.8 + 0.1 * math.sin(pulse * 3)
	end
	for _, e in ipairs(edges) do
		e.BackgroundTransparency = edgeT
	end
	blur.Size = lerp(blur.Size, status == "Suffocating" and 14 or (level == 2 and 4 or 0), math.min(1, dt * 3))
	if level > lastWarnLevel and warnSound then
		warnSound:Play()
	end
	lastWarnLevel = level
	if breathSound then
		breathSound.Volume = lerp(breathSound.Volume, level == 2 and 0.8 or 0, math.min(1, dt * 2))
	end

	-------------------------------------------------- weather
	local eventId = workspace:GetAttribute("WeatherEvent") or ""
	local phase = workspace:GetAttribute("WeatherPhase") or "Clear"
	local ends = workspace:GetAttribute("WeatherPhaseEnds") or 0
	local ev = Config.Weather.Events[eventId]
	local left = ends - workspace:GetServerTimeNow()

	local target = 0
	if ev and phase == "Active" then
		target = 1
	elseif ev and phase == "Warning" then
		target = 0.12 -- haze builds on the horizon
	end
	local rate = dt / math.max(Config.Weather.RampTime, 0.1)
	if intensity < target then
		intensity = math.min(target, intensity + rate)
	else
		intensity = math.max(target, intensity - rate)
	end

	local vis = ev and ev.Visual
	lastVis = vis or lastVis
	if intensity > 0.001 and not vis then
		vis = lastVis
	end
	if vis then
		atmosphere.Density = lerp(baseAtmo.Density, vis.AtmosphereDensity, intensity)
		atmosphere.Haze = lerp(baseAtmo.Haze, vis.AtmosphereHaze, intensity)
		atmosphere.Color = baseAtmo.Color:Lerp(vis.AtmosphereColor, intensity)
		atmosphere.Decay = baseAtmo.Decay:Lerp(vis.AtmosphereDecay, intensity)
		tint.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 225, 200), intensity)
		tint.Contrast = -0.1 * intensity
		local inside = player:GetAttribute("Inside")
		dust.Rate = vis.ParticleRate * intensity * (inside and 0.08 or 1)
		dust.Color = ColorSequence.new(vis.ParticleColor)
		if vis.WindSoundId and windSound.SoundId ~= vis.WindSoundId then
			windSound.SoundId = vis.WindSoundId
			windSound:Play()
		end
		windSound.Volume = intensity * (inside and 0.25 or 0.8)
	elseif intensity <= 0.001 then
		atmosphere.Density, atmosphere.Haze = baseAtmo.Density, baseAtmo.Haze
		atmosphere.Color, atmosphere.Decay = baseAtmo.Color, baseAtmo.Decay
		tint.TintColor, tint.Contrast = Color3.new(1, 1, 1), 0
		dust.Rate = 0
		windSound.Volume = 0
	end
	dustBox.CFrame = CFrame.new(camera.CFrame.Position) * CFrame.new(-30, 0, 0)

	-- banner
	if ev and phase == "Warning" then
		banner.Visible = true
		bannerTitle.Text = string.upper(ev.DisplayName) .. " INCOMING  •  " .. fmt(left)
		bannerSub.Text = "Get inside a pressurized room before it hits"
		bannerStroke.Transparency = 0.2 + 0.3 * math.abs(math.sin(pulse * 2))
	elseif ev and phase == "Active" then
		banner.Visible = true
		bannerTitle.Text = string.upper(ev.DisplayName) .. "  •  " .. fmt(left) .. " left"
		local fx = ev.Effects or {}
		local bits = {}
		if (fx.O2Drain or 1) > 1 then
			table.insert(bits, string.format("air drains x%g", fx.O2Drain))
		end
		if (fx.WalkSpeed or 1) < 1 then
			table.insert(bits, "slower movement")
		end
		if (fx.Solar or 1) < 1 then
			table.insert(bits, "solar weakened")
		end
		if (fx.Damage or 0) > 0 then
			table.insert(bits, "damage outside")
		end
		bannerSub.Text = "Outside: " .. table.concat(bits, "  •  ")
		bannerStroke.Transparency = 0.2
	elseif ev and phase == "Ending" then
		banner.Visible = true
		bannerTitle.Text = string.upper(ev.DisplayName) .. " PASSING"
		bannerSub.Text = "Conditions improving"
	else
		banner.Visible = false
	end
end)
