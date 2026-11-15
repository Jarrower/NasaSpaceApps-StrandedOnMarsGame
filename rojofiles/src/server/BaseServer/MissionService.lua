--[[
	MissionService  (ModuleScript)
	Location: ServerScriptService > BaseServer > MissionService
	Mission mode only. All numbers: Config.Mission.

	FLOW
	  Lobby -> Intro (lander touches down) -> for each sol:
	      Sol     (SolLength s: plug in cells, events happen)
	      Report  (what got power -> what changed)
	      Fact    ("Did you know?")
	  -> Victory (rocket launches)   or   Failed (any meter hits 0 / not enough fuel)

	RULES (end of every sol, from what is plugged in at that moment)
	  each station in Config.Mission.Stations changes its Meter by On / Off
	  Solar powered and no dust storm this sol -> SolarBonus extra cells next sol
	  Fuel powered -> fuel +1. You lose as soon as there aren't enough sols left
	  to make Config.Mission.FuelNeeded fuel.
	  Meters never go above MaxMeter. Any meter at 0 = mission failed.

	STATE (ReplicatedStorage > MissionState attributes, read by MissionClient)
	  Phase, PhaseEnds, Paused, Sol, Sols, Oxygen, Food, Health, Fuel, FuelNeeded,
	  Dust, CellsTotal, CellsUsed, On_<Id>, By_<Id>, Alert, AlertEnds, ...
	One-off messages go through BaseRemotes > MissionEvent:
	  Banner, Report, Fact, Intro, Launch, Victory, Failed, Toast, SolarStorm, Micrometeorite

	Dev API (DevService): DevSkip, DevPause, DevSetSolLength, DevSetMeter, DevAddCell,
	  DevEvent, DevWin, DevLose, DevJumpToSol, DevShowFact, DevTeleport
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Mission = {}
local S, Config, MC, Stations, Events, Rocket, Facts, state, remotes

local token = 0
local phase = "Lobby"
local paused, skip = false, false
local forceEndsAt = nil
local meters = {}
local fuel = 0
local sol = 0
local nextSol = nil
local bonusCells = 0
local dustThisSol = false
local history, record = {}, nil
local usedFacts = {}
local ready = {}
local finished = false
local lastEnd = nil  -- { Kind = "Victory"/"Failed", Data = ... } for late joiners

local METERS = { "Oxygen", "Food", "Health" }

------------------------------------------------------------------ helpers
local function now()
	return workspace:GetServerTimeNow()
end

local function signed(n)
	return (n >= 0 and "+" or "-") .. tostring(math.abs(n))
end

local function broadcast(kind, data)
	remotes.Event:FireAllClients(kind, data)
end

local function publish()
	for _, m in ipairs(METERS) do
		state:SetAttribute(m, math.max(0, meters[m] or 0))
	end
	state:SetAttribute("Fuel", fuel)
	state:SetAttribute("FuelNeeded", MC.FuelNeeded)
	state:SetAttribute("Sol", sol)
	state:SetAttribute("Sols", MC.Sols)
	state:SetAttribute("Paused", paused)
	state:SetAttribute("Dust", dustThisSol)
end

local function setPhase(name, duration)
	phase = name
	ready = {}
	state:SetAttribute("Phase", name)
	state:SetAttribute("PhaseLength", duration or 0)
	state:SetAttribute("PhaseEnds", duration and (now() + duration) or 0)
	state:SetAttribute("Ready", 0)
end

-- Wait `seconds` of mission time. Pause stretches it, skip / everyone Ready ends it.
-- Returns false if the mission was stopped (restart / failure) meanwhile.
local function waitPhase(seconds, my)
	local endsAt = now() + seconds
	state:SetAttribute("PhaseEnds", endsAt)
	while true do
		local dt = task.wait(0.1)
		if my ~= token then
			return false
		end
		if forceEndsAt then
			endsAt = math.min(endsAt, forceEndsAt)
			forceEndsAt = nil
			state:SetAttribute("PhaseEnds", endsAt)
		end
		if paused then
			endsAt += dt
			state:SetAttribute("PhaseEnds", endsAt)
		elseif skip then
			skip = false
			return true
		elseif now() >= endsAt then
			return true
		end
	end
end

local function stationDef(id)
	for _, d in ipairs(MC.Stations) do
		if d.Id == id then
			return d
		end
	end
	return nil
end

local function change(meter, amount, text, kind)
	if meter == "Fuel" then
		fuel = math.max(0, fuel + amount)
	else
		meters[meter] = math.min(MC.MaxMeter, (meters[meter] or 0) + amount)
	end
	if record then
		table.insert(record.Changes, { Meter = meter, Amount = amount, Text = text, Kind = kind })
	end
	publish()
end

local function firstDead()
	for _, m in ipairs(METERS) do
		if (meters[m] or 0) <= 0 then
			return m
		end
	end
	return nil
end

local function spawnCF(i)
	local base = Stations.GetSpawnCFrame()
	local angle = (i or 0) * 0.9
	return base * CFrame.new(math.cos(angle) * 4, 0, math.sin(angle) * 4)
end

local function teleportAll()
	for i, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			char:PivotTo(spawnCF(i))
		end
	end
end

------------------------------------------------------------------ end screens
local FAIL_INFO = {
	Oxygen = {
		Title = "Out of air!",
		Why = "The crew breathes oxygen every sol. Each sol the Oxygen Generator had no power, Oxygen went down by 40.",
		Tip = "When Oxygen is getting low, power the Oxygen Generator first.",
	},
	Food = {
		Title = "Out of food!",
		Why = "The crew eats every sol. Each sol the Greenhouse had no power, Food went down by 30.",
		Tip = "Keep the Greenhouse powered so the plants keep growing.",
	},
	Health = {
		Title = "Too much radiation!",
		Why = "Mars has thin air and no magnetic field to block radiation. Without the Shield Bunker, the crew gets hurt.",
		Tip = "Power the Shield Bunker, and run inside as soon as the storm alarm sounds.",
	},
	Fuel = {
		Title = "Not enough rocket fuel!",
		Why = "The rocket needs %d fuel to fly home. The Fuel Plant only makes fuel on sols when it has power.",
		Tip = "Power the Fuel Plant early, and power the Solar Panels so you get extra cells.",
	},
}

local function buildFailure(meter)
	local info = FAIL_INFO[meter] or FAIL_INFO.Oxygen
	local lines = {}
	if meter == "Fuel" then
		for _, r in ipairs(history) do
			if r.Powered and r.Powered.Fuel == false then
				table.insert(lines, string.format("Sol %d: the Fuel Plant had no power → no fuel made", r.Sol))
			end
		end
		table.insert(lines, string.format("Fuel made: %d of %d, with %d sol%s left", fuel, MC.FuelNeeded,
			MC.Sols - sol, (MC.Sols - sol) == 1 and "" or "s"))
	else
		for _, r in ipairs(history) do
			for _, c in ipairs(r.Changes) do
				if c.Meter == meter and c.Amount < 0 then
					table.insert(lines, string.format("Sol %d: %s", r.Sol, c.Text))
				end
			end
		end
	end
	while #lines > 6 do
		table.remove(lines, 1)
	end
	if #lines == 0 then
		table.insert(lines, "(Mission ended from the dev panel)")
	end
	local fact = Facts.Pick(meter, {})
	return {
		Meter = meter,
		Sol = math.max(sol, 1),
		Title = info.Title,
		Why = string.format(info.Why, MC.FuelNeeded),
		Tip = info.Tip,
		Lines = lines,
		Fact = fact,
		Meters = { Oxygen = math.max(0, meters.Oxygen or 0), Food = math.max(0, meters.Food or 0), Health = math.max(0, meters.Health or 0) },
		Fuel = fuel,
	}
end

local function buildStats()
	local counts = {}
	for _, d in ipairs(MC.Stations) do
		counts[d.Id] = 0
	end
	local storms, safe = 0, 0
	for _, r in ipairs(history) do
		for id, on in pairs(r.Powered or {}) do
			if on then
				counts[id] = (counts[id] or 0) + 1
			end
		end
		for _, n in ipairs(r.Notes) do
			if n.Id == "SolarStorm" then
				storms += 1
				if n.Good then
					safe += 1
				end
			end
		end
	end
	local rows = {}
	for _, d in ipairs(MC.Stations) do
		table.insert(rows, { Icon = d.Icon, Name = d.Name, Count = counts[d.Id] or 0 })
	end
	return {
		Sols = MC.Sols,
		Meters = { Oxygen = meters.Oxygen, Food = meters.Food, Health = meters.Health },
		Fuel = fuel,
		FuelNeeded = MC.FuelNeeded,
		Stations = rows,
		Storms = storms,
		StormsSafe = safe,
		Crew = (function()
			local names = {}
			for _, p in ipairs(Players:GetPlayers()) do
				table.insert(names, p.DisplayName)
			end
			return names
		end)(),
	}
end

------------------------------------------------------------------ dust
function Mission.StartDust()
	if dustThisSol then
		return false
	end
	dustThisSol = true
	if record then
		record.Seen.DustStorm = true
		table.insert(record.Notes, { Id = "DustStorm", Text = "🌪️ Dust storm: the Sun was blocked all sol", Good = false })
	end
	Events.StartDust(MC.SolLength + 20)
	Stations.SetNote("Solar", "Dust storm! No bonus cell this sol")
	publish()
	return true
end

------------------------------------------------------------------ called by MissionEvents
function Mission.IsPaused()
	return paused
end

function Mission.GetPhase()
	return phase
end

function Mission.NoteEvent(id, text, good)
	if record then
		record.Seen[id] = true
		table.insert(record.Notes, { Id = id, Text = text, Good = good })
	end
end

function Mission.Fail(meter)
	if finished then
		return
	end
	finished = true
	token += 1
	Events.Cancel()
	Stations.SetLocked(true)
	setPhase("Failed")
	local data = buildFailure(meter)
	lastEnd = { Kind = "Failed", Data = data }
	broadcast("Failed", data)
	print("[Mission] Failed on sol " .. sol .. ": " .. tostring(meter))
end

-- Immediate meter change from an event (solar storm, leak)
function Mission.ApplyEvent(meter, amount, text)
	if phase ~= "Sol" and phase ~= "Wrapup" then
		return
	end
	change(meter, amount, text, "event")
	local dead = firstDead()
	if dead then
		token += 1 -- stop the sol now
		local my = token
		Stations.SetLocked(true)
		task.delay(2.5, function() -- let the impact message show first
			if my == token then
				Mission.Fail(dead)
			end
		end)
	end
end

------------------------------------------------------------------ the mission
local function victory(my)
	finished = true
	Stations.SetLocked(true)
	setPhase("Launch", MC.EndScreenDelay)
	broadcast("Launch", { Rocket = Rocket.GetModel(), Duration = MC.EndScreenDelay })
	Rocket.Launch(MC.EndScreenDelay)
	if not waitPhase(MC.EndScreenDelay, my) then
		return
	end
	setPhase("Victory")
	local data = buildStats()
	lastEnd = { Kind = "Victory", Data = data }
	broadcast("Victory", data)
	print("[Mission] Victory!")
end

local function resolveSol()
	local powered = Stations.Snapshot()
	record.Powered = powered
	local lines = {}
	for _, d in ipairs(MC.Stations) do
		local on = powered[d.Id] == true
		local line = { Id = d.Id, Icon = d.Icon, Name = d.Name, On = on }
		if d.Meter then
			local amt = on and d.On or d.Off
			local why = on and "had power" or "had no power"
			if d.Id == "Shield" then
				why = on and "had power (safe sleep)" or "had no power (radiation while sleeping)"
			end
			change(d.Meter, amt, string.format("%s %s → %s %s", d.Name, why, d.Meter, signed(amt)), "station")
			line.Text, line.Good = d.Meter .. " " .. signed(amt), amt >= 0
		elseif d.Fuel then
			if on then
				change("Fuel", d.Fuel, d.Name .. " had power → fuel +" .. d.Fuel, "station")
			end
			line.Text = (on and ("Rocket fuel +" .. d.Fuel) or "No fuel made") .. string.format("  (%d/%d)", fuel, MC.FuelNeeded)
			line.Good = on
		elseif d.Id == "Solar" then
			if on and not dustThisSol then
				bonusCells = MC.SolarBonus
				line.Text, line.Good = string.format("+%d power cell next sol", MC.SolarBonus), true
			elseif on then
				line.Text, line.Good = "Dust blocked the Sun → no bonus cell", false
			else
				line.Text, line.Good = "No bonus cell next sol", false
			end
		end
		table.insert(lines, line)
	end
	return lines
end

local function runSol(my)
	local cells = MC.StartCells + bonusCells
	bonusCells = 0
	dustThisSol = false
	local eventId = Events.Roll(sol)
	record = { Sol = sol, Event = eventId, Cells = cells, Changes = {}, Notes = {}, Seen = {}, Powered = nil }
	table.insert(history, record)
	Stations.BeginSol(cells)
	Events.BeginSol()
	publish()

	local banner = { Sol = sol, Sols = MC.Sols, Cells = cells, Bonus = cells > MC.StartCells, Kind = "calm" }
	if eventId == "DustStorm" then
		Mission.StartDust()
		local ev = MC.Events.DustStorm
		banner.Title = string.format("Sol %d: %s", sol, ev.Banner)
		banner.Sub = ev.Sub
		banner.Kind = "dust"
	elseif sol == 1 then
		banner.Title = "Sol 1: Welcome to Mars Base 7!"
		banner.Sub = string.format("You have %d power cells. Walk to a station and press E to plug one in.", cells)
	else
		banner.Title = string.format("Sol %d: All quiet... for now", sol)
		banner.Sub = string.format("You have %d power cells%s. Choose wisely!", cells, banner.Bonus and " (Solar bonus!)" or "")
	end
	setPhase("Sol", MC.SolLength)
	broadcast("Banner", banner)

	if eventId == "SolarStorm" or eventId == "Micrometeorite" then
		local f = MC.EventStart
		Events.Schedule(eventId, MC.SolLength * (f[1] + math.random() * (f[2] - f[1])))
	end
	if not waitPhase(MC.SolLength, my) then
		return false
	end

	-- let a running event finish before the sol ends
	if Events.IsBusy() then
		setPhase("Wrapup")
		while Events.IsBusy() do
			task.wait(0.1)
			if my ~= token then
				return false
			end
		end
	end
	Events.BeginSol() -- drop anything scheduled that never started (sol skipped early)
	Stations.SetLocked(true)
	if dustThisSol then
		Events.StopDust()
	end

	local lines = resolveSol()
	local notes = {}
	for _, n in ipairs(record.Notes) do
		table.insert(notes, { Text = n.Text, Good = n.Good })
	end
	setPhase("Report", MC.ReportTime)
	broadcast("Report", {
		Sol = sol, Sols = MC.Sols, Lines = lines, Notes = notes,
		NextCells = MC.StartCells + bonusCells, Last = sol >= MC.Sols,
		Fuel = fuel, FuelNeeded = MC.FuelNeeded,
	})
	local dead = firstDead()
	if not waitPhase(MC.ReportTime, my) then
		return false
	end
	if dead then
		Mission.Fail(dead)
		return false
	end
	if fuel + (MC.Sols - sol) < MC.FuelNeeded then
		Mission.Fail("Fuel")
		return false
	end

	-- "Did you know?"
	local tag = "General"
	for _, id in ipairs({ "SolarStorm", "Micrometeorite", "DustStorm" }) do
		if record.Seen[id] then
			tag = id
			break
		end
	end
	local fact = Facts.Pick(tag, usedFacts)
	usedFacts[fact.Id] = true
	setPhase("Fact", MC.FactTime)
	broadcast("Fact", { Sol = sol, Title = fact.Title, Text = fact.Text, Source = fact.Source, Url = fact.Url })
	return waitPhase(MC.FactTime, my)
end

local function run(my)
	teleportAll()
	setPhase("Intro", MC.IntroTime)
	broadcast("Intro", { Rocket = Rocket.GetModel(), Duration = MC.IntroTime })
	Rocket.Land(math.max(1, MC.IntroTime - 1.5))
	if not waitPhase(MC.IntroTime, my) then
		return
	end
	sol = 1
	while sol <= MC.Sols do
		publish()
		if not runSol(my) then
			return
		end
		if nextSol then
			sol, nextSol = nextSol, nil
		else
			sol += 1
		end
	end
	sol = MC.Sols
	publish()
	victory(my)
end

local function reset()
	token += 1
	Events.Cancel()
	Rocket.Reset()
	meters = {}
	for _, m in ipairs(METERS) do
		meters[m] = MC.StartMeters[m] or 100
	end
	fuel, sol, bonusCells, nextSol = 0, 0, 0, nil
	history, record, usedFacts = {}, nil, {}
	paused, skip, forceEndsAt, finished, dustThisSol = false, false, nil, false, false
	lastEnd = nil
	Stations.UnplugAll()
	Stations.SetLocked(true)
	publish()
end

function Mission.Start()
	if phase ~= "Lobby" and phase ~= "Victory" and phase ~= "Failed" then
		return false, "A mission is already running"
	end
	reset()
	local my = token
	task.spawn(run, my)
	print("[Mission] Started")
	return true, "Mission started"
end

function Mission.Restart(toLobby)
	reset()
	if toLobby then
		setPhase("Lobby")
		broadcast("Lobby", {})
		return true, "Back to the title screen"
	end
	phase = "Lobby"
	return Mission.Start()
end

------------------------------------------------------------------ dev panel
function Mission.DevSkip()
	if phase == "Lobby" or phase == "Victory" or phase == "Failed" then
		return false, "No mission running"
	end
	skip = true
	return true, "Skipped: " .. phase
end

function Mission.DevPause(on)
	paused = on == true
	publish()
	return true, paused and "Mission PAUSED" or "Mission running"
end

function Mission.DevSetSolLength(seconds)
	MC.SolLength = math.clamp(math.floor(tonumber(seconds) or 60), 5, 600)
	if phase == "Sol" then
		forceEndsAt = now() + MC.SolLength
	end
	return true, "Sol length = " .. MC.SolLength .. "s"
end

function Mission.DevSetMeter(meter, value)
	value = math.floor(tonumber(value) or 0)
	if meter == "Fuel" then
		fuel = math.max(0, value)
	elseif table.find(METERS, meter) then
		meters[meter] = math.clamp(value, 0, MC.MaxMeter)
	else
		return false, "Unknown meter"
	end
	publish()
	if meter ~= "Fuel" and value <= 0 and (phase == "Sol" or phase == "Report" or phase == "Fact") then
		if record then
			table.insert(record.Changes, { Meter = meter, Amount = -1, Text = "Dev panel set " .. meter .. " to 0", Kind = "event" })
		end
		Mission.Fail(meter)
	end
	return true, meter .. " = " .. value
end

function Mission.DevAddCell(n)
	if phase ~= "Sol" then
		return false, "Only during a sol"
	end
	Stations.AddCells(n or 1)
	return true, "+1 power cell"
end

function Mission.DevEvent(id)
	if phase ~= "Sol" then
		return false, "Start a mission and wait for a sol first"
	end
	if id == "DustStorm" then
		if Mission.StartDust() then
			broadcast("Banner", { Sol = sol, Sols = MC.Sols, Kind = "dust", Title = "Dust storm coming!", Sub = MC.Events.DustStorm.Sub })
			return true, "Dust storm started"
		end
		return false, "Already dusty this sol"
	end
	return Events.Trigger(id)
end

function Mission.DevWin()
	if phase == "Lobby" then
		reset()
	end
	token += 1
	local my = token
	Events.Cancel()
	fuel = math.max(fuel, MC.FuelNeeded)
	sol = MC.Sols
	publish()
	task.spawn(victory, my)
	return true, "Launching the rocket!"
end

function Mission.DevLose(meter)
	if not FAIL_INFO[meter] then
		return false, "Unknown reason"
	end
	if meter ~= "Fuel" then
		meters[meter] = 0
		publish()
	end
	finished = false
	Mission.Fail(meter)
	return true, "Mission failed: " .. meter
end

function Mission.DevJumpToSol(n)
	n = math.clamp(math.floor(tonumber(n) or 1), 1, MC.Sols)
	if phase == "Lobby" or phase == "Victory" or phase == "Failed" then
		return false, "Start a mission first"
	end
	nextSol = n
	skip = true
	return true, "Jumping to sol " .. n .. " after this sol (set Fuel too, or the fuel check may fail you)"
end

function Mission.DevShowFact(i)
	local f = Facts.Get(i)
	broadcast("Fact", { Sol = sol, Title = f.Title, Text = f.Text, Source = f.Source, Url = f.Url, Preview = true })
	return true, "Showing fact " .. f.Id
end

function Mission.DevTeleport(player, where)
	local char = player.Character
	if not char then
		return false, "No character"
	end
	local cf
	if where == "Hub" then
		cf = spawnCF(0)
	elseif where == "Bunker" then
		local p = Stations.GetBunkerPosition()
		cf = p and CFrame.new(p + Vector3.new(0, 3, 0))
	elseif where == "Pad" then
		local m = Rocket.GetModel()
		cf = m and (m:GetPivot() * CFrame.new(16, 0, 0))
	else
		local port = Stations.GetPort(where)
		cf = port and (port.CFrame * CFrame.new(0, 2, -5))
	end
	if not cf then
		return false, "Nothing to teleport to"
	end
	char:PivotTo(cf)
	return true, "Teleported to " .. tostring(where)
end

------------------------------------------------------------------ players
local function stripTools(container)
	for _, t in ipairs(container:GetChildren()) do
		if t:IsA("Tool") and (t:FindFirstChild("Miner") or t.Name:match("^Drill")) then
			t:Destroy()
		end
	end
end

local function onCharacter(player, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum.UseJumpPower = true
		hum.JumpPower = MC.JumpPower
		hum.WalkSpeed = MC.WalkSpeed
		player:SetAttribute("BaseWalkSpeed", MC.WalkSpeed)
	end
	stripTools(char)
	task.defer(function()
		local bp = player:FindFirstChildOfClass("Backpack")
		if bp then
			stripTools(bp)
		end
	end)
end

local function hookPlayer(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	player.ChildAdded:Connect(function(c)
		if c:IsA("Backpack") then
			c.ChildAdded:Connect(function()
				stripTools(c)
			end)
		end
	end)
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		bp.ChildAdded:Connect(function()
			stripTools(bp)
		end)
	end
end

------------------------------------------------------------------ init
function Mission.Init(services)
	S = services
	Config = S.Config
	MC = Config.Mission
	Stations = S.StationService
	Events = S.MissionEvents
	Rocket = S.RocketService
	Facts = require(ReplicatedStorage:WaitForChild("BaseShared"):WaitForChild("MissionFacts"))
	state = S.MissionState
	remotes = S.MissionRemotes

	workspace.Gravity = MC.Gravity

	-- Sandbox prototypes in Workspace.BaseBuilding would sit around the map.
	-- Move them out of sight while the game runs (your saved place is not changed).
	if MC.HideSandboxModels then
		local bb = workspace:FindFirstChild(Config.Build.RootFolder)
		if bb then
			local hidden = ServerStorage:FindFirstChild("MissionHidden") or Instance.new("Folder")
			hidden.Name = "MissionHidden"
			hidden.Parent = ServerStorage
			bb.Parent = hidden
		end
	end
	-- ores are just rocks in the mission
	for _, folderName in ipairs(Config.Mining.OreFolders) do
		local f = workspace:FindFirstChild(folderName)
		for _, d in ipairs(f and f:GetDescendants() or {}) do
			if d:IsA("ProximityPrompt") then
				d.Enabled = false
			end
		end
	end

	reset()
	setPhase("Lobby")

	remotes.Action.OnServerInvoke = function(player, action)
		if action == "Start" or action == "Again" then
			return Mission.Start()
		elseif action == "Ready" then
			if phase == "Report" or phase == "Fact" then
				ready[player] = true
				local n, total = 0, #Players:GetPlayers()
				for p in pairs(ready) do
					if p.Parent then
						n += 1
					end
				end
				state:SetAttribute("Ready", n)
				if n >= total then
					skip = true
				end
				return true
			end
			return false
		elseif action == "GetEnd" then
			return lastEnd
		end
		return false
	end

	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		hookPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		ready[p] = nil
		task.defer(function()
			if #Players:GetPlayers() == 0 and phase ~= "Lobby" then
				Mission.Restart(true)
			end
		end)
	end)
end

return Mission
