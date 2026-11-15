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


------------------------------------------------------------------ AUTO MODE
-- Doors open as the owner walks up. Stepping into the chamber closes the door
-- behind you, sprays decontamination mist, then opens the other door.
-- Only one door is ever open. Uses ReplicatedStorage > BaseAssets
-- (MistEmitter, SpraySound, DoorHissSound, SlideSound) if present.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function asset(name, parent)
	local f = ReplicatedStorage:FindFirstChild("BaseAssets")
	local a = f and f:FindFirstChild(name)
	if a then
		a = a:Clone()
		a.Parent = parent
	end
	return a
end

local function setupAuto(model)
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
	model.Destroying:Connect(function()
		active[model] = nil
	end)

	local cf, size = model:GetAttribute("Center"), model:GetAttribute("Size")
	local alongX = size.X >= size.Z
	local axis = cf:VectorToWorldSpace(alongX and Vector3.xAxis or Vector3.zAxis)
	local tangent = Vector3.yAxis:Cross(axis)
	local halfWidth = (alongX and size.Z or size.X) / 2

	-- +u points into the base (towards the end that is attached to a tile)
	local ctx = Placement.BuildContext()
	local used = ctx.LinearSocketUsed[model] or {}
	local sign = (used[2] and not used[1]) and -1 or 1
	local function u(pos)
		return (pos - cf.Position):Dot(axis) * sign
	end

	-- split door panels into an outer and an inner group
	local panels = {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			for _, j in ipairs(model:GetDescendants()) do
				if (j:IsA("WeldConstraint") or j:IsA("JointInstance")) and (j.Part0 == d or j.Part1 == d) then
					j:Destroy()
				end
			end
			d.Anchored = true
			table.insert(panels, d)
		end
	end
	if #panels == 0 then
		return
	end
	local avg = 0
	for _, p in ipairs(panels) do
		avg += u(p.Position)
	end
	avg /= #panels
	local groups = { Outer = { Panels = {} }, Inner = { Panels = {} } }
	for _, p in ipairs(panels) do
		table.insert((#panels == 1 or u(p.Position) < avg) and groups.Outer.Panels or groups.Inner.Panels, p)
	end
	if #groups.Inner.Panels == 0 then
		groups.Inner = groups.Outer
	end

	for _, g in pairs(groups) do
		local center, uSum = Vector3.zero, 0
		for _, p in ipairs(g.Panels) do
			center += p.Position
			uSum += u(p.Position)
		end
		center /= #g.Panels
		g.U = uSum / #g.Panels
		g.States = {}
		for _, p in ipairs(g.Panels) do
			local offset
			if cfg.OpenDirection == "Side" then
				local away = (p.Position - center):Dot(tangent)
				local dir = (#g.Panels > 1 and away ~= 0) and math.sign(away) or 1
				offset = tangent * dir * (math.abs(p.Size:Dot(p.CFrame:VectorToObjectSpace(tangent))) + 0.1)
			elseif cfg.OpenDirection == "Down" then
				offset = Vector3.new(0, -p.Size.Y * cfg.OpenFraction, 0)
			else
				offset = Vector3.new(0, p.Size.Y * cfg.OpenFraction, 0)
			end
			g.States[p] = { Closed = p.CFrame, Open = p.CFrame + offset, CanCollide = p.CanCollide }
		end
	end

	-- effects in the middle of the chamber
	local main = Placement.MainPart(model)
	local fxAtt = Instance.new("Attachment")
	fxAtt.Name = "AirlockFX"
	fxAtt.Parent = main
	fxAtt.WorldPosition = cf.Position + axis * sign * ((groups.Outer.U + groups.Inner.U) / 2)
	local mist = asset("MistEmitter", fxAtt) or makeEmitter(fxAtt)
	mist.Enabled = false
	local spray = asset("SpraySound", fxAtt)
	local hiss = asset("DoorHissSound", fxAtt)
	local slide = asset("SlideSound", fxAtt)
	if not slide and cfg.SoundId then
		slide = Instance.new("Sound")
		slide.SoundId = cfg.SoundId
		slide.Parent = fxAtt
	end

	local function setGroup(g, open)
		for p, st in pairs(g.States) do
			if open then
				p.CanCollide = false
			end
			local tw = TweenService:Create(p, TweenInfo.new(cfg.OpenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ CFrame = open and st.Open or st.Closed })
			tw:Play()
			if not open then
				tw.Completed:Connect(function(state)
					if state == Enum.PlaybackState.Completed then
						p.CanCollide = st.CanCollide
					end
				end)
			end
		end
		if slide then
			slide:Play()
		end
		if open and hiss then
			hiss:Play()
		end
	end

	-- who is where
	local function players()
		local list = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if not Config.Build.OwnerOnlyInteract or plr.UserId == model:GetAttribute("Owner") then
				local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
				if hrp and hum and hum.Health > 0 then
					local rel = hrp.Position - cf.Position
					if math.abs(rel:Dot(tangent)) <= halfWidth + 2 and math.abs(rel.Y) <= size.Y then
						table.insert(list, u(hrp.Position))
					end
				end
			end
		end
		return list
	end
	local function anyIn(list, a, b)
		for _, v in ipairs(list) do
			if v >= a and v <= b then
				return true
			end
		end
		return false
	end

	local state = { Open = nil, NeedEmpty = false, EmptySince = nil, Busy = false }
	local function other(side)
		return side == "Outer" and "Inner" or "Outer"
	end

	task.spawn(function()
		while model.Parent do
			task.wait(0.2)
			if not state.Busy then
				local list = players()
				local o, i = groups.Outer.U, groups.Inner.U
				local zone = {
					Outer = anyIn(list, o - cfg.ZoneDepth, o - 0.75),
					Inner = anyIn(list, i + 0.75, i + cfg.ZoneDepth),
				}
				local chamber = anyIn(list, o + 0.75, i - 0.75)
				local doorway = {
					Outer = anyIn(list, o - 1.5, o + 1.5),
					Inner = anyIn(list, i - 1.5, i + 1.5),
				}
				if state.NeedEmpty and not chamber then
					state.NeedEmpty = false
				end

				if not state.Open then
					local side = zone.Outer and "Outer" or (zone.Inner and "Inner") or nil
					if side then
						state.Open, state.EmptySince = side, nil
						setGroup(groups[side], true)
					end
				else
					local side = state.Open
					if chamber and not zone[side] and not doorway[side] and not state.NeedEmpty and groups.Inner ~= groups.Outer then
						-- cycle: close behind, mist, open the other door
						state.Busy = true
						task.spawn(function()
							setGroup(groups[side], false)
							task.wait(cfg.OpenTime)
							mist.Enabled = true
							mist:Emit(cfg.ParticleCount)
							if spray then
								spray:Play()
							end
							task.wait(cfg.MistTime)
							mist.Enabled = false
							if spray then
								spray:Stop()
							end
							if model.Parent then
								state.Open = other(side)
								state.NeedEmpty = true
								state.EmptySince = nil
								setGroup(groups[state.Open], true)
							end
							state.Busy = false
						end)
					elseif not zone[side] and not chamber and not doorway[side] then
						state.EmptySince = state.EmptySince or os.clock()
						if os.clock() - state.EmptySince >= cfg.CloseDelay then
							setGroup(groups[side], false)
							state.Open, state.EmptySince = nil, nil
						end
					else
						state.EmptySince = nil
					end
				end
			end
		end
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
			if Config.Airlock.Mode == "Auto" then
				setupAuto(model)
			else
				setup(model)
			end
		end
	end)
	for _, m in ipairs(Placement.GetPieces()) do
		if Placement.Def(m).IsAirlock and m:GetAttribute("State") == "Built" then
			if Config.Airlock.Mode == "Auto" then
				setupAuto(m)
			else
				setup(m)
			end
		end
	end
end

return Airlock
