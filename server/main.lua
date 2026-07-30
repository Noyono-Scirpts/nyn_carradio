---@diagnostic disable: undefined-global

local vehicleRadios = {}

local function debugPrint(...)
    if not Config.Debug then return end
    print(('[nyn_carradio:server] %s'):format(table.concat({ ... }, ' ')))
end

RegisterNetEvent('nyn_carradio:server:setRadio', function(netId, station, isManual)
    local src = source
    if isManual == nil then isManual = true end

    if type(netId) ~= 'number' or type(station) ~= 'table' then
        return
    end

    vehicleRadios[netId] = station
    debugPrint(('setRadio netId=%s type=%s by=%s'):format(netId, tostring(station.type), src))
    TriggerClientEvent('nyn_carradio:client:syncRadio', -1, netId, station, isManual, src, isManual)
end)

RegisterNetEvent('nyn_carradio:server:requestRadioState', function(netId)
    local src = source
    if type(netId) ~= 'number' then return end

    if vehicleRadios[netId] then
        TriggerClientEvent('nyn_carradio:client:syncRadio', src, netId, vehicleRadios[netId], false)
    else
        TriggerClientEvent('nyn_carradio:client:initializeRadioState', src, netId)
    end
end)

-- Cleanup stale radio state for despawned vehicles
CreateThread(function()
    debugPrint('server started')
    while true do
        Wait(60000)
        for netId in pairs(vehicleRadios) do
            local entity = NetworkGetEntityFromNetworkId(netId)
            if not entity or entity == 0 or not DoesEntityExist(entity) then
                vehicleRadios[netId] = nil
            end
        end
    end
end)
