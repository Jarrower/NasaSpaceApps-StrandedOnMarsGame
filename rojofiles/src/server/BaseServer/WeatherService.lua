--[[
	WeatherService  (ModuleScript)
	Location: ServerScriptService > BaseServer > WeatherService

	Runs the weather cycle:  Clear -> Warning -> Active -> Ending -> Clear ...
	Events (dust storms, ...) and their effects are defined in Config.Weather.

	State is published as Workspace attributes so clients can draw visuals:
	  WeatherEvent      ("" when clear, else the event id e.g. "DustStorm")
	  WeatherPhase      "Clear" | "Warning" | "Active" | "Ending"
	  WeatherPhaseEnds  server time (workspace:GetServerTimeNow()) when the phase ends
	  SolarMultiplier   read by Config.Power.GetOutput

	API for other systems:
	  Weather.GetIntensity()      0..1 (ramps up/down with RampTime)
	  Weather.GetEffect(name)     current multiplier/value, e.g. GetEffect("O2Drain")
	  Weather.GetEvent()          event id or nil
	  Weather.Start(id, duration?)  Weather.Warn(id)  Weather.Clear()   (dev panel)
	  Weather.Changed             BindableEvent(phase, eventId)

	In Mission mode there is no random cycle: storms only happen when
	Weather.Start is called (MissionEvents uses it for the dust storm visuals).
]]

local Weather = {}
Weather.Changed = Instance.new("BindableEvent")

local S, Config
local state = { Event = nil, Phase = "Clear", Started = 0, Ends = 0, Duration = 0 }
local token = 0
-- Random weather cycle (off in Mission mode: MissionService starts dust storms itself)
local autoCycle = true

local NEUTRAL = { O2Drain = 1, WalkSpeed = 1, Solar = 1, Damage = 0 }

local function now()
	return workspace:GetServerTimeNow()
end

local function randRange(r)
	return math.random(r[1], r[2])
end

local function pickEvent()
	local total = 0
	for _, ev in pairs(Config.Weather.Events) do
		total += ev.Weight or 1
	end
	local roll = math.random() * total
	for id, ev in pairs(Config.Weather.Events) do
		roll -= ev.Weight or 1
		if roll <= 0 then
			return id
		end
	end
	return next(Config.Weather.Events)
end

function Weather.GetEvent()
	return state.Event
end

function Weather.GetPhase()
	return state.Phase
end

function Weather.GetIntensity()
	if state.Phase ~= "Active" and state.Phase ~= "Ending" then
		return 0
	end
	local ramp = math.max(Config.Weather.RampTime, 0.01)
	local t = now()
	if state.Phase == "Active" then
		return math.clamp((t - state.Started) / ramp, 0, 1)
	end
	return math.clamp((state.Ends - t) / ramp, 0, 1) -- Ending
end

function Weather.GetEffect(name)
	local neutral = NEUTRAL[name] or 0
	local ev = state.Event and Config.Weather.Events[state.Event]
	if not ev or not ev.Effects or ev.Effects[name] == nil then
		return neutral
	end
	local i = Weather.GetIntensity()
	return neutral + (ev.Effects[name] - neutral) * i
end

local function publish()
	workspace:SetAttribute("WeatherEvent", state.Event or "")
	workspace:SetAttribute("WeatherPhase", state.Phase)
	workspace:SetAttribute("WeatherPhaseEnds", state.Ends)
	Weather.Changed:Fire(state.Phase, state.Event)
end

local function setPhase(phase, duration)
	state.Phase = phase
	state.Started = now()
	state.Ends = state.Started + duration
	publish()
end

-- Main cycle. Every call bumps the token so dev commands can interrupt it.
local function runCycle(startWith, eventId, duration)
	token += 1
	local my = token
	task.spawn(function()
		local phase = startWith or "Clear"
		while my == token do
			if phase == "Clear" then
				state.Event = nil
				if not autoCycle then
					setPhase("Clear", 0)
					break -- stay clear until Weather.Start is called again
				end
				setPhase("Clear", randRange(Config.Weather.TimeBetween))
				task.wait(state.Ends - now())
				phase, eventId = "Warning", pickEvent()
			elseif phase == "Warning" then
				state.Event = eventId or pickEvent()
				setPhase("Warning", Config.Weather.WarningTime)
				task.wait(state.Ends - now())
				phase = "Active"
			elseif phase == "Active" then
				state.Event = eventId or state.Event or pickEvent()
				local ev = Config.Weather.Events[state.Event]
				local d = duration or randRange(ev.Duration)
				duration = nil
				setPhase("Active", d)
				task.wait(state.Ends - now())
				phase = "Ending"
			elseif phase == "Ending" then
				setPhase("Ending", Config.Weather.RampTime)
				task.wait(state.Ends - now())
				phase = "Clear"
			end
		end
	end)
end

-- Dev / scripted control
function Weather.Start(eventId, duration)
	if not Config.Weather.Events[eventId] then
		return false
	end
	state.Event = eventId
	runCycle("Active", eventId, duration)
	return true
end

function Weather.Warn(eventId)
	if not Config.Weather.Events[eventId] then
		return false
	end
	runCycle("Warning", eventId)
	return true
end

function Weather.Clear()
	if state.Phase == "Active" then
		runCycle("Ending")
	else
		runCycle("Clear")
	end
end

function Weather.Init(services)
	S = services
	Config = S.Config
	workspace:SetAttribute("SolarMultiplier", 1)
	publish()
	autoCycle = Config.Weather.Enabled and Config.GameMode ~= "Mission"
	if not autoCycle then
		return -- Start/Warn/Clear still work (dev panel, Mission dust storms)
	end
	runCycle("Clear")

	-- Keep solar output in sync (recompute power only when it really changes)
	task.spawn(function()
		local last = 1
		while true do
			task.wait(1)
			local m = math.floor(Weather.GetEffect("Solar") * 20 + 0.5) / 20 -- 5% steps
			if m ~= last then
				last = m
				workspace:SetAttribute("SolarMultiplier", m)
				if S.NetworkService then
					S.NetworkService.Request()
				end
			end
		end
	end)
end

return Weather
