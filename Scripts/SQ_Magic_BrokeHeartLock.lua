local tbTable = GameMain:GetMod("MagicHelper");
local tbMagic = tbTable:GetMagic("SQBrokeHeartLock");

-- 常量定义
local MAGIC_CONFIG = {
    CAST_TIME = "Param1",           -- 施法时间参数名
    MIN_LING_REQUIREMENT = 2000,    -- 最低灵力需求
    LING_COST = 800,               -- 施法灵力消耗
    HEART_LOCK_VALUE = 1           -- 心锁值
}

function tbMagic:Init()
    self.targetId = nil
    self.target = nil
    self.initialLingCost = 0
    self.jianghuSeed = 0
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
    
    -- 检查施法者是否有施展心锁神通的能力
    local canBreakHeartLock = not npc:HasModifier("CannotBreakHeartLock")
    
    return isAlive and canAct and hasEnoughLing and canBreakHeartLock
end

function tbMagic:TargetCheck(k, t)
    -- 添加空值检查
    if not t then
        return false
    end
    
    -- 检查是否有江湖种子
    local hasJianghuSeed = t.JiangHuSeed and t.JiangHuSeed > 0
    
    -- 检查目标是否可被施加心锁
    local canBeLocked = not t:HasModifier("HeartLockImmune")
    
    -- 检查目标是否已有心锁
    local hasHeartLock = self:HasHeartLock(t)
    
    return hasJianghuSeed and canBeLocked and not hasHeartLock
end

-- 检查目标是否已有心锁
function tbMagic:HasHeartLock(target)
    if not target or not target.JiangHuSeed then
        return false
    end
    
    -- 检查江湖数据中的心锁状态
    local data = JianghuMgr:GetKnowNpcData(target.JiangHuSeed)
    if data and data.hlock and data.hlock == MAGIC_CONFIG.HEART_LOCK_VALUE then
        return true
    end
    
    return false
end

function tbMagic:MagicEnter(IDs, IsThing)
    -- 记录目标信息
    if IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修复索引
        self.target = ThingMgr:FindThingByID(self.targetId)
        
        if self.target then
            -- 记录江湖种子
            self.jianghuSeed = self.target.JiangHuSeed or 0
            
            print(string.format("【%s】开始对【%s】施展心锁神通，江湖种子: %d", 
                  self.bind and self.bind:GetName() or "未知NPC", 
                  self.target:GetName(), 
                  self.jianghuSeed))
        else
            print("警告：未找到目标NPC")
            return false
        end
    else
        print("错误：未提供有效目标ID")
        return false
    end
    
    -- 验证目标有效性
    if not self:ValidateTarget() then
        print("错误：目标无效，无法施展心锁神通")
        return false
    end
    
    -- 触发施法开始效果
    if self.bind then
        -- 添加施法状态
        self.bind:AddModifier("CastingMagic")
        self.bind:AddModifier("HeartLockCasting")
        
        -- 添加目标状态
        self.target:AddModifier("BeingHeartLocked")
        
        -- 消耗初始灵力
        self.initialLingCost = self:ConsumeInitialResources()
        
        -- 显示开始信息
        self:ShowHeartLockStartMessage()
    end
    
    return true
end

function tbMagic:MagicStep(dt, duration)
    -- 返回值: 0继续 1成功并结束 -1失败并结束		
    
    -- 安全检查
    if not self:ValidateCastingState() then
        return -1
    end
    
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 8  -- 默认8秒
    local progress = math.min(duration / castTime, 1.0)
    
    -- 设置施法进度（UI显示）
    self:SetProgress(progress)
    
    -- 施法过程中的效果
    self:UpdateCastingEffects(progress)
    
    -- 持续消耗灵力
    self:ConsumeResourcesOverTime(dt, progress)
    
    -- 心锁进度效果
    self:UpdateHeartLockProgress(progress)
    
    -- 检查施法是否完成
    if duration >= castTime then
        return 1
    end
    
    return 0
end

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
    if not self.target or not self.bind then
        print("错误：目标或施法者不存在")
        return
    end
    
    -- 执行心锁逻辑
    local success = self:ApplyHeartLock()
    
    if success then
        self:TriggerSuccessEffects()
        self:ShowHeartLockSuccessMessage()
    else
        print("错误：施加心锁失败")
        self:OnMagicFailed()
    end
end

-- 施加心锁
function tbMagic:ApplyHeartLock()
    if not self.target or not self.target.JiangHuSeed then
        return false
    end
    
    local jhSeed = self.target.JiangHuSeed
    
    -- 安全检查
    if jhSeed <= 0 then
        print("错误：目标江湖种子无效")
        return false
    end
    
    -- 添加江湖NPC数据
    local success, result = pcall(function()
        JianghuMgr:AddKnowNpcData(jhSeed)
        return true
    end)
    
    if not success then
        print("错误：添加江湖NPC数据失败 - " .. tostring(result))
        return false
    end
    
    -- 获取并设置心锁数据
    local data = JianghuMgr:GetKnowNpcData(jhSeed)
    if not data then
        print("错误：无法获取江湖NPC数据")
        return false
    end
    
    -- 设置心锁
    data.hlock = MAGIC_CONFIG.HEART_LOCK_VALUE
    
    print(string.format("成功为【%s】(种子:%d)施加心锁", 
          self.target:GetName(), jhSeed))
    
    return true
end

-- 施法失败处理
function tbMagic:OnMagicFailed()
    if self.bind then
        -- 添加失败反噬效果
        self.bind:AddModifier("HeartLockBackfire")
        
        -- 部分灵力消耗
        local partialCost = math.floor(self.initialLingCost * 0.3)
        if self.bind.LingV > partialCost then
            self.bind.LingV = self.bind.LingV - partialCost
        end
        
        print(string.format("【%s】心锁神通施展失败", self.bind.Name))
        
        -- 显示失败信息
        self:ShowHeartLockFailedMessage()
    end
end

-- 验证目标有效性
function tbMagic:ValidateTarget()
    if not self.target then
        return false
    end
    
    -- 检查目标是否有江湖种子
    if not self.target.JiangHuSeed or self.target.JiangHuSeed <= 0 then
        return false
    end
    
    -- 检查目标是否已有心锁
    if self:HasHeartLock(self.target) then
        return false
    end
    
    return true
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
    
    -- 检查目标状态
    if not self.target or not self.target.IsAlive then
        return false
    end
    
    -- 检查目标是否仍有效
    if not self:ValidateTarget() then
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
    
    local costPerSecond = 400  -- 每秒消耗灵力
    local cost = costPerSecond * dt
    
    if self.bind.LingV > cost then
        self.bind.LingV = self.bind.LingV - cost
    else
        -- 灵力不足，施法失败
        self.bind.LingV = 0
    end
end

-- 更新心锁进度效果
function tbMagic:UpdateHeartLockProgress(progress)
    if not self.target then return end
    
    -- 根据进度更新视觉效果
    if progress < 0.3 then
        self.target:AddModifier("HeartLockGathering")
    elseif progress < 0.7 then
        self.target:RemoveModifier("HeartLockGathering")
        self.target:AddModifier("HeartLockForming")
    else
        self.target:RemoveModifier("HeartLockForming")
        self.target:AddModifier("HeartLockSealing")
    end
end

-- 更新施法效果
function tbMagic:UpdateCastingEffects(progress)
    if not self.bind then return end
    
    -- 根据进度更新特效
    if progress < 0.3 then
        self.bind:AddModifier("HeartLockChanneling")
    elseif progress < 0.7 then
        self.bind:RemoveModifier("HeartLockChanneling")
        self.bind:AddModifier("HeartLockBinding")
    else
        self.bind:RemoveModifier("HeartLockBinding")
        self.bind:AddModifier("HeartLockFinishing")
    end
end

-- 触发成功效果
function tbMagic:TriggerSuccessEffects()
    if not self.bind or not self.target then return end
    
    -- 添加成功特效
    self.bind:AddModifier("HeartLockSuccess")
    self.target:AddModifier("HeartLocked")
    
    -- 增加双方关系影响
    self:UpdateRelationship()
    
    -- 发送世界消息
    self:SendWorldMessage()
end

-- 更新双方关系
function tbMagic:UpdateRelationship()
    if self.bind and self.target then
        -- 目标对施法者产生特殊关系
        local relationData = self.target.PropertyMgr.RelationData:GetRelationData(self.bind)
        if relationData then
            relationData.Value = math.max(-100, relationData.Value - 20)  -- 降低好感度
        end
    end
end

-- 发送世界消息
function tbMagic:SendWorldMessage()
    if self.bind and self.target then
        CS.XiaWorld.MessageMgr.Instance:AddChainEventMessage(
            18, -1, 
            string.format("传闻【%s】施展心锁神通，成功锁住了【%s】的心脉，江湖中又多了一段恩怨情仇。", 
            self.bind.Name, self.target.Name), 
            0, 0, nil, "心锁神通", -1
        )
    end
end

-- 显示心锁开始信息
function tbMagic:ShowHeartLockStartMessage()
    if self.bind and self.target then
        world:ShowMsgBox(
            string.format("【%s】开始对【%s】施展心锁神通...", 
            self.bind.Name, self.target.Name),
            "心锁神通开始"
        )
    end
end

-- 显示心锁成功信息
function tbMagic:ShowHeartLockSuccessMessage()
    if self.bind and self.target then
        world:ShowMsgBox(
            string.format("心锁神通施展成功！【%s】的心脉已被锁住。", 
            self.target.Name),
            "心锁成功"
        )
    end
end

-- 显示心锁失败信息
function tbMagic:ShowHeartLockFailedMessage()
    if self.bind then
        world:ShowMsgBox(
            string.format("【%s】的心锁神通施展失败，受到法术反噬！", 
            self.bind.Name),
            "心锁失败"
        )
    end
end

-- 清理施法状态
function tbMagic:CleanupCastingState()
    if self.bind then
        self.bind:RemoveModifier("CastingMagic")
        self.bind:RemoveModifier("HeartLockCasting")
        self.bind:RemoveModifier("HeartLockChanneling")
        self.bind:RemoveModifier("HeartLockBinding")
        self.bind:RemoveModifier("HeartLockFinishing")
    end
    
    if self.target then
        self.target:RemoveModifier("BeingHeartLocked")
        self.target:RemoveModifier("HeartLockGathering")
        self.target:RemoveModifier("HeartLockForming")
        self.target:RemoveModifier("HeartLockSealing")
    end
end

-- 清理临时数据
function tbMagic:Cleanup()
    self.targetId = nil
    self.target = nil
    self.initialLingCost = 0
    self.jianghuSeed = 0
end

-- 存档数据
function tbMagic:OnGetSaveData()
    if self.targetId then
        return {
            targetId = self.targetId,
            initialLingCost = self.initialLingCost,
            jianghuSeed = self.jianghuSeed
        }
    end
    return nil
end

-- 读档数据
function tbMagic:OnLoadData(tbData, IDs, IsThing)	
    if tbData then
        self.targetId = tbData.targetId
        self.initialLingCost = tbData.initialLingCost or 0
        self.jianghuSeed = tbData.jianghuSeed or 0
        
        if self.targetId then
            self.target = ThingMgr:FindThingByID(self.targetId)
        end
    elseif IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修复索引
        self.target = ThingMgr:FindThingByID(self.targetId)
        self.initialLingCost = 0
        self.jianghuSeed = self.target and self.target.JiangHuSeed or 0
    end
end

-- 神通描述信息
function tbMagic:GetDescription()
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 8
    
    return {
        Name = "心锁神通",
        Desc = "施展神秘神通，锁住目标心脉，在江湖中留下特殊印记。",
        Effect = "在目标的江湖数据中设置心锁标记",
        CastTime = string.format("施法时间: %d秒", castTime),
        Requirement = "需要目标有江湖种子且未有心锁"
    }
end