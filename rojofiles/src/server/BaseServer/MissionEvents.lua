--[[
	MissionEvents  (ModuleScript)
	Location: ServerScriptService > BaseServer > MissionEvents
	Mission mode only. All numbers: Config.Mission.Events.

	At most one event per sol (MissionService rolls it with Events.Roll):
	  DustStorm       announced at the start of the sol. Uses WeatherService's dust
	                  storm visuals. Solar Panels give no bonus cell (MissionService).
	  SolarStorm      surprise alarm. The crew has WarningTime seconds to get inside
	                  the Shield Bunker. At impact:
	                    bunker powered + everyone inside  -> no damage
	                    bunker powered + anyone outside   -> Health -DamageOutside
	                    bunker NOT powered (door locked)  -> Health -DamageUnpowered
	  Micrometeorite  surprise hit near a station. A leaking pipe sparks. The crew
	                  clicks it (or presses E) Clicks times within TimeLimit seconds,
	                  or Oxygen -OxygenLoss.

	Spots for the leak: Workspace > MissionBase > MeteorSpots (Parts). If there are
	none, a spot next to a random station's Power Port is used.

	API: Events.Roll(sol)  Events.BeginSol()  Events.Schedule(id, delay)
	     Events.Trigger(id)  Events.Cancel()  Events.IsBusy()
	     Events.StartDust(seconds)  Events.StopDust()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Events = {}
local S, Config, MC, state
local token = 0
local busy = false
local cleanup = {}

local function now()
	return workspace:GetServerTimeNow()
end

local function broadcast(kind, data)
	S.MissionRemotes.Event:FireAllClients(kind, data)
end

local function paused()
	return S.MissionService and S.MissionService.IsPaused()
end

-- Wait until `t` (server time) or until stop() returns true. Pausing the
-- mission pauses the countdown. Returns false if the event was cancelled.
local function waitUntil(t, my, stop)
	while true do
		local dt = task.wait(0.1)
		if my ~= token then
			return false, t
		end
		if paused() then
			t += dt
			state:SetAttribute("AlertEnds", t)
		elseif (stop and stop()) or now() >= t then
			return true, t
		end
	end
end

local function clearAlert()
	state:SetAttribute("Alert", "")
	state:SetAttribute("AlertEnds", 0)
end

local function doCleanup()
	for _, inst in ipairs(cleanup) do
		if typeof(inst) == "Instance" then
			inst:Destroy()
		elseif typeof(inst) == "RBXScriptConnection" then
			inst:Disconnect()
		end
	end
	cleanup = {}
end

------------------------------------------------------------------ rolling
function Events.Roll(sol)
	if sol == 1 and MC.CalmFirstSol then
		return "None"
	end
	local total = 0
	for _, ev in pairs(MC.Events) do
		total += ev.Weight or 0
	end
	if total <= 0 then
		return "None"
	end
	local roll = math.random() * total
	-- fixed order so the same seed gives the same result
	for _, id in ipairs({ "None", "DustStorm", "SolarStorm", "Micrometeorite" }) do
		local ev = MC.Events[id]
		if ev then
			roll -= ev.Weight or 0
			if roll <= 0 then
				return id
			end
		end
	end
	return "None"
end

function Events.IsBusy()
	return busy
end

------------------------------------------------------------------ dust storm
function Events.StartDust(seconds)
	local ev = MC.Events.DustStorm
	if S.WeatherService and ev and ev.WeatherEvent then
		S.WeatherService.Start(ev.WeatherEvent, seconds)
	end
end

function Events.StopDust()
	if S.WeatherService then
		S.WeatherService.Clear()
	end
end

------------------------------------------------------------------ solar storm
local function runSolarStorm(my)
	local ev = MC.Events.SolarStorm
	local Stations = S.StationService
	busy = true
	local endsAt = now() + ev.WarningTime
	state:SetAttribute("Alert", "SolarStorm")
	state:SetAttribute("AlertEnds", endsAt)
	broadcast("SolarStorm", { Phase = "Warning", EndsAt = endsAt, BunkerPos = Stations.GetBunkerPosition() })

	local ok = waitUntil(endsAt, my)
	if not ok then
		return
	end

	local powered = Stations.IsPowered("Shield")
	local outside = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if not Stations.IsInBunker(p) then
			table.insert(outside, p.DisplayName)
		end
	end
	local damage, text, short
	if not powered then
		damage = ev.DamageUnpowered
		text = "The Shield Bunker had no power, so its door stayed locked. Nobody could hide. Health -" .. damage .. "."
		short = "bunker had no power, door locked"
	elseif #outside > 0 then
		damage = ev.DamageOutside
		text = table.concat(outside, ", ") .. (#outside == 1 and " was" or " were") .. " caught outside the bunker! Health -" .. damage .. "."
		short = "crew caught outside the bunker"
	else
		damage = 0
		text = "Everyone was safe inside the Shield Bunker. No damage!"
		short = "everyone safe in the bunker"
	end
	clearAlert()
	broadcast("SolarStorm", { Phase = "Impact", Safe = damage == 0, Text = text, Damage = damage })
	S.MissionService.NoteEvent("SolarStorm", "☢️ Solar storm: " .. short .. (damage > 0 and (" → Health -" .. damage) or ""), damage == 0)
	busy = false
	if damage > 0 then
		S.MissionService.ApplyEvent("Health", -damage, "Solar storm: " .. short .. " → Health -" .. damage)
	end
end

------------------------------------------------------------------ micrometeorite
local function pickSpot()
	local base = workspace:FindFirstChild("MissionBase")
	local folder = base and base:FindFirstChild("MeteorSpots")
	local spots = {}
	for _, p in ipairs(folder and folder:GetChildren() or {}) do
		if p:IsA("BasePart") then
			table.insert(spots, p)
		end
	end
	if #spots > 0 then
		local p = spots[math.random(1, #spots)]
		return p.CFrame, p:GetAttribute("Station") or "the base"
	end
	-- fallback: beside a random station's Power Port
	local d = MC.Stations[math.random(1, #MC.Stations)]
	local port = S.StationService.GetPort(d.Id)
	if port then
		return port.CFrame * CFrame.new(4, 1, 0), d.Name
	end
	return CFrame.new(33, 6, 3), "the base"
end

local function runMicrometeorite(my)
	local ev = MC.Events.Micrometeorite
	busy = true
	local cf, where = pickSpot()
	local endsAt = now() + ev.TimeLimit
	local hits, fixed = 0, false

	-- incoming streak + harmless flash
	local rock = Instance.new("Part")
	rock.Name = "Micrometeorite"
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(1.2, 1.2, 1.2)
	rock.Material = Enum.Material.Neon
	rock.Color = Color3.fromRGB(255, 170, 80)
	rock.Anchored, rock.CanCollide, rock.CanQuery, rock.CanTouch = true, false, false, false
	rock.Position = cf.Position + Vector3.new(90, 180, 50)
	rock.Parent = workspace
	table.insert(cleanup, rock)
	local trail0 = Instance.new("Attachment", rock)
	trail0.Position = Vector3.new(0, 0.5, 0)
	local trail1 = Instance.new("Attachment", rock)
	trail1.Position = Vector3.new(0, -0.5, 0)
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = trail0, trail1
	trail.Lifetime = 0.5
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120))
	trail.LightEmission = 1
	trail.Parent = rock
	local fall = TweenService:Create(rock, TweenInfo.new(1.1, Enum.EasingStyle.Linear), { Position = cf.Position })
	fall:Play()
	fall.Completed:Wait()
	if my ~= token then
		return
	end
	rock.Transparency = 1
	local boom = Instance.new("Explosion")
	boom.Position = cf.Position
	boom.BlastPressure = 0
	boom.BlastRadius = 4
	boom.DestroyJointRadiusPercent = 0 -- visual only, never hurts players
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Parent = workspace

	-- the leak
	local leak = Instance.new("Part")
	leak.Name = "AirLeak"
	leak.Shape = Enum.PartType.Ball
	leak.Size = Vector3.new(2.6, 2.6, 2.6)
	leak.Material = Enum.Material.Neon
	leak.Color = Color3.fromRGB(255, 120, 60)
	leak.Anchored, leak.CanCollide = true, false
	leak.CFrame = cf
	leak.Parent = workspace
	table.insert(cleanup, leak)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Rate = 50
	sparks.Lifetime = NumberRange.new(0.3, 0.7)
	sparks.Speed = NumberRange.new(8, 14)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.LightEmission = 1
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 120, 40))
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Parent = leak
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Rate = 25
	steam.Lifetime = NumberRange.new(0.6, 1.2)
	steam.Speed = NumberRange.new(4, 8)
	steam.SpreadAngle = Vector2.new(25, 25)
	steam.Color = ColorSequence.new(Color3.fromRGB(235, 240, 250))
	steam.Transparency = NumberSequence.new(0.4, 1)
	steam.Size = NumberSequence.new(1, 3)
	steam.Parent = leak
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 70)
	light.Range = 14
	light.Brightness = 3
	light.Parent = leak
	local assets = ReplicatedStorage:FindFirstChild("BaseAssets")
	local hiss = assets and assets:FindFirstChild("SpraySound")
	if hiss then
		hiss = hiss:Clone()
		hiss.Looped = true
		hiss.Parent = leak
		hiss:Play()
	end

	local last = {}
	local function hit(player)
		if fixed or my ~= token then
			return
		end
		if last[player] and os.clock() - last[player] < 0.15 then
			return
		end
		last[player] = os.clock()
		hits += 1
		local left = math.max(0, ev.Clicks - hits)
		leak.Size = Vector3.one * (0.8 + 1.8 * left / ev.Clicks)
		sparks.Rate = 10 + 40 * left / ev.Clicks
		state:SetAttribute("AlertProgress", hits)
		if hits >= ev.Clicks then
			fixed = true
		end
	end
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 40
	click.Parent = leak
	table.insert(cleanup, click.MouseClick:Connect(hit))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Fix the leak"
	prompt.ObjectText = "Air pipe"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = leak
	table.insert(cleanup, prompt.Triggered:Connect(hit))

	state:SetAttribute("Alert", "Micrometeorite")
	state:SetAttribute("AlertEnds", endsAt)
	state:SetAttribute("AlertProgress", 0)
	state:SetAttribute("AlertGoal", ev.Clicks)
	broadcast("Micrometeorite", { Phase = "Start", EndsAt = endsAt, Position = cf.Position, Clicks = ev.Clicks, Where = where })

	local ok = waitUntil(endsAt, my, function()
		return fixed
	end)
	if not ok then
		return
	end
	doCleanup()
	clearAlert()
	busy = false
	if fixed then
		broadcast("Micrometeorite", { Phase = "Fixed", Text = "Leak fixed! No air was lost." })
		S.MissionService.NoteEvent("Micrometeorite", "☄️ Micrometeorite: the crew fixed the leak in time", true)
	else
		local loss = ev.OxygenLoss
		broadcast("Micrometeorite", { Phase = "Failed", Text = "The leak wasn't fixed in time. Oxygen -" .. loss .. "." })
		S.MissionService.NoteEvent("Micrometeorite", "☄️ Micrometeorite: leak not fixed → Oxygen -" .. loss, false)
		S.MissionService.ApplyEvent("Oxygen", -loss, "Micrometeorite leak not fixed → Oxygen -" .. loss)
	end
end

------------------------------------------------------------------ control
local RUNNERS = { SolarStorm = runSolarStorm, Micrometeorite = runMicrometeorite }

-- Start a surprise event now (dev panel, or from Schedule). Dust is handled by MissionService.
function Events.Trigger(id)
	local fn = RUNNERS[id]
	if not fn then
		return false, "Unknown event " .. tostring(id)
	end
	if busy then
		return false, "Another event is still running"
	end
	local my = token
	busy = true
	task.spawn(function()
		local ok, err = pcall(fn, my)
		if not ok then
			warn("[MissionEvents] " .. id .. " failed: " .. tostring(err))
		end
		if my == token then
			busy = false
		end
	end)
	return true, (MC.Events[id].Name or id) .. " started"
end

-- Called at the start of every sol: drops events scheduled for an earlier sol.
local schedule = 0
function Events.BeginSol()
	schedule += 1
end

function Events.Schedule(id, delay)
	local mySchedule, my = schedule, token
	task.delay(delay, function()
		-- wait out a pause before starting
		while paused() and my == token do
			task.wait(0.2)
		end
		if mySchedule == schedule and my == token and S.MissionService.GetPhase() == "Sol" then
			Events.Trigger(id)
		end
	end)
end

function Events.Cancel()
	token += 1
	schedule += 1
	busy = false
	doCleanup()
	clearAlert()
	Events.StopDust()
end

function Events.Init(services)
	S = services
	Config = S.Config
	MC = Config.Mission
	state = S.MissionState
	clearAlert()
end

return Events
