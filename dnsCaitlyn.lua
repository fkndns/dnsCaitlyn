require "PremiumPrediction"
require "GamsteronPrediction"
require "DamageLib"
require "2DGeometry"
require "MapPositionGOS"
require "GGPrediction"

local EnemyHeroes = {}
local AllyHeroes = {}
local EnemySpawnPos = nil
local AllySpawnPos = nil

local function IsNearEnemyTurret(pos, distance)
    --PrintChat("Checking Turrets")
    local turrets = _G.SDK.ObjectManager:GetTurrets(GetDistance(pos) + 1000)
    for i = 1, #turrets do
        local turret = turrets[i]
        if turret and GetDistance(turret.pos, pos) <= distance+915 and turret.team == 300-myHero.team then
            --PrintChat("turret")
            return turret
        end
    end
end

local function IsUnderEnemyTurret(pos)
    --PrintChat("Checking Turrets")
    local turrets = _G.SDK.ObjectManager:GetTurrets(GetDistance(pos) + 1000)
    for i = 1, #turrets do
        local turret = turrets[i]
        if turret and GetDistance(turret.pos, pos) <= 915 and turret.team == 300-myHero.team then
            --PrintChat("turret")
            return turret
        end
    end
end

function GetDifference(a,b)
    local Sa = a^2
    local Sb = b^2
    local Sdif = (a-b)^2
    return math.sqrt(Sdif)
end

function GetDistanceSqr(Pos1, Pos2)
    local Pos2 = Pos2 or myHero.pos
    local dx = Pos1.x - Pos2.x
    local dz = (Pos1.z or Pos1.y) - (Pos2.z or Pos2.y)
    return dx^2 + dz^2
end

function GetDistance(Pos1, Pos2)
    return math.sqrt(GetDistanceSqr(Pos1, Pos2))
end

function IsImmobile(unit)
    local MaxDuration = 0
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        if buff and buff.count > 0 then
            local BuffType = buff.type
            if BuffType == 5 or BuffType == 11 or BuffType == 21 or BuffType == 22 or BuffType == 24 or BuffType == 29 or buff.name == "recall" then
                local BuffDuration = buff.duration
                if BuffDuration > MaxDuration then
                    MaxDuration = BuffDuration
                end
            end
        end
    end
    return MaxDuration
end

function GetEnemyHeroes()
    for i = 1, Game.HeroCount() do
        local Hero = Game.Hero(i)
        if Hero.isEnemy then
            table.insert(EnemyHeroes, Hero)
            PrintChat(Hero.name)
        end
    end
    --PrintChat("Got Enemy Heroes")
end

function GetEnemyBase()
    for i = 1, Game.ObjectCount() do
        local object = Game.Object(i)
        
        if not object.isAlly and object.type == Obj_AI_SpawnPoint then 
            EnemySpawnPos = object
            break
        end
    end
end

function GetAllyBase()
    for i = 1, Game.ObjectCount() do
        local object = Game.Object(i)
        
        if object.isAlly and object.type == Obj_AI_SpawnPoint then 
            AllySpawnPos = object
            break
        end
    end
end

function GetAllyHeroes()
    for i = 1, Game.HeroCount() do
        local Hero = Game.Hero(i)
        if Hero.isAlly then
            table.insert(AllyHeroes, Hero)
            PrintChat(Hero.name)
        end
    end
    --PrintChat("Got Enemy Heroes")
end

function GetBuffStart(unit, buffname)
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        if buff.name == buffname and buff.count > 0 then 
            return buff.startTime
        end
    end
    return nil
end

function GetBuffExpire(unit, buffname)
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        if buff.name == buffname and buff.count > 0 then 
            return buff.expireTime
        end
    end
    return nil
end

function GetBuffStacks(unit, buffname)
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        if buff.name == buffname and buff.count > 0 then 
            return buff.count
        end
    end
    return 0
end

local function GetWaypoints(unit) -- get unit's waypoints
    local waypoints = {}
    local pathData = unit.pathing
    table.insert(waypoints, unit.pos)
    local PathStart = pathData.pathIndex
    local PathEnd = pathData.pathCount
    if PathStart and PathEnd and PathStart >= 0 and PathEnd <= 20 and pathData.hasMovePath then
        for i = pathData.pathIndex, pathData.pathCount do
            table.insert(waypoints, unit:GetPath(i))
        end
    end
    return waypoints
end

local function GetUnitPositionNext(unit)
    local waypoints = GetWaypoints(unit)
    if #waypoints == 1 then
        return nil -- we have only 1 waypoint which means that unit is not moving, return his position
    end
    return waypoints[2] -- all segments have been checked, so the final result is the last waypoint
end

local function GetUnitPositionAfterTime(unit, time)
    local waypoints = GetWaypoints(unit)
    if #waypoints == 1 then
        return unit.pos -- we have only 1 waypoint which means that unit is not moving, return his position
    end
    local max = unit.ms * time -- calculate arrival distance
    for i = 1, #waypoints - 1 do
        local a, b = waypoints[i], waypoints[i + 1]
        local dist = GetDistance(a, b)
        if dist >= max then
            return Vector(a):Extended(b, dist) -- distance of segment is bigger or equal to maximum distance, so the result is point A extended by point B over calculated distance
        end
        max = max - dist -- reduce maximum distance and check next segments
    end
    return waypoints[#waypoints] -- all segments have been checked, so the final result is the last waypoint
end

function GetTarget(range)
    if _G.SDK then
        return _G.SDK.TargetSelector:GetTarget(range, _G.SDK.DAMAGE_TYPE_MAGICAL);
    else
        return _G.GOS:GetTarget(range,"AD")
    end
end

function GotBuff(unit, buffname)
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        --PrintChat(buff.name)
        if buff.name == buffname and buff.count > 0 then 
            return buff.count
        end
    end
    return 0
end

function BuffActive(unit, buffname)
    for i = 0, unit.buffCount do
        local buff = unit:GetBuff(i)
        if buff.name == buffname and buff.count > 0 then 
            return true
        end
    end
    return false
end

function IsReady(spell)
    return myHero:GetSpellData(spell).currentCd == 0 and myHero:GetSpellData(spell).level > 0 and myHero:GetSpellData(spell).mana <= myHero.mana and Game.CanUseSpell(spell) == 0
end

function Mode()
    if _G.SDK then
        if _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_COMBO] then
            return "Combo"
        elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_HARASS] or Orbwalker.Key.Harass:Value() then
            return "Harass"
        elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LANECLEAR] or Orbwalker.Key.Clear:Value() then
            return "LaneClear"
        elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_LASTHIT] or Orbwalker.Key.LastHit:Value() then
            return "LastHit"
        elseif _G.SDK.Orbwalker.Modes[_G.SDK.ORBWALKER_MODE_FLEE] then
            return "Flee"
        end
    else
        return GOS.GetMode()
    end
end

function GetItemSlot(unit, id)
    for i = ITEM_1, ITEM_7 do
        if unit:GetItemData(i).itemID == id then
            return i
        end
    end
    return 0
end

function IsFacing(unit)
    local V = Vector((unit.pos - myHero.pos))
    local D = Vector(unit.dir)
    local Angle = 180 - math.deg(math.acos(V*D/(V:Len()*D:Len())))
    if math.abs(Angle) < 80 then 
        return true  
    end
    return false
end

function IsMyHeroFacing(unit)
    local V = Vector((myHero.pos - unit.pos))
    local D = Vector(myHero.dir)
    local Angle = 180 - math.deg(math.acos(V*D/(V:Len()*D:Len())))
    if math.abs(Angle) < 80 then 
        return true  
    end
    return false
end

function SetMovement(bool)
    if _G.PremiumOrbwalker then
        _G.PremiumOrbwalker:SetAttack(bool)
        _G.PremiumOrbwalker:SetMovement(bool)       
    elseif _G.SDK then
        _G.SDK.Orbwalker:SetMovement(bool)
        _G.SDK.Orbwalker:SetAttack(bool)
    end
end


local function CheckHPPred(unit, SpellSpeed)
     local speed = SpellSpeed
     local range = myHero.pos:DistanceTo(unit.pos)
     local time = range / speed
     if _G.SDK and _G.SDK.Orbwalker then
         return _G.SDK.HealthPrediction:GetPrediction(unit, time)
     elseif _G.PremiumOrbwalker then
         return _G.PremiumOrbwalker:GetHealthPrediction(unit, time)
    end
end

function EnableMovement()
    SetMovement(true)
end

local function IsValid(unit)
    if (unit and unit.valid and unit.isTargetable and unit.alive and unit.visible and unit.networkID and unit.pathing and unit.health > 0) then
        return true;
    end
    return false;
end


local function ValidTarget(unit, range)
    if (unit and unit.valid and unit.isTargetable and unit.alive and unit.visible and unit.networkID and unit.pathing and unit.health > 0) then
        if range then
            if GetDistance(unit.pos) <= range then
                return true;
            end
        else
            return true
        end
    end
    return false;
end

class "Manager"

function Manager:__init()
    if myHero.charName == "Caitlyn" then
        DelayAction(function() self:LoadCaitlyn() end, 1.05)
    end
end


function Manager:LoadCaitlyn()
    Caitlyn:Spells()
    Caitlyn:Menu()
    --
    --GetEnemyHeroes()
    Callback.Add("Tick", function() Caitlyn:Tick() end)
    Callback.Add("Draw", function() Caitlyn:Draw() end)
    if _G.SDK then
        _G.SDK.Orbwalker:OnPreAttack(function(...) Caitlyn:OnPreAttack(...) end)
        _G.SDK.Orbwalker:OnPostAttackTick(function(...) Caitlyn:OnPostAttackTick(...) end)
        _G.SDK.Orbwalker:OnPostAttack(function(...) Caitlyn:OnPostAttack(...) end)
    end
end

class "Caitlyn"

local EnemyLoaded = false
local attackedfirst = 0
local WasInRange = false
local casted = 0

function Caitlyn:Menu()
    self.Menu = MenuElement({type = MENU, id = "Caitlyn", name = "dnsCaitlyn v0.1"})
    self.Menu:MenuElement({id = "QSpell", name = "Q", type = MENU})
	self.Menu.QSpell:MenuElement({id = "QCombo", name = "Combo", value = true})
	self.Menu.QSpell:MenuElement({id = "QComboHitChance", name = "HitChance", value = 0.7, min = 0.1, max = 1.0, step = 0.1})
	self.Menu.QSpell:MenuElement({id = "QHarass", name = "Harass", value = false})
	self.Menu.QSpell:MenuElement({id = "QHarassHitChance", name = "HitChance", value = 0.7, min = 0.1, max = 1.0, step = 0.1})
	self.Menu.QSpell:MenuElement({id = "QHarassMana", name = "Mana %", value = 40, min = 0, max = 100, identifier = "%"})
	self.Menu.QSpell:MenuElement({id = "QLaneClear", name = "LaneClear", value = false})
	self.Menu.QSpell:MenuElement({id = "QLaneClearMana", name = "Mana %", value = 60, min = 0, max = 100, identifier = "%"})
	self.Menu.QSpell:MenuElement({id = "QLastHit", name = "LastHit Cannon when out of aa range", value = true})
	self.Menu.QSpell:MenuElement({id = "QKS", name = "KS", value = true})
	self.Menu:MenuElement({id = "WSpell", name = "W", type = MENU})
	self.Menu.WSpell:MenuElement({id = "WImmo", name = "Auto W immobile Targets", value = true})
	self.Menu:MenuElement({id = "ESpell", name = "E", type = MENU})
	self.Menu.ESpell:MenuElement({id = "ECombo", name = "Combo", value = true})
	self.Menu.ESpell:MenuElement({id = "EComboHitChance", name = "HitChance", value = 1, min = 0.1, max = 1.0, step = 0.1})
	self.Menu.ESpell:MenuElement({id = "EHarass", name = "Harass", value = false})
	self.Menu.ESpell:MenuElement({id = "EHarassHitChance", name = "HitChance", value = 1, min = 0.1, max = 1.0, step = 0.1})
	self.Menu.ESpell:MenuElement({id = "EHarassMana", name = "Mana %", value = 60, min = 0, max = 100, identifier = "%"})
	self.Menu.ESpell:MenuElement({id = "EGap", name = "Peel Meele Champs", value = true})
	self.Menu:MenuElement({id = "RSpell", name = "R", type = MENU})
	self.Menu.RSpell:MenuElement({id = "RKS", name = "KS", value = true})
	self.Menu:MenuElement({id = "MakeDraw", name = "U wanna hav dravvs?", type = MENU})
	self.Menu.MakeDraw:MenuElement({id = "UseDraws", name = "U wanna hav dravvs?", value = false})
	self.Menu.MakeDraw:MenuElement({id = "QDraws", name = "U wanna Q-Range dravvs?", value = false})
	self.Menu.MakeDraw:MenuElement({id = "RDraws", name = "U wanna R-Range dravvs?", value = false})

end

function Caitlyn:Spells()
    QSpellData = {speed = 2200, range = 1300, delay = 0.625, radius = 150, collision = {}, type = "linear"}
	WSpellData = {speed = math.huge, range = 800, delay = 0.25, radius = 60, collision = {}, type = "circular"}
	ESpellData = {speed = math.huge, range = 750, delay = 0.15, radius = 100, collision = {minion}, type = "linear"}
end


function Caitlyn:Draw()
    if self.Menu.MakeDraw.UseDraws:Value() then
        if self.Menu.MakeDraw.QDraws:Value() then
            Draw.Circle(myHero.pos, 1300, 1, Draw.Color(237, 255, 255, 255))
        end
		if self.Menu.MakeDraw.RDraws:Value() then
			Draw.Circle(myHero.pos, 3500, 1, Draw.Color(237, 255, 255, 255))
		end
    end
end



function Caitlyn:Tick()
    if _G.JustEvade and _G.JustEvade:Evading() or (_G.ExtLibEvade and _G.ExtLibEvade.Evading) or Game.IsChatOpen() or myHero.dead then return end
    target = GetTarget(1400)
    AARange = _G.SDK.Data:GetAutoAttackRange(myHero)
    self:Logic()
	self:KS()
	self:LastHit()
	self:LaneClear()
    if EnemyLoaded == false then
        local CountEnemy = 0
        for i, enemy in pairs(EnemyHeroes) do
            CountEnemy = CountEnemy + 1
        end
        if CountEnemy < 1 then
            GetEnemyHeroes()
        else
            EnemyLoaded = true
            PrintChat("Enemy Loaded")
        end
	end
end

function Caitlyn:KS()
	for i, enemy in pairs(EnemyHeroes) do
		local RRange = 3500 + enemy.boundingRadius
		if enemy and not enemy.dead and ValidTarget(enemy, RRange) then
			local RDamage = getdmg("R", enemy, myHero, myHero:GetSpellData(_R).level)
			if self:CanUse(_R, "KS") and GetDistance(enemy.pos, myHero.pos) < RRange and GetDistance(enemy.pos, myHero.pos) > 900 and enemy.health < RDamage then
				Control.CastSpell(HK_R, enemy)
			end
		end
		local QRange = 1300 + enemy.boundingRadius
		if enemy and not enemy.dead and ValidTarget(enemy, QRange) then
			local QDamage = getdmg("Q", enemy, myHero, myHero:GetSpellData(_Q).level)
			local pred = _G.PremiumPrediction:GetPrediction(myHero, enemy, QSpellData)
			if pred.CastPos and _G.PremiumPrediction.HitChance.High(pred.HitChance) and self:CanUse(_Q, "KS") and enemy.health < QDamage and GetDistance(pred.CastPos) > 650 and GetDistance(pred.CastPos) < 1300 then
				Control.CastSpell(HK_Q, pred.CastPos)
			end
		end
		local WRange = 800 + enemy.boundingRadius
		if enemy and not enemy.dead and ValidTarget(enemy, WRange) and self:CanUse(_W, "TrapImmo") then
			local pred = _G.PremiumPrediction:GetPrediction(myHero, enemy, WSpellData)
			if pred.Castpos and _G.PremiumPrediction.HitChance.Immobile(pred.HitChance) and GetDistance(pred.CastPos) < 800 then
				Control.CastSpell(HK_W, pred.CastPos)
			end
		end
		if enemy and not enemy.dead and GetDistance(enemy.pos, myHero.pos) < 300 + enemy.boundingRadius and IsFacing(enemy) and self:CanUse(_E, "NetGap") then
			Control.CastSpell(HK_E, enemy)
		end
	end
end

function Caitlyn:CanUse(spell, mode)
	local ManaPercent = myHero.mana / myHero.maxMana * 100
	--PrintChat("Can use Runs")
	if mode == nil then
		mode = Mode()
	end
	
	if spell == _Q then
		--PrintChat("Q spell asked for")
		if mode == "Combo" and IsReady(spell) and self.Menu.QSpell.QCombo:Value() then
			--PrintChat("CanUse Q and Combo mode")
			return true
		end
		if mode == "Harass" and IsReady(spell) and self.Menu.QSpell.QHarass:Value() and ManaPercent > self.Menu.QSpell.QHarassMana:Value() then
			return true
		end
		if mode == "LaneClear" and IsReady(spell) and self.Menu.QSpell.QLaneClear:Value() and ManaPercent > self.Menu.QSpell.QLaneClearMana:Value() then
			--PrintChat("Checking for Laneclear")
			return true
		end
		if mode == "KS" and IsReady(spell) and self.Menu.QSpell.QKS:Value() then
			return true
		end
		if mode == "LastHit" and IsReady(spell) and self.Menu.QSpell.QLastHit:Value() then
			return true
		end
	elseif spell == _W then
		if mode == "TrapImmo" and IsReady(spell) and self.Menu.WSpell.WImmo:Value() then
			return true
		end
	elseif spell == _E then
		if mode == "Combo" and IsReady(spell) and self.Menu.ESpell.ECombo:Value() then
			return true
		end
		if mode == "Harass" and IsReady(spell) and self.Menu.ESpell.EHarass:Value()and ManaPercent > self.Menu.ESpell.EHarassMana:Value() then
			return true
		end
		if mode == "NetGap" and IsReady(spell) and self.Menu.ESpell.EGap:Value() then
			return true
		end
	elseif spell == _R then
		if mode == "KS" and IsReady(spell) and self.Menu.RSpell.RKS:Value() then
			return true
		end
	end
	return false
end


function Caitlyn:Logic()
    if target == nil then 
        return 
    end
    if Mode() == "Combo" and target then
	--PrintChat("Combo Mode and Target")
        if self:CanUse(_Q, "Combo") and ValidTarget(target, 1300 + target.boundingRadius)  then
		--PrintChat("ValidTarget can Use q")
            local pred = _G.PremiumPrediction:GetPrediction(myHero, target, QSpellData)
			if pred.CastPos and pred.HitChance > self.Menu.QSpell.QComboHitChance:Value() and GetDistance(pred.CastPos) > 650 and GetDistance(pred.CastPos) < 1300 then
			--PrintChat("Prediction cheks, ready to cast q")
				Control.CastSpell(HK_Q, pred.CastPos)

				end
        end
		if self:CanUse(_E, "Combo") and ValidTarget(target, 750 + target.boundingRadius) then
			local pred = _G.PremiumPrediction:GetPrediction(myHero, target, ESpellData)
			if pred.CastPos and pred.HitChance > self.Menu.ESpell.EComboHitChance:Value() and GetDistance(pred.CastPos)	< 750 then 
				Control.CastSpell(HK_E, pred.CastPos)
			end
		end
	end 
	if Mode() == "Harass" and target then
		if self:CanUse(_Q, "Harass") and ValidTarget(target, 1300 + target.boundingRadius)  then
            local pred = _G.PremiumPrediction:GetPrediction(myHero, target, QSpellData)
			if pred.CastPos and pred.HitChance > self.Menu.QSpell.QHarassHitChance:Value() and GetDistance(pred.CastPos) > 650 and GetDistance(pred.CastPos) < 1300 then
				Control.CastSpell(HK_Q, pred.CastPos)
			end
        end
		if self:CanUse(_E, "Harass") and ValidTarget(target, 750 + target.boundingRadius) then
			local pred = _G.PremiumPrediction:GetPrediction(myHero, target, ESpellData)
			if pred.CastPos and pred.HitChance > self.Menu.ESpell.EHarassHitChanceHitChance:Value() and GetDistance < 750 then 
				Control.CastSpell(HK_E, pred.CastPos)
			end
		end
	end
end

function Caitlyn:LaneClear()
	if self:CanUse(_Q, "LaneClear") and Mode() == "LaneClear" then
		local CloseCheckDistance = 60
		local SurroundedMinion = nil
		local MinionsAround = 0
		local minions = _G.SDK.ObjectManager:GetEnemyMinions(1300)
		for i = 1, #minions do
			local minion = minions[i]
			local CloseMinions = 0
			for j = 1, #minions do
				local minion2 = minions[j]
				if GetDistance(minion2.pos, minion.pos) < CloseCheckDistance then
					CloseMinions = CloseMinions + 1
				end
			end
			if SurroundedMinion == nil or CloseMinions > MinionsAround then
				SurroundedMinion = minion
				MinionsAround = CloseMinions
			end
		end
		if SurroundedMinion ~= nil and GetDistance(SurroundedMinion.pos) < 1300 + myHero.boundingRadius then
			Control.CastSpell(HK_Q, SurroundedMinion)
		end
	end
end

function Caitlyn:LastHit()
	if self:CanUse(_Q, "LastHit") and (Mode() == "LastHit" or Mode() == "LaneClear") then
		local minions = _G.SDK.ObjectManager:GetEnemyMinions(1300)
		for i = 1, #minions do
			local minion = minions[i]
			if GetDistance(minion.pos) > 650 and GetDistance(minion.pos) < 1300 and (minion.charName == "SRU_ChaosMinionSiege" or minion.charName == "SRU_OrderMinionSiege") then
				local QDam = getdmg("Q", minion, myHero, myHero:GetSpellData(_Q).level)
				if minion and not minion.dead and QDam >= minion.health then
					Control.CastSpell(HK_Q, minion)
				end
			end
		end
	end
end

function Caitlyn:OnPostAttack(args)
end

function Caitlyn:OnPostAttackTick(args)
end

function Caitlyn:OnPreAttack(args)
end



function OnLoad()
    Manager()
end