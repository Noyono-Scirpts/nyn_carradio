local isUIOpen = false
local isUIOpenInHoldMode = false
local isHolding = false
local pressTime = 0
local uiOpened = false

local function openRadioUI()
    isUIOpen = true
    isUIOpenInHoldMode = true
    SendNUIMessage({
        action = 'open',
        stations = Config.Stations
    })
end

local function closeRadioUI()
    isUIOpen = false
    isUIOpenInHoldMode = false
    SendNUIMessage({
        action = 'close'
    })
end

RegisterCommand('+nc_carradio', function()
    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    
    if not vehicle or vehicle == 0 then
        return
    end

    pressTime = GetGameTimer()
    isHolding = true
    uiOpened = false

    CreateThread(function()
        while isHolding do
            if not uiOpened and (GetGameTimer() - pressTime) >= 350 then
                local currentVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
                if currentVehicle and currentVehicle ~= 0 then
                    uiOpened = true
                    openRadioUI()
                else
                    isHolding = false
                end
                break
            end
            Wait(10)
        end
    end)
end, false)

RegisterCommand('-nc_carradio', function()
    if not isHolding then return end
    isHolding = false

    if isUIOpenInHoldMode then
        closeRadioUI()
    else
        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, false)
        if vehicle and vehicle ~= 0 then
            isUIOpen = true
            SendNUIMessage({
                action = 'cycleNext',
                stations = Config.Stations
            })
        end
    end
end, false)

RegisterKeyMapping('+nc_carradio', 'Otevrit autoradio', 'keyboard', Config.Keybind)

RegisterNUICallback('close', function(data, cb)
    isUIOpen = false
    isUIOpenInHoldMode = false
    SendNUIMessage({ action = 'close' })
    cb('ok')
end)

RegisterNUICallback('selectStation', function(data, cb)
    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    
    if vehicle and vehicle ~= 0 then
        TriggerServerEvent('nc_carradio:server:setRadio', VehToNet(vehicle), {
            index = data.index,
            name = data.name,
            image = data.image,
            type = data.type,
            value = data.value
        })
    end
    cb('ok')
end)

RegisterNetEvent('nc_carradio:client:syncRadio', function(netId, station, showUI)
    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    
    if vehicle and vehicle ~= 0 then
        local currentNetId = VehToNet(vehicle)
        if currentNetId == netId then
            if station.type == 'native' then
                SendNUIMessage({ action = 'stopStream' })
                SetVehRadioStation(vehicle, station.value)
            elseif station.type == 'stream' then
                SetVehRadioStation(vehicle, "OFF")
                SendNUIMessage({
                    action = 'playStream',
                    url = station.value
                })
            elseif station.type == 'off' then
                SetVehRadioStation(vehicle, "OFF")
                SendNUIMessage({ action = 'stopStream' })
            end
            
            local shouldShowUI = showUI and not isUIOpenInHoldMode
            if shouldShowUI then
                isUIOpen = true
            end

            SendNUIMessage({
                action = 'syncVisuals',
                index = station.index,
                name = station.name,
                image = station.image,
                type = station.type,
                showUI = shouldShowUI,
                stations = Config.Stations
            })
        end
    end
end)

CreateThread(function()
    local lastVehicle = 0
    while true do
        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, false)
        
        if vehicle ~= 0 and lastVehicle == 0 then
            TriggerServerEvent('nc_carradio:server:requestRadioState', VehToNet(vehicle))
        end

        if vehicle == 0 and lastVehicle ~= 0 then
            if isUIOpen then
                isUIOpen = false
                isUIOpenInHoldMode = false
                SendNUIMessage({ action = 'close' })
            end
            isHolding = false
            SendNUIMessage({ action = 'stopAll' })
        end
        
        lastVehicle = vehicle
        
        if vehicle ~= 0 then
            SetUserRadioControlEnabled(false)
            HideHudComponentThisFrame(16)
            
            if isUIOpen then
                DisableControlAction(0, 14, true)
                DisableControlAction(0, 15, true)
                DisableControlAction(0, 81, true)
                DisableControlAction(0, 82, true)
                DisableControlAction(0, 174, true)
                DisableControlAction(0, 175, true)
                
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 37, true)
                DisableControlAction(0, 44, true)
                DisableControlAction(0, 140, true)

                if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 175) or IsDisabledControlJustPressed(0, 81) then
                    SendNUIMessage({ action = 'nextStation' })
                elseif IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 174) or IsDisabledControlJustPressed(0, 82) then
                    SendNUIMessage({ action = 'prevStation' })
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)
