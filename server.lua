local vehicleRadios = {}

RegisterNetEvent('nc_carradio:server:setRadio', function(netId, station, isManual)
    if isManual == nil then isManual = true end
    vehicleRadios[netId] = station
    TriggerClientEvent('nc_carradio:client:syncRadio', -1, netId, station, isManual, source, isManual)
end)

RegisterNetEvent('nc_carradio:server:requestRadioState', function(netId)
    local src = source
    if vehicleRadios[netId] then
        TriggerClientEvent('nc_carradio:client:syncRadio', src, netId, vehicleRadios[netId], false)
    else
        TriggerClientEvent('nc_carradio:client:initializeRadioState', src, netId)
    end
end)
