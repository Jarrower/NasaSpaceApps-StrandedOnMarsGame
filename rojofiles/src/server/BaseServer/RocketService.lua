--[[
	RocketService  (ModuleScript)
	Location: ServerScriptService > BaseServer > RocketService
	Mission mode only.

	Uses a Model named Config.Mission.RocketModelName ("RocketCapsule") found
	anywhere in Workspace. If there is none, a simple placeholder capsule is
	built while the game runs (nothing is saved to your place).

	The rocket stands on Workspace > MissionBase > RocketPad > Pad (top centre).
	All its parts are anchored and it is moved with PivotTo, so physics and
	Mars gravity can't knock it over. An engine glow ("MissionEngine") is
	added under it while the game runs.

	API: Rocket.Reset()            stand on the pad, engine off
	     Rocket.Land(seconds)      drop in from the sky (intro)
	     Rocket.Launch(seconds)    lift off (victory)
	     Rocket.GetModel()
]]

local RunService = game:GetService("RunService")

local Rocket = {}
local S, MC
local model, engine
local restCF, height = nil, 0
local token = 0

------------------------------------------------------------------ building
local function part(props)
	local p = Instance.new(props.Class or "Part")
	props.Class = nil
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function buildPlaceholder()
	local m = Instance.new("Model")
	m.Name = MC.RocketModelName .. " (placeholder)"
	local white, orange = Color3.fromRGB(235, 235, 230), Color3.fromRGB(255, 122, 61)
	local up = CFrame.Angles(0, 0, math.rad(90)) -- cylinders point along X; turn them upright
	local body = part({ Name = "Body", Shape = Enum.PartType.Cylinder, Size = Vector3.new(22, 8, 8), Color = white,
		Material = Enum.Material.SmoothPlastic, CFrame = CFrame.new(0, 13, 0) * up, Parent = m })
	part({ Name = "Stripe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, 8.3, 8.3), Color = orange,
		Material = Enum.Material.SmoothPlastic, CFrame = CFrame.new(0, 18, 0) * up, Parent = m })
	part({ Name = "Nose", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8), Color = white,
		Material = Enum.Material.SmoothPlastic, CFrame = CFrame.new(0, 24, 0), Parent = m })
	part({ Name = "Tip", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Color = orange,
		Material = Enum.Material.Neon, CFrame = CFrame.new(0, 28, 0), Parent = m })
	part({ Name = "Window", Size = Vector3.new(0.4, 2.5, 2.5), Color = Color3.fromRGB(90, 190, 255),
		Material = Enum.Material.Glass, Transparency = 0.2, CFrame = CFrame.new(4, 20, 0), Parent = m })
	part({ Name = "Nozzle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 5, 5), Color = Color3.fromRGB(60, 62, 70),
		Material = Enum.Material.Metal, CFrame = CFrame.new(0, 1, 0) * up, Parent = m })
	for i = 0, 2 do
		local a = math.rad(120 * i)
		part({ Class = "WedgePart", Name = "Fin", Size = Vector3.new(0.6, 6, 4), Color = orange,
			Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.Angles(0, a, 0) * CFrame.new(0, 4, 5) * CFrame.Angles(0, math.rad(180), 0), Parent = m })
	end
	m.PrimaryPart = body
	m.Parent = workspace
	return m
end

local function findModel()
	local m = workspace:FindFirstChild(MC.RocketModelName, true)
	if m and m:IsA("Model") then
		return m
	end
	warn("[Rocket] No Model named '" .. MC.RocketModelName .. "' in Workspace - using a placeholder capsule")
	return buildPlaceholder()
end

local function padTop()
	local base = workspace:FindFirstChild("MissionBase")
	local padFolder = base and base:FindFirstChild("RocketPad")
	local pad = padFolder and padFolder:FindFirstChild("Pad")
	if pad and pad:IsA("BasePart") then
		-- top of the pad, whatever way the part is rotated
		local cf, size = pad.CFrame, pad.Size
		local halfY = 0.5 * (math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.RightVector.Y) * size.X + math.abs(cf.LookVector.Y) * size.Z)
		return Vector3.new(pad.Position.X, pad.Position.Y + halfY, pad.Position.Z)
	end
	warn("[Rocket] No MissionBase.RocketPad.Pad - the rocket stands at (150, 4, 30)")
	return Vector3.new(150, 4, 30)
end

-- lowest world Y of all parts (works for any model)
local function bottomY(m)
	local low = math.huge
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "MissionEngine" then
			local cf, s = p.CFrame, p.Size
			local halfY = 0.5 * (math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.RightVector.Y) * s.X + math.abs(cf.LookVector.Y) * s.Z)
			low = math.min(low, p.Position.Y - halfY)
		end
	end
	return low
end

local function makeEngine()
	local cf, size = model:GetBoundingBox()
	engine = part({ Name = "MissionEngine", Size = Vector3.new(2, 1, 2), Transparency = 1, CanCollide = false,
		CanQuery = false, CanTouch = false, CFrame = CFrame.new(cf.Position.X, bottomY(model) - 0.5, cf.Position.Z),
		Parent = model })
	local fire = Instance.new("ParticleEmitter")
	fire.Name = "Flame"
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.EmissionDirection = Enum.NormalId.Bottom
	fire.Rate = 0
	fire.Speed = NumberRange.new(25, 40)
	fire.Lifetime = NumberRange.new(0.3, 0.6)
	fire.SpreadAngle = Vector2.new(12, 12)
	fire.LightEmission = 1
	fire.Size = NumberSequence.new(math.max(2, size.X * 0.35), 0.5)
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 230, 140), Color3.fromRGB(255, 90, 30))
	fire.Parent = engine
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.EmissionDirection = Enum.NormalId.Bottom
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(10, 20)
	smoke.Lifetime = NumberRange.new(1.5, 3)
	smoke.SpreadAngle = Vector2.new(60, 60)
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 140, 100))
	smoke.Size = NumberSequence.new(3, 10)
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Parent = engine
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(255, 150, 70)
	light.Range = 30
	light.Brightness = 4
	light.Enabled = false
	light.Parent = engine
	if MC.Sounds and MC.Sounds.Launch then
		local snd = Instance.new("Sound")
		snd.Name = "Roar"
		snd.SoundId = MC.Sounds.Launch
		snd.Volume = 1
		snd.RollOffMaxDistance = 600
		snd.Parent = engine
	end
end

local function setEngine(on)
	if not engine then
		return
	end
	engine.Flame.Rate = on and 250 or 0
	engine.Smoke.Rate = on and 60 or 0
	engine.Glow.Enabled = on
	local roar = engine:FindFirstChild("Roar")
	if roar then
		if on then
			roar:Play()
		else
			roar:Stop()
		end
	end
end

local function place(h)
	height = h
	if model and restCF then
		model:PivotTo(restCF + Vector3.new(0, h, 0))
	end
end

-- Move from height a to b over `seconds` with an easing function f(t)
local function animate(a, b, seconds, f, done)
	token += 1
	local my = token
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if my ~= token then
			conn:Disconnect()
			return
		end
		local t = math.clamp((os.clock() - t0) / math.max(seconds, 0.05), 0, 1)
		place(a + (b - a) * f(t))
		if t >= 1 then
			conn:Disconnect()
			if done then
				done()
			end
		end
	end)
end

------------------------------------------------------------------ API
function Rocket.GetModel()
	return model
end

function Rocket.Reset()
	token += 1
	setEngine(false)
	place(0)
end

function Rocket.Land(seconds)
	local start = 260
	place(start)
	setEngine(true)
	animate(start, 0, seconds, function(t)
		return 1 - (1 - t) ^ 3 -- slows down as it lands
	end, function()
		task.delay(0.6, function()
			if height == 0 then
				setEngine(false)
			end
		end)
	end)
end

function Rocket.Launch(seconds)
	setEngine(true)
	animate(0, 900, seconds, function(t)
		return t * t * t -- speeds up as it climbs
	end)
end

function Rocket.Init(services)
	S = services
	MC = S.Config.Mission
	local ok, err = pcall(function()
		model = findModel()
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
			end
		end
		local pivot = model:GetPivot()
		local top = padTop()
		local offset = pivot.Position.Y - bottomY(model) -- pivot height above the model's lowest point
		restCF = CFrame.new(top.X, top.Y + offset, top.Z) * (pivot - pivot.Position)
		-- centre the model's footprint on the pad
		model:PivotTo(restCF)
		local bb = model:GetBoundingBox()
		restCF += Vector3.new(top.X - bb.Position.X, 0, top.Z - bb.Position.Z)
		model:PivotTo(restCF)
		makeEngine()
	end)
	if not ok then
		warn("[Rocket] Setup failed: " .. tostring(err))
	end
end

return Rocket
