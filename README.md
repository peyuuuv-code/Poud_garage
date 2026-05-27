# Poud_garage

ESX garage system for `owned_vehicles` with `ox_target`, custom NUI, and `oxmysql`.

## DEPENDENCIES

- `es_extended`
- `oxmysql`
- `ox_target`

## SETUP

1. Add the resource after `oxmysql`, `ox_target`, `es_extended`, and your vehicle shop.
2. Add `ensure Poud_garage` to `server.cfg`.
3. Existing `esx_vehicleshop` works because it stores vehicles in `owned_vehicles`.

## Vehicle shop bridge

The garage is not locked to one vehicle shop. Configure `Config.VehicleShop` in `config.lua`.

If your shop has exports, set:

```lua
Config.VehicleShop.resource = 'your_vehicle_shop'
Config.VehicleShop.exports.getVehicleLabel = 'GetVehicleLabel'
Config.VehicleShop.exports.getVehicleByModel = 'GetVehicleByModel'
```

If the shop has no exports, the garage falls back to the `vehicles` database table and reads labels from `model` + `name`.

Other scripts can register a purchased vehicle through:

```lua
exports.Poud_garage:AddOwnedVehicle(ownerIdentifier, plate, vehicleProps, 'car', false)
```

## PREVIEW

<img width="1331" height="873" alt="image" src="https://github.com/user-attachments/assets/f09668dc-82f5-4f0e-ae63-52a977b758c5" />


<img width="1158" height="731" alt="image" src="https://github.com/user-attachments/assets/31560ea4-ce8f-42e7-80f1-38781c734948" />


<img width="1318" height="908" alt="image" src="https://github.com/user-attachments/assets/6434fcff-fc61-41ea-b529-2214b6fd3336" />
