local busy = false
local lastStoredVehicle
local valetPed
local attendantPeds = {}
local attendantProps = {}
local openGarageId
local openImpoundId
local openMode = 'garage'
local promptVisible = false
local currentStoreGarage
local cleanupValet
local nuiReady = false
local lastGaragePayload

local function notify(message, type)
    if Config.UsePoudNotify and GetResourceState('Poud_notify') == 'started' then
        exports.Poud_notify:Notify(message, type or 'info', 4500)
        return
    end

    ESX.ShowNotification(message)
end

local function getUiText(overrides)
    local text = {}

    for key, value in pairs(Config.Text) do
        text[key] = value
    end

    for key, value in pairs(overrides or {}) do
        text[key] = value
    end

    return text
end

RegisterNetEvent('Poud_garage:notify', function(message, type)
    notify(message, type)
end)

local function closeGarageUi()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    openGarageId = nil
    openImpoundId = nil
    openMode = 'garage'
    lastGaragePayload = nil
end

local function sendGarageUi(payload)
    lastGaragePayload = payload
    SendNUIMessage(payload)

    CreateThread(function()
        for _ = 1, 8 do
            if nuiReady then return end

            Wait(250)
            SendNUIMessage(payload)
        end
    end)
end

local function setParkingPrompt(visible, garage)
    if promptVisible == visible and currentStoreGarage == garage then return end

    promptVisible = visible
    currentStoreGarage = garage
end

local function createBlip(coords, label, settings)
    settings = settings or Config.Blips
    if not settings.enabled then return end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, settings.sprite)
    SetBlipColour(blip, settings.color)
    SetBlipScale(blip, settings.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
end

local function trimPlate(plate)
    plate = tostring(plate or '')

    if Config.TrimPlate then
        plate = plate:gsub('^%s*(.-)%s*$', '%1')
    end

    return plate
end

local function loadModel(model)
    if HasModelLoaded(model) then return true end

    RequestModel(model)

    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) do
        Wait(10)

        if GetGameTimer() > timeout then
            return false
        end
    end

    return true
end

local function drawText(text, x, y, scale, colour, center)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(colour.r, colour.g, colour.b, colour.a)
    SetTextCentre(center == true)
    SetTextDropshadow(0, 0, 0, 0, 0)
    SetTextEdge(0, 0, 0, 0, 0)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function drawTextRight(text, rightX, y, scale, colour)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(colour.r, colour.g, colour.b, colour.a)
    SetTextCentre(false)
    SetTextRightJustify(true)
    SetTextWrap(0.0, rightX)
    SetTextDropshadow(0, 0, 0, 0, 0)
    SetTextEdge(0, 0, 0, 0, 0)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, y)
    SetTextRightJustify(false)
end

local function drawParkingBox()
    if not Config.ParkingBox.enabled then return end

    local box = Config.ParkingBox
    local x = box.x
    local y = box.y
    local width = box.width
    local height = box.height
    local keyWidth = 0.020
    local keyHeight = height * 0.52
    local keyX = x
    local textY = y - 0.012
    local gap = 0.009
    local leftTextRightX = keyX - (keyWidth / 2) - gap
    local rightTextX = keyX + (keyWidth / 2) + gap

    DrawRect(x, y, width, height, box.background.r, box.background.g, box.background.b, box.background.a)
    DrawRect(keyX, y, keyWidth, keyHeight, box.keyBackground.r, box.keyBackground.g, box.keyBackground.b, box.keyBackground.a)

    drawTextRight(Config.Text.parkBoxBefore, leftTextRightX, textY, 0.30, box.text)
    drawText(Config.StoreKeyLabel, keyX, textY, 0.29, box.keyText, true)
    drawText(Config.Text.parkBoxAfter, rightTextX, textY, 0.30, box.text, false)
end

local function isSpawnClear(coords)
    return ESX.Game.IsSpawnPointClear(vec3(coords.x, coords.y, coords.z), Config.SpawnCheckRadius)
end

local function findAvailableSpawn(spawn)
    if isSpawnClear(spawn) then
        return spawn
    end

    local radius = Config.SpawnFallbackRadius
    local step = Config.SpawnFallbackStep

    for distance = step, radius, step do
        for angle = 0, 315, 45 do
            local radians = math.rad(angle)
            local coords = vec4(
                spawn.x + math.cos(radians) * distance,
                spawn.y + math.sin(radians) * distance,
                spawn.z,
                spawn.w
            )

            if isSpawnClear(coords) then
                return coords
            end
        end
    end

    return nil
end

local function getOffsetVec4(origin, offset)
    local x = origin.x + offset.x
    local y = origin.y + offset.y
    local z = origin.z + offset.z

    return vec4(x, y, z, origin.w)
end

local function spawnRetrievedVehicle(garageId, vehicleProps, spawnPoint)
    local garage = Config.Garages[garageId]
    if not garage or not vehicleProps or not vehicleProps.model then return end

    spawnPoint = spawnPoint or findAvailableSpawn(garage.spawn)

    if not spawnPoint then
        notify(Config.Text.spawnBlocked, 'error')
        return
    end

    closeGarageUi()

    ESX.Game.SpawnVehicle(vehicleProps.model, vec3(spawnPoint.x, spawnPoint.y, spawnPoint.z), spawnPoint.w, function(vehicle)
        ESX.Game.SetVehicleProperties(vehicle, vehicleProps)
        SetVehicleOnGroundProperly(vehicle)
        SetVehicleDoorsLocked(vehicle, 1)
        notify(Config.Text.vehicleRetrieved, 'success')
    end, true)
end

local function spawnImpoundedVehicle(impoundId, vehicleProps)
    local impound = Config.Impounds[impoundId]
    if not impound or not vehicleProps or not vehicleProps.model then return end

    local spawnPoint = findAvailableSpawn(impound.spawn)
    if not spawnPoint then
        notify(Config.Text.spawnBlocked, 'error')
        return
    end

    closeGarageUi()

    ESX.Game.SpawnVehicle(vehicleProps.model, vec3(spawnPoint.x, spawnPoint.y, spawnPoint.z), spawnPoint.w, function(vehicle)
        ESX.Game.SetVehicleProperties(vehicle, vehicleProps)
        SetVehicleOnGroundProperly(vehicle)
        SetVehicleDoorsLocked(vehicle, 1)
        notify(Config.Text.vehicleImpounded, 'success')
    end, true)
end

local function takeOutVehicle(garageId, plate)
    if busy then return end

    local garage = Config.Garages[garageId]
    if not garage then return end

    local spawnPoint = findAvailableSpawn(garage.spawn)

    if not spawnPoint then
        notify(Config.Text.spawnBlocked, 'error')
        return
    end

    busy = true

    ESX.TriggerServerCallback('Poud_garage:takeOutVehicle', function(success, data)
        busy = false

        if not success then
            notify(data or Config.Text.invalidVehicle, 'error')
            return
        end

        spawnRetrievedVehicle(garageId, data, spawnPoint)
    end, garageId, plate)
end

local function openGarage(garageId)
    if busy then return end

    local garage = Config.Garages[garageId]
    if not garage then return end

    openGarageId = garageId
    openImpoundId = nil
    openMode = 'garage'
    SetNuiFocus(true, true)
    sendGarageUi({
        action = 'open',
        loading = true,
        garage = {
            id = garageId,
            label = garage.label
        },
        vehicles = {},
        text = Config.Text
    })

    busy = true

    ESX.TriggerServerCallback('Poud_garage:getVehicles', function(vehicles, message)
        busy = false

        if message then
            notify(message, 'error')
            sendGarageUi({
                action = 'updateVehicles',
                loading = false,
                vehicles = {},
                text = Config.Text
            })
            return
        end

        sendGarageUi({
            action = 'updateVehicles',
            loading = false,
            vehicles = vehicles or {},
            text = Config.Text
        })
    end, garageId)
end

local function openImpound(impoundId)
    if busy then return end

    local impound = Config.Impounds[impoundId]
    if not impound then return end

    openGarageId = nil
    openImpoundId = impoundId
    openMode = 'impound'
    SetNuiFocus(true, true)
    sendGarageUi({
        action = 'open',
        loading = true,
        garage = {
            id = impoundId,
            label = impound.label
        },
        vehicles = {},
        text = getUiText({
            garageTitle = Config.Text.impoundTitle,
            noVehicles = Config.Text.noImpoundedVehicles
        })
    })

    busy = true

    ESX.TriggerServerCallback('Poud_garage:getImpoundedVehicles', function(vehicles, message)
        busy = false

        if message then
            notify(message, 'error')
            sendGarageUi({
                action = 'updateVehicles',
                loading = false,
                vehicles = {},
                text = getUiText({
                    garageTitle = Config.Text.impoundTitle,
                    noVehicles = Config.Text.noImpoundedVehicles
                })
            })
            return
        end

        for _, vehicle in ipairs(vehicles or {}) do
            vehicle.canTakeOut = true
            vehicle.actionLabel = Config.Text.retrieveVehicle
            vehicle.extraDescription = Config.Text.impoundFee:format(vehicle.fee or Config.Impound.fee)
        end

        sendGarageUi({
            action = 'updateVehicles',
            loading = false,
            vehicles = vehicles or {},
            text = getUiText({
                garageTitle = Config.Text.impoundTitle,
                noVehicles = Config.Text.noImpoundedVehicles
            })
        })
    end, impoundId)
end

RegisterCommand('poud_garage_testui', function()
    SetNuiFocus(true, true)
    sendGarageUi({
        action = 'open',
        loading = false,
        garage = {
            id = 'test',
            label = 'Test Garage'
        },
        vehicles = {
            {
                label = 'Test Vehicle',
                plate = 'TEST123',
                stored = true
            }
        },
        text = Config.Text
    })
end, false)

cleanupValet = function()
    if valetPed and DoesEntityExist(valetPed) then
        DeleteEntity(valetPed)
    end

    valetPed = nil
end

local function cleanupAttendants()
    for _, prop in pairs(attendantProps) do
        if DoesEntityExist(prop) then
            DeleteEntity(prop)
        end
    end

    for _, ped in pairs(attendantPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end

    attendantPeds = {}
    attendantProps = {}
end

local function finishStoreVehicle(garageId, vehicle, props)
    lastStoredVehicle = vehicle
    TriggerServerEvent('Poud_garage:storeVehicle', garageId, props.plate, props)
end

local function runValetParking(garageId, vehicle, props)
    local ped = PlayerPedId()

    if not Config.Valet.enabled then
        finishStoreVehicle(garageId, vehicle, props)
        return
    end

    if not loadModel(Config.Valet.model) then
        finishStoreVehicle(garageId, vehicle, props)
        return
    end

    notify(Config.Text.parkingStarted, 'info')
    TaskLeaveVehicle(ped, vehicle, 0)

    local leaveTimeout = GetGameTimer() + 4500
    while IsPedInVehicle(ped, vehicle, false) and GetGameTimer() < leaveTimeout do
        Wait(100)
    end

    local vehicleCoords = GetEntityCoords(vehicle)
    local spawnCoords = GetOffsetFromEntityInWorldCoords(vehicle, Config.Valet.spawnOffset.x, Config.Valet.spawnOffset.y, Config.Valet.spawnOffset.z)

    cleanupValet()
    valetPed = CreatePed(4, Config.Valet.model, spawnCoords.x, spawnCoords.y, spawnCoords.z, GetEntityHeading(vehicle), true, true)
    SetBlockingOfNonTemporaryEvents(valetPed, true)
    SetPedFleeAttributes(valetPed, 0, false)
    SetPedCanRagdoll(valetPed, false)

    TaskGoToCoordAnyMeans(valetPed, vehicleCoords.x, vehicleCoords.y, vehicleCoords.z, Config.Valet.walkSpeed, 0, false, 786603, 0.0)

    local walkTimeout = GetGameTimer() + 7000
    while #(GetEntityCoords(valetPed) - vehicleCoords) > 3.0 and GetGameTimer() < walkTimeout do
        Wait(100)
    end

    TaskEnterVehicle(valetPed, vehicle, 8000, -1, 1.0, 1, 0)

    local enterTimeout = GetGameTimer() + 9000
    while not IsPedInVehicle(valetPed, vehicle, false) and GetGameTimer() < enterTimeout do
        Wait(100)
    end

    if IsPedInVehicle(valetPed, vehicle, false) then
        local driveCoords = GetOffsetFromEntityInWorldCoords(vehicle, Config.Valet.driveAwayOffset.x, Config.Valet.driveAwayOffset.y, Config.Valet.driveAwayOffset.z)
        TaskVehicleDriveToCoord(valetPed, vehicle, driveCoords.x, driveCoords.y, driveCoords.z, Config.Valet.driveSpeed, 0, GetEntityModel(vehicle), Config.Valet.drivingStyle, 3.0, true)
        Wait(Config.Valet.driveTime)
    end

    finishStoreVehicle(garageId, vehicle, props)
end

local function storeCurrentVehicle(garageId)
    if busy then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle == 0 then
        notify(Config.Text.noVehicle, 'error')
        return
    end

    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        notify(Config.Text.notDriver, 'error')
        return
    end

    local props = ESX.Game.GetVehicleProperties(vehicle)
    props.plate = trimPlate(props.plate)

    busy = true

    ESX.TriggerServerCallback('Poud_garage:canStoreVehicle', function(success, message)
        if not success then
            busy = false
            notify(message or Config.Text.notOwned, 'error')
            return
        end

        setParkingPrompt(false)
        runValetParking(garageId, vehicle, props)
    end, garageId, props.plate)
end

RegisterNetEvent('Poud_garage:deleteStoredVehicle', function()
    if lastStoredVehicle and DoesEntityExist(lastStoredVehicle) then
        ESX.Game.DeleteVehicle(lastStoredVehicle)
    end

    lastStoredVehicle = nil
    cleanupValet()
    busy = false
end)

RegisterNetEvent('Poud_garage:storeFailed', function()
    cleanupValet()
    busy = false
end)

RegisterNUICallback('close', function(_, cb)
    closeGarageUi()
    cb({ ok = true })
end)

RegisterNUICallback('ready', function(_, cb)
    nuiReady = true

    if lastGaragePayload then
        SendNUIMessage(lastGaragePayload)
    end

    cb({ ok = true })
end)

RegisterNUICallback('takeOut', function(data, cb)
    local garageId = data and data.garageId or openGarageId
    local plate = data and data.plate

    if openMode == 'impound' and openImpoundId and plate then
        if not busy then
            busy = true

            ESX.TriggerServerCallback('Poud_garage:retrieveImpoundedVehicle', function(success, result)
                busy = false

                if not success then
                    notify(result or Config.Text.invalidVehicle, 'error')
                    return
                end

                spawnImpoundedVehicle(openImpoundId, result)
            end, openImpoundId, plate)
        end
    elseif garageId and plate then
        takeOutVehicle(garageId, plate)
    end

    cb({ ok = true })
end)

RegisterCommand('poud_garage_close', function()
    closeGarageUi()
end, false)

RegisterKeyMapping('poud_garage_close', 'Close garage UI', 'keyboard', 'ESCAPE')

local function getNearestStoreGarage()
    local ped = PlayerPedId()

    if not IsPedInAnyVehicle(ped, false) then return nil end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil end

    local coords = GetEntityCoords(ped)

    for garageId, garage in pairs(Config.Garages) do
        if #(coords - garage.store) <= Config.ParkingPromptDistance then
            return garageId
        end
    end

    return nil
end

local function createGarageZones()
    for garageId, garage in pairs(Config.Garages) do
        createBlip(garage.coords, garage.label)

        if loadModel(Config.Attendant.model) then
            local npc = garage.npc or vec4(garage.coords.x, garage.coords.y, garage.coords.z, 0.0)
            local ped = CreatePed(4, Config.Attendant.model, npc.x, npc.y, npc.z - 1.0, npc.w, false, true)

            FreezeEntityPosition(ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)

            if Config.Attendant.scenario then
                TaskStartScenarioInPlace(ped, Config.Attendant.scenario, 0, true)
            end

            if Config.Attendant.prop and loadModel(Config.Attendant.prop) then
                local prop = CreateObject(Config.Attendant.prop, npc.x, npc.y, npc.z, false, false, false)
                local offset = Config.Attendant.propOffset
                local rotation = Config.Attendant.propRotation

                AttachEntityToEntity(
                    prop,
                    ped,
                    GetPedBoneIndex(ped, Config.Attendant.propBone),
                    offset.x, offset.y, offset.z,
                    rotation.x, rotation.y, rotation.z,
                    true, true, false, true, 1, true
                )

                attendantProps[garageId] = prop
            end

            attendantPeds[garageId] = ped

            exports.ox_target:addLocalEntity(ped, {
                {
                    name = ('poud_garage_open_%s'):format(garageId),
                    icon = 'fa-solid fa-clipboard-list',
                    label = Config.Text.openGarage,
                    distance = Config.InteractionDistance,
                    onSelect = function()
                        openGarage(garageId)
                    end
                }
            })
        end
    end
end

local function createImpoundZones()
    for impoundId, impound in pairs(Config.Impounds) do
        createBlip(impound.coords, impound.label, Config.Impound.blip)

        if loadModel(Config.Impound.ped.model) then
            local npc = impound.npc or vec4(impound.coords.x, impound.coords.y, impound.coords.z, 0.0)
            local ped = CreatePed(4, Config.Impound.ped.model, npc.x, npc.y, npc.z - 1.0, npc.w, false, true)

            FreezeEntityPosition(ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)

            if Config.Impound.ped.scenario then
                TaskStartScenarioInPlace(ped, Config.Impound.ped.scenario, 0, true)
            end

            if Config.Impound.ped.prop and loadModel(Config.Impound.ped.prop) then
                local prop = CreateObject(Config.Impound.ped.prop, npc.x, npc.y, npc.z, false, false, false)
                local offset = Config.Impound.ped.propOffset
                local rotation = Config.Impound.ped.propRotation

                AttachEntityToEntity(
                    prop,
                    ped,
                    GetPedBoneIndex(ped, Config.Impound.ped.propBone),
                    offset.x, offset.y, offset.z,
                    rotation.x, rotation.y, rotation.z,
                    true, true, false, true, 1, true
                )

                attendantProps[('impound_%s'):format(impoundId)] = prop
            end

            attendantPeds[('impound_%s'):format(impoundId)] = ped

            exports.ox_target:addLocalEntity(ped, {
                {
                    name = ('poud_impound_open_%s'):format(impoundId),
                    icon = 'fa-solid fa-truck-pickup',
                    label = Config.Text.openImpound,
                    distance = Config.InteractionDistance,
                    onSelect = function()
                        openImpound(impoundId)
                    end
                }
            })
        end
    end
end

CreateThread(createGarageZones)
CreateThread(createImpoundZones)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    cleanupValet()
    cleanupAttendants()
end)

CreateThread(function()
    while true do
        local wait = 500
        local garageId = getNearestStoreGarage()

        if garageId and not busy then
            wait = 0
            setParkingPrompt(true, garageId)
            drawParkingBox()

            if IsControlJustReleased(0, Config.StoreControl) then
                storeCurrentVehicle(garageId)
            end
        else
            setParkingPrompt(false)
        end

        Wait(wait)
    end
end)
