local function isAdmin()
    return lib.callback.await('st_dealership:server:isDealershipAdmin', false)
end

RegisterCommand('admindealership', function(_, args)
    if not isAdmin() then
        lib.notify({ title='Admin', description="You don't have permission to do that.", type='error' })
        return
    end
    local name=args[1]
    if not name or name=='' then
        lib.notify({ title='Admin', description='Usage: /admindealership <dealership>', type='error' })
        return
    end
    ST.OpenDealershipUI(name,'settings')
end,false)

CreateThread(function()
    TriggerEvent('chat:addSuggestion','/admindealership','Open dealership administration',{ {name='dealership',help='Dealership slug'} })
end)
