-- Service Dependencies
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- External Library
local Knit = require(ReplicatedStorage.Packages:WaitForChild("Knit"))
local Trove = require(ReplicatedStorage.Packages:WaitForChild("Trove"))

-- Service
local MovesetService = Knit.GetService("MovesetService")
local TakeDamage = require(ServerStorage.Services:WaitForChild("HitboxService").TakeDamage)

local DevilSword = {}
DevilSword.__index = DevilSword

local INPUT_RATE_LIMIT = 0.1 
local MAX_COMBO_WINDOW = 0.8 
local VFX_CLEANUP_DELAY = 5

function DevilSword.new()
	local self = setmetatable({}, DevilSword)
	self.PlayerData = {}
	return self
end

function DevilSword:cleanupPlayer(playerName)
	if not self.PlayerData[playerName] then return end

	local data = self.PlayerData[playerName]

	if data.resetTimer then
		task.cancel(data.resetTimer)
	end
	if data.cooldownTimer then
		task.cancel(data.cooldownTimer)
	end
	if data.animationTimer then
		task.cancel(data.animationTimer)
	end

	if data.trove then
		data.trove:Clean()
		data.trove:Destroy()
	end

	self.PlayerData[playerName] = nil

	print(`[DevilSword] Cleaned up data for player: {playerName}`)
end

function DevilSword:initializePlayer(playerName)
	if self.PlayerData[playerName] then return end

	self.PlayerData[playerName] = {
		combo = 0,
		isOnCooldown = false,
		isAnimating = false,
		resetTimer = nil,
		cooldownTimer = nil,
		animationTimer = nil,
		trove = Trove.new(),
		lastInputTime = 0, 
		hitTargets = {},
	}

	print(`[DevilSword] Initialized data for player: {playerName}`)
end

function DevilSword:validateInput(playerName)
	local playerData = self.PlayerData[playerName]
	if not playerData then return false end

	local currentTime = tick()

	if currentTime - playerData.lastInputTime < INPUT_RATE_LIMIT then
		return false
	end

	if playerData.isOnCooldown or playerData.isAnimating then
		return false
	end

	playerData.lastInputTime = currentTime
	return true
end

function DevilSword:createWeaponVFX(rootpart, playerData)
	local VFXRoot = ReplicatedStorage.Assets.VFX.DevilSword.VFXRoot:Clone()
	VFXRoot.Parent = workspace.Effects

	VFXRoot.CFrame = rootpart.CFrame
	VFXRoot.Anchored = true
	VFXRoot.CanCollide = false

	Knit.GetService("WeldService"):WeldParts(VFXRoot, rootpart)
	playerData.trove:Add(VFXRoot)

	for _, descendant in pairs(VFXRoot:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(2)
			task.wait()
		end
	end

	return VFXRoot
end

function DevilSword:spawnSwordModel(VFXRoot, playerData)
	local DevilSword = ReplicatedStorage.Assets.Swords.DevilSword:Clone()
	DevilSword.Parent = workspace.Effects

	Knit.GetService("WeldService"):Weld(DevilSword, DevilSword.Handler)
	DevilSword.Handler.Anchored = true

	local initialCFrame = VFXRoot.CFrame * CFrame.new(-1.5, 0, 2) * CFrame.Angles(math.rad(90), math.rad(180), 0)
	DevilSword.Handler.CFrame = initialCFrame

	playerData.trove:Add(DevilSword)

	for _, part in pairs(DevilSword:GetChildren()) do
		if part:IsA("BasePart") then
			local originalColor = part.Color
			part.Transparency = 1
			part.Color = Color3.new(1, 1, 1) 

			local appearTween = TweenService:Create(
				part,
				TweenInfo.new(0.25, Enum.EasingStyle.Circular),
				{Transparency = 0, Color = originalColor}
			)
			appearTween:Play()
			playerData.trove:Add(appearTween)
		end
	end

	local finalCFrame = VFXRoot.CFrame * CFrame.new(-1.5, 0, 0) * CFrame.Angles(math.rad(90), math.rad(180), 0)
	local moveTween = TweenService:Create(
		DevilSword.Handler,
		TweenInfo.new(1, Enum.EasingStyle.Circular, Enum.EasingDirection.InOut),
		{CFrame = finalCFrame}
	)
	moveTween:Play()
	playerData.trove:Add(moveTween)

	return DevilSword
end

function DevilSword:attachSwordToCharacter(character, playerData)
	local rightArm = character:FindFirstChild("Right Arm")
	if not rightArm then return end

	local DevilSwordArm = ReplicatedStorage.Assets.VFX.DevilSword.RightArm:Clone()
	DevilSwordArm.Parent = character
	playerData.trove:Add(DevilSwordArm)

	local weld = Instance.new("Weld")
	weld.Part0 = DevilSwordArm
	weld.Part1 = rightArm
	weld.Parent = DevilSwordArm
	playerData.trove:Add(weld)

	for _, part in pairs(DevilSwordArm.DevilSword:GetChildren()) do
		if part:IsA("BasePart") then
			part.Transparency = 1
			local appearTween = TweenService:Create(
				part,
				TweenInfo.new(0.25, Enum.EasingStyle.Circular),
				{Transparency = 0}
			)
			appearTween:Play()
			playerData.trove:Add(appearTween)
		end
	end
end

function DevilSword:performHitboxCheck(character, player, damage, animations, hitKey, playerData)
	playerData.hitTargets = {}

	local hitTargets = Knit.GetService("HitboxService"):Start({
		Character = character,
		Length = 5, 
		HitboxType = "Magnitude",
		CheckInFront = true 
	})

	for _, target in pairs(hitTargets) do
		if not table.find(playerData.hitTargets, target) then
			table.insert(playerData.hitTargets, target)

			local damageResult = TakeDamage({Player = player, Damage = damage}, target)
			if damageResult then
				if animations[hitKey] then
					MovesetService:PlayAnimation(target, animations[hitKey])
				end

				print(`[DevilSword] {player.Name} hit {target.Name} for {damage} damage`)
			end
		end
	end
end

function DevilSword:fadeOutEquippedSword(character, playerData)
	local rightArm = character:FindFirstChild("RightArm")
	if not rightArm then return end

	local devilSword = rightArm:FindFirstChild("DevilSword")
	if not devilSword then return end

	for _, part in pairs(devilSword:GetChildren()) do
		if part:IsA("BasePart") then
			local fadeTween = TweenService:Create(
				part,
				TweenInfo.new(0.25, Enum.EasingStyle.Circular),
				{Transparency = 1}
			)
			fadeTween:Play()
			playerData.trove:Add(fadeTween)
		end
	end

	playerData.trove:Add(task.delay(0.3, function()
		if rightArm and rightArm.Parent then
			playerData.trove:Add(rightArm)
		end
	end))
end

function DevilSword:execute(data)
	if not data or type(data) ~= "table" then
		return
	end

	local player = data.Player
	local weapon = data.Weapon  
	local weaponType = data.WeaponType

	if not player or not weapon or not weaponType then
		return
	end

	local playerName = player.Name
	local character = player.Character
	local rootpart = character and character:FindFirstChild("HumanoidRootPart")

	if not character or not rootpart or not player.Parent then
		self:cleanupPlayer(playerName)
		return
	end

	local success, configs = pcall(function()
		return require(ReplicatedStorage.Modules.Configs[weaponType])
	end)

	if not success then
		return
	end

	local weaponConfigs = configs[weapon]
	if not weaponConfigs or not weaponConfigs[script.Name] then
		warn(`[DevilSword] Configuration not found for weapon: {weapon}`)
		return
	end

	local comboConfigs = weaponConfigs[script.Name]
	local animations = comboConfigs.Animation
	local maxHits = comboConfigs.MaxHit or 4
	local comboResetTime = comboConfigs.ComboResetTime or 2
	local finishComboCooldown = comboConfigs.FinishComboCooldown or 1
	local animationDelay = comboConfigs.AnimationDelay or 0.5
	local baseDamage = comboConfigs.BaseDamage or 5

	self:initializePlayer(playerName)
	local playerData = self.PlayerData[playerName]

	if not self:validateInput(playerName) then
		return
	end

	if playerData.resetTimer then
		task.cancel(playerData.resetTimer)
		playerData.resetTimer = nil
	end

	if not character:GetAttribute("Equiped") then
		print(`[DevilSword] {playerName} equipping Devil Sword`)

		playerData.isAnimating = true
		character:SetAttribute("Equiped", true)

		MovesetService:PlayAnimation(player, animations["PullSword"])

		local VFXRoot = self:createWeaponVFX(rootpart, playerData)

		Knit.GetService("SoundService"):Play({
			SoundName = "DevilSwordSpawn",
			Parent = rootpart
		})

		playerData.animationTimer = task.delay(2.5, function()
			if self.PlayerData[playerName] then
				self.PlayerData[playerName].isAnimating = false
				self.PlayerData[playerName].animationTimer = nil
			end
		end)

		playerData.trove:Add(task.delay(0.2, function()
			if not character:GetAttribute("Equiped") then return end

			Knit.GetService("StunService"):Add({
				Target = character,
				WalkSpeed = 0,
				JumpPower = 0,
				Duration = 1,
				AutoRotate = false,
			})

			task.wait(0.1)

			local DevilSword = self:spawnSwordModel(VFXRoot, playerData)

			playerData.trove:Add(task.delay(1, function()
				if not character:GetAttribute("Equiped") then return end

				for _, part in pairs(DevilSword:GetChildren()) do
					if part:IsA("BasePart") then
						local fadeTween = TweenService:Create(
							part,
							TweenInfo.new(0.25, Enum.EasingStyle.Circular),
							{Transparency = 1, Color = Color3.new(1, 1, 1)}
						)
						fadeTween:Play()
						playerData.trove:Add(fadeTween)
					end
				end

				playerData.trove:Add(task.delay(0.25, function()
					if character:GetAttribute("Equiped") then
						self:attachSwordToCharacter(character, playerData)
					end
				end))
			end))
		end))

	else
		print(`[DevilSword] {playerName} performing combo attack {playerData.combo + 1}`)

		playerData.isAnimating = true
		playerData.combo = (playerData.combo % maxHits) + 1

		local animationKey = "Hit" .. playerData.combo
		local hitAnimationKey = "TargetHit" .. playerData.combo

		if animations[animationKey] then
			MovesetService:PlayAnimation(player, animations[animationKey])
		end

		Knit.GetService("SoundService"):Play({
			SoundName = "Swing",
			Parent = rootpart
		})

		playerData.animationTimer = task.delay(animationDelay, function()
			if self.PlayerData[playerName] then
				self.PlayerData[playerName].isAnimating = false
				self.PlayerData[playerName].animationTimer = nil
			end
		end)

		playerData.resetTimer = task.delay(comboResetTime, function()
			if not self.PlayerData[playerName] then return end

			print(`[DevilSword] {playerName} combo timed out, unequipping`)
			character:SetAttribute("Equiped", nil)

			playerData.trove:Add(task.delay(1, function()
				self:fadeOutEquippedSword(character, playerData)
			end))

			playerData.trove:Clean()
			playerData.combo = 0
			playerData.resetTimer = nil
		end)

		Knit.GetService("StunService"):Add({
			Target = character,
			WalkSpeed = 6,
			AutoRotate = true,
			JumpPower = 0,
			Duration = 2
		})

		Knit.GetService("CombatService"):Add({
			Target = character,
			Duration = 0.15,
			Value = "Parry",
		})

		playerData.trove:Add(task.delay(0.15, function()
			local scaledDamage = baseDamage + (playerData.combo - 1)

			self:performHitboxCheck(
				character, 
				player, 
				scaledDamage, 
				animations, 
				hitAnimationKey, 
				playerData
			)
		end))

		if playerData.combo >= maxHits then
			print(`[DevilSword] {playerName} completed full combo, entering cooldown`)

			playerData.isOnCooldown = true
			playerData.combo = 0
			character:SetAttribute("Equiped", nil)

			playerData.trove:Add(task.delay(1, function()
				self:fadeOutEquippedSword(character, playerData)
				playerData.trove:Clean()
			end))

			playerData.cooldownTimer = task.delay(finishComboCooldown, function()
				if self.PlayerData[playerName] then
					playerData.trove:Clean()
					self.PlayerData[playerName].isOnCooldown = false
					self.PlayerData[playerName].cooldownTimer = nil
					print(`[DevilSword] {playerName} cooldown expired`)
				end
			end)
		end
	end
end

return DevilSword
