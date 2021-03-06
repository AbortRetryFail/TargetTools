-- written by slime
-- extended by ARF

local gkpc = gkinterface.GKProcessCommand
local getradar = radar.GetRadarSelectionID
local setradar = radar.SetRadarSelection
local objectpos = Game.GetObjectAtScreenPos
local floor = math.floor


-- Targetless compatability
local function targetless_exists()
	return pcall(function() return targetless end)
end

local function targetless_off()
	if targetless_exists() then
		targetless.var.scanlock = true
		targetless.api.radarlock = true
		targetless.var.lock = true
		return true
	end
	return false
end
local function targetless_on()
	if targetless_exists() then
		targetless.api.radarlock = false
		targetless.var.lock = false
		targetless.var.scanlock = false
		return true
	end
	return false
end

declare("TargetTools", {})
TargetTools.ReTarget = {
	target={0,0},
	active=gkini.ReadString("targettools", "retarget", "ON") == "ON",
}


function TargetTools.ReTarget:OnEvent(event, type)
	if not self.active then return end
	if event == "TARGET_CHANGED" and not PlayerInStation() then
		self.target = {getradar()}
	elseif event == "HUD_SHOW" then
		setradar(self.target[1], self.target[2])
	end
end

RegisterEvent(TargetTools.ReTarget, "TARGET_CHANGED")
RegisterEvent(TargetTools.ReTarget, "HUD_SHOW")

TargetTools.CallSnoop = {
	location=0,
	target={0,0}
}

function TargetTools.CallSnoop:OnEvent(event, args)
	if args.location == GetCurrentSectorid() then
		self.location = args.location
		local nodeid, objectid = args.msg:match("{(%d+), (%d+)} at")
		if nodeid and objectid then 
			self.target = { nodeid, objectid }
		end
	end
end

function TargetTools.CallSnoop.CalledTarget(args)
	local self = TargetTools.CallSnoop
	if self.location == GetCurrentSectorid() then
		setradar(unpack(self.target))
	end
end

RegisterEvent(TargetTools.CallSnoop, "CHAT_MSG_GROUP")
RegisterEvent(TargetTools.CallSnoop, "CHAT_MSG_GUILD")
RegisterUserCommand("CalledTarget", TargetTools.CallSnoop.CalledTarget)


function TargetTools.SendTarget(channel)
	if GetTargetInfo() then
		local formatstr = "Targeting %s (%d%%, %s), \"%s\", {%d, %d} at %dm"
		local shieldformatstr = "Targeting %s (%d%% : %d%%, %s), \"%s\" {%d, %d} at %dm"
		local nohealthformatstr = "Targeting %s {%d, %d} at %dm"
		local name, health, distance, factionid, guild, ship = GetTargetInfo()
		local _, shield = GetPlayerHealth(GetCharacterIDByName(name))
		local nodeid, objectid = radar.GetRadarSelectionID()
		if guild and guild ~= "" then
			name = "["..guild.."] "..name
		end
		local str
		if health and ship and factionid then
			if shield then
				str = shieldformatstr:format(Article(ship), floor(shield), 
										floor(health*100), 
										FactionName[factionid], 
										name, 
										nodeid,
										objectid,
										floor(distance)
										)
			else
				str = formatstr:format(Article(ship), floor(health*100), 
										FactionName[factionid], 
										name, 
										nodeid,
										objectid,
										floor(distance)
										)
			end
		else
			str = nohealthformatstr:format(name, nodeid, objectid, floor(distance))
		end
		SendChat(str, channel:upper())
	end
end


function TargetTools.ReadyAtDist(channel)
	if GetTargetInfo() then
		local name, health, distance, factionid, guild, ship = GetTargetInfo()
		SendChat("Ready at ".. floor(distance) .."m from \""..name.."\"", channel:upper())
	end
end


function TargetTools.AttackedBy(channel)
	if GetLastAggressor() then
		local node, object = GetLastAggressor()
		local charid = GetCharacterID(node)
		if charid == GetCharacterID() then return end
		SendChat("Under attack by "..Article(GetPrimaryShipNameOfPlayer(charid))..", \""..GetPlayerName(charid).."\" !", channel)
	end
end

function TargetTools.GroupOrGuild(fn)
	if GetGroupOwnerID() ~= 0 then
		fn("GROUP")
	else
		fn("GUILD")
	end
end

RegisterUserCommand("GroupTarget", function() TargetTools.SendTarget("GROUP") end)
RegisterUserCommand("GuildTarget", function() TargetTools.SendTarget("GUILD") end)
RegisterUserCommand("GTarget", function() TargetTools.GroupOrGuild(TargetTools.SendTarget) end)
RegisterUserCommand("GroupReady", function() TargetTools.ReadyAtDist("GROUP") end)
RegisterUserCommand("GuildReady", function() TargetTools.ReadyAtDist("GUILD") end)
RegisterUserCommand("GReady", function() TargetTools.GroupOrGuild(TargetTools.ReadyAtDist) end)
RegisterUserCommand("GroupAttacked", function() TargetTools.AttackedBy("GROUP") end)
RegisterUserCommand("GuildAttacked", function() TargetTools.AttackedBy("GUILD") end)
RegisterUserCommand("GAttacked", function() TargetTools.GroupOrGuild(TargetTools.AttackedBy) end)


function TargetTools.GetPlayerIDs(charid)
	if not charid then charid = RequestTargetStats() end
	if not charid then return end
	local nodeid = GetPlayerNodeID(charid)
	local objectid = GetPrimaryShipIDOfPlayer(charid)
	return nodeid, objectid, charid
end


function TargetTools.TargetParent(charid)
	setradar(TargetTools.GetPlayerIDs(charid))
end
RegisterUserCommand("TargetParent", TargetTools.TargetParent)


function TargetTools.TargetTurret(rev) -- this way isn't the best
	local skip = 1
	local nodeid, objectid = getradar()
	
	if not nodeid then
		-- We can't target an object's turrets if we aren't targeting an object.
		TargetTools.TargetFront()
		return
	end
	
	-- Disable targetless functionality while we scan.
	targetless_off()
	
	local childnode, childobject
	local repmin, repmax = 1, 400
	if rev then
		-- Reverse the scan.
		repmin, repmax = repmin*-1, repmax*-1
	end
	
	for rep = repmin, repmax, skip do
		setradar(nodeid, objectid+rep)
		childnode, childobject = getradar()
		
		-- Stop at the first valid object (getradar returns a different objectid from our original target.)
		if childobject ~= objectid then
			break
		end
	end
	
	-- Re-enable targetless functionality when we're done scanning.
	targetless_on()
	
	if childobject == objectid then
		TargetTools.TargetParent()
	end
end

RegisterUserCommand("TargetNextTurret", TargetTools.TargetTurret)
RegisterUserCommand("TargetPrevTurret", function() TargetTools.TargetTurret(true) end)


function TargetTools.GetLocalObjects(charid)
	if not charid then return end
	local nodeid, objectid = GetPlayerNodeID(charid), GetPrimaryShipIDOfPlayer(charid)
	if not nodeid or not objectid then return end
	local localobjects = {}
	targetless_off()
	setradar(nodeid, objectid)
	while true do
		gkpc("LocalRadarNext")
		local nextnode, nextobject = getradar()
		if not nextnode then break end
		local name, health, dist = GetTargetInfo()
		table.insert(localobjects, {nodeid=nextnode, objectid=nextobject, dist=dist})
	end
	targetless_on()
	return localobjects
end

function TargetTools.TargetFront(targetturret, reverse)
	local xstep = 1 / gkinterface.GetXResolution()
	local ystep = 1 / gkinterface.GetYResolution()
	local xmin = 0.5 - 15 * xstep
	local xmax = 0.5 + 15 * xstep
	local ymin = 0.5 - 15 * ystep
	local ymax = 0.5 + 15 * ystep
	gkpc("RadarNone")
	
	--TODO: rewrite this to spiral outwards from the center

	-- Narrow scan for small stuff
	for y=ymin, ymax, ystep do
		for x=xmin, xmax, xstep do
			local node,obj = objectpos(x,y)
			if node and obj then setradar(node,obj) return x,y end
		end
	end
	-- Wider fast scan for big things
	for y=0.45, 0.55, 0.005 do
		for x=0.45, 0.55, 0.005 do
			local node,obj = objectpos(x,y)
			if node and obj then setradar(node,obj) return x,y end
		end
	end

	if targetturret then
		TargetTools.TargetTurret(reverse, true)
	end
end
RegisterUserCommand("TargetFront", TargetTools.TargetFront)


function TargetTools.TargetShipType(type)
	type = type:lower()
	local ships = {}
	local function IsShipType(charid)
		if GetPrimaryShipNameOfPlayer(charid) and GetPrimaryShipNameOfPlayer(charid):lower():match(type) then
			local distance = GetPlayerDistance(charid)
			if charid == GetCharacterID() then distance = 10000 end
			if distance then
				table.insert(ships, {distance=distance, node=GetPlayerNodeID(charid), object=GetPrimaryShipIDOfPlayer(charid)})
			end
		end
	end
	ForEachPlayer(IsShipType)
	if not ships[1] then return end
	table.sort(ships, function(a,b) return a.distance < b.distance end)
	setradar(ships[1].node, ships[1].object)
end

RegisterUserCommand("TargetRag", function() TargetTools.TargetShipType("ragnarok") end)
RegisterUserCommand("TargetShip", function(unused, data)
	if data then
		TargetTools.TargetShipType(table.concat(data, " "))
	else
		TargetTools.TargetShipType(".")
	end
end)


function TargetTools.TargetPlayer(name)
	name = name:lower()
	local ships = {}
	local function IsPlayerName(charid)
		if GetPlayerName(charid):lower():match(name) then
			local distance = GetPlayerDistance(charid)
			if charid == GetCharacterID() then distance = 10000 end -- sort last
			if distance then
				table.insert(ships, {distance=distance, node=GetPlayerNodeID(charid), object=GetPrimaryShipIDOfPlayer(charid)})
			end
		end
	end
	ForEachPlayer(IsPlayerName)
	if not ships[1] then return end
	table.sort(ships, function(a,b) return a.distance < b.distance end)
	setradar(ships[1].node, ships[1].object)
end

RegisterUserCommand("TargetPlayer", function(_, data)
	if data then
		TargetTools.TargetPlayer(table.concat(data, " "))
	else
		TargetTools.TargetPlayer(".")
	end
end)


function TargetTools.TargetCargo(type)
	type = type:lower()
	local _name = GetTargetInfo()
	if _name and not _name:lower():match(type) then gkpc("RadarNone") end
	targetless_off()
	local found = false
	repeat
		gkpc("RadarNext")
		local name = GetTargetInfo()
		if not name then
			print("\127ff0000\""..type.."\" is not in range")
			break
		end
		local nodeid, objectid = getradar()
		if nodeid == 2 and name ~= "Asteroid" and name ~= "Ice Crystal" and name:lower():match(type) then
			found = true
		end
	until found
	targetless_on()
end

RegisterUserCommand("TargetCargo", function(_, data)
	if data then
		TargetTools.TargetCargo(table.concat(data, " "))
	else
		TargetTools.TargetCargo(".")
	end
end)


dofile("ui.lua")
