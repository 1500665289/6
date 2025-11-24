--蛟龙技能反噬
local tbTable = GameMain:GetMod("MagicHelper");
local tbMagic = tbTable:GetMagic("SQoutspread");

function tbMagic:MagicLeave(success)	
	if success ~= true then
		return
	end	
	local regionname = self.workdparam1
	local sec = self.magic.Param1
	local mapstory = self.magic.sParam1
	local desc = self.magic.sParam2
	local effectid = self.magic.Param2
	self.bind.JobEngine:SetNextJob("JobLcOutpread", regionname, sec, mapstory, desc, effectid)
end