--[[
	BuildClient  (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > BuildClient
	Child:    BuildUI (ModuleScript) - all the visuals

	[B] build menu   [R] rotate   [Q] cancel   [X] delete mode
	Left click = place outline (or delete in delete mode)

	The ghost uses the SAME Placement.Solve as the server, so green = the
	server will accept it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("BaseShared")
local Config = require(shared:WaitForChild("Config"))
local Placement = require(shared:WaitForChild("Placement"))
local remotes = ReplicatedStorage:WaitForChild("BaseRemotes")
local PlaceRequest = remotes:WaitForChild("PlaceRequest")
local DeleteRequest = remotes:WaitForChild("DeleteRequest")
local Notify = remotes:WaitForChild("Notify")
ReplicatedStorage:WaitForChild(Config.Build.TemplatesFolder)
task.wait(1) -- give the server a moment to move templates into BuildTemplates

local BuildUI = require(script:WaitForChild("BuildUI"))

local camera = workspace.CurrentCamera
local Keys = Config.Build.Keys

local mode = nil -- nil | buildable name | "Delete"
local rot = 0
local ghost, ghostHL
local lastRes, lastHitPos, lastHitInst
local hoverPiece

local ui
local setMode

local function isMine(piece)
	return piece and piece:GetAttribute("Owner") == player.UserId
end

------------------------------------------------------------------ ghost
local function clearGhost()
	if ghost then
		ghost:Destroy()
	end
	ghost, ghostHL = nil, nil
end

local function makeGhost(typeName)
	clearGhost()
	local def = Config.Buildables[typeName]
	local template = Placement.GetTemplate(typeName)
	if not template then
		ui:Toast("Missing model for " .. def.DisplayName, "bad")
		return
	end
	local m
	if def.Kind == "Wall" then
		m = Instance.new("Model")
		local p = Placement.MainPart(template):Clone()
		p:ClearAllChildren()
		p.Parent = m
		m.PrimaryPart = p
	else
		m = template:Clone()
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = math.max(d.Transparency, 0.5)
		elseif d:IsA("ProximityPrompt") or d:IsA("Sound") or d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	ghostHL = Instance.new("Highlight")
	ghostHL.FillTransparency = 0.55
	ghostHL.OutlineTransparency = 0
	ghostHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	ghostHL.Parent = m
	ghost = m
end

local deleteHL = Instance.new("Highlight")
deleteHL.FillColor = Color3.fromRGB(255, 60, 60)
deleteHL.OutlineColor = Color3.fromRGB(255, 0, 0)
deleteHL.FillTransparency = 0.6
deleteHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
deleteHL.Parent = camera

function setMode(newMode)
	mode = newMode
	lastRes, hoverPiece = nil, nil
	deleteHL.Adornee = nil
	clearGhost()
	if mode and mode ~= "Delete" then
		makeGhost(mode)
	end
	ui:SetMode(mode)
	ui:SetStatus("")
end

ui = BuildUI.new(Config, Placement, {
	OnSelect = function(typeName)
		setMode(mode == typeName and nil or typeName)
	end,
	OnDelete = function()
		setMode(mode == "Delete" and nil or "Delete")
	end,
	OnClose = function()
		setMode(nil)
	end,
})

Notify.OnClientEvent:Connect(function(msg)
	ui:Toast(msg)
end)

------------------------------------------------------------------ own-base prompts
-- Hide build/refinery/fuel/airlock prompts on other players' bases (local only).
if Config.Build.OwnerOnlyInteract then
	local root = workspace:WaitForChild(Config.Build.RootFolder)
	local function watch(prompt)
		if not prompt:IsA("ProximityPrompt") then
			return
		end
		local piece = Placement.GetPiece(prompt)
		if not piece then
			return
		end
		local function apply()
			if not isMine(piece) and prompt.Enabled then
				prompt.Enabled = false
			end
		end
		apply()
		prompt:GetPropertyChangedSignal("Enabled"):Connect(apply)
	end
	for _, d in ipairs(root:GetDescendants()) do
		watch(d)
	end
	root.DescendantAdded:Connect(watch)
end

------------------------------------------------------------------ raycast
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function mouseRay()
	local ignore = { camera }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	local mp = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mp.X, mp.Y)
	return workspace:Raycast(ray.Origin, ray.Direction * 800, rayParams)
end

local function mouseOverGui()
	local mp = UserInputService:GetMouseLocation()
	local inset = game:GetService("GuiService"):GetGuiInset()
	local objs = player.PlayerGui:GetGuiObjectsAtPosition(mp.X, mp.Y - inset.Y)
	for _, o in ipairs(objs) do
		if o.Visible and o.BackgroundTransparency < 1 then
			return true
		end
	end
	return false
end

RunService.RenderStepped:Connect(function()
	if not ui:IsOpen() then
		ui:SetInspect(nil)
		return
	end
	local hit = not mouseOverGui() and mouseRay() or nil
	local hitPiece = hit and Placement.GetPiece(hit.Instance)

	-- Inspect tooltip (when not placing)
	if mode == nil or mode == "Delete" then
		ui:SetInspect(isMine(hitPiece) and hitPiece or nil)
	else
		ui:SetInspect(nil)
	end

	if mode == "Delete" then
		local piece = (not Config.Build.OwnerOnlyDelete or isMine(hitPiece)) and hitPiece or nil
		hoverPiece = piece
		deleteHL.Adornee = piece
		if piece then
			local def = Placement.Def(piece)
			if piece:GetAttribute("State") == "Blueprint" then
				ui:SetStatus("Click to remove " .. def.DisplayName .. " outline - materials refunded", true)
			else
				ui:SetStatus("Click to DEMOLISH " .. def.DisplayName .. " - no refund", false)
			end
		elseif hitPiece then
			ui:SetStatus("That's not your building", false)
		else
			ui:SetStatus("Hover one of your buildings or outlines")
		end
		return
	end

	if not mode or not ghost then
		return
	end
	local def = Config.Buildables[mode]
	local res = hit and Placement.Solve(mode, hit.Position, rot, hit.Instance, player.UserId)
	lastRes, lastHitPos, lastHitInst = res, hit and hit.Position, hit and hit.Instance

	if not res or not res.CFrame then
		ghost.Parent = nil
		local tip = (res and res.Reason)
			or (def.Kind == "Wall" and "Hover near the edge of one of your built tiles")
			or (def.Kind == "Component" and "Hover over one of your built tiles")
			or (def.Kind == "Linear" and "Hover near a free tile edge")
			or "Point at the ground"
		ui:SetStatus(tip)
		return
	end

	if def.Kind == "Wall" then
		ghost.PrimaryPart.Size = res.Size
		ghost.PrimaryPart.CFrame = res.CFrame
	else
		ghost:PivotTo(res.CFrame * Placement.GetInfo(mode).Offset)
	end
	if ghost.Parent ~= camera then
		ghost.Parent = camera
	end
	local color = res.Valid and Color3.fromRGB(92, 222, 140) or Color3.fromRGB(255, 88, 88)
	ghostHL.FillColor = color
	ghostHL.OutlineColor = color

	if res.Valid then
		ui:SetStatus("Cost: " .. Config.CostText(def.Cost) .. (res.Snapped and "  •  snapped to connector" or ""), true)
	else
		ui:SetStatus(res.Reason or "Can't place here", false)
	end
end)

------------------------------------------------------------------ input
local busy = false
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if busy or not mode or mouseOverGui() then
			return
		end
		busy = true
		if mode == "Delete" then
			if hoverPiece then
				local _, msg = DeleteRequest:InvokeServer(hoverPiece)
				ui:Toast(msg)
			end
		elseif lastRes and lastRes.Valid then
			local ok, msg = PlaceRequest:InvokeServer(mode, lastHitPos, rot, lastHitInst)
			if not ok then
				ui:Toast(msg, "bad")
			end
		end
		busy = false
	elseif input.KeyCode == Keys.Menu then
		ui:Toggle()
	elseif input.KeyCode == Keys.Rotate and mode then
		rot = (rot + 1) % 4
	elseif input.KeyCode == Keys.Cancel then
		if mode then
			setMode(nil)
		else
			ui:SetOpen(false)
		end
	elseif input.KeyCode == Keys.Delete then
		ui:SetOpen(true)
		setMode(mode == "Delete" and nil or "Delete")
	end
end)
