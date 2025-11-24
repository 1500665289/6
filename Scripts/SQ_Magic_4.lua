--演示神通
local tbTable = GameMain:GetMod("MagicHelper");--获取神通模块 这里不要动
local tbMagic = tbTable:GetMagic("SQReborn");--创建一个新的神通class



function tbMagic:Init()
end

--神通是否可用
function tbMagic:EnableCheck(npc)
	return true;
end


--目标合法检测 首先会通过magic的SelectTarget过滤，然后再通过这里过滤
--IDs是一个List<int> 如果目标是非对象，里面的值就是地点key，如果目标是物体，值就是对象ID，否则为nil
--IsThing 目标类型是否为物体
function tbMagic:TargetCheck(key, t)	
	if t ~= nil and t.ThingType == CS.XiaWorld.g_emThingType.Npc and t.Race.RaceType ~= CS.XiaWorld.g_emNpcRaceType.Animal and t.IsLingering == true then
		return true;
	else
		return false;
	end
end


--开始施展神通
function tbMagic:MagicEnter(IDs, IsThing)
	self.targetId = IDs[0];--获取目标信息
end

--神通施展过程中，需要返回值
--返回值  0继续 1成功并结束 -1失败并结束
function tbMagic:MagicStep(dt, duration)	
	self:SetProgress(duration/self.magic.Param1);--设置施展进度 主要用于UI显示 这里使用了参数1作为施法时间
	if duration >=self.magic.Param1  then
		return 1;	
	end
	return 0;
end

--施展完成/失败 success是否成功
function tbMagic:MagicLeave(success)
	if success == true then
		local npc = ThingMgr:FindThingByID(self.targetId);
		if npc ~= nil then
			local save = npc.PropertyMgr:GetSaveData();
			save.BodyData.Dead = false
			save.BodyData.Dying = false
			save.BodyData.HealthValue = 300
			save.BodyData.DID = 1
			save.BodyData.Damages:Clear()
			save.BodyData.RemoveParts:Clear()
			npc.PropertyMgr.BodyData:AfterLoad(save)
			npc.DieCause = nil
			npc.CorpseTime = 0;
		end
	end
end



--存档 如果没有返回空 有就返回Table(KV)
function tbMagic:OnGetSaveData()
	
end

--读档 tbData是存档数据 IDs和IsThing同进入
function tbMagic:OnLoadData(tbData,IDs, IsThing)	
	self.targetId = IDs[0];--获取目标信息
end
