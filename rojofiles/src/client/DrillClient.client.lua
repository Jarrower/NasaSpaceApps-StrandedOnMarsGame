--[[
	DrillClient  (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > DrillClient

	PC drilling: equip a tool with a BoolValue "Miner" and click an ore.
	Each click sends one hit to the server (MiningService checks range, tier
	and cooldown). Local feedback: sparks, a small camera shake, and a health
	bar over damaged ores. Mobile/console players use the ore's Mine prompt.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("BaseShared"):WaitForChild("Config"))
if Config.GameMode == "Mission" then
	return -- sandbox only (Mars Base 7 mission uses MissionClient)
end
local DrillHit = ReplicatedStorage:WaitForChild("BaseRemotes"):WaitForChild("DrillHit")
local camera = workspace.CurrentCamera

local THEME = {
	Panel = Color3.fromRGB(18, 19, 25), Good = Color3.fromRGB(92, 222, 140),
	Warn = Color3.fromRGB(255, 170, 60), Bad = Color3.fromRGB(255, 80, 80), Text = Color3.fromRGB(240, 241, 246),
}

------------------------------------------------------------------ helpers
local function equippedDrill()
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	local v = tool and tool:FindFirstChild(Config.Mining.MinerValueName)
	if v and v:IsA("BoolValue") and v.Value then
		return tool
	end
	return nil
end

local function oreFrom(inst)
	while inst and inst ~= workspace do
		if inst:IsA("Model") and inst:GetAttribute("OreMaxHealth") then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function mouseHit()
	local ignore = { camera }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	local mp = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mp.X, mp.Y)
	return workspace:Raycast(ray.Origin, ray.Direction * 200, rayParams)
end

------------------------------------------------------------------ effects
local sparkPart = Instance.new("Part")
sparkPart.Anchored, sparkPart.CanCollide, sparkPart.CanQuery, sparkPart.CanTouch = true, false, false, false
sparkPart.Transparency = 1
sparkPart.Size = Vector3.new(0.2, 0.2, 0.2)
sparkPart.Parent = camera
local sparks = Instance.new("ParticleEmitter")
sparks.Enabled = false
sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120))
sparks.LightEmission = 1
sparks.Lifetime = NumberRange.new(0.2, 0.45)
sparks.Speed = NumberRange.new(12, 22)
sparks.SpreadAngle = Vector2.new(60, 60)
sparks.Acceleration = Vector3.new(0, -40, 0)
sparks.Size = NumberSequence.new(0.35, 0)
sparks.Parent = sparkPart
local dust = sparks:Clone()
dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
dust.Color = ColorSequence.new(Color3.fromRGB(170, 120, 90))
dust.LightEmission = 0
dust.Speed = NumberRange.new(3, 6)
dust.Acceleration = Vector3.new(0, 2, 0)
dust.Size = NumberSequence.new(0.8, 2)
dust.Transparency = NumberSequence.new(0.4, 1)
dust.Parent = sparkPart

local function shake()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	task.spawn(function()
		for _ = 1, 4 do
			hum.CameraOffset = Vector3.new(math.random(-10, 10) / 100, math.random(-10, 10) / 100, 0)
			task.wait(0.03)
		end
		hum.CameraOffset = Vector3.zero
	end)
end

------------------------------------------------------------------ clicking
local lastClick = 0
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local tool = equippedDrill()
	if not tool then
		return
	end
	local tier = math.clamp(player:GetAttribute("DrillTier") or 0, 0, Config.Drill.MaxTier)
	local cooldown = Config.Drill.Tiers[tier].Cooldown
	if os.clock() - lastClick < cooldown then
		return
	end
	local hit = mouseHit()
	local ore = hit and oreFrom(hit.Instance)
	if not ore or ore:GetAttribute("Depleted") then
		return
	end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - hit.Position).Magnitude > Config.Drill.Range then
		return
	end
	lastClick = os.clock()
	DrillHit:FireServer(hit.Instance)
	if (ore:GetAttribute("OreTier") or 0) <= tier then
		sparkPart.CFrame = CFrame.lookAt(hit.Position, hit.Position + hit.Normal)
		sparks:Emit(14)
		dust:Emit(4)
		shake()
	end
end)

------------------------------------------------------------------ health bars
local gui = Instance.new("ScreenGui")
gui.Name = "OreBars"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local ores = {}
local bars = {} -- [ore] = billboard

local function rescan()
	local list = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and d:GetAttribute("OreMaxHealth") then
			table.insert(list, d)
		end
	end
	ores = list
end

local function makeBar(ore)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 34)
	bb.StudsOffsetWorldSpace = Vector3.new(0, select(2, ore:GetBoundingBox()).Y / 2 + 2, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = ore.PrimaryPart or ore:FindFirstChildWhichIsA("BasePart", true)
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 16)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 12
	name.TextColor3 = THEME.Text
	name.TextStrokeTransparency = 0.5
	local id = ore:GetAttribute("OreType")
	local oreDef = id and Config.Ores[id]
	name.Text = (oreDef and Config.ItemName(oreDef.Item) or ore.Name) .. string.format("  T%d", ore:GetAttribute("OreTier") or 0)
	name.Parent = bb
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 18)
	back.Size = UDim2.new(1, 0, 0, 10)
	back.BackgroundColor3 = THEME.Panel
	back.BackgroundTransparency = 0.2
	Instance.new("UICorner", back).CornerRadius = UDim.new(0, 5)
	back.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = THEME.Good
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)
	fill.Parent = back
	bb.Parent = gui
	return bb
end

task.spawn(function()
	while true do
		rescan()
		task.wait(3)
	end
end)

RunService.Heartbeat:Connect(function()
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local holding = equippedDrill() ~= nil
	for _, ore in ipairs(ores) do
		local max = ore:GetAttribute("OreMaxHealth") or 1
		local hp = ore:GetAttribute("OreHealth") or max
		local show = ore.Parent and hrp and not ore:GetAttribute("Depleted")
			and (hp < max or holding) and (ore:GetPivot().Position - hrp.Position).Magnitude < 40
		local bb = bars[ore]
		if show then
			bb = bb or makeBar(ore)
			bars[ore] = bb
			local frac = math.clamp(hp / max, 0, 1)
			local fill = bb:FindFirstChild("Fill", true)
			local cur = fill.Size.X.Scale
			fill.Size = UDim2.fromScale(cur + (frac - cur) * 0.3, 1) -- smooth
			local locked = (ore:GetAttribute("OreTier") or 0) > (player:GetAttribute("DrillTier") or 0)
			fill.BackgroundColor3 = locked and THEME.Bad or (frac > 0.5 and THEME.Good or THEME.Warn)
		elseif bb then
			bb:Destroy()
			bars[ore] = nil
		end
	end
end)
