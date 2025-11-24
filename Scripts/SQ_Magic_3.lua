-- 仙傀神通 - 为目标增加修为
local tbTable = GameMain:GetMod("MagicHelper")  -- 获取神通模块
local tbMagic = tbTable:GetMagic("SQXianKui")     -- 创建新的仙傀神通

-- 注意：
-- 神通脚本运行时有三个固定变量：
-- self.bind  - 执行神通的npcObj
-- self.magic  - 当前神通的数据（XML定义）
-- self.targetId - 目标NPC ID

-- 常量定义
local MAGIC_CONFIG = {
    CAST_TIME = "Param1",           -- 施法时间参数名
    PRACTICE_ADD = 1000000,         -- 增加的修为值
    THING_TYPE = CS.XiaWorld.g_emThingType,
    RACE_TYPE = CS.XiaWorld.g_emNpcRaceType
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
    local hasEnoughLing = npc.LingV and npc.LingV >= 5000  -- 最低灵力需求
    
    -- 检查施法者是否有足够的修为来传输
    local hasEnoughPractice = npc.PropertyMgr and 
                             npc.PropertyMgr.Practice and 
                             npc.PropertyMgr.Practice:GetTotalValue() >= MAGIC_CONFIG.PRACTICE_ADD
    
    return isAlive and canAct and hasEnoughLing and hasEnoughPractice
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
    
    -- 检查是否有修为系统
    local hasPracticeSystem = t.MaxLing and t.MaxLing > 1
    
    -- 检查目标是否存活且可接受修为
    local canReceivePractice = t.IsAlive and 
                             not t:HasModifier("CannotReceivePractice") and
                             t.PropertyMgr and 
                             t.PropertyMgr.Practice
    
    return isNpc and isNotAnimal and hasPracticeSystem and canReceivePractice
end

-- 开始施展神通
function tbMagic:MagicEnter(IDs, IsThing)
    -- 记录目标信息
    if IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修正索引从1开始
        self.targetIsThing = IsThing
        
        print(string.format("【%s】开始施展仙傀神通，目标ID: %d", 
              self.bind and self.bind.Name or "未知NPC", self.targetId))
    else
        print("警告：仙傀神通未找到有效目标")
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
        self.bind:AddModifier("PracticeTransferOut")
        
        -- 添加目标状态
        target:AddModifier("PracticeTransferIn")
        
        -- 消耗初始灵力
        self.initialLingCost = self:ConsumeInitialResources()
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
    
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 10  -- 默认10秒
    local progress = math.min(duration / castTime, 1.0)
    
    -- 设置施法进度（UI显示）
    self:SetProgress(progress)
    
    -- 施法过程中的效果
    self:UpdateCastingEffects(progress)
    
    -- 持续消耗灵力
    self:ConsumeResourcesOverTime(dt, progress)
    
    -- 传输修为效果（渐进式）
    self:TransferPracticeEffect(progress)
    
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
    
    if target and target.PropertyMgr and target.PropertyMgr.Practice then
        -- 增加目标修为
        target.PropertyMgr.Practice:AddPractice(MAGIC_CONFIG.PRACTICE_ADD)
        
        -- 减少施法者修为
        if self.bind and self.bind.PropertyMgr and self.bind.PropertyMgr.Practice then
            self.bind.PropertyMgr.Practice:AddPractice(-MAGIC_CONFIG.PRACTICE_ADD)
        end
        
        -- 触发成功效果
        self:TriggerSuccessEffects(target)
        
        print(string.format("【%s】成功为【%s】传输%d点修为", 
              self.bind.Name, target.Name, MAGIC_CONFIG.PRACTICE_ADD))
    else
        print("错误：传输修为失败，目标不存在")
        self:OnMagicFailed()
    end
end

-- 施法失败处理
function tbMagic:OnMagicFailed()
    if self.bind then
        -- 添加失败反噬效果
        self.bind:AddModifier("PracticeBackfire")
        
        -- 部分灵力消耗
        local partialCost = math.floor(self.initialLingCost * 0.3)
        if self.bind.LingV > partialCost then
            self.bind.LingV = self.bind.LingV - partialCost
        end
        
        print(string.format("【%s】仙傀神通施展失败", self.bind.Name))
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
    
    -- 检查目标是否存在
    local target = self:GetTargetNpc()
    if not target or not target.IsAlive then
        return false
    end
    
    -- 检查施法者是否还有足够的修为
    if self.bind.PropertyMgr and self.bind.PropertyMgr.Practice then
        local currentPractice = self.bind.PropertyMgr.Practice:GetTotalValue()
        if currentPractice < MAGIC_CONFIG.PRACTICE_ADD then
            return false
        end
    end
    
    return true
end

-- 消耗初始资源
function tbMagic:ConsumeInitialResources()
    if not self.bind or not self.bind.LingV then return 0 end
    
    local initialCost = 5000  -- 初始消耗灵力
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

-- 传输修为效果（渐进式）
function tbMagic:TransferPracticeEffect(progress)
    -- 可以在施法过程中添加视觉反馈
    -- 例如：修为传输的光效、粒子效果等
    if progress > 0.5 then
        local target = self:GetTargetNpc()
        if target then
            target:AddModifier("PracticeReceiving")
        end
    end
end

-- 更新施法效果
function tbMagic:UpdateCastingEffects(progress)
    if not self.bind then return end
    
    -- 根据进度更新特效
    if progress < 0.3 then
        self.bind:AddModifier("PracticeGathering")
    elseif progress < 0.7 then
        self.bind:RemoveModifier("PracticeGathering")
        self.bind:AddModifier("PracticeTransferring")
    else
        self.bind:RemoveModifier("PracticeTransferring")
        self.bind:AddModifier("PracticeFinishing")
    end
end

-- 触发成功效果
function tbMagic:TriggerSuccessEffects(target)
    if not self.bind or not target then return end
    
    -- 添加成功特效
    self.bind:AddModifier("PracticeSuccess")
    target:AddModifier("PracticeReceived")
    
    -- 增加双方好感度
    self:IncreaseFavorability(target)
    
    print(string.format("修为传输完成：%s → %s [+%d修为]", 
          self.bind.Name, target.Name, MAGIC_CONFIG.PRACTICE_ADD))
end

-- 增加双方好感度
function tbMagic:IncreaseFavorability(target)
    if self.bind and target then
        -- 增加施法者对目标的好感度
        local relationData = self.bind.PropertyMgr.RelationData:GetRelationData(target)
        if relationData then
            relationData.Value = math.min(100, relationData.Value + 10)
        end
        
        -- 增加目标对施法者的好感度
        local targetRelationData = target.PropertyMgr.RelationData:GetRelationData(self.bind)
        if targetRelationData then
            targetRelationData.Value = math.min(100, targetRelationData.Value + 15)
        end
    end
end

-- 清理施法状态
function tbMagic:CleanupCastingState()
    if self.bind then
        self.bind:RemoveModifier("CastingMagic")
        self.bind:RemoveModifier("PracticeGathering")
        self.bind:RemoveModifier("PracticeTransferring")
        self.bind:RemoveModifier("PracticeFinishing")
        self.bind:RemoveModifier("PracticeTransferOut")
    end
    
    local target = self:GetTargetNpc()
    if target then
        target:RemoveModifier("PracticeTransferIn")
        target:RemoveModifier("PracticeReceiving")
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
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 10
    
    return {
        Name = "仙傀神通",
        Desc = "将自身修为传输给其他修仙者，助其提升境界。",
        Effect = string.format("为目标增加%d点修为", MAGIC_CONFIG.PRACTICE_ADD),
        Cost = string.format("自身减少%d点修为", MAGIC_CONFIG.PRACTICE_ADD),
        CastTime = string.format("施法时间: %d秒", castTime),
        Requirement = "需要非动物NPC目标，且双方都需存活"
    }
end

-- 获取神通消耗信息
function tbMagic:GetCostInfo()
    return {
        PracticeCost = string.format("消耗%d点自身修为", MAGIC_CONFIG.PRACTICE_ADD),
        LingCost = "初始5000灵力，持续每秒1000灵力",
        Requirement = "需要非动物NPC目标"
    }
end