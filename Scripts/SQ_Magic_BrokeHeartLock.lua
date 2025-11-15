local tbTable = GameMain:GetMod("MagicHelper");
local tbMagic = tbTable:GetMagic("SQBrokeHeartLock");


function tbMagic:Init()
end

function tbMagic:TargetCheck(k, t)
	return t.JiangHuSeed > 0
end

function tbMagic:MagicEnter(IDs, IsThing)
	self.targetId = IDs[0]
	self.target = ThingMgr:FindThingByID(self.targetId)
end

function tbMagic:MagicStep(dt, duration)--返回值  0继续 1成功并结束 -1失败并结束		
	self:SetProgress(duration/self.magic.Param1);
	if duration >= self.magic.Param1 then	
		return 1;	
	end
	return 0;
end
function tbMagic:MagicLeave(success)
	if success == true then
		local jhSeed = self.target.JiangHuSeed
		if (jhSeed > 0) then
			JianghuMgr:AddKnowNpcData(jhSeed)
			local data = JianghuMgr:GetKnowNpcData(self.target.JiangHuSeed)

			data.hlock = 1
		end
	end

	self.targetId = nil
	self.target = nil
end

function tbMagic:OnLoadData(tbData,IDs, IsThing)	
	self.targetId = IDs[0]
	self.target = CS.XiaWorld.ThingMgr.Instance:FindThingByID(self.targetId)
end
