--[[
	BuildService  (ModuleScript)
	Location: ServerScriptService > BaseServer > BuildService

	Flow:
	  1. Client picks something in the build menu and clicks -> PlaceRequest
	  2. Server re-solves the placement (Placement.Solve) and spawns an OUTLINE
	     (blueprint) with an "Add Material" ProximityPrompt
	  3. Player holds a material tool and presses the prompt -> materials are
	     deposited into the outline
	  4. When all materials are in -> it becomes a real building (State = "Built")

	Delete outline  -> all deposited materials refunded
	Delete building -> no refund (deleting a tile also removes its walls/components)

	Events other systems can listen to:
	  BuildService.PieceBuilt   (model)
	  BuildService.PieceRemoved (model)  -- fired just before it's destroyed
	  BuildService.Changed      ()       -- anything was placed/built/removed
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildService = {}
BuildService.PieceBuilt = Instance.new("BindableEvent")
BuildService.PieceRemoved = Instance.new("BindableEvent")
BuildService.Changed = Instance.new("BindableEvent")
BuildService.FreeBuild = {} -- [player] = true -> outlines complete instantly (dev panel)

local S, Config, Placement, Inventory
local lastRequest = {}

------------------------------------------------------------------ templates
local function bootstrapTemplates()
	local templates = ReplicatedStorage:FindFirstChild(Config.Build.TemplatesFolder)
	if not templates then
		templates = Instance.new("Folder")
		templates.Name = Config.Build.TemplatesFolder
		templates.Parent = ReplicatedStorage
	end
	local root = Placement.GetRoot()
	if not root then
		root = Instance.new("Folder")
		root.Name = Config.Build.RootFolder
		root.Parent = workspace
	end

	for typeName, def in pairs(Config.Buildables) do
		local templateName = Placement.TemplateName(typeName)
		if not templates:FindFirstChild(templateName) then
			-- Auto-move the prototype model out of Workspace.BaseBuilding
			local found
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("Model") and d.Name == templateName and not d:GetAttribute("BuildType") then
					found = d
					break
				end
			end
			if found then
				found.Parent = templates
			elseif def.Fallback then
				local m = Instance.new("Model")
				m.Name = templateName
				local p = Instance.new("Part")
				p.Name = "Body"
				p.Size = def.Fallback.Size
				p.Color = def.Fallback.Color or Color3.new(1, 1, 1)
				p.Anchored = true
				p.Parent = m
				m.PrimaryPart = p
				m.Parent = templates
				warn(("[Build] No '%s' model found - using a placeholder block. Put your model in ReplicatedStorage.%s")
					:format(templateName, Config.Build.TemplatesFolder))
			else
				warn(("[Build] Missing template '%s' in ReplicatedStorage.%s"):format(templateName, Config.Build.TemplatesFolder))
			end
		end
		if not root:FindFirstChild(def.Folder) then
			local f = Instance.new("Folder")
			f.Name = def.Folder
			f.Parent = root
		end
	end
end

------------------------------------------------------------------ helpers
-- Can this player use prompts on this piece? (own base only)
function BuildService.CanUse(player, model)
	if not Config.Build.OwnerOnlyInteract then
		return true
	end
	local piece = Placement.GetPiece(model) or model
	return piece:GetAttribute("Owner") == player.UserId
end

local function ensureBool(model, name, value)
	local v = model:FindFirstChild(name)
	if not v then
		v = Instance.new("BoolValue")
		v.Name = name
		v.Parent = model
	end
	if value ~= nil then
		v.Value = value
	end
	return v
end
BuildService.EnsureBool = ensureBool

-- Creates (or reuses) one attachment at the piece's centre and puts a prompt on it.
function BuildService.AttachPrompt(model, name, actionText, key, hold)
	local part = Placement.MainPart(model)
	local att = part:FindFirstChild("PromptAtt")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "PromptAtt"
		att.Parent = part
		local center = model:GetAttribute("Center")
		att.WorldPosition = center and center.Position or part.Position
	end
	local size = model:GetAttribute("Size") or part.Size
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = actionText
	p.KeyboardKeyCode = key or Enum.KeyCode.E
	p.HoldDuration = hold or 0
	p.RequiresLineOfSight = false
	p.MaxActivationDistance = math.max(10, math.max(size.X, size.Z) / 2 + 6)
	p.Parent = att
	return p
end

local function setBlueprintLook(model, on)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if on then
				d:SetAttribute("_bpT", d.Transparency)
				d:SetAttribute("_bpM", d.Material.Name)
				d:SetAttribute("_bpC", d.Color)
				d:SetAttribute("_bpCC", d.CanCollide)
				d.Transparency = math.max(d.Transparency, Config.Build.BlueprintTransparency)
				d.Material = Config.Build.BlueprintMaterial
				d.Color = Config.Build.BlueprintColor
				d.CanCollide = false
			elseif d:GetAttribute("_bpT") ~= nil then
				d.Transparency = d:GetAttribute("_bpT")
				d.Material = Enum.Material[d:GetAttribute("_bpM")]
				d.Color = d:GetAttribute("_bpC")
				d.CanCollide = d:GetAttribute("_bpCC")
				for _, a in ipairs({ "_bpT", "_bpM", "_bpC", "_bpCC" }) do
					d:SetAttribute(a, nil)
				end
			end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			if on then
				d:SetAttribute("_bpT", d.Transparency)
				d.Transparency = 1
			elseif d:GetAttribute("_bpT") ~= nil then
				d.Transparency = d:GetAttribute("_bpT")
				d:SetAttribute("_bpT", nil)
			end
		elseif d:IsA("ProximityPrompt") and d.Name ~= "AddMaterial" then
			d.Enabled = not on
		end
	end
end

local function remainingText(model, def)
	local parts = {}
	for item, amt in pairs(def.Cost or {}) do
		local have = model:GetAttribute("Dep_" .. item) or 0
		if have < amt then
			table.insert(parts, string.format("%s %d/%d", Config.ItemName(item), have, amt))
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function isComplete(model, def)
	for item, amt in pairs(def.Cost or {}) do
		if (model:GetAttribute("Dep_" .. item) or 0) < amt then
			return false
		end
	end
	return true
end

------------------------------------------------------------------ build
function BuildService.Complete(model)
	if model:GetAttribute("State") == "Built" then
		return
	end
	local prompt = model:FindFirstChild("AddMaterial", true)
	if prompt then
		prompt:Destroy()
	end
	setBlueprintLook(model, false)
	model:SetAttribute("State", "Built")
	BuildService.PieceBuilt:Fire(model)
	BuildService.Changed:Fire()
end

local function onDeposit(player, model)
	if model:GetAttribute("State") ~= "Blueprint" then
		return
	end
	if not BuildService.CanUse(player, model) then
		S.Notify(player, "That's not your base.")
		return
	end
	local def = Placement.Def(model)
	local items = {}
	if Config.Build.RequireHoldingMaterial then
		local held = Inventory.GetHeld(player)
		if not held then
			S.Notify(player, "Hold a material to build. Needs: " .. remainingText(model, def))
			return
		end
		items = { held }
	else
		for item in pairs(def.Cost) do
			table.insert(items, item)
		end
	end

	local added = 0
	for _, item in ipairs(items) do
		local need = (def.Cost[item] or 0) - (model:GetAttribute("Dep_" .. item) or 0)
		if need > 0 then
			local took = Inventory.Remove(player, item, need)
			if took > 0 then
				model:SetAttribute("Dep_" .. item, (model:GetAttribute("Dep_" .. item) or 0) + took)
				added += took
			end
		end
	end

	if isComplete(model, def) then
		BuildService.Complete(model)
		S.Notify(player, def.DisplayName .. " built!")
		return
	end
	if added == 0 then
		S.Notify(player, "That isn't needed here. Needs: " .. remainingText(model, def))
	end
	local prompt = model:FindFirstChild("AddMaterial", true)
	if prompt then
		prompt.ObjectText = def.DisplayName .. " - needs " .. remainingText(model, def)
	end
end

function BuildService.Place(player, typeName, hitPos, rot, hitInst)
	if typeof(typeName) ~= "string" or typeof(hitPos) ~= "Vector3" then
		return false, "Bad request"
	end
	local def = Config.Buildables[typeName]
	local template = Placement.GetTemplate(typeName)
	if not def or not template then
		return false, "Unknown building"
	end
	if typeof(hitInst) ~= "Instance" then
		hitInst = nil
	end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - hitPos).Magnitude > Config.Build.MaxPlaceDistance then
		return false, "Too far away"
	end

	local res = Placement.Solve(typeName, hitPos, rot, hitInst, player.UserId)
	if not res or not res.Valid then
		return false, (res and res.Reason) or "Can't place here"
	end

	local model = template:Clone()
	if def.Kind == "Wall" then
		local part = Placement.MainPart(model)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= part then
				d:Destroy()
			end
		end
		part.Size = res.Size
		part.CFrame = res.CFrame
		model.PrimaryPart = part
	else
		model:PivotTo(res.CFrame * Placement.GetInfo(typeName).Offset)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end

	model:SetAttribute("BuildType", typeName)
	model:SetAttribute("BuildId", HttpService:GenerateGUID(false))
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("State", "Blueprint")
	model:SetAttribute("Center", res.CFrame)
	model:SetAttribute("Size", res.Size)
	if res.HostTile then
		model:SetAttribute("HostTile", res.HostTile:GetAttribute("BuildId"))
	end
	if res.Side then
		model:SetAttribute("Side", res.Side)
	end
	if res.Slot then
		model:SetAttribute("Slot", res.Slot)
	end
	if def.Kind == "Tile" then
		local base = model:FindFirstChild("Base")
		local floorY = (base and base:IsA("BasePart")) and (base.Position.Y + base.Size.Y / 2)
			or (res.CFrame.Position.Y - res.Size.Y / 2)
		model:SetAttribute("FloorY", floorY)
		ensureBool(model, Config.Power.PoweredValueName, false)
		ensureBool(model, Config.Oxygen.ValueName, false)
	end

	setBlueprintLook(model, true)
	model.Parent = Placement.GetRoot():FindFirstChild(def.Folder)

	if isComplete(model, def) or BuildService.FreeBuild[player] then
		BuildService.Complete(model) -- free buildings / dev free-build
	else
		local prompt = BuildService.AttachPrompt(model, "AddMaterial", "Add Material", Enum.KeyCode.E, 0.3)
		prompt.ObjectText = def.DisplayName .. " - needs " .. remainingText(model, def)
		prompt.Triggered:Connect(function(p)
			onDeposit(p, model)
		end)
		BuildService.Changed:Fire()
	end
	return true, def.DisplayName .. " outline placed"
end

------------------------------------------------------------------ delete
local function removePiece(piece, refundTo, refunded)
	local def = Placement.Def(piece)
	if piece:GetAttribute("State") == "Blueprint" and refundTo then
		for item in pairs(def.Cost or {}) do
			local dep = piece:GetAttribute("Dep_" .. item) or 0
			if dep > 0 then
				Inventory.Add(refundTo, item, dep)
				refunded[item] = (refunded[item] or 0) + dep
			end
		end
	end
	if def.Kind == "Tile" then
		local id = piece:GetAttribute("BuildId")
		for _, other in ipairs(Placement.GetPieces()) do
			if other ~= piece and other:GetAttribute("HostTile") == id then
				removePiece(other, refundTo, refunded)
			end
		end
	end
	BuildService.PieceRemoved:Fire(piece)
	piece:Destroy()
end

-- Remove a piece with no refund and no ownership checks (used by dev tools)
function BuildService.ForceRemove(piece)
	if piece and piece.Parent then
		removePiece(piece, nil, {})
		BuildService.Changed:Fire()
	end
end

function BuildService.Delete(player, target)
	if typeof(target) ~= "Instance" then
		return false, "Bad request"
	end
	local piece = Placement.GetPiece(target)
	local root = Placement.GetRoot()
	if not piece or not piece:IsDescendantOf(root) then
		return false, "That isn't a building"
	end
	if Config.Build.OwnerOnlyDelete and piece:GetAttribute("Owner") ~= player.UserId then
		return false, "You don't own this"
	end
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local center = piece:GetAttribute("Center")
	if not hrp or (center and (hrp.Position - center.Position).Magnitude > Config.Build.MaxPlaceDistance) then
		return false, "Too far away"
	end

	local wasBlueprint = piece:GetAttribute("State") == "Blueprint"
	local refunded = {}
	removePiece(piece, player, refunded)
	BuildService.Changed:Fire()
	if wasBlueprint then
		return true, "Outline removed. Refunded: " .. Config.CostText(refunded)
	end
	return true, "Building demolished (no refund)"
end

------------------------------------------------------------------ init
function BuildService.Init(services)
	S = services
	Config = S.Config
	Placement = S.Placement
	Inventory = S.InventoryService
	bootstrapTemplates()

	local function throttled(player)
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < 0.15 then
			return true
		end
		lastRequest[player] = now
		return false
	end

	S.Remotes.PlaceRequest.OnServerInvoke = function(player, typeName, hitPos, rot, hitInst)
		if throttled(player) then
			return false, "Slow down"
		end
		return BuildService.Place(player, typeName, hitPos, rot, hitInst)
	end
	S.Remotes.DeleteRequest.OnServerInvoke = function(player, target)
		if throttled(player) then
			return false, "Slow down"
		end
		return BuildService.Delete(player, target)
	end
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		lastRequest[p] = nil
	end)
end

return BuildService
