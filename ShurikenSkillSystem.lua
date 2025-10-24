--[[
    Roblox Advanced Skill System (Single Script Version)
    Demonstrates use of:
    - CFrame math and physics
    - Tweens and particle effects
    - Remote communication and cooldown management
    - Object-Oriented Programming (metatables)
    - Optimized, readable Luau scripting for evaluation

    Author: Void_FutureDevs
]]

--// ROBLOX SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

--// REMOTES AND SHARED ASSETS
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
local GetMouseFunction = ReplicatedStorage:WaitForChild("GetMousePosition")
local ModelTemplate = ReplicatedStorage:WaitForChild("Model")
local SHMODEL = ReplicatedStorage:WaitForChild("SHURIQUENDEBIJU")
local Colors = require(ReplicatedStorage:WaitForChild("Colors"))
local CLW = require(game.ServerScriptService:WaitForChild("CLW"))

--// CONFIGURATION
local PowerID = "25"
local Cooldown = 5
local LaunchHeight = 10
local LaunchSpeed = 120

local serverCooldowns = {}
local clwStatus = {}

--=====================================================
--// COOLDOWN SERVICE
--=====================================================
local CooldownService = {}

function CooldownService:IsOnCooldown(player)
	local last = serverCooldowns[player.UserId]
	return last and tick() - last < Cooldown
end

function CooldownService:Set(player)
	serverCooldowns[player.UserId] = tick()
end

function CooldownService:Clear(player)
	serverCooldowns[player.UserId] = nil
end

--=====================================================
--// UTILITIES
--=====================================================
local Util = {}

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

function Util:CreateRayParams(ignore)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Blacklist
	p.FilterDescendantsInstances = ignore
	return p
end

--=====================================================
--// PROJECTILE CLASS (OOP with metatable)
--=====================================================
local Projectile = {}
Projectile.__index = Projectile

function Projectile.new(part, targetPos, color)
	local self = setmetatable({}, Projectile)
	self.Part = part
	self.Target = targetPos
	self.Color = color
	self.Speed = LaunchSpeed
	self.LifeTime = 5
	self.RayParams = Util:CreateRayParams({part})
	self.StartCFrame = part.CFrame
	self.StartTime = tick()
	self:InitPhysics()
	return self
end

function Projectile:InitPhysics()
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.Velocity = (self.Target - self.Part.Position).Unit * self.Speed
	bv.Parent = self.Part
	self.BodyVelocity = bv

	-- add a rotating angular velocity to demonstrate CFrame math
	local av = Instance.new("BodyAngularVelocity")
	av.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	av.AngularVelocity = Vector3.new(math.random(), math.random(), math.random()).Unit * 10
	av.Parent = self.Part
	self.BodyAngularVelocity = av
end

function Projectile:Update(dt)
	if not self.Part or not self.Part.Parent then return false end

	-- simple physics flight
	local result = Workspace:Raycast(self.Part.Position, self.BodyVelocity.Velocity * dt, self.RayParams)
	if result then
		self:Explode(result.Position)
		return false
	end

	-- lifetime expiration
	if tick() - self.StartTime > self.LifeTime then
		self:Explode(self.Part.Position)
		return false
	end
	return true
end

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

	local tween = TweenService:Create(explosion, TweenInfo.new(0.5), {
		Size = Vector3.new(60, 60, 60),
		Transparency = 1
	})
	tween:Play()
	tween.Completed:Connect(function() explosion:Destroy() end)

	if self.Part then self.Part:Destroy() end
end

--=====================================================
--// VISUAL TWEENS + EFFECTS
--=====================================================
local TweenHandler = {}
TweenHandler.__index = TweenHandler

function TweenHandler.new()
	local self = setmetatable({}, TweenHandler)
	self.ValidColors = Util:GetValidColors(Colors)
	return self
end

function TweenHandler:ApplyEffects(parts, newSize, callback)
	local done = 0
	for _, part in ipairs(parts) do
		local color = self.ValidColors[math.random(1, #self.ValidColors)]
		part.BrickColor = color

		local light = Instance.new("PointLight")
		light.Color = color.Color
		light.Range = 10
		light.Brightness = 4
		light.Parent = part

		local aura = Instance.new("ParticleEmitter")
		aura.Texture = "rbxassetid://284205403"
		aura.Color = ColorSequence.new(color.Color)
		aura.Rate = 10
		aura.Size = NumberSequence.new(3)
		aura.Lifetime = NumberRange.new(1, 2)
		aura.Parent = part

		local tween = TweenService:Create(part, TweenInfo.new(2, Enum.EasingStyle.Back), {Size = newSize})
		tween:Play()
		tween.Completed:Connect(function()
			self:AttachModel(part, color)
			done += 1
			if done == #parts then
				callback()
			end
		end)
	end
end

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
--// PROJECTILE MANAGER
--=====================================================
local ProjectileManager = {}
ProjectileManager.Active = {}

function ProjectileManager:Launch(parts, destination)
	for _, part in ipairs(parts) do
		local color = part.BrickColor
		local proj = Projectile.new(part, destination, color)
		table.insert(self.Active, proj)
	end
end

-- Continuous update of all active projectiles
RunService.Heartbeat:Connect(function(dt)
	for i = #ProjectileManager.Active, 1, -1 do
		local proj = ProjectileManager.Active[i]
		if not proj:Update(dt) then
			table.remove(ProjectileManager.Active, i)
		end
	end
end)

--=====================================================
--// MAIN EVENT HANDLER
--=====================================================
RemoteEvent.OnServerEvent:Connect(function(player)
	if CooldownService:IsOnCooldown(player) then return end

	CooldownService:Set(player)

	if not clwStatus[player.UserId] then
		clwStatus[player.UserId] = true
		CLW.ShowCooldownUI(player, PowerID, Cooldown)
	end

	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local target = GetMouseFunction:InvokeClient(player)
	if not target then return end

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

	local tweenHandler = TweenHandler.new()
	tweenHandler:ApplyEffects(parts, Vector3.new(3, 3, 3), function()
		ProjectileManager:Launch(parts, target)
	end)

	delay(Cooldown, function()
		clwStatus[player.UserId] = nil
	end)
end)
