--[[
	StationService  (ModuleScript)
	Location: ServerScriptService > BaseServer > StationService
	Mission mode only (Config.GameMode = "Mission").

	STATIONS
	  Workspace > MissionBase > Stations > <Model with attribute StationId>
	  Each station model has a Part named "PowerPort" (made by setup/MissionSetup.lua).
	  The port gets an [E] prompt: plug in a power cell / unplug it again.
	  If a station or its port is missing, a simple fallback port is made at
	  Config.Mission.Stations[i].FallbackPosition so the game still works.

	POWER CELLS
	  The crew shares one pool. Stations.BeginSol(cells) unplugs everything and
	  sets the pool. Prompts are disabled while Stations.SetLocked(true).

	SHIELD BUNKER
	  Workspace > MissionBase > Bunker
	    BunkerZone  (Part(s), invisible)  inside = safe from solar storms
	    BunkerDoor  (copy of your "metal door"; its own DoorController is disabled)
	  The door only opens from outside when the Shield Bunker is powered.
	  From inside it always opens, so nobody gets trapped.
	  ShelterZone parts (e.g. inside the greenhouse) only make the dust look lighter.

	This module also creates the shared mission state + remotes (it starts first):
	  ReplicatedStorage > MissionState (Folder, attributes)   -> S.MissionState
	  BaseRemotes > MissionEvent (RemoteEvent), MissionAction (RemoteFunction) -> S.MissionRemotes

	API: Stations.BeginSol(cells)  SetLocked(bool)  AddCells(n)  UnplugAll()
	     IsPowered(id)  Snapshot()  SetNote(id, text?)  Toggle(player, id)
	     IsInBunker(player)  GetPort(id)  GetBunkerPosition()  GetSpawnCFrame()
	     Stations.Changed (BindableEvent: id, powered, player)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Stations = {}
Stations.Changed = Instance.new("BindableEvent")

local S, Config, MC
local state, remotes
local list = {}        -- [id] = { Def, Model, Port, Light, Prompt, Gui, Powered, By, Note }
local total, used = 0, 0
local locked = true
local lastPress = {}
local bunker = { Zones = {}, Shelters = {} }

local OFF_COLOR = Color3.fromRGB(70, 72, 80)
local GOOD = Color3.fromRGB(92, 222, 140)
local BAD = Color3.fromRGB(255, 88, 88)

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

local function signed(n)
	return (n >= 0 and "+" or "-") .. tostring(math.abs(n))
end

function Stations.Def(id)
	for _, d in ipairs(MC.Stations) do
		if d.Id == id then
			return d
		end
	end
	return nil
end

-- "Oxygen +10" / "Oxygen -40" / custom text
function Stations.EffectText(d, on)
	if on and d.OnText then
		return d.OnText
	elseif not on and d.OffText then
		return d.OffText
	end
	if d.Meter then
		return d.Meter .. " " .. signed(on and d.On or d.Off)
	end
	return ""
end

local function inBoxCF(position, cf, s, margin)
	local rel = cf:PointToObjectSpace(position)
	margin = margin or 0
	return math.abs(rel.X) <= s.X / 2 + margin and math.abs(rel.Y) <= s.Y / 2 + margin
		and math.abs(rel.Z) <= s.Z / 2 + margin
end

local function inBox(position, part, margin)
	return inBoxCF(position, part.CFrame, part.Size, margin)
end

local function rootOf(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function groundY(x, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1200, 0), params)
	return hit and hit.Position.Y or 3
end

local function broadcast(kind, data)
	remotes.Event:FireAllClients(kind, data)
end
Stations.Broadcast = broadcast

------------------------------------------------------------------ state
local function publish()
	state:SetAttribute("CellsTotal", total)
	state:SetAttribute("CellsUsed", used)
	state:SetAttribute("StationsLocked", locked)
	for id, st in pairs(list) do
		state:SetAttribute("On_" .. id, st.Powered)
		state:SetAttribute("By_" .. id, st.By or "")
	end
end

------------------------------------------------------------------ visuals
local function makeBillboard(st)
	local d = st.Def
	local gui = create("BillboardGui", {
		Name = "StationSign", Size = UDim2.fromOffset(250, 118), StudsOffsetWorldSpace = Vector3.new(0, 6, 0),
		MaxDistance = 140, LightInfluence = 0, AlwaysOnTop = false, ResetOnSpawn = false, Parent = st.Port,
	})
	local frame = create("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(18, 19, 25), BackgroundTransparency = 0.12,
		Parent = gui,
	})
	create("UICorner", { CornerRadius = UDim.new(0, 12), Parent = frame })
	local stroke = create("UIStroke", { Color = d.Color, Thickness = 2, Transparency = 0.3, Parent = frame })
	local function text(name, props)
		props.Name = name
		props.BackgroundTransparency = 1
		props.Font = props.Font or Enum.Font.GothamBold
		props.TextColor3 = props.TextColor3 or Color3.fromRGB(240, 241, 246)
		props.TextScaled = true
		props.Parent = frame
		return create("TextLabel", props)
	end
	text("Title", { Text = d.Icon .. " " .. d.Name, Position = UDim2.new(0, 8, 0, 6), Size = UDim2.new(1, -16, 0, 26), Font = Enum.Font.GothamBlack })
	text("Status", { Text = "OFF", Position = UDim2.new(0, 8, 0, 34), Size = UDim2.new(1, -16, 0, 22) })
	text("On", { Text = "ON: " .. Stations.EffectText(d, true), Position = UDim2.new(0, 8, 0, 60), Size = UDim2.new(1, -16, 0, 18), Font = Enum.Font.GothamMedium, TextColor3 = GOOD })
	text("Off", { Text = "OFF: " .. Stations.EffectText(d, false), Position = UDim2.new(0, 8, 0, 80), Size = UDim2.new(1, -16, 0, 18), Font = Enum.Font.GothamMedium, TextColor3 = BAD })
	text("Note", { Text = "", Position = UDim2.new(0, 8, 0, 98), Size = UDim2.new(1, -16, 0, 16), Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(255, 196, 70) })
	st.Gui, st.Stroke = frame, stroke
end

local function refresh(st)
	local d = st.Def
	-- light on top of the port
	if st.Light then
		st.Light.Color = st.Powered and d.Color or OFF_COLOR
		st.Light.Material = st.Powered and Enum.Material.Neon or Enum.Material.SmoothPlastic
		local pl = st.Light:FindFirstChildOfClass("PointLight")
		if pl then
			pl.Enabled = st.Powered
			pl.Color = d.Color
		end
	end
	if st.Highlight then
		st.Highlight.Enabled = st.Powered
	end
	if st.Model then
		st.Model:SetAttribute("Powered", st.Powered)
	end
	-- sign
	if st.Gui then
		local status = st.Gui:FindFirstChild("Status")
		status.Text = st.Powered and ("POWERED" .. (st.By and ("  by " .. st.By) or "")) or "NO POWER"
		status.TextColor3 = st.Powered and GOOD or BAD
		st.Gui.Note.Text = st.Note or ""
		st.Stroke.Transparency = st.Powered and 0 or 0.6
	end
	-- prompt
	if st.Prompt then
		st.Prompt.Enabled = not locked
		if st.Powered then
			st.Prompt.ActionText = "Unplug power cell"
		elseif used >= total then
			st.Prompt.ActionText = "No cells left"
		else
			st.Prompt.ActionText = "Plug in power cell"
		end
	end
end

local function refreshAll()
	for _, st in pairs(list) do
		refresh(st)
	end
	publish()
end

------------------------------------------------------------------ setup
local function makePort(d, model)
	local pos = d.FallbackPosition
	local port = create("Part", {
		Name = "PowerPort", Anchored = true, Size = Vector3.new(2, 4, 2), Material = Enum.Material.Metal,
		Color = Color3.fromRGB(90, 94, 104),
		CFrame = CFrame.new(pos.X, groundY(pos.X, pos.Z) + 2, pos.Z),
		Parent = model or workspace,
	})
	warn("[Stations] No PowerPort for " .. d.Id .. " - made a fallback one. Run setup/MissionSetup.lua in Studio.")
	return port
end

local function setupStation(d, folder)
	local model
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:GetAttribute("StationId") == d.Id or m.Name == d.Id then
				model = m
				break
			end
		end
	end
	local port = model and model:FindFirstChild("PowerPort", true)
	if not port or not port:IsA("BasePart") then
		port = makePort(d, model)
	end
	local st = { Def = d, Model = model, Port = port, Powered = false }

	-- glowing cap on the port
	local light = port.Parent:FindFirstChild("PortLight")
	if not light then
		light = create("Part", {
			Name = "PortLight", Anchored = true, CanCollide = false, Size = Vector3.new(2.4, 0.5, 2.4),
			CFrame = port.CFrame * CFrame.new(0, port.Size.Y / 2 + 0.25, 0), Parent = port.Parent,
		})
	end
	if not light:FindFirstChildOfClass("PointLight") then
		create("PointLight", { Range = 16, Brightness = 2, Enabled = false, Parent = light })
	end
	st.Light = light

	-- outline the whole station while it is powered
	if model then
		local target = model:FindFirstChild("GlowTarget") -- ObjectValue (the Shield points at the Bunker)
		st.Highlight = create("Highlight", {
			Name = "PoweredGlow", Adornee = (target and target:IsA("ObjectValue") and target.Value) or model, FillTransparency = 1, OutlineColor = d.Color,
			OutlineTransparency = 0.25, DepthMode = Enum.HighlightDepthMode.Occluded, Enabled = false, Parent = model,
		})
	end

	local old = port:FindFirstChild("PowerPrompt")
	if old then
		old:Destroy()
	end
	st.Prompt = create("ProximityPrompt", {
		Name = "PowerPrompt", ActionText = "Plug in power cell", ObjectText = d.Name, HoldDuration = 0,
		KeyboardKeyCode = Enum.KeyCode.E, GamepadKeyCode = Enum.KeyCode.ButtonX, MaxActivationDistance = 12,
		RequiresLineOfSight = false, Parent = port,
	})
	st.Prompt.Triggered:Connect(function(player)
		Stations.Toggle(player, d.Id)
	end)
	makeBillboard(st)
	list[d.Id] = st
end

local function setupBunker()
	local base = workspace:FindFirstChild("MissionBase")
	local b = base and base:FindFirstChild("Bunker")
	if base then
		for _, d in ipairs(base:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "ShelterZone" then
				table.insert(bunker.Shelters, d)
			end
		end
	end
	if not b then
		warn("[Stations] No Workspace.MissionBase.Bunker - run setup/MissionSetup.lua. Solar storms will hurt everyone.")
		return
	end
	for _, d in ipairs(b:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "BunkerZone" then
			table.insert(bunker.Zones, d)
		end
	end
	local door = b:FindFirstChild("BunkerDoor")
	local auto = door and door:FindFirstChild("AutoSlidingDoor", true)
	if not auto then
		warn("[Stations] Bunker has no BunkerDoor/AutoSlidingDoor - the bunker is always open")
		return
	end
	local ctrl = auto:FindFirstChild("DoorController")
	if ctrl and ctrl:IsA("BaseScript") then
		ctrl.Disabled = true -- we drive the door instead (so it can be locked)
	end
	local left, right, zone = auto:FindFirstChild("LeftDoor"), auto:FindFirstChild("RightDoor"), auto:FindFirstChild("DetectionZone")
	if not (left and right and zone) then
		warn("[Stations] BunkerDoor is missing LeftDoor/RightDoor/DetectionZone")
		return
	end
	-- same slide maths as your DoorController
	local diff = right.Position - left.Position
	local axis
	if math.abs(diff.X) >= math.abs(diff.Y) and math.abs(diff.X) >= math.abs(diff.Z) then
		axis = Vector3.xAxis
	elseif math.abs(diff.Y) >= math.abs(diff.Z) then
		axis = Vector3.yAxis
	else
		axis = Vector3.zAxis
	end
	local center = (left.Position + right.Position) / 2
	bunker.Doors = {}
	for _, p in ipairs({ left, right }) do
		p.Anchored = true
		local sign = (p.Position - center):Dot(axis)
		sign = sign == 0 and 1 or math.sign(sign)
		local dist = math.abs(p.Size:Dot(p.CFrame:VectorToObjectSpace(axis))) + 0.1
		table.insert(bunker.Doors, { Part = p, Closed = p.CFrame, Open = p.CFrame + axis * sign * dist })
	end
	bunker.Zone = zone
	bunker.Sound = auto:FindFirstChild("SlideSound", true)
	bunker.Open = false

	-- sign over the door
	local gui = create("BillboardGui", {
		Name = "BunkerSign", Size = UDim2.fromOffset(240, 56), StudsOffsetWorldSpace = Vector3.new(0, 8, 0),
		MaxDistance = 160, LightInfluence = 0, Parent = zone,
	})
	local f = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(18, 19, 25), BackgroundTransparency = 0.1, Parent = gui })
	create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = f })
	create("TextLabel", {
		Name = "Title", Text = "🛡️ SHIELD BUNKER", BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextScaled = true,
		TextColor3 = Color3.fromRGB(240, 241, 246), Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(1, -16, 0, 26), Parent = f,
	})
	bunker.Label = create("TextLabel", {
		Name = "State", Text = "LOCKED", BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextScaled = true,
		TextColor3 = BAD, Position = UDim2.new(0, 8, 0, 30), Size = UDim2.new(1, -16, 0, 20), Parent = f,
	})
end

local TWEEN = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local function setDoor(open)
	if bunker.Open == open then
		return
	end
	bunker.Open = open
	for _, d in ipairs(bunker.Doors) do
		TweenService:Create(d.Part, TWEEN, { CFrame = open and d.Open or d.Closed }):Play()
	end
	if bunker.Sound then
		bunker.Sound:Play()
	end
end

local lastLockedNote = {}
local function doorTick(emptySince)
	if not bunker.Doors then
		return emptySince
	end
	local powered = Stations.IsPowered("Shield")
	local wantOpen, inDoorway = false, false
	for _, player in ipairs(Players:GetPlayers()) do
		local hrp = rootOf(player)
		if hrp then
			local near = inBox(hrp.Position, bunker.Zone, 0)
			for _, d in ipairs(bunker.Doors) do
				if inBoxCF(hrp.Position, d.Closed, d.Part.Size, 1.5) then
					inDoorway = true
				end
			end
			if near then
				if powered or Stations.IsInBunker(player) then
					wantOpen = true -- powered, or leaving from inside
				elseif os.clock() - (lastLockedNote[player] or 0) > 6 then
					lastLockedNote[player] = os.clock()
					S.Notify(player, "The bunker door is LOCKED. Plug a power cell into the Shield Bunker to open it.")
				end
			end
		end
	end
	if wantOpen or (bunker.Open and inDoorway) then
		setDoor(true)
		emptySince = nil
	else
		emptySince = emptySince or os.clock()
		if os.clock() - emptySince >= 1.5 then
			setDoor(false)
		end
	end
	if bunker.Label then
		bunker.Label.Text = powered and "OPEN - safe inside" or "LOCKED - no power"
		bunker.Label.TextColor3 = powered and GOOD or BAD
	end
	return emptySince
end

------------------------------------------------------------------ API
function Stations.GetState()
	return state
end

function Stations.IsPowered(id)
	local st = list[id]
	return st ~= nil and st.Powered
end

function Stations.Snapshot()
	local t = {}
	for id, st in pairs(list) do
		t[id] = st.Powered
	end
	return t
end

function Stations.GetPort(id)
	local st = list[id]
	return st and st.Port
end

function Stations.GetModel(id)
	local st = list[id]
	return st and st.Model
end

function Stations.SetNote(id, text)
	local st = list[id]
	if st then
		st.Note = text
		refresh(st)
	end
end

function Stations.UnplugAll()
	for _, st in pairs(list) do
		st.Powered, st.By = false, nil
	end
	used = 0
	refreshAll()
end

function Stations.BeginSol(cells)
	total = math.max(0, cells)
	for _, st in pairs(list) do
		st.Powered, st.By, st.Note = false, nil, nil
	end
	used = 0
	locked = false
	refreshAll()
end

function Stations.SetLocked(on)
	locked = on
	refreshAll()
end

function Stations.AddCells(n)
	total = math.max(used, total + n)
	refreshAll()
end

function Stations.GetCells()
	return total, used
end

function Stations.Toggle(player, id)
	local st = list[id]
	if not st then
		return false
	end
	local now = os.clock()
	if lastPress[player] and now - lastPress[player] < 0.3 then
		return false
	end
	lastPress[player] = now
	if locked then
		S.Notify(player, "Wait for the next sol to move power cells.")
		return false
	end
	if st.Powered then
		st.Powered, st.By = false, nil
		used -= 1
		broadcast("Toast", { Text = string.format("%s unplugged the %s (%d cell%s free)", player.DisplayName, st.Def.Name, total - used, total - used == 1 and "" or "s"), Kind = "info" })
	elseif used >= total then
		S.Notify(player, "No power cells left! Unplug another station to move its cell here.")
		return false
	else
		st.Powered, st.By = true, player.DisplayName
		used += 1
		broadcast("Toast", { Text = string.format("%s powered the %s (%d cell%s free)", player.DisplayName, st.Def.Name, total - used, total - used == 1 and "" or "s"), Kind = "good" })
	end
	broadcast("Plug", { Id = id, On = st.Powered })
	refreshAll()
	Stations.Changed:Fire(id, st.Powered, player)
	return true
end

function Stations.IsInBunker(player)
	local hrp = rootOf(player)
	if not hrp then
		return false
	end
	for _, z in ipairs(bunker.Zones) do
		if inBox(hrp.Position, z, 0.5) then
			return true
		end
	end
	return false
end

function Stations.HasBunker()
	return #bunker.Zones > 0
end

function Stations.GetBunkerPosition()
	if bunker.Zone then
		return bunker.Zone.Position
	end
	local z = bunker.Zones[1]
	return z and z.Position or (list.Shield and list.Shield.Port.Position)
end

function Stations.GetSpawnCFrame()
	local base = workspace:FindFirstChild("MissionBase")
	local spawn = base and base:FindFirstChild("MissionSpawn", true)
	spawn = spawn or workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		return spawn.CFrame + Vector3.new(0, 4, 0)
	end
	return CFrame.new(33, 10, 3)
end

------------------------------------------------------------------ init
local function remote(class, name)
	local folder = ReplicatedStorage:WaitForChild("BaseRemotes")
	local r = folder:FindFirstChild(name) or Instance.new(class)
	r.Name = name
	r.Parent = folder
	return r
end

function Stations.Init(services)
	S = services
	Config = S.Config
	MC = Config.Mission

	state = ReplicatedStorage:FindFirstChild("MissionState") or Instance.new("Folder")
	state.Name = "MissionState"
	state.Parent = ReplicatedStorage
	remotes = {
		Event = remote("RemoteEvent", "MissionEvent"),
		Action = remote("RemoteFunction", "MissionAction"),
	}
	S.MissionState = state
	S.MissionRemotes = remotes

	local base = workspace:FindFirstChild("MissionBase")
	if not base then
		warn("[Stations] Workspace.MissionBase not found. Run setup/MissionSetup.lua in Studio's Command Bar, then save.")
	end
	local folder = base and base:FindFirstChild("Stations")
	for _, d in ipairs(MC.Stations) do
		local ok, err = pcall(setupStation, d, folder)
		if not ok then
			warn("[Stations] " .. d.Id .. ": " .. tostring(err))
		end
	end
	setupBunker()
	locked = true
	refreshAll()

	-- door + "Inside" attributes (dust looks lighter indoors)
	task.spawn(function()
		local emptySince
		while true do
			task.wait(0.2)
			emptySince = doorTick(emptySince)
			for _, player in ipairs(Players:GetPlayers()) do
				local inB = Stations.IsInBunker(player)
				local inside = inB
				local hrp = rootOf(player)
				if hrp and not inside then
					for _, z in ipairs(bunker.Shelters) do
						if inBox(hrp.Position, z, 0) then
							inside = true
							break
						end
					end
				end
				player:SetAttribute("InBunker", inB)
				player:SetAttribute("Inside", inside)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastPress[p] = nil
		lastLockedNote[p] = nil
	end)
end

return Stations
