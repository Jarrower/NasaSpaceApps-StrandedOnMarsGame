--[[
	AirlockService  (ModuleScript)
	Location: ServerScriptService > BaseServer > AirlockService

	For every BUILT Airlock: each part inside its "Doors" folder gets an
	Open/Close ProximityPrompt. Doors tween open (slide up by default), puff
	particles, and auto-close. With Interlock on, opening one door closes the
	other one first, like a real airlock. All settings: Config.Airlock.
]]

local TweenService = game:GetService("TweenService")

local Airlock = {}
local S, Config, Placement, Build
local active = {}

local function makeEmitter(parent)
	local cfg = Config.Airlock
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "AirlockParticles"
	pe.Enabled = false
	pe.Texture = cfg.ParticleTexture
	pe.Color = ColorSequence.new(cfg.ParticleColor)
	pe.Lifetime = NumberRange.new(0.6, 1.3)
	pe.Speed = NumberRange.new(6, 14)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 3
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	pe.Parent = parent
	return pe
end

local function setup(model)
	if active[model] then
		return
	end
	local cfg = Config.Airlock
	local folder = model:FindFirstChild(cfg.DoorsFolderName)
	if not folder then
		warn("[Airlock] No '" .. cfg.DoorsFolderName .. "' folder in " .. model:GetFullName())
		return
	end
	active[model] = true
	local main = Placement.MainPart(model)

	local centerAtt = Instance.new("Attachment")
	centerAtt.Name = "AirlockFX"
	centerAtt.Parent = main
	centerAtt.WorldPosition = model:GetAttribute("Center").Position
	local centerFX = makeEmitter(centerAtt)

	local sound
	if cfg.SoundId then
		sound = Instance.new("Sound")
		sound.SoundId = cfg.SoundId
		sound.Parent = centerAtt
	end

	local states = {}
	local function setDoor(i, open)
		local st = states[i]
		if st.Open == open then
			return
		end
		st.Open = open
		st.Token += 1
		local token = st.Token
		if open then
			st.Door.CanCollide = false
		end
		local tween = TweenService:Create(st.Door,
			TweenInfo.new(cfg.OpenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
			{ CFrame = open and st.OpenCF or st.ClosedCF })
		tween:Play()
		if not open then
			tween.Completed:Connect(function()
				if not st.Open then
					st.Door.CanCollide = st.CanCollide
				end
			end)
		end
		st.Prompt.ActionText = open and "Close" or "Open"
		st.FX:Emit(cfg.ParticleCount)
		centerFX:Emit(math.floor(cfg.ParticleCount / 2))
		if sound then
			sound:Play()
		end
		if open and cfg.AutoCloseTime > 0 then
			task.delay(cfg.AutoCloseTime, function()
				if st.Token == token and model.Parent then
					setDoor(i, false)
				end
			end)
		end
	end

	local doors = {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(doors, d)
		end
	end

	for i, door in ipairs(doors) do
		-- Unweld the door so tweening it doesn't drag the whole airlock
		for _, j in ipairs(model:GetDescendants()) do
			if (j:IsA("WeldConstraint") or j:IsA("JointInstance")) and (j.Part0 == door or j.Part1 == door) then
				j:Destroy()
			end
		end
		door.Anchored = true

		local closed = door.CFrame
		local offset
		if cfg.OpenDirection == "Down" then
			offset = Vector3.new(0, -door.Size.Y * cfg.OpenFraction, 0)
		elseif cfg.OpenDirection == "Side" then
			offset = closed.RightVector * door.Size.X * cfg.OpenFraction
		else
			offset = Vector3.new(0, door.Size.Y * cfg.OpenFraction, 0)
		end

		-- Prompt stays where the closed door is (so it doesn't fly up with it)
		local att = Instance.new("Attachment")
		att.Name = "DoorAtt"
		att.Parent = main
		att.WorldPosition = closed.Position

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "DoorPrompt"
		prompt.ActionText = "Open"
		prompt.ObjectText = "Airlock Door"
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = cfg.PromptDistance
		prompt.Parent = att

		states[i] = {
			Door = door, ClosedCF = closed, OpenCF = closed + offset,
			Open = false, Token = 0, CanCollide = door.CanCollide,
			Prompt = prompt, FX = makeEmitter(att),
		}

		prompt.Triggered:Connect(function(player)
			if not Build.CanUse(player, model) then
				S.Notify(player, "This airlock belongs to another player.")
				return
			end
			local st = states[i]
			if not st.Open and cfg.Interlock then
				for j, other in ipairs(states) do
					if j ~= i and other.Open then
						setDoor(j, false)
					end
				end
			end
			setDoor(i, not st.Open)
		end)
	end

	model.Destroying:Connect(function()
		active[model] = nil
	end)
end

function Airlock.Init(services)
	S = services
	Config = S.Config
	Placement = S.Placement
	Build = S.BuildService

	Build.PieceBuilt.Event:Connect(function(model)
		local def = Placement.Def(model)
		if def and def.IsAirlock then
			setup(model)
		end
	end)
	for _, m in ipairs(Placement.GetPieces()) do
		if Placement.Def(m).IsAirlock and m:GetAttribute("State") == "Built" then
			setup(m)
		end
	end
end

return Airlock
