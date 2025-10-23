--[[
   
    A complete skill system for Roblox using Luau scripting.
    Demonstrates advanced use of CFrame math, physics, tweens, remote communication, cooldowns, and modular logic.
    Created for Luau Scripter Skill Role evaluation.

    Author: Void_FutureDevs
]]

--- ROBLOX SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

--- SHARED RESOURCES
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent") -- Triggered by client to activate skill
local GetMouseFunction = ReplicatedStorage:WaitForChild("GetMousePosition") -- Used to fetch mouse click position
local ModelTemplate = ReplicatedStorage:WaitForChild("Model") -- Main model containing projectile parts
local SHMODEL = ReplicatedStorage:WaitForChild("SHURIQUENDEBIJU") -- Decorative model to attach to projectiles
local Colors = require(ReplicatedStorage:WaitForChild("Colors")) -- Table of custom BrickColors

--- SERVER MODULES (assumed external modules for visuals or UI)
local CLW = require(game.ServerScriptService:WaitForChild("CLW"))

--- CONSTANT CONFIGURATION
local PowerID = "25" -- ID used to show cooldown visuals
local Cooldown = 5 -- Cooldown duration in seconds
local AlturaExtra = 10 -- Vertical offset when spawning the model

--- COOLDOWN STATE
local serverCooldowns = {} -- Tracks last time player used the skill
local clwStatus = {} -- Ensures cooldown UI is shown only once
local partToModel = {} -- Maps projectile parts to attached decorative models


-- MODULE: CooldownService (Custom logic)
--========================================
local CooldownService = {}

function CooldownService:IsOnCooldown(player, duration)
	local lastUse = serverCooldowns[player.UserId]
	return lastUse and tick() - lastUse < duration
end

function CooldownService:SetCooldown(player)
	serverCooldowns[player.UserId] = tick()
end

function CooldownService:Clear(player)
	serverCooldowns[player.UserId] = nil
end


-- MODULE: Utility Functions
--========================================
local Util = {}

-- Filters colors to use only those with sufficient brightness and contrast
function Util:GetValidColors(colorModule)
	local validColors = {}
	for name, color in pairs(colorModule) do
		local contrast = math.max(color.R, color.G, color.B) - math.min(color.R, color.G, color.B)
		local brightness = (color.R + color.G + color.B) / 3
		if contrast >= 0.4 and brightness >= 0.4 then
			local success, bc = pcall(function()
				return BrickColor.new(name)
			end)
			if success then table.insert(validColors, bc) end
		end
	end
	return validColors
end

-- Creates a RaycastParams object to ignore specific objects
function Util:CreateRaycastParams(ignoreList)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = ignoreList
	return params
end


-- MODULE: TweenHandler
-- Handles visual effects on parts
--========================================
local TweenHandler = {}
TweenHandler.__index = TweenHandler

function TweenHandler.new()
	local self = setmetatable({}, TweenHandler)
	self.ValidColors = Util:GetValidColors(Colors)
	return self
end

-- Applies tweens, lights, particles and triggers model attachment
function TweenHandler:ApplyEffects(parts, newSize, callback)
	local completed = 0
	local colorMap = {}

	for _, part in pairs(parts) do
		if part:IsA("MeshPart") then
			local chosenColor = self.ValidColors[math.random(1, #self.ValidColors)]
			part.BrickColor = chosenColor
			colorMap[part] = chosenColor

			-- Particle emitter to simulate aura effect
			local aura = Instance.new("ParticleEmitter")
			aura.Texture = "rbxassetid://284205403"
			aura.Color = ColorSequence.new(chosenColor.Color)
			aura.Size = NumberSequence.new(3)
			aura.Transparency = NumberSequence.new(0.8, 0.9)
			aura.Rate = 5
			aura.Lifetime = NumberRange.new(1, 2)
			aura.LightEmission = 1
			aura.Parent = part

			-- Light for visual glow
			local light = Instance.new("PointLight")
			light.Color = chosenColor.Color
			light.Brightness = 5
			light.Range = 10
			light.Parent = part

			-- Tween the part to grow to the given size
			local tween = TweenService:Create(part, TweenInfo.new(2, Enum.EasingStyle.Quad), {
				Size = newSize
			})
			tween:Play()

			-- Once the tween completes, attach the decorative model
			tween.Completed:Connect(function()
				self:AttachModelToPart(part, chosenColor)
				completed += 1
				if completed == #parts and callback then
					callback()
				end
			end)
		end
	end
end

-- Attaches the shuriken model to each part
function TweenHandler:AttachModelToPart(part, color)
	if part.Name == "geral" then return end
	if part:FindFirstChild(SHMODEL.Name) then return end

	local clone = SHMODEL:Clone()
	clone:SetPrimaryPartCFrame(part.CFrame)
	clone.Parent = part

	-- Weld to stick model to part
	local weld = Instance.new("WeldConstraint", clone.PrimaryPart)
	weld.Part0 = clone.PrimaryPart
	weld.Part1 = part

	-- Update shuriken color to match part
	clone.Shuriken.BrickColor = color

	-- Unanchor to allow movement
	part.Anchored = false
	clone.PrimaryPart.Anchored = false

	-- Play animation
	local anim = clone:FindFirstChildOfClass("Animation")
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if anim and hum then
		local track = hum:LoadAnimation(anim)
		track:Play()
	end
end


-- MODULE: ProjectileLauncher
-- Launches parts using linear interpolation and raycasting
--========================================
local ProjectileLauncher = {}

function ProjectileLauncher:Launch(parts, destination, character)
	local ignoreList = {character}
	for _, part in ipairs(parts) do
		table.insert(ignoreList, part)
	end

	local rayParams = Util:CreateRaycastParams(ignoreList)
	local speed = 100

	for _, part in ipairs(parts) do
		part.Anchored = false
		local startPos = part.Position
		local direction = (destination - startPos).Unit
		local distance = (destination - startPos).Magnitude
		local duration = distance / speed
		local elapsed = 0

		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			if not part or not part.Parent then conn:Disconnect() return end
			elapsed += dt

			local alpha = math.clamp(elapsed / duration, 0, 1)
			part.CFrame = CFrame.new(startPos:Lerp(destination, alpha))

			local result = Workspace:Raycast(part.Position, direction * speed * dt, rayParams)
			if result then
				local hit = result.Instance
				local model = hit:FindFirstAncestorOfClass("Model")
				if model then
					local hum = model:FindFirstChildOfClass("Humanoid")
					if hum then
						hum:TakeDamage(20)
					end
				end

				ProjectileLauncher:CreateExplosion(result.Position, part.Color)
				part.Anchored = true
				conn:Disconnect()
			elseif alpha >= 1 then
				part.Anchored = true
				conn:Disconnect()
			end
		end)
	end
end

-- Creates visual explosion on collision
function ProjectileLauncher:CreateExplosion(pos, color)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(100, 100, 100)
	p.Position = pos
	p.Anchored = true
	p.CanCollide = false
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = 0.2
	p.Parent = Workspace

	local tween = TweenService:Create(p, TweenInfo.new(0.5), {
		Transparency = 1,
		Size = Vector3.new(80, 80, 80)
	})
	tween:Play()
	tween.Completed:Connect(function()
		p:Destroy()
	end)
end


-- MAIN EVENT LISTENER
-- Handles player requests to activate the skill
--========================================

RemoteEvent.OnServerEvent:Connect(function(player)
    -- Check if player is on cooldown
    if CooldownService:IsOnCooldown(player, Cooldown) then
        -- Prevent skill activation during cooldown
        return
    end

    -- Set the cooldown timer for the player
    CooldownService:SetCooldown(player)

    -- Show cooldown UI once per cooldown
    if not clwStatus[player.UserId] then
        clwStatus[player.UserId] = true
        CLW.ShowCooldownUI(player, PowerID, Cooldown)
    end

    -- Get player character and humanoid root part for positioning
    local character = player.Character
    if not character then return end

    local humanoidRoot = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRoot then return end

    -- Fetch mouse position from client to determine target
    local mousePos = GetMouseFunction:InvokeClient(player)
    if not mousePos then return end

    -- Prepare projectile parts from model template
    local parts = {}
    for _, child in pairs(ModelTemplate:GetChildren()) do
        if child:IsA("MeshPart") then
            local clonePart = child:Clone()
            clonePart.CFrame = humanoidRoot.CFrame * CFrame.new(0, AlturaExtra, 0)
            clonePart.Anchored = true
            clonePart.Parent = Workspace
            table.insert(parts, clonePart)
        end
    end

    -- Initialize TweenHandler and apply visual effects
    local tweenHandler = TweenHandler.new()
    tweenHandler:ApplyEffects(parts, Vector3.new(3, 3, 3), function()
        -- Launch projectiles towards the mouse position after effects complete
        ProjectileLauncher:Launch(parts, mousePos, character)
    end)

    -- Clear cooldown UI after the cooldown duration
    delay(Cooldown, function()
        clwStatus[player.UserId] = nil
    end)
end)

