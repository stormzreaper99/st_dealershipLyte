local QBX = exports.qbx_core
local function isAdmin(src) return Config.AdminPermission ~= nil and IsPlayerAceAllowed(src, Config.AdminPermission) end

lib.callback.register('st_dealership:server:isDealershipAdmin', function(src) return isAdmin(src) end)
lib.callback.register('st_dealership:server:adminGetDealerships', function(src)
    if not isAdmin(src) then return {} end
    local out={};for name,def in pairs(ST.GetAllDealerships())do out[#out+1]={name=name,label=def.label,type=def.type,job=def.job,balance=ST.GetBalance(name),source=def.fromRegistry and'registry'or'config'}end
    table.sort(out,function(a,b)return a.label<b.label end);return out
end)
lib.callback.register('st_dealership:server:adminSetBalance',function(src,name,amount)
    if not isAdmin(src)then return false,'not_authorized'end;if not ST.GetDealership(name)then return false,'not_found'end;amount=tonumber(amount);if not amount then return false,'invalid_amount'end;ST.SetBalance(name,amount);return true
end)
lib.callback.register('st_dealership:server:adminAssignOwner',function(src,name,targetId)
    if not isAdmin(src)then return false,'not_authorized'end;local d=ST.GetDealership(name);if not d then return false,'not_found'end;local p=QBX:GetPlayer(tonumber(targetId));if not p then return false,'player_offline'end
    local ok,err=exports.qbx_core:SetJob(p.PlayerData.citizenid,d.job,Config.DefaultGradeRequirements.owner or 4);if not ok then return false,(err and err.message)or'set_job_failed'end;return true
end)
lib.callback.register('st_dealership:server:adminDeleteDealership',function(src,name)
    if not isAdmin(src)then return false,'not_authorized'end;local d=ST.GetDealership(name);if not d then return false,'not_found'end;if not d.fromRegistry then return false,'cannot_delete_config'end
    local ok,err=pcall(function()MySQL.query.await('DELETE FROM st_dealership_registry WHERE name = ?',{name});MySQL.query.await('DELETE FROM st_dealership_zones WHERE dealership = ?',{name});MySQL.query.await('DELETE FROM st_dealership_accounts WHERE dealership = ?',{name});MySQL.query.await('DELETE FROM st_dealership_display_assignments WHERE dealership = ?',{name});ST.RemoveFromRegistry(name)end)
    if not ok then print(('[st_dealership] delete failed for "%s": %s'):format(tostring(name),tostring(err)));return false,'internal_error'end
    TriggerClientEvent('st_dealership:client:dealershipDeleted',-1,name);return true
end)
