local vehicleRadios = {}

RegisterNetEvent('nc_carradio:server:setRadio', function(netId, station)
    vehicleRadios[netId] = station
    TriggerClientEvent('nc_carradio:client:syncRadio', -1, netId, station, true)
end)

RegisterNetEvent('nc_carradio:server:requestRadioState', function(netId)
    local src = source
    if vehicleRadios[netId] then
        TriggerClientEvent('nc_carradio:client:syncRadio', src, netId, vehicleRadios[netId], false)
    end
end)
