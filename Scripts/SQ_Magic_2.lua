-- 法宝洗练神通
local tbTable = GameMain:GetMod("MagicHelper")  -- 获取神通模块
local tbMagic = tbTable:GetMagic("SQXiLian")     -- 创建新的法宝洗练神通

-- 注意：
-- 神通脚本运行时有三个固定变量：
-- self.bind  - 执行神通的npcObj
-- self.magic  - 当前神通的数据（XML定义）
-- self.targetId - 目标法宝ID

-- 常量定义
local MAGIC_CONFIG = {
    CAST_TIME = "Param1",           -- 施法时间参数名
    GOD_COUNT_ADD = 36,             -- 增加的神数
    FABAO_CHECK = "IsFaBao"         -- 法宝检查属性
}

-- 初始化
function tbMagic:Init()
    self.targetId = nil
    self.targetIsThing = false
end

-- 神通是否可用检查
function tbMagic:EnableCheck(npc)
    if not npc then
        return false
    end
    
    -- 基础状态检查
    local isAlive = npc.IsAlive
    local canAct = not npc:HasModifier("CannotAct")
    local hasEnoughLing = npc.LingV and npc.LingV > 0
    
    return isAlive and canAct and hasEnoughLing
end

-- 目标合法性检查
-- key: 目标键值
-- t: 目标类型
function tbMagic:TargetCheck(key, t)
    -- 基础检查
    if not key or not t then
        return false
    end
    
    -- 检查是否为法宝
    local isFabao = t[MAGIC_CONFIG.FABAO_CHECK] == true
    
    -- 检查法宝是否可被洗练
    local canBeRefined = true
    if t.Fabao then
        -- 可以添加更多法宝状态检查，如是否已绑定、是否在冷却中等
        canBeRefined = t.Fabao:CanAddGodCount()
    end
    
    return isFabao and canBeRefined
end

-- 开始施展神通
function tbMagic:MagicEnter(IDs, IsThing)
    -- 记录目标信息
    if IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修正索引从1开始
        self.targetIsThing = IsThing
        
        print(string.format("【%s】开始对法宝进行洗练，目标ID: %d", 
              self.bind and self.bind.Name or "未知NPC", self.targetId))
    else
        print("警告：洗练神通未找到有效目标")
        return
    end
    
    -- 触发施法开始效果
    if self.bind then
        -- 添加施法状态
        self.bind:AddModifier("CastingMagic")
        
        -- 可以在这里添加施法特效
        self.bind:AddModifier("MagicRefining")
    end
    
    -- 消耗初始灵力
    self:ConsumeInitialLing()
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
    self:ConsumeLingOverTime(dt)
    
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
    local target = self:GetTargetFabao()
    
    if target and target.Fabao then
        -- 增加法宝神数
        target.Fabao:AddGodCount(MAGIC_CONFIG.GOD_COUNT_ADD)
        
        -- 触发成功效果
        self:TriggerSuccessEffects(target)
        
        print(string.format("【%s】成功洗练法宝【%s】，增加%d神数", 
              self.bind.Name, target.Name, MAGIC_CONFIG.GOD_COUNT_ADD))
    else
        print("错误：洗练目标不存在或非法")
    end
end

-- 施法失败处理
function tbMagic:OnMagicFailed()
    if self.bind then
        -- 添加失败反噬效果
        self.bind:AddModifier("MagicBackfire")
        
        print(string.format("【%s】法宝洗练失败", self.bind.Name))
        
        -- 可以在这里添加失败惩罚
        self:ApplyFailurePenalty()
    end
end

-- 获取目标法宝
function tbMagic:GetTargetFabao()
    if not self.targetId then return nil end
    
    local target = ThingMgr:FindThingByID(self.targetId)
    if target and target[MAGIC_CONFIG.FABAO_CHECK] == true then
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
    local target = self:GetTargetFabao()
    if not target then
        return false
    end
    
    return true
end

-- 消耗初始灵力
function tbMagic:ConsumeInitialLing()
    if not self.bind or not self.bind.LingV then return end
    
    local initialCost = 1000  -- 初始消耗灵力
    if self.bind.LingV >= initialCost then
        self.bind.LingV = self.bind.LingV - initialCost
    end
end

-- 持续消耗灵力
function tbMagic:ConsumeLingOverTime(dt)
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

-- 更新施法效果
function tbMagic:UpdateCastingEffects(progress)
    if not self.bind then return end
    
    -- 根据进度更新特效
    if progress < 0.3 then
        self.bind:AddModifier("MagicGathering")
    elseif progress < 0.7 then
        self.bind:RemoveModifier("MagicGathering")
        self.bind:AddModifier("MagicRefining")
    else
        self.bind:RemoveModifier("MagicRefining")
        self.bind:AddModifier("MagicFinishing")
    end
end

-- 触发成功效果
function tbMagic:TriggerSuccessEffects(target)
    if not self.bind or not target then return end
    
    -- 添加成功特效
    self.bind:AddModifier("MagicSuccess")
    target:AddModifier("FabaoEnhance")
    
    -- 可以在这里添加音效、粒子效果等
end

-- 应用失败惩罚
function tbMagic:ApplyFailurePenalty()
    if not self.bind then return end
    
    -- 灵力反噬
    local backlash = 500
    self.bind.LingV = math.max(0, self.bind.LingV - backlash)
    
    -- 短暂虚弱
    self.bind:AddModifier("Weakness", 30)  -- 30秒虚弱
end

-- 清理施法状态
function tbMagic:CleanupCastingState()
    if self.bind then
        self.bind:RemoveModifier("CastingMagic")
        self.bind:RemoveModifier("MagicGathering")
        self.bind:RemoveModifier("MagicRefining")
        self.bind:RemoveModifier("MagicFinishing")
    end
end

-- 清理临时数据
function tbMagic:Cleanup()
    self.targetId = nil
    self.targetIsThing = false
end

-- 存档数据
function tbMagic:OnGetSaveData()
    if self.targetId then
        return {
            targetId = self.targetId,
            targetIsThing = self.targetIsThing
        }
    end
    return nil
end

-- 读档数据
function tbMagic:OnLoadData(tbData, IDs, IsThing)
    if tbData then
        self.targetId = tbData.targetId
        self.targetIsThing = tbData.targetIsThing
    elseif IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修正索引从1开始
        self.targetIsThing = IsThing
    end
end

-- 神通描述信息
function tbMagic:GetDescription()
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 10
    
    return {
        Name = "法宝洗练神通",
        Desc = "对法宝进行洗练，提升法宝的神数和品质。",
        Effect = string.format("增加法宝%d神数", MAGIC_CONFIG.GOD_COUNT_ADD),
        CastTime = string.format("施法时间: %d秒", castTime),
        Requirement = "需要目标为法宝且施法者灵力充足"
    }
end

-- 获取神通消耗信息
function tbMagic:GetCostInfo()
    return {
        LingCost = "初始1000灵力，持续每秒500灵力",
        Requirement = "需要法宝目标"
    }
end