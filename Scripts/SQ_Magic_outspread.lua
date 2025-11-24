-- 蛟龙技能反噬 - 神通扩展
local tbTable = GameMain:GetMod("MagicHelper");
local tbMagic = tbTable:GetMagic("SQoutspread");

-- 常量定义
local MAGIC_CONFIG = {
    MIN_LING_REQUIREMENT = 5000,    -- 最低灵力需求
    LING_COST = 2000,               -- 施法灵力消耗
    DEFAULT_DURATION = 300,          -- 默认持续时间（秒）
    DEFAULT_EFFECT_ID = 1001        -- 默认特效ID
}

function tbMagic:Init()
    self.initialLingCost = 0
    self.isCasting = false
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
    
    -- 检查施法者是否有施展扩展神通的能力
    local canOutspread = not npc:HasModifier("CannotOutspread")
    
    return isAlive and canAct and hasEnoughLing and canOutspread
end

-- 目标合法性检查
function tbMagic:TargetCheck(key, t)
    -- 这个神通可能不需要特定目标，或者有特殊的目标要求
    -- 根据实际需求实现
    return true
end

-- 开始施展神通
function tbMagic:MagicEnter(IDs, IsThing)
    -- 记录目标信息（如果有）
    if IDs and #IDs > 0 then
        self.targetId = IDs[1]
        self.target = ThingMgr:FindThingByID(self.targetId)
    end
    
    -- 触发施法开始效果
    if self.bind then
        -- 添加施法状态
        self.bind:AddModifier("CastingMagic")
        self.bind:AddModifier("OutspreadCasting")
        
        -- 消耗初始灵力
        self.initialLingCost = self:ConsumeInitialResources()
        
        -- 显示开始信息
        self:ShowOutspreadStartMessage()
        
        self.isCasting = true
    end
    
    return true
end

-- 神通施展过程
function tbMagic:MagicStep(dt, duration)
    -- 返回值: 0继续 1成功并结束 -1失败并结束		
    
    -- 安全检查
    if not self:ValidateCastingState() then
        return -1
    end
    
    local castTime = self.magic.Param1 or 5  -- 默认5秒施法时间
    local progress = math.min(duration / castTime, 1.0)
    
    -- 设置施法进度（UI显示）
    self:SetProgress(progress)
    
    -- 施法过程中的效果
    self:UpdateCastingEffects(progress)
    
    -- 持续消耗灵力
    self:ConsumeResourcesOverTime(dt, progress)
    
    -- 检查施法是否完成
    if duration >= castTime then
        return 1
    end
    
    return 0
end

function tbMagic:MagicLeave(success)	
    -- 清理施法状态
    self:CleanupCastingState()
    
    if success ~= true then
        self:OnMagicFailed()
        return
    end	
    
    self:OnMagicSuccess()
end

-- 施法成功处理
function tbMagic:OnMagicSuccess()
    -- 安全检查
    if not self.bind or not self.bind.JobEngine then
        print("错误：施法者或工作引擎不存在")
        self:OnMagicFailed()
        return
    end
    
    -- 获取参数（修复拼写错误）
    local regionname = self.magic.sParam1 or "default_region"  -- 修复：worldparam1 → sParam1
    local sec = self.magic.Param1 or MAGIC_CONFIG.DEFAULT_DURATION
    local mapstory = self.magic.sParam2 or "default_story"
    local desc = self.magic.sParam3 or "神通扩展效果"
    local effectid = self.magic.Param2 or MAGIC_CONFIG.DEFAULT_EFFECT_ID
    
    print(string.format("【%s】施展蛟龙反噬神通，参数：区域=%s, 时长=%d秒, 故事=%s", 
          self.bind.Name, regionname, sec, mapstory))
    
    -- 安全设置下一个工作
    local success, result = pcall(function()
        return self.bind.JobEngine:SetNextJob("JobLcOutspread", regionname, sec, mapstory, desc, effectid)
    end)
    
    if not success then
        print("错误：设置扩展工作失败 - " .. tostring(result))
        self:OnMagicFailed()
        return
    end
    
    -- 触发成功效果
    self:TriggerSuccessEffects()
    
    -- 显示成功信息
    self:ShowOutspreadSuccessMessage(regionname, sec)
    
    print(string.format("【%s】成功施展蛟龙反噬神通，开始扩展效果", self.bind.Name))
end

-- 施法失败处理
function tbMagic:OnMagicFailed()
    if self.bind then
        -- 添加失败反噬效果
        self.bind:AddModifier("OutspreadBackfire")
        
        -- 部分灵力消耗
        local partialCost = math.floor(self.initialLingCost * 0.3)
        if self.bind.LingV > partialCost then
            self.bind.LingV = self.bind.LingV - partialCost
        end
        
        print(string.format("【%s】蛟龙反噬神通施展失败", self.bind.Name))
        
        -- 显示失败信息
        self:ShowOutspreadFailedMessage()
    end
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
    
    -- 检查工作引擎是否存在
    if not self.bind.JobEngine then
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
    
    local costPerSecond = 800  -- 每秒消耗灵力
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
        self.bind:AddModifier("OutspreadGathering")
    elseif progress < 0.7 then
        self.bind:RemoveModifier("OutspreadGathering")
        self.bind:AddModifier("OutspreadChanneling")
    else
        self.bind:RemoveModifier("OutspreadChanneling")
        self.bind:AddModifier("OutspreadFinishing")
    end
end

-- 触发成功效果
function tbMagic:TriggerSuccessEffects()
    if not self.bind then return end
    
    -- 添加成功特效
    self.bind:AddModifier("OutspreadSuccess")
    
    -- 触发蛟龙反噬特效
    self.bind:AddModifier("JiaoLongCounterattack")
    
    -- 发送世界消息
    self:SendWorldMessage()
end

-- 发送世界消息
function tbMagic:SendWorldMessage()
    if not self.bind then return end
    
    CS.XiaWorld.MessageMgr.Instance:AddChainEventMessage(
        18, -1, 
        string.format("传闻【%s】施展蛟龙反噬神通，天地灵气为之震荡，神通之力开始扩展！", 
        self.bind.Name), 
        0, 0, nil, "蛟龙反噬", -1
    )
end

-- 显示扩展开始信息
function tbMagic:ShowOutspreadStartMessage()
    if self.bind then
        world:ShowMsgBox(
            string.format("【%s】开始施展蛟龙反噬神通，凝聚天地灵气...", 
            self.bind.Name),
            "蛟龙反噬开始"
        )
    end
end

-- 显示扩展成功信息
function tbMagic:ShowOutspreadSuccessMessage(regionname, duration)
    if self.bind then
        world:ShowMsgBox(
            string.format("蛟龙反噬神通施展成功！将在【%s】区域持续%d秒", 
            regionname, duration),
            "神通扩展成功"
        )
    end
end

-- 显示扩展失败信息
function tbMagic:ShowOutspreadFailedMessage()
    if self.bind then
        world:ShowMsgBox(
            string.format("【%s】的蛟龙反噬神通施展失败，受到龙气反噬！", 
            self.bind.Name),
            "神通扩展失败"
        )
    end
end

-- 清理施法状态
function tbMagic:CleanupCastingState()
    if self.bind then
        self.bind:RemoveModifier("CastingMagic")
        self.bind:RemoveModifier("OutspreadCasting")
        self.bind:RemoveModifier("OutspreadGathering")
        self.bind:RemoveModifier("OutspreadChanneling")
        self.bind:RemoveModifier("OutspreadFinishing")
    end
    
    self.isCasting = false
end

-- 清理临时数据
function tbMagic:Cleanup()
    self.initialLingCost = 0
    self.targetId = nil
    self.target = nil
end

-- 存档数据
function tbMagic:OnGetSaveData()
    return {
        initialLingCost = self.initialLingCost,
        targetId = self.targetId,
        isCasting = self.isCasting
    }
end

-- 读档数据
function tbMagic:OnLoadData(tbData, IDs, IsThing)
    if tbData then
        self.initialLingCost = tbData.initialLingCost or 0
        self.targetId = tbData.targetId
        self.isCasting = tbData.isCasting or false
        
        if self.targetId then
            self.target = ThingMgr:FindThingByID(self.targetId)
        end
    end
end

-- 神通描述信息
function tbMagic:GetDescription()
    local duration = self.magic.Param1 or MAGIC_CONFIG.DEFAULT_DURATION
    local region = self.magic.sParam1 or "未知区域"
    
    return {
        Name = "蛟龙反噬神通",
        Desc = "施展无上神通，引动蛟龙之力，在指定区域产生持续的反噬效果。",
        Effect = string.format("在【%s】区域产生持续%d秒的扩展效果", region, duration),
        Requirement = "需要足够的灵力且具备蛟龙血脉"
    }
end

-- 获取神通消耗信息
function tbMagic:GetCostInfo()
    return {
        LingCost = string.format("初始%d灵力，持续每秒800灵力", MAGIC_CONFIG.LING_COST),
        Requirement = "需要具备施展扩展神通的能力"
    }
end