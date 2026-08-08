---@diagnostic disable: undefined-global

local isUIOpen = false
local isUIOpenInHoldMode = false
local isHolding = false
local pressTime = 0
local uiOpened = false
local currentStation = nil -- last applied station (for native keep-alive)
local isExtensionOpen = false

local function debugPrint(...)
    if not Config.Debug then return end
    print(('[nyn_carradio:client] %s'):format(table.concat({ ... }, ' ')))
end

local function notify(nType, titleOrKey, messageOrKey, duration)
    local title = Locale(titleOrKey)
    local message = Locale(messageOrKey)
    if not title or title == '' then return end
    message = message or ''
    duration = duration or 4000
    nType = nType or 'info'

    local system = Config.Notify or 'nyn_lib'

    if system == 'ox_lib' and GetResourceState('ox_lib') == 'started' then
        exports.ox_lib:notify({
            title = title,
            description = message,
            type = nType == 'success' and 'success' or (nType == 'error' and 'error' or 'inform'),
            duration = duration,
        })
        return
    end

    -- Default: naše nyn_lib notifikace
    if GetResourceState('nyn_lib') == 'started' then
        local ok = pcall(function()
            exports.nyn_lib:newnotification(nType, title, message, duration)
        end)
        if ok then return end
    end

    if GetResourceState('ox_lib') == 'started' then
        exports.ox_lib:notify({
            title = title,
            description = message,
            type = nType == 'success' and 'success' or (nType == 'error' and 'error' or 'inform'),
            duration = duration,
        })
    end
end

RegisterNetEvent('nyn_carradio:client:notify', function(nType, title, message, duration)
    notify(nType, title, message, duration)
end)

--- Active Car Radio+ session (playing or paused) — blocks base Q radio
local function isPlusSessionActive()
    local ext = Config.ExtensionResource or 'nyn_carradio_plus'
    if GetResourceState(ext) ~= 'started' then return false end
    local active = false
    pcall(function()
        local st = exports[ext]:GetState()
        active = st and (st.playing or st.paused) and true or false
    end)
    return active
end

local function notifyPlusBlockingQ()
    if Config.NotifyOnBlocked == false then return end
    notify('error', 'notify_plus_busy_title', 'notify_plus_busy')
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
    currentStation = station

    -- Stop plus ONLY when user picks a real base station (native/stream).
    -- Never kill Plus for off / virgin init — that races re-enter and silences cabin audio.
    if station.type == 'native' or station.type == 'stream' then
        local ext = Config.ExtensionResource or 'nyn_carradio_plus'
        if GetResourceState(ext) == 'started' then
            local playing = false
            pcall(function()
                local st = exports[ext]:GetState()
                playing = st and (st.playing or st.paused) and true or false
            end)
            if playing then
                pcall(function()
                    exports[ext]:Stop()
                end)
            end
        end
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
        -- Plus handles its own xsound; base only stops HTML stream
        killNativeRadio(vehicle)
        SendNUIMessage({ action = 'stopStream' })
    else -- off / fallback
        -- If Plus is still playing on this car, keep it — don't push silence
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

    if isPlusSessionActive() then
        notifyPlusBlockingQ()
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
                    if isPlusSessionActive() then
                        notifyPlusBlockingQ()
                        isHolding = false
                        break
                    end
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

    if isPlusSessionActive() then
        if isUIOpenInHoldMode then
            closeRadioUI()
        end
        notifyPlusBlockingQ()
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

        if isPlusSessionActive() then
            notifyPlusBlockingQ()
            cb({ ok = false, error = 'plus_busy' })
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
            -- Plus may still be playing after exit (cabin muffling) even when base
            -- has no station yet — never force OFF / broadcast that stops Plus.
            if isPlusSessionActive() then
                killNativeRadio(vehicle)
                SendNUIMessage({ action = 'stopStream' })
                return
            end
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
            -- stopAll also kills Plus NUI media — only stop base HTML stream when Plus is live
            if isPlusSessionActive() then
                SendNUIMessage({ action = 'stopStream', locales = GetUiLocales() })
            else
                SendNUIMessage({ action = 'stopAll', locales = GetUiLocales() })
            end

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
            if isExtensionOpen then
                isExtensionOpen = false
                SetNuiFocus(false, false)
                SendNUIMessage({ action = 'closeExtension' })
            end
            isHolding = false
            currentStation = nil
            -- Keep Plus cabin audio on the car; only stop base HTML streams
            if isPlusSessionActive() then
                SendNUIMessage({ action = 'stopStream', locales = GetUiLocales() })
            else
                SendNUIMessage({ action = 'stopAll', locales = GetUiLocales() })
            end
            SetUserRadioControlEnabled(true)
        end

        lastVehicle = vehicle

        if vehicle ~= 0 then
            suppressDefaultRadioHud(vehicle)

            -- Keep GTA native station alive (other scripts often force OFF)
            if currentStation and currentStation.type == 'native' and currentStation.value then
                if not isEmergencyVehicle(vehicle) then
                    SetVehicleRadioEnabled(vehicle, true)
                    if GetPlayerRadioStationName() ~= currentStation.value then
                        SetVehRadioStation(vehicle, currentStation.value)
                    end
                end
            end

            if isEmergencyVehicle(vehicle) then
                killNativeRadio(vehicle)
                if isUIOpen then
                    isUIOpen = false
                    isUIOpenInHoldMode = false
                    SendNUIMessage({ action = 'close' })
                end
                isHolding = false
            elseif not isExtensionOpen and not isPlusSessionActive() then
                -- Mouse wheel = radio (same as GTA in-vehicle); works with UI closed too
                DisableControlAction(0, 14, true)
                DisableControlAction(0, 15, true)

                if isUIOpen then
                    DisableControlAction(0, 174, true)
                    DisableControlAction(0, 175, true)
                    DisableControlAction(0, 24, true)
                    DisableControlAction(0, 25, true)
                    DisableControlAction(0, 37, true)
                    DisableControlAction(0, 44, true)
                    DisableControlAction(0, 140, true)
                end

                local nextPressed = IsDisabledControlJustPressed(0, 14)
                    or (isUIOpen and IsDisabledControlJustPressed(0, 175))
                local prevPressed = IsDisabledControlJustPressed(0, 15)
                    or (isUIOpen and IsDisabledControlJustPressed(0, 174))

                if nextPressed then
                    if isUIOpen then
                        SendNUIMessage({ action = 'nextStation' })
                    else
                        isUIOpen = true
                        SendNUIMessage({
                            action = 'cycleNext',
                            stations = Config.Stations,
                            locales = GetUiLocales(),
                        })
                    end
                elseif prevPressed then
                    if isUIOpen then
                        SendNUIMessage({ action = 'prevStation' })
                    else
                        isUIOpen = true
                        SendNUIMessage({
                            action = 'cyclePrev',
                            stations = Config.Stations,
                            locales = GetUiLocales(),
                        })
                    end
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

--- Plus (no ui_page) forwards NUI payloads here so SendNUIMessage runs in base
local function forwardNuiMessage(payload)
    if type(payload) == 'table' then
        SendNUIMessage(payload)
    end
end

RegisterNetEvent('nyn_carradio:client:forwardNui', forwardNuiMessage)
AddEventHandler('nyn_carradio:client:forwardNui', forwardNuiMessage)

exports('ForwardNui', forwardNuiMessage)

----------------------------------------------------------------------
-- EXTENSION BRIDGE — drop-in nyn_carradio_plus (YouTube přes xsound)
----------------------------------------------------------------------

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
    if not Config.EnableExtension then
        if Config.NotifyOnBlocked ~= false then
            notify('error', 'notify_plus_missing_title', 'notify_extension_disabled')
        end
        return false
    end
    if isExtensionOpen then return true end

    local vehicle = getVehicle()
    if not vehicle or vehicle == 0 then
        if Config.NotifyOnBlocked ~= false then
            notify('error', 'notify_not_in_vehicle_title', 'notify_not_in_vehicle')
        end
        return false
    end

    if not hasExtension() then
        if Config.NotifyOnBlocked ~= false then
            notify('error', 'notify_plus_missing_title', 'notify_plus_missing')
        end
        return false
    end

    isExtensionOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openExtension',
        tab = 'stations',
        extension = extensionInfo(),
        state = (function()
            local ok, st = pcall(function()
                return exports[extensionResource()]:GetState()
            end)
            return ok and st or nil
        end)(),
    })
    return true
end

local function closeExtensionUI()
    if not isExtensionOpen then return false end
    isExtensionOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeExtension' })
    return true
end

local function toggleExtensionUI()
    if isExtensionOpen then
        return closeExtensionUI()
    end
    return openExtensionUI()
end

--- Used by nyn_carradio_plus (command / keybind žijí v + scriptu)
exports('OpenExtension', openExtensionUI)
exports('CloseExtension', closeExtensionUI)
exports('ToggleExtension', toggleExtensionUI)
exports('IsExtensionOpen', function()
    return isExtensionOpen
end)
exports('IsExtensionEnabled', function()
    return Config.EnableExtension == true
end)

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
        notify('error', 'notify_not_in_vehicle_title', 'notify_not_in_vehicle')
        cb({ ok = false, error = 'not_in_vehicle' })
        return
    end

    local ok, err = exports[extensionResource()]:Play({
        url = data and data.url,
        title = data and data.title,
        volume = data and data.volume,
        distance = data and data.distance,
        clientPlaying = data and data.clientPlaying,
    })

    -- FiveM export někdy nevrátí 2. hodnotu spolehlivě
    if ok == true or ok == 1 then
        cb({ ok = true })
    else
        local errCode = type(err) == 'string' and err or 'play_failed'
        local msg = errCode == 'no_xsound'
            and 'Video nelze přehrát — xsound neběží.'
            or 'Video nelze přehrát.'
        notify('error', 'Car Radio+', msg)
        cb({ ok = false, error = errCode })
    end
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

RegisterNUICallback('extensionSetVolume', function(data, cb)
    if not hasExtension() then
        cb({ ok = false, error = 'missing_extension' })
        return
    end
    local ok = exports[extensionResource()]:SetVolume(data and data.volume)
    cb({ ok = ok and true or false })
end)

RegisterNUICallback('extensionPlaylist', function(data, cb)
    if not hasExtension() then
        cb({ ok = false, error = 'missing_extension' })
        return
    end
    local action = data and data.action
    if type(action) ~= 'string' or action == '' then
        cb({ ok = false, error = 'invalid' })
        return
    end

    local ok, result = pcall(function()
        return exports[extensionResource()]:PlaylistAction(action, data and data.payload or {})
    end)
    if not ok then
        cb({ ok = false, error = 'export_failed' })
        return
    end
    cb(type(result) == 'table' and result or { ok = false, error = 'bad_result' })
end)

RegisterNUICallback('extensionPlayPlaylist', function(data, cb)
    if not hasExtension() then
        cb({ ok = false, error = 'missing_extension' })
        return
    end

    local vehicle = getVehicle()
    if not vehicle or vehicle == 0 then
        notify('error', 'notify_not_in_vehicle_title', 'notify_not_in_vehicle')
        cb({ ok = false, error = 'not_in_vehicle' })
        return
    end

    local playlistId = data and data.id
    local volume = data and data.volume
    local ok, err = exports[extensionResource()]:PlayPlaylist(playlistId, volume)
    if ok == true or ok == 1 then
        cb({ ok = true })
    else
        cb({ ok = false, error = type(err) == 'string' and err or 'play_failed' })
    end
end)
