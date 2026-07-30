---@diagnostic disable: undefined-global

local isUIOpen = false
local isUIOpenInHoldMode = false
local isHolding = false
local pressTime = 0
local uiOpened = false

local function debugPrint(...)
    if not Config.Debug then return end
    print(('[nyn_carradio:client] %s'):format(table.concat({ ... }, ' ')))
end

local function notify(type, titleKey, messageKey)
    if not nyn_lib or not nyn_lib.client or not nyn_lib.client.Notify then return end
    nyn_lib.client.Notify(type, Locale(titleKey), Locale(messageKey))
end

---@param vehicle number
---@return boolean
local function isEmergencyVehicle(vehicle)
    if not Config.DisableInEmergency then
        return false
    end
    if not vehicle or vehicle == 0 then
        return false
    end
    return nyn_lib.client.IsEmergencyVehicle(vehicle)
end

---@return number
local function getVehicle()
    return nyn_lib.client.GetCurrentVehicle()
end

--- Vypne native GTA rádio (kolo + stanice + audio)
---@param vehicle number
local function killNativeRadio(vehicle)
    if not vehicle or vehicle == 0 then return end
    SetVehicleRadioEnabled(vehicle, false)
    SetVehRadioStation(vehicle, 'OFF')
end

--- Každý frame ve vozidle: default GTA radio wheel/HUD pryč
---@param vehicle number
local function suppressDefaultRadioHud(vehicle)
    SetUserRadioControlEnabled(false)
    HideHudComponentThisFrame(16)
    DisableControlAction(0, 81, true) -- next radio
    DisableControlAction(0, 82, true) -- prev radio
    DisableControlAction(0, 83, true) -- next track
    DisableControlAction(0, 84, true) -- prev track
    DisableControlAction(0, 85, true) -- radio wheel
end

local function openRadioUI()
    isUIOpen = true
    isUIOpenInHoldMode = true
    SendNUIMessage({
        action = 'open',
        stations = Config.Stations,
        locales = GetUiLocales(),
    })
end

local function closeRadioUI()
    isUIOpen = false
    isUIOpenInHoldMode = false
    SendNUIMessage({
        action = 'close'
    })
end

local function applyStationLocally(vehicle, station)
    if not station then return end

    -- Switching away from YouTube/plus → stop plus audio
    if station.type ~= 'youtube' and station.type ~= 'plus' and GetResourceState(Config.ExtensionResource or 'nyn_carradio_plus') == 'started' then
        pcall(function()
            exports[Config.ExtensionResource or 'nyn_carradio_plus']:Stop()
        end)
    end

    if station.type == 'native' and station.value then
        SendNUIMessage({ action = 'stopStream' })
        SetVehicleRadioEnabled(vehicle, true)
        SetVehRadioStation(vehicle, station.value)
    elseif station.type == 'stream' then
        killNativeRadio(vehicle)
        SendNUIMessage({
            action = 'playStream',
            url = station.value
        })
    elseif station.type == 'youtube' or station.type == 'plus' then
        -- Handled by nyn_carradio_plus (xsound + cabin muffling)
        killNativeRadio(vehicle)
        SendNUIMessage({ action = 'stopStream' })
    else -- off / fallback
        killNativeRadio(vehicle)
        SendNUIMessage({ action = 'stopStream' })
    end
end

local function forceRadioOff(vehicle)
    killNativeRadio(vehicle)
    SendNUIMessage({ action = 'stopStream' })
end

local function offStationPayload()
    local station = Config.Stations[1]
    return {
        index = 0,
        name = station.name,
        image = station.image,
        type = station.type,
        value = station.value
    }
end

RegisterCommand('+nyn_carradio', function()
    local vehicle = getVehicle()

    if not vehicle or vehicle == 0 then
        return
    end

    if isEmergencyVehicle(vehicle) then
        if Config.NotifyOnBlocked then
            notify('error', 'notify_emergency_title', 'notify_emergency')
        end
        return
    end

    pressTime = GetGameTimer()
    isHolding = true
    uiOpened = false

    CreateThread(function()
        while isHolding do
            if not uiOpened and (GetGameTimer() - pressTime) >= 600 then
                local currentVehicle = getVehicle()
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

RegisterCommand('-nyn_carradio', function()
    if not isHolding then return end
    isHolding = false

    local vehicle = getVehicle()
    if isEmergencyVehicle(vehicle) then
        if isUIOpenInHoldMode then
            closeRadioUI()
        end
        return
    end

    if isUIOpenInHoldMode then
        closeRadioUI()
    else
        if vehicle and vehicle ~= 0 then
            isUIOpen = true
            SendNUIMessage({
                action = 'cycleNext',
                stations = Config.Stations,
                locales = GetUiLocales(),
            })
        end
    end
end, false)

RegisterKeyMapping('+nyn_carradio', Locale('keybind_open'), 'keyboard', Config.Keybind)

RegisterNUICallback('close', function(_, cb)
    isUIOpen = false
    isUIOpenInHoldMode = false
    SendNUIMessage({ action = 'close' })
    cb({ ok = true })
end)

RegisterNUICallback('selectStation', function(data, cb)
    local vehicle = getVehicle()

    if vehicle and vehicle ~= 0 then
        if isEmergencyVehicle(vehicle) then
            forceRadioOff(vehicle)
            cb({ ok = true })
            return
        end

        applyStationLocally(vehicle, data)

        TriggerServerEvent('nyn_carradio:server:setRadio', VehToNet(vehicle), {
            index = data.index,
            name = data.name,
            image = data.image,
            type = data.type,
            value = data.value
        }, true)
    end
    cb({ ok = true })
end)

RegisterNetEvent('nyn_carradio:client:syncRadio', function(netId, station, showUI, initiator, isManual)
    local vehicle = getVehicle()

    if vehicle and vehicle ~= 0 then
        local currentNetId = VehToNet(vehicle)
        if currentNetId == netId then
            if isEmergencyVehicle(vehicle) then
                forceRadioOff(vehicle)
                return
            end

            if isManual and initiator == GetPlayerServerId(PlayerId()) then
                return
            end

            applyStationLocally(vehicle, station)

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
                stations = Config.Stations,
                locales = GetUiLocales(),
            })
        end
    end
end)

-- No server state yet: start OFF (ignore GTA autoplay)
RegisterNetEvent('nyn_carradio:client:initializeRadioState', function(netId)
    CreateThread(function()
        Wait(100)
        local vehicle = getVehicle()

        if vehicle and vehicle ~= 0 and VehToNet(vehicle) == netId then
            forceRadioOff(vehicle)
            TriggerServerEvent('nyn_carradio:server:setRadio', netId, offStationPayload(), false)
        end
    end)
end)

CreateThread(function()
    debugPrint('client started')
    local lastVehicle = 0

    while true do
        local vehicle = getVehicle()

        -- Enter vehicle: kill GTA radio immediately, then sync our state
        if vehicle ~= 0 and lastVehicle == 0 then
            killNativeRadio(vehicle)
            SendNUIMessage({ action = 'stopAll', locales = GetUiLocales() })

            if isEmergencyVehicle(vehicle) then
                forceRadioOff(vehicle)
            else
                TriggerServerEvent('nyn_carradio:server:requestRadioState', VehToNet(vehicle))
            end
        end

        -- Exit vehicle: restore default radio control
        if vehicle == 0 and lastVehicle ~= 0 then
            if isUIOpen then
                isUIOpen = false
                isUIOpenInHoldMode = false
                SendNUIMessage({ action = 'close' })
            end
            isHolding = false
            SendNUIMessage({ action = 'stopAll', locales = GetUiLocales() })
            SetUserRadioControlEnabled(true)
        end

        lastVehicle = vehicle

        if vehicle ~= 0 then
            suppressDefaultRadioHud(vehicle)

            if isEmergencyVehicle(vehicle) then
                killNativeRadio(vehicle)
                if isUIOpen then
                    isUIOpen = false
                    isUIOpenInHoldMode = false
                    SendNUIMessage({ action = 'close' })
                end
                isHolding = false
            elseif isUIOpen then
                DisableControlAction(0, 14, true)
                DisableControlAction(0, 15, true)
                DisableControlAction(0, 174, true)
                DisableControlAction(0, 175, true)

                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 37, true)
                DisableControlAction(0, 44, true)
                DisableControlAction(0, 140, true)

                if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 175) then
                    SendNUIMessage({ action = 'nextStation' })
                elseif IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 174) then
                    SendNUIMessage({ action = 'prevStation' })
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

----------------------------------------------------------------------
-- EXTENSION BRIDGE — drop-in nyn_carradio_plus (YouTube přes xsound)
----------------------------------------------------------------------

local isExtensionOpen = false

local function extensionResource()
    return Config.ExtensionResource or 'nyn_carradio_plus'
end

local function hasExtension()
    return GetResourceState(extensionResource()) == 'started'
end

local function extensionInfo()
    if not hasExtension() then
        return { available = false, xsound = false, features = {} }
    end

    local ok, info = pcall(function()
        return exports[extensionResource()]:GetInfo()
    end)

    if ok and type(info) == 'table' then
        info.available = true
        return info
    end

    return {
        available = true,
        xsound = GetResourceState('xsound') == 'started',
        features = { youtube = true },
    }
end

local function openExtensionUI()
    if not Config.EnableExtension then return end
    if isExtensionOpen then return end

    isExtensionOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openExtension',
        tab = 'search',
        extension = extensionInfo(),
        state = hasExtension() and (function()
            local ok, st = pcall(function()
                return exports[extensionResource()]:GetState()
            end)
            return ok and st or nil
        end)() or nil,
    })
end

local function closeExtensionUI()
    if not isExtensionOpen then return end
    isExtensionOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeExtension' })
end

RegisterCommand(Config.ExtensionCommand or 'carradio', function()
    if not Config.EnableExtension then return end
    if isExtensionOpen then
        closeExtensionUI()
    else
        openExtensionUI()
    end
end, false)

RegisterNUICallback('closeExtension', function(_, cb)
    isExtensionOpen = false
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNUICallback('extensionPlay', function(data, cb)
    if not hasExtension() then
        cb({ ok = false, error = 'missing_extension' })
        return
    end

    local vehicle = getVehicle()
    if not vehicle or vehicle == 0 then
        if nyn_lib and nyn_lib.client and nyn_lib.client.Notify then
            nyn_lib.client.Notify('error', 'Car Radio+', 'Musíš sedět ve vozidle.')
        end
        cb({ ok = false, error = 'not_in_vehicle' })
        return
    end

    local ok, err = exports[extensionResource()]:Play({
        url = data and data.url,
        title = data and data.title,
        volume = data and data.volume,
        distance = data and data.distance,
    })

    cb({ ok = ok and true or false, error = err })
end)

RegisterNUICallback('extensionPause', function(_, cb)
    if not hasExtension() then
        cb({ ok = false })
        return
    end
    cb({ ok = exports[extensionResource()]:Pause() and true or false })
end)

RegisterNUICallback('extensionResume', function(_, cb)
    if not hasExtension() then
        cb({ ok = false })
        return
    end
    cb({ ok = exports[extensionResource()]:Resume() and true or false })
end)

RegisterNUICallback('extensionStop', function(_, cb)
    if not hasExtension() then
        cb({ ok = false })
        return
    end
    cb({ ok = exports[extensionResource()]:Stop() and true or false })
end)
