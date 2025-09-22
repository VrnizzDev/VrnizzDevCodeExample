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

-- Constants for configuration
local INPUT_RATE_LIMIT = 0.1 
local MAX_COMBO_WINDOW = 0.8 
local VFX_CLEANUP_DELAY = 5

-- Constructor: Creates a new DevilSword instance
function DevilSword.new()
	local self = setmetatable({}, DevilSword)
	self.PlayerData = {}
	return self
end

-- Cleanup: Removes all player data and cancels active tasks
function DevilSword:cleanupPlayer(playerName)
	local data = self.PlayerData[playerName]
	if not data then return end

	self:cancelPlayerTimers(data)
	self:cleanupPlayerTrove(data)
	
	self.PlayerData[playerName] = nil
	print(`[DevilSword] Cleaned up data for player: {playerName}`)
end

-- Helper: Cancels all active timers for a player
function DevilSword:cancelPlayerTimers(data)
	local timers = {data.resetTimer, data.cooldownTimer, data.animationTimer}
	
	for _, timer in pairs(timers) do
		if timer then
			task.cancel(timer)
		end
	end
end

-- Helper: Cleans up and destroys the player's trove
function DevilSword:cleanupPlayerTrove(data)
	if not data.trove then return end
	
	data.trove:Clean()
	data.trove:Destroy()
end

-- Initialization: Sets up initial data structure for a player
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

-- Validation: Checks if player input is valid and not rate-limited
function DevilSword:validateInput(playerName)
	local playerData = self.PlayerData[playerName]
	if not playerData then return false end

	if not self:isInputRateLimitPassed(playerData) then return false end
	if self:isPlayerBusy(playerData) then return false end

	playerData.lastInputTime = tick()
	return true
end

-- Helper: Checks if enough time has passed since last input
function DevilSword:isInputRateLimitPassed(playerData)
	local currentTime = tick()
	return currentTime - playerData.lastInputTime >= INPUT_RATE_LIMIT
end

-- Helper: Checks if player is currently in cooldown or animating
function DevilSword:isPlayerBusy(playerData)
	return playerData.isOnCooldown or playerData.isAnimating
end

-- VFX: Creates and configures the weapon visual effects
function DevilSword:createWeaponVFX(rootpart, playerData)
	local VFXRoot = self:cloneAndSetupVFXRoot(rootpart)
	self:weldVFXToCharacter(VFXRoot, rootpart, playerData)
	self:emitParticleEffects(VFXRoot)
	
	return VFXRoot
end

-- Helper: Clones and positions the VFX root
function DevilSword:cloneAndSetupVFXRoot(rootpart)
	local VFXRoot = ReplicatedStorage.Assets.VFX.DevilSword.VFXRoot:Clone()
	VFXRoot.Parent = workspace.Effects
	VFXRoot.CFrame = rootpart.CFrame
	VFXRoot.Anchored = true
	VFXRoot.CanCollide = false
	
	return VFXRoot
end

-- Helper: Welds VFX to character and adds to cleanup trove
function DevilSword:weldVFXToCharacter(VFXRoot, rootpart, playerData)
	Knit.GetService("WeldService"):WeldParts(VFXRoot, rootpart)
	playerData.trove:Add(VFXRoot)
end

-- Helper: Activates particle emitters in the VFX
function DevilSword:emitParticleEffects(VFXRoot)
	for _, descendant in pairs(VFXRoot:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant:Emit(2)
			task.wait()
		end
	end
end

-- Animation: Spawns and animates the sword model during equip sequence
function DevilSword:spawnSwordModel(VFXRoot, playerData)
	local DevilSword = self:createSwordModel(VFXRoot, playerData)
	self:animateSwordAppearance(DevilSword, playerData)
	self:animateSwordMovement(DevilSword, VFXRoot, playerData)
	
	return DevilSword
end

-- Helper: Creates and positions the sword model
function DevilSword:createSwordModel(VFXRoot, playerData)
	local DevilSword = ReplicatedStorage.Assets.Swords.DevilSword:Clone()
	DevilSword.Parent = workspace.Effects

	Knit.GetService("WeldService"):Weld(DevilSword, DevilSword.Handler)
	DevilSword.Handler.Anchored = true

	local initialCFrame = VFXRoot.CFrame * CFrame.new(-1.5, 0, 2) * CFrame.Angles(math.rad(90), math.rad(180), 0)
	DevilSword.Handler.CFrame = initialCFrame

	playerData.trove:Add(DevilSword)
	return DevilSword
end

-- Helper: Animates sword parts becoming visible
function DevilSword:animateSwordAppearance(DevilSword, playerData)
	for _, part in pairs(DevilSword:GetChildren()) do
		if not part:IsA("BasePart") then continue end
		
		self:setupPartForAppearance(part)
		local appearTween = self:createAppearanceTween(part)
		appearTween:Play()
		playerData.trove:Add(appearTween)
	end
end

-- Helper: Sets up part initial state for appearance animation
function DevilSword:setupPartForAppearance(part)
	part.Transparency = 1
	part.Color = Color3.new(1, 1, 1)
end

-- Helper: Creates tween for part appearance
function DevilSword:createAppearanceTween(part)
	local originalColor = part.Color
	return TweenService:Create(
		part,
		TweenInfo.new(0.25, Enum.EasingStyle.Circular),
		{Transparency = 0, Color = originalColor}
	)
end

-- Helper: Animates sword movement to final position
function DevilSword:animateSwordMovement(DevilSword, VFXRoot, playerData)
	local finalCFrame = VFXRoot.CFrame * CFrame.new(-1.5, 0, 0) * CFrame.Angles(math.rad(90), math.rad(180), 0)
	local moveTween = TweenService:Create(
		DevilSword.Handler,
		TweenInfo.new(1, Enum.EasingStyle.Circular, Enum.EasingDirection.InOut),
		{CFrame = finalCFrame}
	)
	moveTween:Play()
	playerData.trove:Add(moveTween)
end

-- Equipment: Attaches sword model to character's arm
function DevilSword:attachSwordToCharacter(character, playerData)
	local rightArm = character:FindFirstChild("Right Arm")
	if not rightArm then return end

	local DevilSwordArm = self:createArmSword(character, rightArm, playerData)
	self:animateArmSwordAppearance(DevilSwordArm, playerData)
end

-- Helper: Creates and welds sword to character's arm
function DevilSword:createArmSword(character, rightArm, playerData)
	local DevilSwordArm = ReplicatedStorage.Assets.VFX.DevilSword.RightArm:Clone()
	DevilSwordArm.Parent = character
	playerData.trove:Add(DevilSwordArm)

	local weld = Instance.new("Weld")
	weld.Part0 = DevilSwordArm
	weld.Part1 = rightArm
	weld.Parent = DevilSwordArm
	playerData.trove:Add(weld)
	
	return DevilSwordArm
end

-- Helper: Animates arm-mounted sword becoming visible
function DevilSword:animateArmSwordAppearance(DevilSwordArm, playerData)
	for _, part in pairs(DevilSwordArm.DevilSword:GetChildren()) do
		if not part:IsA("BasePart") then continue end
		
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

-- Combat: Performs hitbox detection and damage calculation
function DevilSword:performHitboxCheck(character, player, damage, animations, hitKey, playerData)
	playerData.hitTargets = {}

	local hitTargets = self:getHitboxTargets(character)
	self:processDamageForTargets(hitTargets, player, damage, animations, hitKey, playerData)
end

-- Helper: Gets targets within hitbox range
function DevilSword:getHitboxTargets(character)
	return Knit.GetService("HitboxService"):Start({
		Character = character,
		Length = 5, 
		HitboxType = "Magnitude",
		CheckInFront = true 
	})
end

-- Helper: Processes damage and animations for all hit targets
function DevilSword:processDamageForTargets(hitTargets, player, damage, animations, hitKey, playerData)
	for _, target in pairs(hitTargets) do
		if table.find(playerData.hitTargets, target) then continue end
		
		table.insert(playerData.hitTargets, target)
		self:dealDamageToTarget(target, player, damage, animations, hitKey)
	end
end

-- Helper: Deals damage to a single target and plays hit animation
function DevilSword:dealDamageToTarget(target, player, damage, animations, hitKey)
	local damageResult = TakeDamage({Player = player, Damage = damage}, target)
	if not damageResult then return end

	if animations[hitKey] then
		MovesetService:PlayAnimation(target, animations[hitKey])
	end

	print(`[DevilSword] {player.Name} hit {target.Name} for {damage} damage`)
end

-- Visual: Fades out the equipped sword from character
function DevilSword:fadeOutEquippedSword(character, playerData)
	local rightArm = character:FindFirstChild("RightArm")
	if not rightArm then return end

	local devilSword = rightArm:FindFirstChild("DevilSword")
	if not devilSword then return end

	self:fadeOutSwordParts(devilSword, playerData)
	self:scheduleArmCleanup(rightArm, playerData)
end

-- Helper: Fades out all sword parts
function DevilSword:fadeOutSwordParts(devilSword, playerData)
	for _, part in pairs(devilSword:GetChildren()) do
		if not part:IsA("BasePart") then continue end
		
		local fadeTween = TweenService:Create(
			part,
			TweenInfo.new(0.25, Enum.EasingStyle.Circular),
			{Transparency = 1}
		)
		fadeTween:Play()
		playerData.trove:Add(fadeTween)
	end
end

-- Helper: Schedules cleanup of the right arm
function DevilSword:scheduleArmCleanup(rightArm, playerData)
	playerData.trove:Add(task.delay(0.3, function()
		if rightArm and rightArm.Parent then
			playerData.trove:Add(rightArm)
		end
	end))
end

-- Main execution function - handles both equipping and combat
function DevilSword:execute(data)
	if not self:isValidExecuteData(data) then return end

	local player, weapon, weaponType = data.Player, data.Weapon, data.WeaponType
	local playerName = player.Name
	local character, rootpart = self:getCharacterComponents(player)
	
	if not self:isValidCharacterState(character, rootpart, player, playerName) then return end

	local weaponConfigs = self:getWeaponConfigs(weaponType, weapon)
	if not weaponConfigs then return end

	self:initializePlayer(playerName)
	local playerData = self.PlayerData[playerName]

	if not self:validateInput(playerName) then return end

	-- Main execution branch: equip or attack
	if character:GetAttribute("Equiped") then
		self:executeComboAttack(player, character, rootpart, playerData, weaponConfigs)
	else
		self:executeEquipSequence(player, character, rootpart, playerData, weaponConfigs)
	end
end

-- Helper: Validates the input data structure
function DevilSword:isValidExecuteData(data)
	if not data or type(data) ~= "table" then return false end
	return data.Player and data.Weapon and data.WeaponType
end

-- Helper: Gets character and root part references
function DevilSword:getCharacterComponents(player)
	local character = player.Character
	local rootpart = character and character:FindFirstChild("HumanoidRootPart")
	return character, rootpart
end

-- Helper: Validates character state and cleans up if invalid
function DevilSword:isValidCharacterState(character, rootpart, player, playerName)
	if character and rootpart and player.Parent then
		return true
	end
	
	self:cleanupPlayer(playerName)
	return false
end

-- Helper: Gets weapon configuration data
function DevilSword:getWeaponConfigs(weaponType, weapon)
	local success, configs = pcall(function()
		return require(ReplicatedStorage.Modules.Configs[weaponType])
	end)

	if not success then return nil end

	local weaponConfigs = configs[weapon]
	if not weaponConfigs or not weaponConfigs[script.Name] then
		warn(`[DevilSword] Configuration not found for weapon: {weapon}`)
		return nil
	end

	return weaponConfigs[script.Name]
end

-- Execution: Handles the sword equipping sequence
function DevilSword:executeEquipSequence(player, character, rootpart, playerData, comboConfigs)
	print(`[DevilSword] {player.Name} equipping Devil Sword`)

	self:startEquipAnimation(player, character, playerData, comboConfigs.Animation)
	self:setupEquipEffects(rootpart, playerData)
	self:scheduleEquipSequence(player, character, rootpart, playerData)
end

-- Helper: Starts equip animation and sets character state
function DevilSword:startEquipAnimation(player, character, playerData, animations)
	playerData.isAnimating = true
	character:SetAttribute("Equiped", true)
	MovesetService:PlayAnimation(player, animations["PullSword"])
end

-- Helper: Creates VFX and sound effects for equipping
function DevilSword:setupEquipEffects(rootpart, playerData)
	local VFXRoot = self:createWeaponVFX(rootpart, playerData)
	
	Knit.GetService("SoundService"):Play({
		SoundName = "DevilSwordSpawn",
		Parent = rootpart
	})
	
	return VFXRoot
end

-- Helper: Schedules the complete equip sequence with timings
function DevilSword:scheduleEquipSequence(player, character, rootpart, playerData)
	-- Set animation timer
	playerData.animationTimer = task.delay(2.5, function()
		if not self.PlayerData[player.Name] then return end
		self.PlayerData[player.Name].isAnimating = false
		self.PlayerData[player.Name].animationTimer = nil
	end)

	-- Schedule main equip sequence
	playerData.trove:Add(task.delay(0.2, function()
		self:executeMainEquipSequence(character, rootpart, playerData)
	end))
end

-- Helper: Executes the main part of the equip sequence
function DevilSword:executeMainEquipSequence(character, rootpart, playerData)
	if not character:GetAttribute("Equiped") then return end

	self:applyEquipStun(character)
	
	task.wait(0.1)
	local VFXRoot = self:createWeaponVFX(rootpart, playerData)
	local DevilSword = self:spawnSwordModel(VFXRoot, playerData)
	
	self:scheduleEquipFinalization(character, DevilSword, playerData)
end

-- Helper: Applies movement restrictions during equip
function DevilSword:applyEquipStun(character)
	Knit.GetService("StunService"):Add({
		Target = character,
		WalkSpeed = 0,
		JumpPower = 0,
		Duration = 1,
		AutoRotate = false,
	})
end

-- Helper: Schedules the final steps of equipping
function DevilSword:scheduleEquipFinalization(character, DevilSword, playerData)
	playerData.trove:Add(task.delay(1, function()
		if not character:GetAttribute("Equiped") then return end

		self:fadeOutSpawnedSword(DevilSword, playerData)
		self:scheduleArmAttachment(character, playerData)
	end))
end

-- Helper: Fades out the spawned sword model
function DevilSword:fadeOutSpawnedSword(DevilSword, playerData)
	for _, part in pairs(DevilSword:GetChildren()) do
		if not part:IsA("BasePart") then continue end
		
		local fadeTween = TweenService:Create(
			part,
			TweenInfo.new(0.25, Enum.EasingStyle.Circular),
			{Transparency = 1, Color = Color3.new(1, 1, 1)}
		)
		fadeTween:Play()
		playerData.trove:Add(fadeTween)
	end
end

-- Helper: Schedules attaching sword to character's arm
function DevilSword:scheduleArmAttachment(character, playerData)
	playerData.trove:Add(task.delay(0.25, function()
		if character:GetAttribute("Equiped") then
			self:attachSwordToCharacter(character, playerData)
		end
	end))
end

-- Execution: Handles combo attack sequence
function DevilSword:executeComboAttack(player, character, rootpart, playerData, comboConfigs)
	local animations = comboConfigs.Animation
	local maxHits = comboConfigs.MaxHit or 4
	local comboResetTime = comboConfigs.ComboResetTime or 2
	local finishComboCooldown = comboConfigs.FinishComboCooldown or 1
	local animationDelay = comboConfigs.AnimationDelay or 0.5
	local baseDamage = comboConfigs.BaseDamage or 5

	self:cancelComboResetTimer(playerData)
	self:executeComboHit(player, character, rootpart, playerData, animations, baseDamage, animationDelay)
	self:setupComboResetTimer(player, character, playerData, comboResetTime)
	self:checkComboCompletion(player, character, playerData, maxHits, finishComboCooldown)
end

-- Helper: Cancels existing combo reset timer
function DevilSword:cancelComboResetTimer(playerData)
	if playerData.resetTimer then
		task.cancel(playerData.resetTimer)
		playerData.resetTimer = nil
	end
end

-- Helper: Executes a single combo hit
function DevilSword:executeComboHit(player, character, rootpart, playerData, animations, baseDamage, animationDelay)
	print(`[DevilSword] {player.Name} performing combo attack {playerData.combo + 1}`)

	playerData.isAnimating = true
	playerData.combo = (playerData.combo % 4) + 1 -- Assuming max 4 hits

	self:playComboAnimation(player, animations, playerData.combo)
	self:playSwingSound(rootpart)
	self:setAnimationTimer(player, playerData, animationDelay)
	self:applyCombatEffects(character, playerData, player, baseDamage, animations)
end

-- Helper: Plays the appropriate combo animation
function DevilSword:playComboAnimation(player, animations, comboCount)
	local animationKey = "Hit" .. comboCount
	if animations[animationKey] then
		MovesetService:PlayAnimation(player, animations[animationKey])
	end
end

-- Helper: Plays swing sound effect
function DevilSword:playSwingSound(rootpart)
	Knit.GetService("SoundService"):Play({
		SoundName = "Swing",
		Parent = rootpart
	})
end

-- Helper: Sets up animation timer
function DevilSword:setAnimationTimer(player, playerData, animationDelay)
	playerData.animationTimer = task.delay(animationDelay, function()
		if not self.PlayerData[player.Name] then return end
		self.PlayerData[player.Name].isAnimating = false
		self.PlayerData[player.Name].animationTimer = nil
	end)
end

-- Helper: Applies combat effects and performs hit detection
function DevilSword:applyCombatEffects(character, playerData, player, baseDamage, animations)
	self:applyMovementRestrictions(character)
	self:addParryState(character)
	self:scheduleHitboxCheck(character, player, playerData, baseDamage, animations)
end

-- Helper: Applies movement restrictions during attack
function DevilSword:applyMovementRestrictions(character)
	Knit.GetService("StunService"):Add({
		Target = character,
		WalkSpeed = 6,
		AutoRotate = true,
		JumpPower = 0,
		Duration = 2
	})
end

-- Helper: Adds parry state to character
function DevilSword:addParryState(character)
	Knit.GetService("CombatService"):Add({
		Target = character,
		Duration = 0.15,
		Value = "Parry",
	})
end

-- Helper: Schedules hitbox check with delay
function DevilSword:scheduleHitboxCheck(character, player, playerData, baseDamage, animations)
	playerData.trove:Add(task.delay(0.15, function()
		local scaledDamage = baseDamage + (playerData.combo - 1)
		local hitAnimationKey = "TargetHit" .. playerData.combo
		
		self:performHitboxCheck(
			character, 
			player, 
			scaledDamage, 
			animations, 
			hitAnimationKey, 
			playerData
		)
	end))
end

-- Helper: Sets up combo reset timer
function DevilSword:setupComboResetTimer(player, character, playerData, comboResetTime)
	playerData.resetTimer = task.delay(comboResetTime, function()
		self:handleComboTimeout(player, character, playerData)
	end)
end

-- Helper: Handles combo timeout and unequipping
function DevilSword:handleComboTimeout(player, character, playerData)
	if not self.PlayerData[player.Name] then return end

	print(`[DevilSword] {player.Name} combo timed out, unequipping`)
	character:SetAttribute("Equiped", nil)

	playerData.trove:Add(task.delay(1, function()
		self:fadeOutEquippedSword(character, playerData)
	end))

	playerData.trove:Clean()
	playerData.combo = 0
	playerData.resetTimer = nil
end

-- Helper: Checks if combo is complete and handles cooldown
function DevilSword:checkComboCompletion(player, character, playerData, maxHits, finishComboCooldown)
	if playerData.combo < maxHits then return end

	print(`[DevilSword] {player.Name} completed full combo, entering cooldown`)
	self:initiateComboCooldown(player, character, playerData, finishComboCooldown)
end

-- Helper: Initiates cooldown after full combo completion
function DevilSword:initiateComboCooldown(player, character, playerData, finishComboCooldown)
	playerData.isOnCooldown = true
	playerData.combo = 0
	character:SetAttribute("Equiped", nil)

	self:scheduleComboCleanup(character, playerData)
	self:setupCooldownTimer(player, playerData, finishComboCooldown)
end

-- Helper: Schedules cleanup after combo completion
function DevilSword:scheduleComboCleanup(character, playerData)
	playerData.trove:Add(task.delay(1, function()
		self:fadeOutEquippedSword(character, playerData)
		playerData.trove:Clean()
	end))
end

-- Helper: Sets up cooldown timer
function DevilSword:setupCooldownTimer(player, playerData, finishComboCooldown)
	playerData.cooldownTimer = task.delay(finishComboCooldown, function()
		if not self.PlayerData[player.Name] then return end
		
		playerData.trove:Clean()
		self.PlayerData[player.Name].isOnCooldown = false
		self.PlayerData[player.Name].cooldownTimer = nil
		print(`[DevilSword] {player.Name} cooldown expired`)
	end)
end

return DevilSword
