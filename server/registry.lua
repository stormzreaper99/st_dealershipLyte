local registryCache={}
local function normalizeRow(row)return{label=row.label,type=row.type,job=row.job,account=row.name..'_bank',startingBalance=tonumber(row.starting_balance)or 0,fromRegistry=true,location={blip={x=row.pos_x,y=row.pos_y,z=row.pos_z,sprite=row.blip_sprite,color=row.blip_color,scale=row.blip_scale},showroom={x=row.pos_x,y=row.pos_y,z=row.pos_z},spawns={},testDriveReturn=nil},rules={marginTarget=.18,requiresInspectionBeforeSale=true},theme={}}end
function ST.GetDealership(name)return registryCache[name]or Config.Dealerships[name]end
function ST.GetAllDealerships()local o={};for n,d in pairs(Config.Dealerships)do o[n]=d end;for n,d in pairs(registryCache)do o[n]=d end;return o end
function ST.RemoveFromRegistry(name)registryCache[name]=nil end
local function loadRegistry()for _,row in ipairs(MySQL.query.await('SELECT * FROM st_dealership_registry')or{})do registryCache[row.name]=normalizeRow(row)end end
local function isAdmin(src)return IsPlayerAceAllowed(src,'command.newdealership')end
lib.callback.register('st_dealership:server:canCreateDealership',function(src,name,job)if not isAdmin(src)then return false,'not_authorized'end;if not name or name==''or name:match('%s')or name:match('[^%w_%-]')then return false,'invalid_name'end;if ST.GetDealership(name)then return false,'name_taken'end;if not job or job==''then return false,'invalid_job'end;return true end)
lib.callback.register('st_dealership:server:createDealership',function(src,data)
    if not isAdmin(src)then return false,'not_authorized'end;if not data or not data.name or ST.GetDealership(data.name)then return false,'name_taken'end
    local ok,err=pcall(function()
        MySQL.insert.await([[INSERT INTO st_dealership_registry (name,label,type,job,blip_sprite,blip_color,blip_scale,pos_x,pos_y,pos_z,heading,starting_balance,created_by) VALUES (?, ?, ?, ?, 225, 3, 0.8, ?, ?, ?, ?, ?, ?)]],{data.name,data.label,data.type or'used',data.job,data.pos.x,data.pos.y,data.pos.z,data.heading or 0.0,data.startingBalance or 25000,ST.GetPlayerCitizenId(src)})
        local row=MySQL.single.await('SELECT * FROM st_dealership_registry WHERE name = ?',{data.name});if not row then error('insert succeeded but row was not found')end;registryCache[data.name]=normalizeRow(row)
        MySQL.insert([[INSERT INTO st_dealership_zones (dealership,zone_type,shape,label,pos_x,pos_y,pos_z,heading) VALUES (?, 'management_pc', 'point', 'Management PC', ?, ?, ?, ?)]],{data.name,data.pos.x,data.pos.y,data.pos.z,data.heading or 0.0})
        ST.SeedAccount(data.name,data.startingBalance or 25000);local runtimeOk,fileResult=ST.CreateDealershipJob(data.job,data.label);if not runtimeOk then print(('[st_dealership] job "%s" could not be registered: %s'):format(tostring(data.job),tostring(fileResult)))end
        TriggerClientEvent('st_dealership:client:dealershipCreated',-1,data.name,{label=registryCache[data.name].label,type=registryCache[data.name].type,job=registryCache[data.name].job,location=registryCache[data.name].location});TriggerClientEvent('st_dealership:client:syncZones',-1,data.name,ST.GetZones(data.name))
    end)
    if not ok then registryCache[data.name]=nil;print(('[st_dealership] /newdealership failed for "%s": %s'):format(tostring(data.name),tostring(err)));return false,'internal_error'end;return true
end)
CreateThread(function()loadRegistry();ST.SeedAllAccounts();local a,b=0,0;for _ in pairs(Config.Dealerships)do a=a+1 end;for _ in pairs(registryCache)do b=b+1 end;print(('[st_dealership] loaded %d config dealership(s), %d registry dealership(s)'):format(a,b))end)
