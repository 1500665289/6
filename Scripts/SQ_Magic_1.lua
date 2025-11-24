-- 演示神通 - 聚宝神通
local tbTable = GameMain:GetMod("MagicHelper")  -- 获取神通模块
local tbMagic = tbTable:GetMagic("SQJuBao")     -- 创建新的神通class

-- 注意：
-- 神通脚本运行时有三个固定变量：
-- self.bind  - 执行神通的npcObj
-- self.magic  - 当前神通的数据（XML定义）
-- self.targetId - 目标ID（在OnLoadData中设置）

-- 常量定义
local MAGIC_CONFIG = {
    LING_V_REQUIREMENT = 1000000,  -- 灵力需求
    CAST_TIME = "Param1"           -- 施法时间参数名
}

function tbMagic:Init()
    -- 神通初始化，可以在这里设置默认值
    self.targetId = nil
end

-- 神通是否可用检查
function tbMagic:EnableCheck(npc)
    if not npc then
        return false
    end
    
    local hasEnoughLing = npc.LingV >= MAGIC_CONFIG.LING_V_REQUIREMENT
    local isAlive = npc.IsAlive
    local canAct = not npc:HasModifier("CannotAct")
    
    return hasEnoughLing and isAlive and canAct
end

-- 目标合法性检查
-- key: 目标键值
-- t: 目标类型
function tbMagic:TargetCheck(key, t)
    -- 基础检查：目标存在且有效
    if not key or not t then
        return false
    end
    
    -- 可以根据需要添加更复杂的目标检查逻辑
    -- 例如：检查目标距离、阵营、状态等
    
    return true
end

-- 开始施展神通
function tbMagic:MagicEnter(IDs, IsThing)
    -- 记录目标信息
    if IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 使用第一个目标
        self.isThingTarget = IsThing
    end
    
    -- 触发施法开始效果
    if self.bind then
        -- 可以在这里添加施法特效、音效等
        self.bind:AddModifier("CastingMagic")  -- 添加施法状态
    end
    
    print(string.format("【%s】开始施展聚宝神通，目标ID: %s", 
          self.bind and self.bind.Name or "未知", tostring(self.targetId)))
end

-- 神通施展过程
-- dt: 时间增量
-- duration: 已持续时间
-- 返回值: 0-继续 1-成功结束 -1-失败结束
function tbMagic:MagicStep(dt, duration)
    -- 安全检查
    if not self.bind or not self.bind.IsAlive then
        return -1  -- NPC死亡或不存在，施法失败
    end
    
    local castTime = self.magic[MAGIC_CONFIG.CAST_TIME] or 5  -- 默认5秒
    local progress = duration / castTime
    
    -- 设置施法进度（UI显示）
    self:SetProgress(math.min(progress, 1.0))
    
    -- 可以在这里添加施法过程中的特效或状态变化
    if progress < 0.5 then
        -- 施法前半段效果
        self.bind:AddModifier("MagicGathering")
    else
        -- 施法后半段效果
        self.bind:RemoveModifier("MagicGathering")
        self.bind:AddModifier("MagicReleasing")
    end
    
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
    if self.bind then
        self.bind:RemoveModifier("CastingMagic")
        self.bind:RemoveModifier("MagicGathering")
        self.bind:RemoveModifier("MagicReleasing")
    end
    
    if success then
        -- 施法成功逻辑
        self:OnMagicSuccess()
    else
        -- 施法失败逻辑
        self:OnMagicFailed()
    end
    
    -- 清理临时数据
    self:Cleanup()
end

-- 施法成功处理
function tbMagic:OnMagicSuccess()
    if self.bind then
        -- 触发故事线
        self.bind.LuaHelper:TriggerStory("Story_SQJuBao")
        
        -- 添加成功效果
        self.bind:AddModifier("MagicSuccess")
        
        -- 消耗灵力
        local lingCost = MAGIC_CONFIG.LING_V_REQUIREMENT * 0.1  -- 消耗10%需求灵力
        self.bind.LingV = math.max(0, self.bind.LingV - lingCost)
        
        print(string.format("【%s】聚宝神通施展成功，消耗灵力: %d", 
              self.bind.Name, lingCost))
        
        -- 可以在这里添加更多的成功效果，如生成物品、增加属性等
        self:SpawnTreasure()
    end
end

-- 施法失败处理
function tbMagic:OnMagicFailed()
    if self.bind then
        -- 添加失败反噬效果
        self.bind:AddModifier("MagicBackfire")
        
        -- 少量灵力消耗（即使失败也有消耗）
        local lingCost = MAGIC_CONFIG.LING_V_REQUIREMENT * 0.05  -- 消耗5%需求灵力
        self.bind.LingV = math.max(0, self.bind.LingV - lingCost)
        
        print(string.format("【%s】聚宝神通施展失败，受到反噬", self.bind.Name))
    end
end

-- 生成宝物（成功时的具体效果）
function tbMagic:SpawnTreasure()
    if not self.bind then return end
    
    -- 根据NPC的运气值决定宝物品质
    local luck = self.bind.Luck or 50
    local treasureQuality = math.min(5, math.max(1, math.floor(luck / 20)))
    
    -- 生成随机宝物
    local treasureList = {
        "Item_Gold", "Item_SpiritStone", "Item_MagicHerb", 
        "Item_RareOre", "Item_Artifact"
    }
    
    local selectedTreasure = treasureList[math.min(#treasureList, treasureQuality)]
    
    -- 在地图上生成宝物
    local item = ThingMgr:AddItemThing(0, selectedTreasure, Map, 1, false)
    if item then
        Map:DropItem(item, self.bind.Key, false, false, false, false, 0, false)
        print(string.format("【%s】聚宝神通生成宝物: %s", self.bind.Name, selectedTreasure))
    end
end

-- 清理临时数据
function tbMagic:Cleanup()
    self.targetId = nil
    self.isThingTarget = nil
end

-- 存档数据
function tbMagic:OnGetSaveData()
    if self.targetId then
        return {
            targetId = self.targetId,
            isThingTarget = self.isThingTarget
        }
    end
    return nil
end

-- 读档数据
function tbMagic:OnLoadData(tbData, IDs, IsThing)
    if tbData then
        self.targetId = tbData.targetId
        self.isThingTarget = tbData.isThingTarget
    elseif IDs and #IDs > 0 then
        self.targetId = IDs[1]  -- 修正索引从1开始
        self.isThingTarget = IsThing
    end
end

-- 神通描述信息（可选，用于UI显示）
function tbMagic:GetDescription()
    return {
        Name = "聚宝神通",
        Desc = "消耗大量灵力，召唤随机宝物。需要100万以上灵力方可施展。",
        Requirement = string.format("灵力需求: %d", MAGIC_CONFIG.LING_V_REQUIREMENT)
    }
end