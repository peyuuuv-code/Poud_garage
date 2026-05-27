local ESX = exports.es_extended:getSharedObject()
local vehicleLabels = {}

local function dbg(message)
    if Config.Debug then
        print(('[Poud_garage] %s'):format(message))
    end
end

local function trimPlate(plate)
    plate = tostring(plate or '')

    if Config.TrimPlate then
        plate = plate:gsub('^%s*(.-)%s*$', '%1')
    end

    return plate
end

local function notify(source, message, type)
    TriggerClientEvent('Poud_garage:notify', source, message, type or 'info')
end

local function isNearGarage(source, garage, coords, limit)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end

    local playerCoords = GetEntityCoords(ped)
    return #(playerCoords - coords) <= (limit or Config.ServerDistanceLimit)
end

local function getImpoundFee(impound)
    return tonumber(impound.fee or Config.Impound.fee) or 0
end

local function canPay(xPlayer, amount)
    if amount <= 0 then return true end

    if Config.Impound.account == 'money' or Config.Impound.account == 'cash' then
        return xPlayer.getMoney() >= amount
    end

    local account = xPlayer.getAccount(Config.Impound.account)
    return account and account.money >= amount
end

local function removePayment(xPlayer, amount)
    if amount <= 0 then return end

    if Config.Impound.account == 'money' or Config.Impound.account == 'cash' then
        xPlayer.removeMoney(amount, 'Vehicle Impound')
        return
    end

    xPlayer.removeAccountMoney(Config.Impound.account, amount, 'Vehicle Impound')
end

local function decodeVehicle(raw)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return nil end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return nil end

    return decoded
end

local function getModelKey(model)
    if type(model) == 'number' then
        return tostring(model)
    end

    if type(model) == 'string' then
        return model:lower()
    end

    return nil
end

local function cacheVehicleLabels()
    if not Config.VehicleShop.databaseFallback then return end

    local cfg = Config.VehicleShop
    local query = ('SELECT `%s` AS model, `%s` AS label FROM `%s`'):format(cfg.modelColumn, cfg.labelColumn, cfg.vehiclesTable)
    local ok, rows = pcall(MySQL.query.await, query)

    if not ok then
        dbg(('vehicle label cache skipped: %s'):format(rows))
        return
    end

    vehicleLabels = {}

    for _, row in ipairs(rows or {}) do
        if row.model and row.label then
            vehicleLabels[tostring(row.model):lower()] = row.label
            vehicleLabels[tostring(joaat(row.model))] = row.label
        end
    end

    dbg(('cached %s vehicle labels'):format(#(rows or {})))
end

local function callShopExport(exportName, ...)
    local cfg = Config.VehicleShop
    if not cfg.enabled or not cfg.resource or not exportName then return nil end
    if GetResourceState(cfg.resource) ~= 'started' then return nil end

    local ok, result = pcall(function(...)
        return exports[cfg.resource][exportName](...)
    end, ...)

    if ok then return result end

    dbg(('vehicle shop export failed: %s'):format(result))
    return nil
end

local function getVehicleLabel(model)
    local cfg = Config.VehicleShop

    local label = callShopExport(cfg.exports.getVehicleLabel, model)
    if label then return label end

    local vehicle = callShopExport(cfg.exports.getVehicleByModel, model)
    if type(vehicle) == 'table' then
        return vehicle.label or vehicle.name or vehicle.model
    end

    return vehicleLabels[getModelKey(model)] or ('Model %s'):format(model)
end

local function normalizeGarageVehicle(row)
    local props = decodeVehicle(row.vehicle)
    if not props or not props.model then return nil end

    local model = props.model

    return {
        plate = trimPlate(row.plate or props.plate),
        label = getVehicleLabel(model),
        model = model,
        stored = row.stored == 1 or row.stored == true,
        type = row.type or 'car',
        props = props
    }
end

local function getPlayerVehicle(source, plate)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end

    return MySQL.single.await(
        'SELECT * FROM owned_vehicles WHERE owner = ? AND plate = ?',
        { xPlayer.getIdentifier(), trimPlate(plate) }
    )
end

local function addOwnedVehicle(owner, plate, vehicleProps, vehicleType, stored, job)
    if type(vehicleProps) ~= 'table' then return false end

    plate = trimPlate(plate or vehicleProps.plate)
    vehicleProps.plate = plate

    local affected = MySQL.insert.await(
        'INSERT INTO owned_vehicles (owner, plate, vehicle, type, job, stored) VALUES (?, ?, ?, ?, ?, ?)',
        { owner, plate, json.encode(vehicleProps), vehicleType or 'car', job, stored and 1 or 0 }
    )

    return affected ~= nil
end

exports('AddOwnedVehicle', addOwnedVehicle)
exports('GetVehicleLabel', getVehicleLabel)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        cacheVehicleLabels()
    end
end)

ESX.RegisterServerCallback('Poud_garage:getVehicles', function(source, cb, garageId)
    local ok, vehicles, message = pcall(function()
        local xPlayer = ESX.GetPlayerFromId(source)
        local garage = Config.Garages[garageId]

        if not xPlayer or not garage then
            return {}
        end

        if not isNearGarage(source, garage, garage.coords) then
            return {}, Config.Text.tooFar
        end

        local rows = MySQL.query.await(
            'SELECT plate, vehicle, type, stored FROM owned_vehicles WHERE owner = ? AND type = ? ORDER BY plate ASC',
            { xPlayer.getIdentifier(), garage.type or 'car' }
        )

        local garageVehicles = {}

        for _, row in ipairs(rows or {}) do
            local vehicle = normalizeGarageVehicle(row)
            if vehicle then
                garageVehicles[#garageVehicles + 1] = vehicle
            end
        end

        return garageVehicles
    end)

    if not ok then
        dbg(('getVehicles failed: %s'):format(vehicles))
        cb({}, Config.Text.dbError)
        return
    end

    cb(vehicles or {}, message)
end)

ESX.RegisterServerCallback('Poud_garage:takeOutVehicle', function(source, cb, garageId, plate)
    local garage = Config.Garages[garageId]
    if not garage then
        cb(false, Config.Text.invalidVehicle)
        return
    end

    if not isNearGarage(source, garage, garage.coords) then
        cb(false, Config.Text.tooFar)
        return
    end

    local row = getPlayerVehicle(source, plate)
    if not row then
        cb(false, Config.Text.notOwned)
        return
    end

    if row.type ~= (garage.type or 'car') then
        cb(false, Config.Text.wrongGarageType)
        return
    end

    if not (row.stored == 1 or row.stored == true) then
        cb(false, Config.Text.alreadyOut)
        return
    end

    local props = decodeVehicle(row.vehicle)
    if not props or not props.model then
        cb(false, Config.Text.invalidVehicle)
        return
    end

    props.plate = trimPlate(row.plate or props.plate)

    MySQL.update.await('UPDATE owned_vehicles SET stored = 0 WHERE plate = ?', { trimPlate(plate) })
    cb(true, props)
end)

ESX.RegisterServerCallback('Poud_garage:canStoreVehicle', function(source, cb, garageId, plate)
    local garage = Config.Garages[garageId]
    if not garage then
        cb(false, Config.Text.invalidVehicle)
        return
    end

    if not isNearGarage(source, garage, garage.store, Config.StoreDistanceLimit) then
        cb(false, Config.Text.tooFar)
        return
    end

    local row = getPlayerVehicle(source, plate)
    if not row then
        cb(false, Config.Text.notOwned)
        return
    end

    if row.type ~= (garage.type or 'car') then
        cb(false, Config.Text.wrongGarageType)
        return
    end

    cb(true)
end)

ESX.RegisterServerCallback('Poud_garage:getImpoundedVehicles', function(source, cb, impoundId)
    local ok, vehicles, message = pcall(function()
        local xPlayer = ESX.GetPlayerFromId(source)
        local impound = Config.Impounds[impoundId]

        if not xPlayer or not impound then
            return {}
        end

        if not isNearGarage(source, impound, impound.coords) then
            return {}, Config.Text.tooFar
        end

        local rows = MySQL.query.await(
            'SELECT plate, vehicle, type, stored FROM owned_vehicles WHERE owner = ? AND type = ? AND stored = 0 ORDER BY plate ASC',
            { xPlayer.getIdentifier(), impound.type or 'car' }
        )

        local impoundedVehicles = {}
        local fee = getImpoundFee(impound)

        for _, row in ipairs(rows or {}) do
            local vehicle = normalizeGarageVehicle(row)
            if vehicle then
                vehicle.fee = fee
                impoundedVehicles[#impoundedVehicles + 1] = vehicle
            end
        end

        return impoundedVehicles
    end)

    if not ok then
        dbg(('getImpoundedVehicles failed: %s'):format(vehicles))
        cb({}, Config.Text.dbError)
        return
    end

    cb(vehicles or {}, message)
end)

ESX.RegisterServerCallback('Poud_garage:retrieveImpoundedVehicle', function(source, cb, impoundId, plate)
    local xPlayer = ESX.GetPlayerFromId(source)
    local impound = Config.Impounds[impoundId]

    if not xPlayer or not impound then
        cb(false, Config.Text.invalidVehicle)
        return
    end

    if not isNearGarage(source, impound, impound.coords) then
        cb(false, Config.Text.tooFar)
        return
    end

    local row = getPlayerVehicle(source, plate)
    if not row then
        cb(false, Config.Text.notOwned)
        return
    end

    if row.type ~= (impound.type or 'car') then
        cb(false, Config.Text.wrongGarageType)
        return
    end

    if row.stored == 1 or row.stored == true then
        cb(false, Config.Text.invalidVehicle)
        return
    end

    local fee = getImpoundFee(impound)
    if not canPay(xPlayer, fee) then
        cb(false, Config.Text.notEnoughMoney)
        return
    end

    local props = decodeVehicle(row.vehicle)
    if not props or not props.model then
        cb(false, Config.Text.invalidVehicle)
        return
    end

    props.plate = trimPlate(row.plate or props.plate)

    if Config.Impound.repairOnRetrieve then
        props.engineHealth = 1000.0
        props.bodyHealth = 1000.0
        props.tankHealth = 1000.0
    end

    local changed = MySQL.update.await(
        'UPDATE owned_vehicles SET vehicle = ?, stored = 2 WHERE owner = ? AND plate = ? AND stored = 0',
        { json.encode(props), xPlayer.getIdentifier(), trimPlate(plate) }
    )

    if not changed or changed < 1 then
        cb(false, Config.Text.alreadyOut)
        return
    end

    removePayment(xPlayer, fee)
    cb(true, props)
end)

RegisterNetEvent('Poud_garage:storeVehicle', function(garageId, plate, props)
    local source = source
    local garage = Config.Garages[garageId]

    if not garage then return end

    local function fail(message)
        notify(source, message, 'error')
        TriggerClientEvent('Poud_garage:storeFailed', source)
    end

    if not isNearGarage(source, garage, garage.store, Config.StoreDistanceLimit) then
        fail(Config.Text.tooFar)
        return
    end

    local row = getPlayerVehicle(source, plate)
    if not row then
        fail(Config.Text.notOwned)
        return
    end

    if row.type ~= (garage.type or 'car') then
        fail(Config.Text.wrongGarageType)
        return
    end

    props = type(props) == 'table' and props or decodeVehicle(row.vehicle)
    if not props then
        fail(Config.Text.invalidVehicle)
        return
    end

    props.plate = trimPlate(plate)

    local changed = MySQL.update.await(
        'UPDATE owned_vehicles SET vehicle = ?, stored = 1 WHERE plate = ?',
        { json.encode(props), trimPlate(plate) }
    )

    if changed and changed > 0 then
        TriggerClientEvent('Poud_garage:deleteStoredVehicle', source)
        notify(source, Config.Text.vehicleStored, 'success')
        return
    end

    fail(Config.Text.dbError)
end)
