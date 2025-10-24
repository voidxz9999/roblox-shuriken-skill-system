--[[
    Roblox Advanced Skill System 
    ----------------------------------------------------
    Demonstrates:
    - Advanced CFrame math and physics
    - TweenService animations and visual FX
    - Remote communication between client and server
    - Cooldown handling and UI communication
    - Object-Oriented Programming with metatables
    - Efficient and readable Luau scripting practices

    This script is designed to meet the upper intermediate-to-advanced
    level of the Luau Scripter Evaluation test.

    Author: Void_FutureDevs
]]

--=====================================================
--// ROBLOX SERVICES
--=====================================================
-- Services provide access to Roblox engine APIs.
-- These are core components required for gameplay logic.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

--=====================================================
--// SHARED RESOURCES (CLIENT <-> SERVER COMMUNICATION)
--=====================================================
-- RemoteEvent and RemoteFunction are stored in ReplicatedStorage
-- to allow both client and server scripts to access them.
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent") -- Used to trigger skill activation from client
local GetMouseFunction = ReplicatedStorage:WaitForChild("GetMousePosition") -- Client function to return 3D mouse hit position

-- These are asset references required for visuals and effects
local ModelTemplate = ReplicatedStorage:WaitForChild("Model") -- Base model that contains projectile MeshParts
local SHMODEL = ReplicatedStorage:WaitForChild("SHURIQUENDEBIJU") -- Decorative object attached to each projectile
local Colors = require(ReplicatedStorage:WaitForChild("Colors")) -- Color palette table (custom BrickColors)

-- External UI/visual module assumed to exist in ServerScriptService
local CLW = require(game.ServerScriptService:WaitForChild("CLW"))

--=====================================================
--// CONSTANT CONFIGURATION
--=====================================================
local PowerID = "25"           -- Used for UI cooldown tracking
local Cooldown = 5             -- Time in seconds before the player can use the skill again
local LaunchHeight = 10        -- Vertical offset when spawning projectiles
local LaunchSpeed = 120        -- Linear speed of the projectile

-- Cooldown and UI tracking tables
local serverCooldowns = {}     -- Stores timestamp of each player's last use
local clwStatus = {}           -- Tracks whether cooldown UI is active for a player

--=====================================================
--// COOLDOWN SERVICE (Handles skill reuse timing)
--=====================================================
local CooldownService = {}

-- Checks if a player is still under cooldown
function CooldownService:IsOnCooldown(player)
	local last = serverCooldowns[player.UserId]
	return last and tick() - last < Cooldown
end

-- Registers the current use of the skill for cooldown tracking
function CooldownService:Set(player)
	serverCooldowns[player.UserId] = tick()
end

-- Clears a player’s cooldown data (useful for resets or debugging)
function CooldownService:Clear(player)
	serverCooldowns[player.UserId] = nil
end

--=====================================================
--// UTILITY MODULE (Helper functions)
--=====================================================
local Util = {}

-- Filters valid BrickColors from a color module, based on brightness and contrast
-- Ensures that chosen colors are visually distinguishable and suitable for FX
function Util:GetValidColors(tbl)
	local valid = {}
	for name, c in pairs(tbl) do
		local contrast = math.max(c.R, c.G, c.B) - math.min(c.R, c.G, c.B)
		local brightness = (c.R + c.G + c.B) / 3
		if contrast > 0.4 and brightness > 0.4 then
			local ok, bc = pcall(function() return BrickColor.new(name) end)
			if ok then table.insert(valid, bc) end
		end
	end
	return valid
end

-- Creates a reusable RaycastParams object for raycasting operations
-- This function ensures certain parts are ignored during collision detection
function Util:CreateRayParams(ignore)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Blacklist
	p.FilterDescendantsInstances = ignore
	return p
end

--=====================================================
--// PROJECTILE CLASS (OOP with METATABLES)
--=====================================================
-- Each projectile instance is represented as an object with properties and methods.
-- Demonstrates use of Lua metatables for creating reusable entities.
local Projectile = {}
Projectile.__index = Projectile

-- Constructor for a projectile
function Projectile.new(part, targetPos, color)
	local self = setmetatable({}, Projectile)
	self.Part = part
	self.Target = targetPos
	self.Color = color
	self.Speed = LaunchSpeed
	self.LifeTime = 5                 -- Time in seconds before projectile auto-destroys
	self.RayParams = Util:CreateRayParams({part})
	self.StartCFrame = part.CFrame
	self.StartTime = tick()
	self:InitPhysics()                -- Adds physical behavior to projectile
	return self
end

-- Initializes physics using Roblox body movers
function Projectile:InitPhysics()
	-- BodyVelocity applies linear motion towards target
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.Velocity = (self.Target - self.Part.Position).Unit * self.Speed
	bv.Parent = self.Part
	self.BodyVelocity = bv

	-- BodyAngularVelocity adds constant spinning motion for realism
	local av = Instance.new("BodyAngularVelocity")
	av.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	av.AngularVelocity = Vector3.new(math.random(), math.random(), math.random()).Unit * 10
	av.Parent = self.Part
	self.BodyAngularVelocity = av
end

-- Called every frame (via RunService) to update position and detect collisions
function Projectile:Update(dt)
	if not self.Part or not self.Part.Parent then return false end

	-- Perform raycast in direction of travel to detect collision
	local result = Workspace:Raycast(self.Part.Position, self.BodyVelocity.Velocity * dt, self.RayParams)
	if result then
		self:Explode(result.Position)
		return false
	end

	-- Automatically remove projectile if lifetime expires
	if tick() - self.StartTime > self.LifeTime then
		self:Explode(self.Part.Position)
		return false
	end

	return true
end

-- Creates a visual explosion effect upon collision or timeout
function Projectile:Explode(pos)
	local explosion = Instance.new("Part")
	explosion.Shape = Enum.PartType.Ball
	explosion.Color = self.Color.Color
	explosion.Material = Enum.Material.Neon
	explosion.Size = Vector3.new(20, 20, 20)
	explosion.Position = pos
	explosion.Anchored = true
	explosion.CanCollide = false
	explosion.Parent = Workspace

	-- Tween visual size and transparency for smooth explosion animation
	local tween = TweenService:Create(explosion, TweenInfo.new(0.5), {
		Size = Vector3.new(60, 60, 60),
		Transparency = 1
	})
	tween:Play()
	tween.Completed:Connect(function() explosion:Destroy() end)

	-- Destroy the projectile part itself
	if self.Part then self.Part:Destroy() end
end

--=====================================================
--// VISUAL FX HANDLER (Tweens, Lighting, Particles)
--=====================================================
local TweenHandler = {}
TweenHandler.__index = TweenHandler

-- Constructor that precomputes valid BrickColors for later use
function TweenHandler.new()
	local self = setmetatable({}, TweenHandler)
	self.ValidColors = Util:GetValidColors(Colors)
	return self
end

-- Applies visual transformations and transitions to each projectile part
function TweenHandler:ApplyEffects(parts, newSize, callback)
	local done = 0
	for _, part in ipairs(parts) do
		-- Randomly select color from prevalidated palette
		local color = self.ValidColors[math.random(1, #self.ValidColors)]
		part.BrickColor = color

		-- Add a glowing PointLight for a neon effect
		local light = Instance.new("PointLight")
		light.Color = color.Color
		light.Range = 10
		light.Brightness = 4
		light.Parent = part

		-- Add a particle emitter to simulate aura energy
		local aura = Instance.new("ParticleEmitter")
		aura.Texture = "rbxassetid://284205403"
		aura.Color = ColorSequence.new(color.Color)
		aura.Rate = 10
		aura.Size = NumberSequence.new(3)
		aura.Lifetime = NumberRange.new(1, 2)
		aura.Parent = part

		-- Tween to smoothly enlarge the projectile before launch
		local tween = TweenService:Create(part, TweenInfo.new(2, Enum.EasingStyle.Back), {Size = newSize})
		tween:Play()
		tween.Completed:Connect(function()
			-- Attach decorative model when tween ends
			self:AttachModel(part, color)
			done += 1
			if done == #parts then
				callback() -- Launch once all effects are done
			end
		end)
	end
end

-- Attaches decorative shuriken model using a WeldConstraint
function TweenHandler:AttachModel(part, color)
	local clone = SHMODEL:Clone()
	clone:SetPrimaryPartCFrame(part.CFrame)
	clone.Parent = part

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = clone.PrimaryPart
	weld.Part1 = part
	weld.Parent = clone.PrimaryPart

	clone.PrimaryPart.BrickColor = color
	part.Anchored = false
end

--=====================================================
--// PROJECTILE MANAGER (Handles all active projectiles)
--=====================================================
local ProjectileManager = {}
ProjectileManager.Active = {} -- Holds currently active projectiles

-- Launch all parts toward destination as projectiles
function ProjectileManager:Launch(parts, destination)
	for _, part in ipairs(parts) do
		local color = part.BrickColor
		local proj = Projectile.new(part, destination, color)
		table.insert(self.Active, proj)
	end
end

-- Continuously updates projectiles every frame
RunService.Heartbeat:Connect(function(dt)
	for i = #ProjectileManager.Active, 1, -1 do
		local proj = ProjectileManager.Active[i]
		if not proj:Update(dt) then
			table.remove(ProjectileManager.Active, i)
		end
	end
end)

--=====================================================
--// MAIN EVENT HANDLER (Skill Activation)
--=====================================================
-- This section listens for RemoteEvent triggers from the client.
-- It performs cooldown checks, creates projectiles, applies effects,
-- and launches them using the previously defined classes.
RemoteEvent.OnServerEvent:Connect(function(player)
	-- Check if player is currently on cooldown
	if CooldownService:IsOnCooldown(player) then return end

	-- Register new cooldown
	CooldownService:Set(player)

	-- Trigger cooldown UI for player (only once)
	if not clwStatus[player.UserId] then
		clwStatus[player.UserId] = true
		CLW.ShowCooldownUI(player, PowerID, Cooldown)
	end

	-- Validate character and root part
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Request mouse target position from client
	local target = GetMouseFunction:InvokeClient(player)
	if not target then return end

	-- Clone projectile MeshParts from model template
	local parts = {}
	for _, child in ipairs(ModelTemplate:GetChildren()) do
		if child:IsA("MeshPart") then
			local clone = child:Clone()
			clone.CFrame = root.CFrame * CFrame.new(0, LaunchHeight, 0)
			clone.Anchored = true
			clone.Parent = Workspace
			table.insert(parts, clone)
		end
	end

	-- Create visual handler and prepare projectiles
	local tweenHandler = TweenHandler.new()
	tweenHandler:ApplyEffects(parts, Vector3.new(3, 3, 3), function()
		ProjectileManager:Launch(parts, target)
	end)

	-- Reset cooldown UI status after time passes
	delay(Cooldown, function()
		clwStatus[player.UserId] = nil
	end)
end)
