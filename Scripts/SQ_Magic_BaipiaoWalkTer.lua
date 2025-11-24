local tbTable = GameMain:GetMod("MagicHelper");
local tbMagic = tbTable:GetMagic("SQBaipiaoWalkTer");


function tbMagic:Init()
end

function tbMagic:TargetCheck(k, t)
	return t.IsWalkTrader
end

function tbMagic:MagicStep(dt, duration)--返回值  0继续 1成功并结束 -1失败并结束		
	self:SetProgress(duration/self.magic.Param1);
	if duration >= self.magic.Param1 then	
		return 1;	
	end
	return 0;
end
function tbMagic:MagicLeave(success)
	if success ~= true then
		self.TargetID = nil
		self.target = nil
		return
	end
	
	if (TradeMgr.WalkTrader:WalkTraderBaipiao(self.target)) then
		self.target:AddMemery(
			string.format(
				"[color=MYCOLOR]%s[/color]被[color=#HECOLOR]%s[/color]打动了，送给其一件物品。", 
				self.target:GetName(), 
				self.bind:GetName())
			, 0
		)
	end
end


function tbMagic:MagicEnter(IDs, IsThing)
	self.TargetID = IDs[0]
	self.target = ThingMgr:FindThingByID(self.TargetID)
end

function tbMagic:OnLoadData(tbData,IDs, IsThing)	
	self.TargetID = IDs[0]
	self.target = CS.XiaWorld.ThingMgr.Instance:FindThingByID(self.TargetID)
end
