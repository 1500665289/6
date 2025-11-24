-- 诱淬神通 - 提升目标灵魂水晶品质
local tbTable = GameMain:GetMod("MagicHelper")  -- 获取神通模块
local tbMagic = tbTable:GetMagic("SQYouCui")     -- 创建新的诱淬神通

-- 注意：
-- 神通脚本运行时有三个固定变量：
-- self.bind  - 执行神通的npcObj
-- self.magic  - 当前神通的数据（XML定义）
-- self.targetId - 目标ID

-- 常量定义
local MAGIC_CONFIG = {
    CAST_TIME = "Param1",           -- 施法时间参数名
    MIN_LING_REQUIREMENT = 5000,    -- 最低灵力需求
    LING_COST = 2000,               -- 施法灵力消耗
    MAX_RATE = 12,                  -- 最大品质等级
    BASE_POWER_UP = 1               -- 基础提升等级
}

-- 初始化
function tbMagic:Init()
    self.targetId = nil
    self.targetIsThing = false
    self.initialLingCost = 0
    self.targetRate = 0
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
    
    -- 检查施法者是否有淬炼能力
    local canRefine = not npc:HasModifier("CannotRefineSoul")
    
    return isAlive and canAct and hasEnoughLing and canRefine
end

-- 目标合法性检查
-- key: 目标键值
-- t: 目标类型
function tbMagic:TargetCheck(key, t)
    -- 基础检查
    if not key or not t then
        return false
    end
    
    -- 检查目标是否可被淬炼
    local canBeRefined = self:CanBeRefined(t)
    
    -- 检查品质是否已达到上限
    local isNotMaxRate = t.Rate and t.Rate < MAGIC_CONFIG.MAX_RATE
    
    -- 检查目标是否适合淬炼
    local isSuitableTarget = self:IsSuitableTarget(t)
    
    return canBeRefined and isNotMaxRate and isSuitableTarget
end

-- 检查目标是否可被淬炼
function tbMagic:CanBeRefined(target)
    if not target then return false end
    
    -- 检查目标是否有Rate属性
    local hasRate = target.Rate ~= nil
    
    -- 检查目标是否有SoulCrystalYouPowerUp方法
    local hasPowerUpMethod = target.SoulCrystalYouPowerUp ~= nil
    
    -- 检查目标是否处于可淬炼状态
    local isRefinable = not target:HasModifier("CannotBeRefined")
    
    return hasRate and hasPowerUpMethod and isRefinable
end

-- 检查目标是否适合淬炼
function tbMagic:IsSuitableTarget(target)
    if not target then return false end
    
    -- 排除特定类型的物品
    local isNotForbiddenType = true
    
    -- 可以添加更多特定检查
    -- 例如：检查是否为灵魂水晶、法宝等特定类型
    
    return isNotForbiddenType
end

-- 开始施展神通
function tbMagic:MagicEnter(IDs, IsThing)
    -- 记录目标信息
    if IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修正索引从1开始
        self.targetIsThing = IsThing
        
        print(string.format("【%s】开始施展诱淬神通，目标ID: %d", 
              self.bind and self.bind.Name or "未知NPC", self.targetId))
    else
        print("警告：诱淬神通未找到有效目标")
        return false
    end
    
    -- 验证目标有效性
    local target = self:GetTarget()
    if not target then
        print("错误：目标不存在或无效")
        return false
    end
    
    -- 记录目标当前品质
    self.targetRate = target.Rate or 0
    
    -- 检查品质是否可提升
    if self.targetRate >= MAGIC_CONFIG.MAX_RATE then
        print(string.format("错误：目标品质已达上限(%d)，无法继续淬炼", MAGIC_CONFIG.MAX_RATE))
        return false
    end
    
    -- 触发施法开始效果
    if self.bind then
        -- 添加施法状态
        self.bind:AddModifier("CastingMagic")
        self.bind:AddModifier("SoulRefining")
        
        -- 添加目标状态
        target:AddModifier("BeingRefined")
        
        -- 消耗初始灵力
        self.initialLingCost = self:ConsumeInitialResources()
        
        -- 显示开始信息
        self:ShowRefinementStartMessage(target)
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
    
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 8  -- 默认8秒
    local progress = math.min(duration / castTime, 1.0)
    
    -- 设置施法进度（UI显示）
    self:SetProgress(progress)
    
    -- 施法过程中的效果
    self:UpdateCastingEffects(progress)
    
    -- 持续消耗灵力
    self:ConsumeResourcesOverTime(dt, progress)
    
    -- 淬炼进度效果
    self:UpdateRefinementProgress(progress)
    
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
    local target = self:GetTarget()
    
    if target then
        -- 执行淬炼
        local success = self:PerformRefinement(target)
        
        if success then
            self:TriggerSuccessEffects(target)
            self:ShowRefinementSuccessMessage(target)
        else
            print("错误：淬炼过程失败")
            self:OnMagicFailed()
        end
    else
        print("错误：淬炼目标不存在")
        self:OnMagicFailed()
    end
end

-- 执行淬炼逻辑
function tbMagic:PerformRefinement(target)
    if not target then return false end
    
    -- 计算提升等级
    local currentRate = target.Rate or 0
    local rateDifference = MAGIC_CONFIG.MAX_RATE - currentRate
    local powerUpAmount = math.min(MAGIC_CONFIG.BASE_POWER_UP, rateDifference)
    
    if powerUpAmount <= 0 then
        print("错误：目标品质已达上限，无法继续淬炼")
        return false
    end
    
    -- 执行淬炼
    local success, result = pcall(function()
        return target:SoulCrystalYouPowerUp(0, 1, powerUpAmount)
    end)
    
    if not success then
        print("错误：淬炼方法调用失败 - " .. tostring(result))
        return false
    end
    
    -- 记录淬炼结果
    self.oldRate = currentRate
    self.newRate = currentRate + powerUpAmount
    
    return true
end

-- 施法失败处理
function tbMagic:OnMagicFailed()
    if self.bind then
        -- 添加失败反噬效果
        self.bind:AddModifier("RefinementBackfire")
        
        -- 部分灵力消耗
        local partialCost = math.floor(self.initialLingCost * 0.3)
        if self.bind.LingV > partialCost then
            self.bind.LingV = self.bind.LingV - partialCost
        end
        
        print(string.format("【%s】诱淬神通施展失败", self.bind.Name))
        
        -- 显示失败信息
        self:ShowRefinementFailedMessage()
    end
end

-- 获取目标
function tbMagic:GetTarget()
    if not self.targetId then return nil end
    
    local target = ThingMgr:FindThingByID(self.targetId)
    if target then
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
    local target = self:GetTarget()
    if not target then
        return false
    end
    
    -- 检查目标是否仍可被淬炼
    if not self:CanBeRefined(target) then
        return false
    end
    
    -- 检查目标品质是否已满
    if target.Rate and target.Rate >= MAGIC_CONFIG.MAX_RATE then
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
    
    local costPerSecond = 500  -- 每秒消耗灵力
    local cost = costPerSecond * dt
    
    if self.bind.LingV > cost then
        self.bind.LingV = self.bind.LingV - cost
    else
        -- 灵力不足，施法失败
        self.bind.LingV = 0
    end
end

-- 更新淬炼进度效果
function tbMagic:UpdateRefinementProgress(progress)
    local target = self:GetTarget()
    if not target then return end
    
    -- 根据进度更新视觉效果
    if progress < 0.3 then
        target:AddModifier("SoulEnergyGathering")
    elseif progress < 0.7 then
        target:RemoveModifier("SoulEnergyGathering")
        target:AddModifier("SoulPurifying")
    else
        target:RemoveModifier("SoulPurifying")
        target:AddModifier("SoulEmpowering")
    end
end

-- 更新施法效果
function tbMagic:UpdateCastingEffects(progress)
    if not self.bind then return end
    
    -- 根据进度更新特效
    if progress < 0.3 then
        self.bind:AddModifier("RefinementGathering")
    elseif progress < 0.7 then
        self.bind:RemoveModifier("RefinementGathering")
        self.bind:AddModifier("RefinementChanneling")
    else
        self.bind:RemoveModifier("RefinementChanneling")
        self.bind:AddModifier("RefinementFinishing")
    end
end

-- 触发成功效果
function tbMagic:TriggerSuccessEffects(target)
    if not self.bind or not target then return end
    
    -- 添加成功特效
    self.bind:AddModifier("RefinementSuccess")
    target:AddModifier("SoulEnhanced")
    
    -- 显示品质提升信息
    self:ShowQualityImprovementMessage(target)
    
    -- 增加熟练度
    self:IncreaseProficiency()
end

-- 显示品质提升信息
function tbMagic:ShowQualityImprovementMessage(target)
    if self.oldRate and self.newRate then
        print(string.format("【%s】的品质从 %d 提升到 %d", 
              target.Name, self.oldRate, self.newRate))
        
        -- 显示世界消息
        CS.XiaWorld.MessageMgr.Instance:AddChainEventMessage(
            18, -1, 
            string.format("传闻【%s】施展诱淬神通，成功将【%s】的品质从 %d 提升到 %d！", 
            self.bind.Name, target.Name, self.oldRate, self.newRate), 
            0, 0, nil, "诱淬神通", -1
        )
    end
end

-- 增加熟练度
function tbMagic:IncreaseProficiency()
    if self.bind then
        -- 增加淬炼熟练度
        self.bind:AddModifier("RefinementProficiency")
        
        -- 可以在这里添加更多的熟练度系统逻辑
        print(string.format("【%s】的淬炼熟练度提升了", self.bind.Name))
    end
end

-- 显示淬炼开始信息
function tbMagic:ShowRefinementStartMessage(target)
    if self.bind and target then
        local currentRate = target.Rate or 0
        world:ShowMsgBox(
            string.format("【%s】开始为【%s】施展诱淬神通，当前品质：%d/%d", 
            self.bind.Name, target.Name, currentRate, MAGIC_CONFIG.MAX_RATE),
            "诱淬神通开始"
        )
    end
end

-- 显示淬炼成功信息
function tbMagic:ShowRefinementSuccessMessage(target)
    if self.bind and target and self.newRate then
        world:ShowMsgBox(
            string.format("诱淬神通施展成功！【%s】的品质提升到 %d！", 
            target.Name, self.newRate),
            "淬炼成功"
        )
    end
end

-- 显示淬炼失败信息
function tbMagic:ShowRefinementFailedMessage()
    if self.bind then
        world:ShowMsgBox(
            string.format("【%s】的诱淬神通施展失败，受到法术反噬！", self.bind.Name),
            "淬炼失败"
        )
    end
end

-- 清理施法状态
function tbMagic:CleanupCastingState()
    if self.bind then
        self.bind:RemoveModifier("CastingMagic")
        self.bind:RemoveModifier("RefinementGathering")
        self.bind:RemoveModifier("RefinementChanneling")
        self.bind:RemoveModifier("RefinementFinishing")
        self.bind:RemoveModifier("SoulRefining")
    end
    
    local target = self:GetTarget()
    if target then
        target:RemoveModifier("BeingRefined")
        target:RemoveModifier("SoulEnergyGathering")
        target:RemoveModifier("SoulPurifying")
        target:RemoveModifier("SoulEmpowering")
    end
end

-- 清理临时数据
function tbMagic:Cleanup()
    self.targetId = nil
    self.targetIsThing = false
    self.initialLingCost = 0
    self.targetRate = 0
    self.oldRate = nil
    self.newRate = nil
end

-- 存档数据
function tbMagic:OnGetSaveData()
    if self.targetId then
        return {
            targetId = self.targetId,
            targetIsThing = self.targetIsThing,
            initialLingCost = self.initialLingCost,
            targetRate = self.targetRate
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
        self.targetRate = tbData.targetRate or 0
    elseif IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修正索引从1开始
        self.targetIsThing = IsThing
        self.initialLingCost = 0
        self.targetRate = 0
    end
end

-- 神通描述信息
function tbMagic:GetDescription()
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 8
    
    return {
        Name = "诱淬神通",
        Desc = "施展精妙神通，诱使目标灵魂水晶提升品质，凝聚其内在能量，激发其潜在灵性。",
        Effect = string.format("提升目标品质1级（最高%d级）", MAGIC_CONFIG.MAX_RATE),
        CastTime = string.format("施法时间: %d秒", castTime),
        Requirement = "需要目标具有Rate属性且品质未达上限"
    }
end

-- 获取神通消耗信息
function tbMagic:GetCostInfo()
    return {
        LingCost = string.format("初始%d灵力，持续每秒500灵力", MAGIC_CONFIG.LING_COST),
        Requirement = "需要可淬炼的目标，且品质未达上限"
    }
end