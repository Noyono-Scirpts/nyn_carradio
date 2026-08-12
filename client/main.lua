---@diagnostic disable: undefined-global

local isUIOpen = false
local isUIOpenInHoldMode = false
local isHolding = false
local pressTime = 0
local uiOpened = false
local currentStation = nil -- last applied station (for native keep-alive)
local isExtensionOpen = false

local uiLocales = nil
local nuiBootstrapped = false

local cachedVehicle = 0
local cachedIsEmergency = false
local cachedPlusActive = false
local lastPlusCheck = 0
local lastNativeKeepAlive = 0

local PLUS_CHECK_MS = 400
local NATIVE_KEEPALIVE_MS = 500
local HUD_CONTROLS = { 81, 82, 83, 84, 85 }

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

local function invalidatePlusCache(active)
    if active == nil then
        lastPlusCheck = 0
        return
    end
    cachedPlusActive = active
    lastPlusCheck = GetGameTimer()
end

local function markPlusSessionEnded()
    cachedPlusActive = false
    lastPlusCheck = GetGameTimer()
end

RegisterNetEvent('nyn_carradio:client:plusSessionEnded', markPlusSessionEnded)
AddEventHandler('nyn_carradio:client:plusSessionEnded', markPlusSessionEnded)
exports('PlusSessionEnded', markPlusSessionEnded)

local function refreshPlusActive()
    local now = GetGameTimer()
    if now - lastPlusCheck < PLUS_CHECK_MS then
        return cachedPlusActive
    end
    lastPlusCheck = now
    cachedPlusActive = isPlusSessionActive()
    return cachedPlusActive
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

local function refreshVehicleCache(vehicle)
    if vehicle == cachedVehicle then
        return cachedIsEmergency
    end
    cachedVehicle = vehicle
    cachedIsEmergency = vehicle ~= 0 and isEmergencyVehicle(vehicle) or false
    return cachedIsEmergency
end

local function getUiLocales()
    if not uiLocales then
        uiLocales = GetUiLocales()
    end
    return uiLocales
end

local function bootstrapNui(force)
    if nuiBootstrapped and not force then return end
    nuiBootstrapped = true
    SendNUIMessage({
        action = 'init',
        stations = Config.Stations,
        locales = getUiLocales(),
    })
end

local function sendNui(payload)
    if type(payload) ~= 'table' then return end
    SendNUIMessage(payload)
end

--- Always attach stations so NUI never opens with an empty carousel (init can race).
local function sendRadioUi(action, extra)
    local payload = {
        action = action,
        stations = Config.Stations,
        locales = getUiLocales(),
    }
    if type(extra) == 'table' then
        for k, v in pairs(extra) do
            payload[k] = v
        end
    end
    sendNui(payload)
end

---@return number
local function getVehicle()
    return nyn_lib.client.GetCurrentVehicle()
end

--- Seat index for ped in vehicle, or nil
---@param vehicle number
---@param ped number|nil
---@return number|nil
local function getPedSeat(vehicle, ped)
    ped = ped or PlayerPedId()
    if not vehicle or vehicle == 0 or not ped or ped == 0 then return nil end
    local maxPassengers = GetVehicleMaxNumberOfPassengers(vehicle)
    for seat = -1, maxPassengers - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            return seat
        end
    end
    return nil
end

--- Driver (-1) + front passenger (0), unless Config.AllowRearSeatControl (base Q radio only).
---@param vehicle number|nil
---@param notifyBlocked boolean|nil
---@return boolean
local function canControlRadio(vehicle, notifyBlocked)
    vehicle = vehicle or getVehicle()
    if not vehicle or vehicle == 0 then
        return false
    end
    if Config.AllowRearSeatControl then
        return true
    end
    local seat = getPedSeat(vehicle)
    if seat == -1 or seat == 0 then
        return true
    end
    if notifyBlocked and Config.NotifyOnBlocked ~= false then
        notify('error', 'notify_seat_title', 'notify_seat')
    end
    return false
end

exports('CanControlRadio', function(vehicle)
    return canControlRadio(vehicle, false)
end)

--- Plus seat rules from nyn_carradio_plus Config.AllowRearSeatControl (not base Q).
---@param vehicle number|nil
---@param notifyBlocked boolean|nil
---@return boolean
local function canControlPlus(vehicle, notifyBlocked)
    vehicle = vehicle or getVehicle()
    if not vehicle or vehicle == 0 then
        return false
    end

    local res = Config.ExtensionResource or 'nyn_carradio_plus'
    if GetResourceState(res) == 'started' then
        local ok, allowed = pcall(function()
            return exports[res]:CanControlRadio(vehicle)
        end)
        if ok then
            if allowed then
                return true
            end
            if notifyBlocked and Config.NotifyOnBlocked ~= false then
                notify('error', 'notify_seat_title', 'notify_seat')
            end
            return false
        end
    end

    -- Plus missing / old export: keep front seats only
    return canControlRadio(vehicle, notifyBlocked)
end

---@param vehicle number
local function killNativeRadio(vehicle)
    if not vehicle or vehicle == 0 then return end
    SetVehicleRadioEnabled(vehicle, false)
    SetVehRadioStation(vehicle, 'OFF')
end

---@param vehicle number
local function suppressDefaultRadioHudFrame()
    HideHudComponentThisFrame(16)
    for i = 1, #HUD_CONTROLS do
        DisableControlAction(0, HUD_CONTROLS[i], true)
    end
end

local function maintainNativeStation(vehicle, isEmergency)
    if isEmergency then return end
    if not currentStation or currentStation.type ~= 'native' or not currentStation.value then
        return
    end

    local now = GetGameTimer()
    if now - lastNativeKeepAlive < NATIVE_KEEPALIVE_MS then
        return
    end
    lastNativeKeepAlive = now

    SetVehicleRadioEnabled(vehicle, true)
    if GetPlayerRadioStationName() ~= currentStation.value then
        SetVehRadioStation(vehicle, currentStation.value)
    end
end

local function openRadioUI()
    isUIOpen = true
    isUIOpenInHoldMode = true
    bootstrapNui(true)
    sendRadioUi('open')
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
    lastNativeKeepAlive = 0

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

    if not canControlRadio(vehicle, true) then
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
                    if not canControlRadio(currentVehicle, true) then
                        isHolding = false
                        break
                    end
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

    if not canControlRadio(vehicle, true) then
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
            bootstrapNui(true)
            sendRadioUi('cycleNext')
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

        if not canControlRadio(vehicle, true) then
            cb({ ok = false, error = 'seat' })
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

            bootstrapNui(true)
            sendRadioUi('syncVisuals', {
                index = station.index,
                name = station.name,
                image = station.image,
                type = station.type,
                showUI = shouldShowUI,
            })
        end
    end
end)

RegisterNetEvent('nyn_carradio:client:initializeRadioState', function(netId)
    CreateThread(function()
        Wait(100)
        local vehicle = getVehicle()

        if vehicle and vehicle ~= 0 and VehToNet(vehicle) == netId then
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
    Wait(250)
    bootstrapNui()
end)

CreateThread(function()
    debugPrint('client started')
    local lastVehicle = 0

    while true do
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle ~= 0 and lastVehicle == 0 then
            SetUserRadioControlEnabled(false)
            killNativeRadio(vehicle)
            invalidatePlusCache(isPlusSessionActive())
            bootstrapNui(true)
            if cachedPlusActive then
                sendNui({ action = 'stopStream' })
            else
                sendNui({ action = 'stopAll' })
            end

            if refreshVehicleCache(vehicle) then
                forceRadioOff(vehicle)
            else
                TriggerServerEvent('nyn_carradio:server:requestRadioState', VehToNet(vehicle))
            end
        end

        if vehicle == 0 and lastVehicle ~= 0 then
            cachedVehicle = 0
            cachedIsEmergency = false
            lastNativeKeepAlive = 0
            if isUIOpen then
                isUIOpen = false
                isUIOpenInHoldMode = false
                sendNui({ action = 'close' })
            end
            if isExtensionOpen then
                isExtensionOpen = false
                SetNuiFocus(false, false)
                sendNui({ action = 'closeExtension' })
            end
            isHolding = false
            currentStation = nil
            invalidatePlusCache(isPlusSessionActive())
            if cachedPlusActive then
                sendNui({ action = 'stopStream' })
            else
                sendNui({ action = 'stopAll' })
            end
            SetUserRadioControlEnabled(true)
        end

        lastVehicle = vehicle

        if vehicle ~= 0 then
            suppressDefaultRadioHudFrame()

            local isEmergency = refreshVehicleCache(vehicle)
            local plusActive = refreshPlusActive()

            maintainNativeStation(vehicle, isEmergency)

            if isEmergency then
                killNativeRadio(vehicle)
                if isUIOpen then
                    isUIOpen = false
                    isUIOpenInHoldMode = false
                    sendNui({ action = 'close' })
                end
                isHolding = false
            elseif not isExtensionOpen and not plusActive and canControlRadio(vehicle, false) then
                DisableControlAction(0, 14, true)
                DisableControlAction(0, 15, true)

                if isUIOpenInHoldMode then
                    DisableControlAction(0, 174, true)
                    DisableControlAction(0, 175, true)
                    DisableControlAction(0, 24, true)
                    DisableControlAction(0, 25, true)
                    DisableControlAction(0, 37, true)
                    DisableControlAction(0, 44, true)
                    DisableControlAction(0, 140, true)
                end

                local wheelNext = IsDisabledControlJustPressed(0, 14)
                local wheelPrev = IsDisabledControlJustPressed(0, 15)
                -- Quick scroll: wheel down = next. Hold-Q UI: both wheel + arrows.
                local nextPressed = wheelNext
                    or (isUIOpenInHoldMode and IsDisabledControlJustPressed(0, 175))
                local prevPressed = (isUIOpenInHoldMode and (wheelPrev or IsDisabledControlJustPressed(0, 174)))
                    or false

                if nextPressed then
                    bootstrapNui(true)
                    if isUIOpen then
                        sendRadioUi('nextStation')
                    else
                        isUIOpen = true
                        sendRadioUi('cycleNext')
                    end
                elseif prevPressed then
                    bootstrapNui(true)
                    sendRadioUi('prevStation')
                end
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)

local function forwardNuiMessage(payload)
    if type(payload) == 'table' then
        SendNUIMessage(payload)
    end
end

RegisterNetEvent('nyn_carradio:client:forwardNui', forwardNuiMessage)
AddEventHandler('nyn_carradio:client:forwardNui', forwardNuiMessage)

exports('ForwardNui', forwardNuiMessage)


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

    if not canControlPlus(vehicle, true) then
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
    bootstrapNui()
    SendNUIMessage({
        action = 'openExtension',
        tab = 'now',
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

    if not canControlPlus(vehicle, true) then
        cb({ ok = false, error = 'seat' })
        return
    end

    local ok, err = exports[extensionResource()]:Play({
        url = data and data.url,
        title = data and data.title,
        thumbnail = data and data.thumbnail,
        volume = data and data.volume,
        distance = data and data.distance,
        clientPlaying = data and data.clientPlaying,
    })

    if ok == true or ok == 1 then
        invalidatePlusCache(true)
        cb({ ok = true })
    else
        local errCode = type(err) == 'string' and err or 'play_failed'
        local msg = errCode == 'no_xsound'
            and 'Video nelze pĹ™ehrĂˇt â€” xsound nebÄ›ĹľĂ­.'
            or 'Video nelze pĹ™ehrĂˇt.'
        notify('error', 'Car Radio+', msg)
        cb({ ok = false, error = errCode })
    end
end)

RegisterNUICallback('extensionPause', function(_, cb)
    if not hasExtension() then
        cb({ ok = false })
        return
    end
    if not canControlPlus(nil, true) then
        cb({ ok = false, error = 'seat' })
        return
    end
    cb({ ok = exports[extensionResource()]:Pause() and true or false })
end)

RegisterNUICallback('extensionResume', function(_, cb)
    if not hasExtension() then
        cb({ ok = false })
        return
    end
    if not canControlPlus(nil, true) then
        cb({ ok = false, error = 'seat' })
        return
    end
    cb({ ok = exports[extensionResource()]:Resume() and true or false })
end)

RegisterNUICallback('extensionStop', function(_, cb)
    if not hasExtension() then
        cb({ ok = false })
        return
    end
    if not canControlPlus(nil, true) then
        cb({ ok = false, error = 'seat' })
        return
    end
    pcall(function()
        exports[extensionResource()]:Stop()
    end)
    markPlusSessionEnded()
    cb({ ok = true })
end)

RegisterNUICallback('extensionSkip', function(_, cb)
    if not hasExtension() then
        cb({ ok = false, error = 'missing_extension' })
        return
    end
    if not canControlPlus(nil, true) then
        cb({ ok = false, error = 'seat' })
        return
    end
    local ok, err = exports[extensionResource()]:Skip()
    cb({ ok = ok and true or false, error = type(err) == 'string' and err or nil })
end)

RegisterNUICallback('extensionQueue', function(data, cb)
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

    if not canControlPlus(vehicle, true) then
        cb({ ok = false, error = 'seat' })
        return
    end

    local ok, err = exports[extensionResource()]:Queue({
        url = data and data.url,
        title = data and data.title,
        thumbnail = data and data.thumbnail,
        volume = data and data.volume,
    })

    if ok == true or ok == 1 then
        invalidatePlusCache(true)
        cb({ ok = true })
    else
        cb({ ok = false, error = type(err) == 'string' and err or 'play_failed' })
    end
end)

RegisterNUICallback('extensionSetVolume', function(data, cb)
    if not hasExtension() then
        cb({ ok = false, error = 'missing_extension' })
        return
    end
    if not canControlPlus(nil, true) then
        cb({ ok = false, error = 'seat' })
        return
    end
    local ok = exports[extensionResource()]:SetVolume(data and data.volume)
    cb({ ok = ok and true or false })
end)

RegisterNUICallback('extensionResolveMeta', function(data, cb)
    if not hasExtension() then
        cb({ ok = false, results = {} })
        return
    end
    local urls = data and data.urls
    if type(urls) ~= 'table' then
        cb({ ok = true, results = {} })
        return
    end
    local ok, results = pcall(function()
        return exports[extensionResource()]:ResolveMetaBatch(urls)
    end)
    cb({ ok = ok and true or false, results = (ok and results) or {} })
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

    if not canControlPlus(vehicle, true) then
        cb({ ok = false, error = 'seat' })
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
