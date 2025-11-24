-- 重生神通 - 复活已死亡的NPC
local tbTable = GameMain:GetMod("MagicHelper")  -- 获取神通模块
local tbMagic = tbTable:GetMagic("SQReborn")     -- 创建新的重生神通

-- 注意：
-- 神通脚本运行时有三个固定变量：
-- self.bind  - 执行神通的npcObj
-- self.magic  - 当前神通的数据（XML定义）
-- self.targetId - 目标NPC ID

-- 常量定义
local MAGIC_CONFIG = {
    CAST_TIME = "Param1",           -- 施法时间参数名
    THING_TYPE = CS.XiaWorld.g_emThingType,
    RACE_TYPE = CS.XiaWorld.g_emNpcRaceType,
    REVIVE_HEALTH = 300,            -- 复活后的生命值
    REVIVE_DID = 1,                 -- 复活后的DID
    MIN_LING_REQUIREMENT = 10000,   -- 最低灵力需求
    LING_COST = 5000               -- 施法灵力消耗
}

-- 初始化
function tbMagic:Init()
    self.targetId = nil
    self.targetIsThing = false
    self.initialLingCost = 0
end

-- 神通是否可用检查
function tbMagic:EnableCheck(npc)
    if not npc then
        return false
    end
    
    -- 基础状态检查
    local isAlive = npc.IsAlive
    local canAct = not npc:HasModifier("CannotAct")
    local hasEnoughLing = npc.LingV and npc.LingV >= MAGIC_CONFIG.MIN_LING_REQUIREMENT
    
    -- 检查施法者是否有复活能力
    local canResurrect = not npc:HasModifier("CannotResurrect")
    
    return isAlive and canAct and hasEnoughLing and canResurrect
end

-- 目标合法性检查
-- key: 目标键值
-- t: 目标类型
function tbMagic:TargetCheck(key, t)
    -- 基础检查
    if not key or not t then
        return false
    end
    
    -- 检查是否为NPC
    local isNpc = t.ThingType == MAGIC_CONFIG.THING_TYPE.Npc
    
    -- 检查是否为动物（排除动物）
    local isNotAnimal = t.Race and t.Race.RaceType ~= MAGIC_CONFIG.RACE_TYPE.Animal
    
    -- 检查是否为游魂状态（可被复活）
    local isLingering = t.IsLingering == true
    
    -- 检查是否可被复活
    local canBeResurrected = self:CanBeResurrected(t)
    
    return isNpc and isNotAnimal and isLingering and canBeResurrected
end

-- 检查目标是否可被复活
function tbMagic:CanBeResurrected(target)
    if not target then return false end
    
    -- 检查是否已彻底死亡（无法复活）
    local isPermanentlyDead = target:HasModifier("PermanentlyDead")
    local isSoulDestroyed = target:HasModifier("SoulDestroyed")
    local isReincarnated = target:HasModifier("Reincarnated")
    
    -- 检查死亡时间是否过长
    local isTooLongDead = target.CorpseTime and target.CorpseTime > 2592000  -- 30天以上
    
    -- 检查是否有复活限制
    local hasResurrectionRestriction = target:HasModifier("ResurrectionForbidden")
    
    return not (isPermanentlyDead or isSoulDestroyed or isReincarnated or 
                isTooLongDead or hasResurrectionRestriction)
end

-- 开始施展神通
function tbMagic:MagicEnter(IDs, IsThing)
    -- 记录目标信息
    if IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修正索引从1开始
        self.targetIsThing = IsThing
        
        print(string.format("【%s】开始施展重生神通，目标ID: %d", 
              self.bind and self.bind.Name or "未知NPC", self.targetId))
    else
        print("警告：重生神通未找到有效目标")
        return false
    end
    
    -- 验证目标有效性
    local target = self:GetTargetNpc()
    if not target then
        print("错误：目标NPC不存在或无效")
        return false
    end
    
    -- 触发施法开始效果
    if self.bind then
        -- 添加施法状态
        self.bind:AddModifier("CastingMagic")
        self.bind:AddModifier("ResurrectionCasting")
        
        -- 添加目标状态
        target:AddModifier("BeingResurrected")
        
        -- 消耗初始灵力
        self.initialLingCost = self:ConsumeInitialResources()
        
        -- 显示开始信息
        self:ShowResurrectionStartMessage(target)
    end
    
    return true
end

-- 神通施展过程
-- dt: 时间增量
-- duration: 已持续时间
-- 返回值: 0-继续 1-成功结束 -1-失败结束
function tbMagic:MagicStep(dt, duration)
    -- 安全检查
    if not self:ValidateCastingState() then
        return -1  -- 施法状态无效，失败结束
    end
    
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 15  -- 默认15秒
    local progress = math.min(duration / castTime, 1.0)
    
    -- 设置施法进度（UI显示）
    self:SetProgress(progress)
    
    -- 施法过程中的效果
    self:UpdateCastingEffects(progress)
    
    -- 持续消耗灵力
    self:ConsumeResourcesOverTime(dt, progress)
    
    -- 复活进度效果
    self:UpdateResurrectionProgress(progress)
    
    -- 检查施法是否完成
    if duration >= castTime then
        return 1  -- 施法成功完成
    end
    
    return 0  -- 继续施法
end

-- 施展完成/失败
-- success: 是否成功
function tbMagic:MagicLeave(success)
    -- 清理施法状态
    self:CleanupCastingState()
    
    if success then
        self:OnMagicSuccess()
    else
        self:OnMagicFailed()
    end
    
    -- 清理临时数据
    self:Cleanup()
end

-- 施法成功处理
function tbMagic:OnMagicSuccess()
    local target = self:GetTargetNpc()
    
    if target then
        -- 执行复活
        local success = self:PerformResurrection(target)
        
        if success then
            self:TriggerSuccessEffects(target)
            self:ShowResurrectionSuccessMessage(target)
        else
            print("错误：复活过程失败")
            self:OnMagicFailed()
        end
    else
        print("错误：复活目标不存在")
        self:OnMagicFailed()
    end
end

-- 执行复活逻辑
function tbMagic:PerformResurrection(target)
    if not target then return false end
    
    -- 保存当前状态
    local saveData = target.PropertyMgr:GetSaveData()
    if not saveData then
        print("错误：无法获取目标保存数据")
        return false
    end
    
    -- 复活逻辑
    saveData.BodyData.Dead = false
    saveData.BodyData.Dying = false
    saveData.BodyData.HealthValue = MAGIC_CONFIG.REVIVE_HEALTH
    saveData.BodyData.DID = MAGIC_CONFIG.REVIVE_DID
    
    -- 清除伤害和移除部位
    saveData.BodyData.Damages:Clear()
    saveData.BodyData.RemoveParts:Clear()
    
    -- 应用复活状态
    target.PropertyMgr.BodyData:AfterLoad(saveData)
    
    -- 清除死亡状态
    target.DieCause = nil
    target.CorpseTime = 0
    
    -- 添加复活后效果
    target:AddModifier("RecentlyResurrected")
    target:AddModifier("ResurrectionWeakness", 3600)  -- 1小时虚弱状态
    
    -- 恢复部分属性
    self:RestoreTargetAttributes(target)
    
    return true
end

-- 恢复目标属性
function tbMagic:RestoreTargetAttributes(target)
    if not target then return end
    
    -- 恢复基础生命值
    if target.PropertyMgr and target.PropertyMgr.BodyData then
        target.PropertyMgr.BodyData.HealthValue = MAGIC_CONFIG.REVIVE_HEALTH
    end
    
    -- 恢复部分灵力
    if target.LingV then
        target.LingV = math.max(100, target.LingV * 0.1)  -- 恢复10%灵力，至少100点
    end
    
    -- 清除负面状态
    target:RemoveModifier("Poison")
    target:RemoveModifier("Bleeding")
    target:RemoveModifier("Curse")
end

-- 施法失败处理
function tbMagic:OnMagicFailed()
    if self.bind then
        -- 添加失败反噬效果
        self.bind:AddModifier("ResurrectionBackfire")
        
        -- 部分灵力消耗
        local partialCost = math.floor(self.initialLingCost * 0.5)
        if self.bind.LingV > partialCost then
            self.bind.LingV = self.bind.LingV - partialCost
        end
        
        print(string.format("【%s】重生神通施展失败", self.bind.Name))
        
        -- 显示失败信息
        self:ShowResurrectionFailedMessage()
    end
end

-- 获取目标NPC
function tbMagic:GetTargetNpc()
    if not self.targetId then return nil end
    
    local target = ThingMgr:FindThingByID(self.targetId)
    if target and target.ThingType == MAGIC_CONFIG.THING_TYPE.Npc then
        return target
    end
    
    return nil
end

-- 验证施法状态
function tbMagic:ValidateCastingState()
    -- 检查施法者状态
    if not self.bind or not self.bind.IsAlive then
        return false
    end
    
    -- 检查灵力是否充足
    if not self.bind.LingV or self.bind.LingV <= 0 then
        return false
    end
    
    -- 检查目标是否存在且仍为游魂
    local target = self:GetTargetNpc()
    if not target or target.IsLingering ~= true then
        return false
    end
    
    -- 检查目标是否仍可被复活
    if not self:CanBeResurrected(target) then
        return false
    end
    
    return true
end

-- 消耗初始资源
function tbMagic:ConsumeInitialResources()
    if not self.bind or not self.bind.LingV then return 0 end
    
    local initialCost = MAGIC_CONFIG.LING_COST
    if self.bind.LingV >= initialCost then
        self.bind.LingV = self.bind.LingV - initialCost
        return initialCost
    end
    
    return 0
end

-- 持续消耗资源
function tbMagic:ConsumeResourcesOverTime(dt, progress)
    if not self.bind or not self.bind.LingV then return end
    
    local costPerSecond = 1000  -- 每秒消耗灵力
    local cost = costPerSecond * dt
    
    if self.bind.LingV > cost then
        self.bind.LingV = self.bind.LingV - cost
    else
        -- 灵力不足，施法失败
        self.bind.LingV = 0
    end
end

-- 更新复活进度效果
function tbMagic:UpdateResurrectionProgress(progress)
    local target = self:GetTargetNpc()
    if not target then return end
    
    -- 根据进度更新视觉效果
    if progress < 0.3 then
        target:AddModifier("SoulGathering")
    elseif progress < 0.7 then
        target:RemoveModifier("SoulGathering")
        target:AddModifier("BodyReforming")
    else
        target:RemoveModifier("BodyReforming")
        target:AddModifier("LifeReturning")
    end
end

-- 更新施法效果
function tbMagic:UpdateCastingEffects(progress)
    if not self.bind then return end
    
    -- 根据进度更新特效
    if progress < 0.3 then
        self.bind:AddModifier("LifeForceGathering")
    elseif progress < 0.7 then
        self.bind:RemoveModifier("LifeForceGathering")
        self.bind:AddModifier("SoulChanneling")
    else
        self.bind:RemoveModifier("SoulChanneling")
        self.bind:AddModifier("LifeTransferring")
    end
end

-- 触发成功效果
function tbMagic:TriggerSuccessEffects(target)
    if not self.bind or not target then return end
    
    -- 添加成功特效
    self.bind:AddModifier("ResurrectionSuccess")
    target:AddModifier("Resurrected")
    
    -- 增加双方关系
    self:IncreaseRelationship(target)
    
    -- 触发复活事件
    self:TriggerResurrectionEvent(target)
end

-- 增加双方关系
function tbMagic:IncreaseRelationship(target)
    if self.bind and target then
        -- 目标对施法者极度感激
        local relationData = target.PropertyMgr.RelationData:GetRelationData(self.bind)
        if relationData then
            relationData.Value = math.min(100, relationData.Value + 50)  -- 大幅增加好感
        end
    end
end

-- 触发复活事件
function tbMagic:TriggerResurrectionEvent(target)
    -- 发送世界消息
    CS.XiaWorld.MessageMgr.Instance:AddChainEventMessage(
        18, -1, 
        string.format("传闻【%s】施展无上神通，成功复活了【%s】，此举震动修仙界！", 
        self.bind.Name, target.Name), 
        0, 0, nil, "重生神通", -1
    )
    
    -- 增加门派声望
    self:IncreaseSchoolReputation()
end

-- 增加门派声望
function tbMagic:IncreaseSchoolReputation()
    -- 这里可以添加增加门派声望的逻辑
    print(string.format("【%s】的门派因复活神通而声望大增！", self.bind.Name))
end

-- 显示复活开始信息
function tbMagic:ShowResurrectionStartMessage(target)
    if self.bind and target then
        world:ShowMsgBox(
            string.format("【%s】开始为【%s】施展重生神通，凝聚天地灵气，汇聚生命之力...", 
            self.bind.Name, target.Name),
            "重生神通开始"
        )
    end
end

-- 显示复活成功信息
function tbMagic:ShowResurrectionSuccessMessage(target)
    if self.bind and target then
        world:ShowMsgBox(
            string.format("重生神通施展成功！【%s】已成功复活【%s】！", 
            self.bind.Name, target.Name),
            "重生成功"
        )
    end
end

-- 显示复活失败信息
function tbMagic:ShowResurrectionFailedMessage()
    if self.bind then
        world:ShowMsgBox(
            string.format("【%s】的重生神通施展失败，受到法术反噬！", self.bind.Name),
            "重生失败"
        )
    end
end

-- 清理施法状态
function tbMagic:CleanupCastingState()
    if self.bind then
        self.bind:RemoveModifier("CastingMagic")
        self.bind:RemoveModifier("LifeForceGathering")
        self.bind:RemoveModifier("SoulChanneling")
        self.bind:RemoveModifier("LifeTransferring")
        self.bind:RemoveModifier("ResurrectionCasting")
    end
    
    local target = self:GetTargetNpc()
    if target then
        target:RemoveModifier("BeingResurrected")
        target:RemoveModifier("SoulGathering")
        target:RemoveModifier("BodyReforming")
        target:RemoveModifier("LifeReturning")
    end
end

-- 清理临时数据
function tbMagic:Cleanup()
    self.targetId = nil
    self.targetIsThing = false
    self.initialLingCost = 0
end

-- 存档数据
function tbMagic:OnGetSaveData()
    if self.targetId then
        return {
            targetId = self.targetId,
            targetIsThing = self.targetIsThing,
            initialLingCost = self.initialLingCost
        }
    end
    return nil
end

-- 读档数据
function tbMagic:OnLoadData(tbData, IDs, IsThing)
    if tbData then
        self.targetId = tbData.targetId
        self.targetIsThing = tbData.targetIsThing
        self.initialLingCost = tbData.initialLingCost or 0
    elseif IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修正索引从1开始
        self.targetIsThing = IsThing
        self.initialLingCost = 0
    end
end

-- 神通描述信息
function tbMagic:GetDescription()
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 15
    
    return {
        Name = "重生神通",
        Desc = "施展无上神通，复活已死亡的修仙者，凝聚其消散的魂魄，重铸其破损的肉身。",
        Effect = string.format("复活目标，恢复%d点生命值", MAGIC_CONFIG.REVIVE_HEALTH),
        CastTime = string.format("施法时间: %d秒", castTime),
        Requirement = "需要目标为游魂状态的非动物NPC"
    }
end

-- 获取神通消耗信息
function tbMagic:GetCostInfo()
    return {
        LingCost = string.format("初始%d灵力，持续每秒1000灵力", MAGIC_CONFIG.LING_COST),
        Requirement = "需要游魂状态的目标，且死亡时间不超过30天"
    }
end