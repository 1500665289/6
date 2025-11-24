-- 变幻神通 - 触发故事线变化
local tbTable = GameMain:GetMod("MagicHelper")  -- 获取神通模块
local tbMagic = tbTable:GetMagic("SQBianHuan")    -- 创建新的变幻神通

-- 注意：
-- 神通脚本运行时有三个固定变量：
-- self.bind  - 执行神通的npcObj
-- self.magic  - 当前神通的数据（XML定义）
-- self.targetId - 目标ID（可选）

-- 常量定义
local MAGIC_CONFIG = {
    CAST_TIME = "Param1",           -- 施法时间参数名
    MIN_LING_REQUIREMENT = 3000,    -- 最低灵力需求
    LING_COST = 1000,               -- 施法灵力消耗
    STORY_NAME = "Story_SQBianHuan" -- 触发的故事名称
}

-- 初始化
function tbMagic:Init()
    self.targetId = nil
    self.targetIsThing = false
    self.initialLingCost = 0
    self.storyTriggered = false
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
    
    -- 检查施法者是否有触发故事的能力
    local canTriggerStory = not npc:HasModifier("CannotTriggerStory")
    
    -- 检查故事是否已触发过（可选，防止重复触发）
    local storyNotTriggered = not npc:HasModifier("StoryTriggered_" .. MAGIC_CONFIG.STORY_NAME)
    
    return isAlive and canAct and hasEnoughLing and canTriggerStory and storyNotTriggered
end

-- 目标合法性检查
-- key: 目标键值
-- t: 目标类型
function tbMagic:TargetCheck(key, t)
    -- 基础检查
    if not key or not t then
        return false
    end
    
    -- 检查目标是否可被变幻影响
    local canBeTransformed = self:CanBeTransformed(t)
    
    -- 检查目标是否处于可变化状态
    local isTransformable = not t:HasModifier("CannotBeTransformed")
    
    return canBeTransformed and isTransformable
end

-- 检查目标是否可被变幻影响
function tbMagic:CanBeTransformed(target)
    if not target then return false end
    
    -- 可以添加特定类型的检查
    -- 例如：只允许对NPC、特定物品等使用变幻神通
    local isNpc = target.ThingType == CS.XiaWorld.g_emThingType.Npc
    local isItem = target.ThingType == CS.XiaWorld.g_emThingType.Item
    local isBuilding = target.ThingType == CS.XiaWorld.g_emThingType.Building
    
    -- 允许对NPC、物品、建筑使用变幻神通
    return isNpc or isItem or isBuilding
end

-- 开始施展神通
function tbMagic:MagicEnter(IDs, IsThing)
    -- 记录目标信息（如果有目标）
    if IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修正索引从1开始
        self.targetIsThing = IsThing
        
        print(string.format("【%s】开始施展变幻神通，目标ID: %d", 
              self.bind and self.bind.Name or "未知NPC", self.targetId))
    else
        print(string.format("【%s】开始施展变幻神通（无目标）", 
              self.bind and self.bind.Name or "未知NPC"))
    end
    
    -- 触发施法开始效果
    if self.bind then
        -- 添加施法状态
        self.bind:AddModifier("CastingMagic")
        self.bind:AddModifier("TransformationCasting")
        
        -- 如果有目标，为目标添加状态
        local target = self:GetTarget()
        if target then
            target:AddModifier("BeingTransformed")
        end
        
        -- 消耗初始灵力
        self.initialLingCost = self:ConsumeInitialResources()
        
        -- 显示开始信息
        self:ShowTransformationStartMessage(target)
        
        -- 触发变幻开始特效
        self:TriggerTransformationStartEffects(target)
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
    
    -- 变幻进度效果
    self:UpdateTransformationProgress(progress)
    
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
    -- 触发故事线
    local success = self:TriggerStory()
    
    if success then
        self:TriggerSuccessEffects()
        self:ShowTransformationSuccessMessage()
        
        -- 标记故事已触发
        self.storyTriggered = true
    else
        print("错误：故事触发失败")
        self:OnMagicFailed()
    end
end

-- 触发故事线
function tbMagic:TriggerStory()
    if not self.bind then
        print("错误：施法者不存在，无法触发故事")
        return false
    end
    
    -- 安全检查
    if not self.bind.LuaHelper then
        print("错误：施法者没有LuaHelper组件")
        return false
    end
    
    -- 触发故事
    local success, result = pcall(function()
        return self.bind.LuaHelper:TriggerStory(MAGIC_CONFIG.STORY_NAME)
    end)
    
    if not success then
        print("错误：触发故事失败 - " .. tostring(result))
        return false
    end
    
    print(string.format("【%s】成功触发故事线：%s", 
          self.bind.Name, MAGIC_CONFIG.STORY_NAME))
    
    return true
end

-- 施法失败处理
function tbMagic:OnMagicFailed()
    if self.bind then
        -- 添加失败反噬效果
        self.bind:AddModifier("TransformationBackfire")
        
        -- 部分灵力消耗
        local partialCost = math.floor(self.initialLingCost * 0.5)
        if self.bind.LingV > partialCost then
            self.bind.LingV = self.bind.LingV - partialCost
        end
        
        print(string.format("【%s】变幻神通施展失败", self.bind.Name))
        
        -- 显示失败信息
        self:ShowTransformationFailedMessage()
        
        -- 触发失败效果
        self:TriggerFailureEffects()
    end
end

-- 获取目标
function tbMagic:GetTarget()
    if not self.targetId then return nil end
    
    local target = ThingMgr:FindThingByID(self.targetId)
    return target
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
    
    -- 检查目标状态（如果有目标）
    local target = self:GetTarget()
    if target and not target.IsAlive then
        return false
    end
    
    -- 检查故事是否已触发过（防止重复触发）
    if self.bind:HasModifier("StoryTriggered_" .. MAGIC_CONFIG.STORY_NAME) then
        print("警告：故事已触发过，无法重复触发")
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
    
    local costPerSecond = 300  -- 每秒消耗灵力
    local cost = costPerSecond * dt
    
    if self.bind.LingV > cost then
        self.bind.LingV = self.bind.LingV - cost
    else
        -- 灵力不足，施法失败
        self.bind.LingV = 0
    end
end

-- 触发变幻开始特效
function tbMagic:TriggerTransformationStartEffects(target)
    if not self.bind then return end
    
    -- 施法者特效
    self.bind:AddModifier("MagicAura")
    
    -- 目标特效（如果有目标）
    if target then
        target:AddModifier("TransformationAura")
    end
    
    -- 可以在这里添加音效、粒子效果等
    print("变幻神通开始施展，周围空间开始扭曲...")
end

-- 更新变幻进度效果
function tbMagic:UpdateTransformationProgress(progress)
    local target = self:GetTarget()
    
    -- 根据进度更新视觉效果
    if progress < 0.3 then
        -- 初期：能量聚集
        self.bind:AddModifier("EnergyGathering")
        if target then
            target:AddModifier("EnergySurrounding")
        end
    elseif progress < 0.7 then
        -- 中期：形态变化
        self.bind:RemoveModifier("EnergyGathering")
        self.bind:AddModifier("FormChanging")
        if target then
            target:RemoveModifier("EnergySurrounding")
            target:AddModifier("FormShifting")
        end
    else
        -- 后期：稳定成型
        self.bind:RemoveModifier("FormChanging")
        self.bind:AddModifier("FormStabilizing")
        if target then
            target:RemoveModifier("FormShifting")
            target:AddModifier("FormStabilized")
        end
    end
end

-- 更新施法效果
function tbMagic:UpdateCastingEffects(progress)
    if not self.bind then return end
    
    -- 根据进度更新特效
    if progress < 0.3 then
        self.bind:AddModifier("TransformationGathering")
    elseif progress < 0.7 then
        self.bind:RemoveModifier("TransformationGathering")
        self.bind:AddModifier("TransformationChanneling")
    else
        self.bind:RemoveModifier("TransformationChanneling")
        self.bind:AddModifier("TransformationFinishing")
    end
end

-- 触发成功效果
function tbMagic:TriggerSuccessEffects()
    if not self.bind then return end
    
    -- 添加成功特效
    self.bind:AddModifier("TransformationSuccess")
    
    -- 目标成功效果
    local target = self:GetTarget()
    if target then
        target:AddModifier("TransformationComplete")
    end
    
    -- 标记故事已触发
    self.bind:AddModifier("StoryTriggered_" .. MAGIC_CONFIG.STORY_NAME)
    
    -- 触发世界变化
    self:TriggerWorldChanges()
end

-- 触发世界变化
function tbMagic:TriggerWorldChanges()
    -- 这里可以添加触发故事后的世界变化
    -- 例如：改变天气、生成NPC、修改地形等
    
    print("变幻神通成功施展，世界线开始变化...")
    
    -- 发送世界消息
    CS.XiaWorld.MessageMgr.Instance:AddChainEventMessage(
        18, -1, 
        string.format("传闻【%s】施展无上变幻神通，引发了天地异变，世界线开始动荡！", 
        self.bind.Name), 
        0, 0, nil, "变幻神通", -1
    )
end

-- 触发失败效果
function tbMagic:TriggerFailureEffects()
    -- 触发失败特效
    if self.bind then
        self.bind:AddModifier("MagicBackfire")
    end
    
    local target = self:GetTarget()
    if target then
        target:AddModifier("TransformationFailed")
    end
end

-- 显示变幻开始信息
function tbMagic:ShowTransformationStartMessage(target)
    if self.bind then
        local targetName = target and target.Name or "无特定目标"
        world:ShowMsgBox(
            string.format("【%s】开始施展变幻神通，目标：%s", 
            self.bind.Name, targetName),
            "变幻神通开始"
        )
    end
end

-- 显示变幻成功信息
function tbMagic:ShowTransformationSuccessMessage()
    if self.bind then
        world:ShowMsgBox(
            string.format("变幻神通施展成功！【%s】成功改变了世界线！", 
            self.bind.Name),
            "变幻成功"
        )
    end
end

-- 显示变幻失败信息
function tbMagic:ShowTransformationFailedMessage()
    if self.bind then
        world:ShowMsgBox(
            string.format("【%s】的变幻神通施展失败，时空发生紊乱！", 
            self.bind.Name),
            "变幻失败"
        )
    end
end

-- 清理施法状态
function tbMagic:CleanupCastingState()
    if self.bind then
        self.bind:RemoveModifier("CastingMagic")
        self.bind:RemoveModifier("TransformationCasting")
        self.bind:RemoveModifier("TransformationGathering")
        self.bind:RemoveModifier("TransformationChanneling")
        self.bind:RemoveModifier("TransformationFinishing")
        self.bind:RemoveModifier("MagicAura")
        self.bind:RemoveModifier("EnergyGathering")
        self.bind:RemoveModifier("FormChanging")
        self.bind:RemoveModifier("FormStabilizing")
    end
    
    local target = self:GetTarget()
    if target then
        target:RemoveModifier("BeingTransformed")
        target:RemoveModifier("TransformationAura")
        target:RemoveModifier("EnergySurrounding")
        target:RemoveModifier("FormShifting")
        target:RemoveModifier("FormStabilized")
    end
end

-- 清理临时数据
function tbMagic:Cleanup()
    self.targetId = nil
    self.targetIsThing = false
    self.initialLingCost = 0
    -- 注意：不清理storyTriggered，用于存档
end

-- 存档数据
function tbMagic:OnGetSaveData()
    return {
        targetId = self.targetId,
        targetIsThing = self.targetIsThing,
        initialLingCost = self.initialLingCost,
        storyTriggered = self.storyTriggered
    }
end

-- 读档数据
function tbMagic:OnLoadData(tbData, IDs, IsThing)
    if tbData then
        self.targetId = tbData.targetId
        self.targetIsThing = tbData.targetIsThing
        self.initialLingCost = tbData.initialLingCost or 0
        self.storyTriggered = tbData.storyTriggered or false
    elseif IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修正索引从1开始
        self.targetIsThing = IsThing
        self.initialLingCost = 0
        self.storyTriggered = false
    end
end

-- 神通描述信息
function tbMagic:GetDescription()
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 10
    
    return {
        Name = "变幻神通",
        Desc = "施展无上神通，改变世界线，触发命运转折，引发天地异变。",
        Effect = string.format("触发故事线：%s", MAGIC_CONFIG.STORY_NAME),
        CastTime = string.format("施法时间: %d秒", castTime),
        Requirement = "需要足够的灵力且故事未触发过"
    }
end

-- 获取神通消耗信息
function tbMagic:GetCostInfo()
    return {
        LingCost = string.format("初始%d灵力，持续每秒300灵力", MAGIC_CONFIG.LING_COST),
        Requirement = "需要故事未触发过"
    }
end

-- 检查故事是否已触发
function tbMagic:IsStoryTriggered()
    return self.storyTriggered
end

-- 重置故事触发状态（用于特殊情况下重新触发）
function tbMagic:ResetStoryTrigger()
    self.storyTriggered = false
    if self.bind then
        self.bind:RemoveModifier("StoryTriggered_" .. MAGIC_CONFIG.STORY_NAME)
    end
    print("故事触发状态已重置")
end