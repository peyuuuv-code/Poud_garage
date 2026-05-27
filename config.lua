Config = {}

Config.Locale = 'en'
Config.Debug = false
Config.UsePoudNotify = true
Config.InteractionDistance = 2.2
Config.ServerDistanceLimit = 18.0
Config.StoreDistanceLimit = 10.0
Config.ParkingPromptDistance = 6.0
Config.StoreControl = 38
Config.StoreKeyLabel = 'E'
Config.SpawnCheckRadius = 3.5
Config.SpawnFallbackRadius = 8.0
Config.SpawnFallbackStep = 2.5
Config.TrimPlate = true

Config.ParkingBox = {
    enabled = true,
    x = 0.5,
    y = 0.88,
    width = 0.15,
    height = 0.034,
    background = { r = 30, g = 28, b = 44, a = 230 },
    keyBackground = { r = 54, g = 50, b = 78, a = 245 },
    keyText = { r = 243, g = 241, b = 255, a = 255 },
    text = { r = 243, g = 241, b = 255, a = 255 }
}

Config.Valet = {
    enabled = true,
    model = `s_m_m_autoshop_02`,
    walkSpeed = 1.4,
    driveSpeed = 8.0,
    driveTime = 4500,
    spawnOffset = vec3(-4.0, -3.0, 0.0),
    driveAwayOffset = vec3(0.0, 28.0, 0.0),
    drivingStyle = 786603
}

Config.Attendant = {
    model = `s_m_m_autoshop_02`,
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    prop = `prop_notepad_01`,
    propBone = 60309,
    propOffset = vec3(0.08, 0.02, 0.02),
    propRotation = vec3(-90.0, 0.0, 0.0)
}

Config.Impound = {
    account = 'bank',
    repairOnRetrieve = true,
    fee = 2500,
    ped = {
        model = `s_m_m_trucker_01`,
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        prop = `prop_notepad_01`,
        propBone = 60309,
        propOffset = vec3(0.08, 0.02, 0.02),
        propRotation = vec3(-90.0, 0.0, 0.0)
    },
    blip = {
        enabled = true,
        sprite = 357,
        color = 17,
        scale = 0.75
    }
}

Config.VehicleShop = {
    enabled = true,
    resource = 'esx_vehicleshop',
    exports = {
        getVehicleLabel = nil,
        getVehicleByModel = 'GetVehicleByModel'
    },
    databaseFallback = true,
    vehiclesTable = 'vehicles',
    modelColumn = 'model',
    labelColumn = 'name'
}

Config.Blips = {
    enabled = true,
    sprite = 357,
    color = 3,
    scale = 0.75
}

Config.Garages = {
    legion = {
        label = 'Legion Garage',
        type = 'car',
        coords = vec3(215.78, -810.12, 30.73),
        npc = vec4(215.78, -810.12, 30.73, 340.0),
        spawn = vec4(229.61, -800.11, 30.57, 157.0),
        store = vec3(218.58, -781.64, 30.75)
    },
    sandy = {
        label = 'Sandy Garage',
        type = 'car',
        coords = vec3(1737.72, 3710.49, 34.14),
        npc = vec4(1737.72, 3710.49, 34.14, 25.0),
        spawn = vec4(1732.54, 3712.27, 34.11, 20.0),
        store = vec3(1729.78, 3716.19, 34.15)
    },
    paleto = {
        label = 'Paleto Garage',
        type = 'car',
        coords = vec3(103.52, 6613.27, 31.82),
        npc = vec4(106.58, 6612.45, 31.97, 222.39),
        spawn = vec4(117.64, 6599.62, 32.01, 276.20),
        store = vec3(123.85, 6613.65, 31.83)
    }
}

Config.Impounds = {
    city = {
        label = 'City Impound',
        type = 'car',
        coords = vec3(409.08, -1623.12, 29.29),
        npc = vec4(409.08, -1623.12, 29.29, 232.0),
        spawn = vec4(401.46, -1631.44, 29.29, 230.0),
        fee = 2500
    }
}
