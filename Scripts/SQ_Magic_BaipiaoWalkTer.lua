local tbTable = GameMain:GetMod("MagicHelper");
local tbMagic = tbTable:GetMagic("SQBaipiaoWalkTer");

-- 常量定义
local MAGIC_CONFIG = {
    CAST_TIME = "Param1",           -- 施法时间参数名
    MIN_LING_REQUIREMENT = 1000,    -- 最低灵力需求
    LING_COST = 500                -- 施法灵力消耗
}

function tbMagic:Init()
    self.targetId = nil
    self.target = nil
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
    
    return isAlive and canAct and hasEnoughLing
end

function tbMagic:TargetCheck(k, t)
    -- 添加空值检查
    if not t then
        return false
    end
    
    -- 检查是否为行商
    return t.IsWalkTrader == true
end

function tbMagic:MagicStep(dt, duration)
    -- 返回值: 0继续 1成功并结束 -1失败并结束		
    
    -- 安全检查
    if not self:ValidateCastingState() then
        return -1
    end
    
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 5  -- 默认5秒
    self:SetProgress(duration / castTime);
    
    if duration >= castTime then	
        return 1;	
    end
    
    return 0;
end

function tbMagic:MagicLeave(success)
    -- 清理临时数据
    if success ~= true then
        self.targetId = nil
        self.target = nil
        return
    end
    
    -- 安全检查
    if not self.target or not self.bind then
        print("错误：目标或施法者不存在")
        self:Cleanup()
        return
    end
    
    -- 执行白嫖逻辑
    local success, result = pcall(function()
        return TradeMgr.WalkTrader:WalkTraderBaipiao(self.target)
    end)
    
    if not success then
        print("错误：白嫖行商失败 - " .. tostring(result))
        return
    end
    
    if result then
        -- 添加记忆
        self.target:AddMemery(
            string.format(
                "[color=MYCOLOR]%s[/color]被[color=#HECOLOR]%s[/color]打动了，送给其一件物品。", 
                self.target:GetName(), 
                self.bind:GetName()
            ), 
            0
        )
        
        print(string.format("【%s】成功白嫖了行商【%s】", 
              self.bind:GetName(), self.target:GetName()))
    end
    
    self:Cleanup()
end

function tbMagic:MagicEnter(IDs, IsThing)
    -- 记录目标信息
    if IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修复索引
        self.target = ThingMgr:FindThingByID(self.targetId)
        
        if self.target then
            print(string.format("【%s】开始对行商【%s】施展白嫖神通", 
                  self.bind and self.bind:GetName() or "未知", 
                  self.target:GetName()))
        else
            print("警告：未找到目标行商")
            return false
        end
    else
        print("错误：未提供有效目标ID")
        return false
    end
    
    -- 消耗初始灵力
    self:ConsumeInitialResources()
    
    return true
end

function tbMagic:OnLoadData(tbData, IDs, IsThing)	
    if IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修复索引
        self.target = ThingMgr:FindThingByID(self.targetId)
    end
    
    -- 恢复存档数据
    if tbData then
        self.targetId = tbData.targetId
        self.initialLingCost = tbData.initialLingCost or 0
    end
end

-- 新增：存档数据
function tbMagic:OnGetSaveData()
    if self.targetId then
        return {
            targetId = self.targetId,
            initialLingCost = self.initialLingCost
        }
    end
    return nil
end

-- 新增：验证施法状态
function tbMagic:ValidateCastingState()
    if not self.bind or not self.bind.IsAlive then
        return false
    end
    
    if not self.target or not self.target.IsWalkTrader then
        return false
    end
    
    if not self.bind.LingV or self.bind.LingV <= 0 then
        return false
    end
    
    return true
end

-- 新增：消耗初始资源
function tbMagic:ConsumeInitialResources()
    if not self.bind or not self.bind.LingV then return 0 end
    
    local initialCost = MAGIC_CONFIG.LING_COST
    if self.bind.LingV >= initialCost then
        self.bind.LingV = self.bind.LingV - initialCost
        self.initialLingCost = initialCost
        return initialCost
    end
    
    return 0
end

-- 新增：清理资源
function tbMagic:Cleanup()
    self.targetId = nil
    self.target = nil
    self.initialLingCost = 0
end

-- 新增：神通描述
function tbMagic:GetDescription()
    return {
        Name = "白嫖行商神通",
        Desc = "施展特殊神通，让行商心甘情愿地赠送物品",
        Effect = "从行商处获得免费物品",
        Requirement = "需要目标为行商且施法者灵力充足"
    }
end