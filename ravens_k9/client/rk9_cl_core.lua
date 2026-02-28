-- ============================================================
--  Raven's K9 System  |  rk9_cl_core.lua
--  Author: Raven
--  Client-side core: player state, base commands, shared
--  helpers used by all other client scripts.
-- ============================================================

local QBCore     = exports['qb-core']:GetCoreObject()
local RK9PlayerData = {}
local RK9MyCerts    = {}

-- ─── Internal helpers ─────────────────────────────────────────

--- Returns true if the local player currently holds a LEO job.
local function RK9_IsLEO()
    local job = RK9PlayerData.job and RK9PlayerData.job.name or ''
    for _, allowed in ipairs(RK9Config.AllowedJobs) do
        if job == allowed then return true end
    end
    return false
end

--- Returns true if the player holds the specified cert and it isn't expired.
local function RK9_HasActiveCert(certType)
    for _, c in ipairs(RK9MyCerts) do
        if c.cert_type == certType and not RK9Certs.IsExpired(c.expires_at) then
            return true
        end
    end
    return false
end

--- Fire an ox_lib notification.
local function RK9_Notify(msg, ntype)
    lib.notify({
        title       = "🐾 Raven's K9",
        description = msg,
        type        = ntype or 'inform',
        position    = RK9Config.NotifyPos,
    })
end

-- ─── Player data sync ─────────────────────────────────────────

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    RK9PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(pd)
    RK9PlayerData = pd
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    RK9PlayerData = QBCore.Functions.GetPlayerData()
    if RK9_IsLEO() then
        TriggerServerEvent('rk9:sv:fetchMyCerts')
    end
end)

-- ─── Cert data reception ──────────────────────────────────────

RegisterNetEvent('rk9:cl:receiveMyCerts', function(certs)
    RK9MyCerts = certs or {}
end)

RegisterNetEvent('rk9:cl:receiveTargetCerts', function(targetCid, certs)
    RK9_OpenCertViewMenu(targetCid, certs)
end)

-- ─── Notification relay ───────────────────────────────────────

RegisterNetEvent('rk9:cl:notify', function(msg, ntype)
    RK9_Notify(msg, ntype)
end)

-- ─── Sniff result display ─────────────────────────────────────

RegisterNetEvent('rk9:cl:sniffResult', function(detected, items)
    if detected and #items > 0 then
        local parts = {}
        for _, i in ipairs(items) do
            table.insert(parts, i.item .. ' [' .. i.cert .. ']')
        end
        RK9_Notify('K9 Alert! Detected: ' .. table.concat(parts, ', '), 'error')
    else
        RK9_Notify('K9 found nothing of interest.', 'success')
    end
end)

-- Tracking blip used by the detection script; listener moved to
-- `rk9_cl_detection.lua` to support mode colors. Leave a minimal
-- export here to avoid breaking other resources that may query it.

exports('RK9_CreateBlip', function(coords, colour, label)
    -- helper for other client scripts; detection.lua will call this.
    if not coords then return end
    local b = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(b, 280)
    SetBlipColour(b, colour or 6)
    SetBlipScale(b, 0.8)
    SetBlipAsShortRange(b, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'K9 Track Target')
    EndTextCommandSetBlipName(b)
    return b
end)

-- ─── View nearby K9 certs logic ───────────────────────────────

local function RK9_ViewNearby()
    if not RK9_IsLEO() then
        RK9_Notify('This system is restricted to LEO personnel.', 'error')
        return
    end
    local myPed    = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local closest, closestDist = nil, RK9Config.ViewNearbyRadius

    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local dist = #(myCoords - GetEntityCoords(GetPlayerPed(pid)))
            if dist < closestDist then
                closestDist = dist
                closest     = pid
            end
        end
    end

    if not closest then
        RK9_Notify('No nearby player found within 10m.', 'error')
        return
    end

    TriggerServerEvent('rk9:sv:requestTargetCerts', GetPlayerServerId(closest))
end

-- ─── Commands ────────────────────────────────────────────────

RegisterCommand(RK9Config.Cmds.OpenMenu, function()
    if not RK9_IsLEO() then
        RK9_Notify('This system is restricted to LEO personnel.', 'error')
        return
    end
    TriggerServerEvent('rk9:sv:fetchMyCerts')
    Wait(300)
    RK9_OpenMainMenu()
end, false)

RegisterCommand(RK9Config.Cmds.SniffPed, function()
    if not RK9_IsLEO() then RK9_Notify('LEO access only.', 'error') return end
    TriggerEvent('rk9:cl:doSniffPed')
end, false)

RegisterCommand(RK9Config.Cmds.SniffVehicle, function()
    if not RK9_IsLEO() then RK9_Notify('LEO access only.', 'error') return end
    TriggerEvent('rk9:cl:doSniffVehicle')
end, false)

RegisterCommand(RK9Config.Cmds.TrackHuman, function()
    if not RK9_IsLEO() then RK9_Notify('LEO access only.', 'error') return end
    TriggerEvent('rk9:cl:doTrackHuman')
end, false)

RegisterCommand(RK9Config.Cmds.StopTrack, function()
    TriggerEvent('rk9:cl:stopTracking')
end, false)

RegisterCommand(RK9Config.Cmds.ViewNearbyCerts, function()
    RK9_ViewNearby()
end, false)

-- ─── Exports for other client scripts ────────────────────────

exports('RK9_IsLEO',        function() return RK9_IsLEO() end)
exports('RK9_HasActiveCert', RK9_HasActiveCert)
exports('RK9_GetMyCerts',   function() return RK9MyCerts end)
exports('RK9_Notify',       RK9_Notify)
