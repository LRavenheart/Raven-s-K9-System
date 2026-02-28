-- ============================================================
--  Raven's K9 System  |  rk9_cl_detection.lua
--  Author: Raven
--  Sniff animations, ped/vehicle item detection, and human
--  tracking thread management across three modes:
--    nearby  — proximity, humantrack cert
--    fleeing — proximity, humantrack cert
--    missing — server-wide, humantrack + sar certs required
-- ============================================================

local RK9ActionLocked = false   -- prevents overlapping actions
local RK9TrackingActive = false -- tracks whether the tracking loop is running

-- ─── Sniff animation + progress bar ──────────────────────────

local function RK9_PlaySniffAnim(duration, callback)
    if RK9ActionLocked then
        exports['ravens_k9']:RK9_Notify('Already performing a K9 action.', 'error')
        return
    end
    RK9ActionLocked = true

    local ped      = PlayerPedId()
    local animDict = 'amb@world_human_stand_impatient@male@no_sign@idle_a'
    local animName = 'idle_a'

    RequestAnimDict(animDict)
    local timeout = 0
    while not HasAnimDictLoaded(animDict) and timeout < 100 do
        Wait(10); timeout = timeout + 1
    end

    TaskPlayAnim(ped, animDict, animName, 2.0, -2.0, duration, 1, 0, false, false, false)

    if lib.progressBar then
        lib.progressBar({
            duration     = duration,
            label        = '🐾 K9 Sniffing…',
            useWhileDead = false,
            canCancel    = false,
            disable      = { move = true, car = true, combat = true },
        })
    else
        Wait(duration)
    end

    ClearPedTasksImmediately(ped)
    RK9ActionLocked = false
    if callback then callback() end
end

--- Returns cert type IDs that are active (not expired) and relevant
--- to item detection. Excludes behaviour-only certs: patrol, humantrack, sar.
local function RK9_GetDetectionCerts()
    local active = {}
    for _, c in ipairs(exports['ravens_k9']:RK9_GetMyCerts()) do
        if not RK9Certs.IsExpired(c.expires_at)
            and c.cert_type ~= 'patrol'
            and c.cert_type ~= 'humantrack'
            and c.cert_type ~= 'sar'
        then
            active[#active + 1] = c.cert_type
        end
    end
    return active
end

-- ─── Sniff Ped ───────────────────────────────────────────────

RegisterNetEvent('rk9:cl:doSniffPed', function()
    if not exports['ravens_k9']:RK9_IsLEO() then
        exports['ravens_k9']:RK9_Notify('LEO access only.', 'error') return
    end

    local certTypes = RK9_GetDetectionCerts()
    if #certTypes == 0 then
        exports['ravens_k9']:RK9_Notify(
            'No active detection certifications. Obtain Firearms, Narcotics, or Explosives certification.',
            'error'
        )
        return
    end

    local myCoords = GetEntityCoords(PlayerPedId())
    local closestSid, closestDist = nil, RK9Config.DetectionRadius

    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local dist = #(myCoords - GetEntityCoords(GetPlayerPed(pid)))
            if dist < closestDist then
                closestDist = dist
                closestSid  = GetPlayerServerId(pid)
            end
        end
    end

    if not closestSid then
        exports['ravens_k9']:RK9_Notify(
            'No player within sniff range (' .. RK9Config.DetectionRadius .. 'm).', 'error'
        )
        return
    end

    RK9_PlaySniffAnim(RK9Config.SniffDuration, function()
        TriggerServerEvent('rk9:sv:sniffPed', closestSid, certTypes)
    end)
end)

-- ─── Sniff Vehicle ────────────────────────────────────────────

RegisterNetEvent('rk9:cl:doSniffVehicle', function()
    if not exports['ravens_k9']:RK9_IsLEO() then
        exports['ravens_k9']:RK9_Notify('LEO access only.', 'error') return
    end

    local certTypes = RK9_GetDetectionCerts()
    if #certTypes == 0 then
        exports['ravens_k9']:RK9_Notify('No active detection certifications.', 'error')
        return
    end

    local myCoords = GetEntityCoords(PlayerPedId())
    local closestVeh, closestDist = nil, RK9Config.VehicleRadius

    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local dist = #(myCoords - GetEntityCoords(veh))
        if dist < closestDist then
            closestDist = dist
            closestVeh  = veh
        end
    end

    if not closestVeh then
        exports['ravens_k9']:RK9_Notify(
            'No vehicle within sniff range (' .. RK9Config.VehicleRadius .. 'm).', 'error'
        )
        return
    end

    local plate = GetVehicleNumberPlateText(closestVeh)
    RK9_PlaySniffAnim(RK9Config.SniffDuration, function()
        TriggerServerEvent('rk9:sv:sniffVehicle', plate, certTypes)
    end)
end)

-- ─── Human Tracking ───────────────────────────────────────────
--
--  Three tracking modes — all require the humantrack certification:
--
--    nearby  (humantrack)

-- Server may ask this client for its current coordinates when another
-- handler initiates a track. Reply with the raw vector so the server can
-- forward it to the requesting player.
RegisterNetEvent('rk9:cl:provideTrackCoords', function(requesterSrc, mode)
    local coords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('rk9:sv:trackCoordsResponse', requesterSrc, coords, mode)
end)
--      Proximity-based. Shows players within RK9Config.TrackingRadius.
--      General patrol use. Grey blip.
--
--    fleeing (humantrack)
--      Proximity-based. Shows players within RK9Config.TrackingRadius.
--      Intended for active pursuit of a suspect who was recently in range.
--      Yellow blip. Longer timeout than nearby.
--
--    missing (humantrack + sar)
--      Server-wide. Shows ALL online players regardless of distance.
--      Locked to handlers who also hold the Search and Rescue certification.
--      Blue blip. Maximum timeout for extended search operations.
--
--  Once started, all modes share the same live blip update loop.
--  Mode is passed to the server event so the correct blip colour is applied.
--  Each mode auto-expires via RK9Config.TrackingTimeout after its allotted time.

local RK9TrackMode    = nil   -- 'nearby' | 'fleeing' | 'missing'
local RK9TrackTimeout = nil   -- handle returned by SetTimeout for the active session

-- Opens the tracking mode selection menu.
-- Missing Person is only shown if the handler also holds the SAR cert.
RegisterNetEvent('rk9:cl:doTrackHuman', function()
    if not exports['ravens_k9']:RK9_IsLEO() then
        exports['ravens_k9']:RK9_Notify('LEO access only.', 'error') return
    end
    if not exports['ravens_k9']:RK9_HasActiveCert('humantrack') then
        exports['ravens_k9']:RK9_Notify('Human Tracking certification required.', 'error')
        return
    end
    if RK9TrackingActive then
        exports['ravens_k9']:RK9_Notify(
            'Already tracking a target. Use /' .. RK9Config.Cmds.StopTrack .. ' to stop first.',
            'error'
        )
        return
    end

    -- Check SAR cert separately so we can show a contextual option or locked message
    local hasSAR = exports['ravens_k9']:RK9_HasActiveCert('sar')

    local opts = {
        {
            title       = '⬜  Nearby Suspect',
            description = 'Scan within ' .. RK9Config.TrackingRadius .. 'm. Standard patrol tracking.',
            onSelect    = function() RK9_OpenTrackPlayerPicker('nearby') end,
        },
        {
            title       = '🟡  Fleeing Suspect',
            description = 'Scan within ' .. RK9Config.TrackingRadius .. 'm. Active pursuit — extended timeout.',
            onSelect    = function() RK9_OpenTrackPlayerPicker('fleeing') end,
        },
    }

    if hasSAR then
        -- SAR cert held — show the Missing Person option
        opts[#opts + 1] = {
            title       = '🔵  Missing Person',
            description = 'Server-wide search. Search and Rescue operations — maximum timeout.',
            onSelect    = function() RK9_OpenTrackPlayerPicker('missing') end,
        }
    else
        -- SAR cert not held — show the option as locked with an explanation
        opts[#opts + 1] = {
            title       = '🔒  Missing Person (Locked)',
            description = 'Requires Search and Rescue certification. Contact an evaluator.',
            disabled    = true,
        }
    end

    opts[#opts + 1] = { title = 'Cancel', onSelect = function() end }

    lib.registerContext({
        id      = 'rk9_track_mode_picker',
        title   = '👣 Human Tracking — Select Mode',
        options = opts,
    })
    lib.showContext('rk9_track_mode_picker')
end)

-- Builds the player selection list for the chosen tracking mode.
--   nearby / fleeing → proximity-gated to RK9Config.TrackingRadius
--   missing          → all online players server-wide
function RK9_OpenTrackPlayerPicker(mode)
    local myCoords = GetEntityCoords(PlayerPedId())
    local list     = {}

    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local dist = #(myCoords - GetEntityCoords(GetPlayerPed(pid)))
            -- Nearby and fleeing are distance-gated; missing is server-wide
            if mode == 'missing' or dist <= RK9Config.TrackingRadius then
                list[#list + 1] = {
                    playerId = pid,
                    serverId = GetPlayerServerId(pid),
                    name     = GetPlayerName(pid),
                    dist     = dist,
                }
            end
        end
    end

    if #list == 0 then
        if mode == 'missing' then
            exports['ravens_k9']:RK9_Notify('No online players found.', 'error')
        else
            exports['ravens_k9']:RK9_Notify(
                'No players within ' .. RK9Config.TrackingRadius .. 'm range.', 'error'
            )
        end
        return
    end

    -- Sort nearest-first for all modes (distance is useful context even server-wide)
    table.sort(list, function(a, b) return a.dist < b.dist end)

    local modeTitles = {
        nearby  = '⬜ Nearby Suspect',
        fleeing = '🟡 Fleeing Suspect',
        missing = '🔵 Missing Person',
    }

    local opts = {}
    for _, p in ipairs(list) do
        local pp = p
        local distLabel = pp.dist < 1000
            and (math.floor(pp.dist) .. 'm away')
            or  (string.format('%.1fkm away', pp.dist / 1000))
        opts[#opts + 1] = {
            title       = pp.name,
            description = distLabel .. '  |  Server ID: ' .. pp.serverId,
            onSelect    = function()
                RK9_BeginTracking(pp.serverId, mode)
            end,
        }
    end
    opts[#opts + 1] = {
        title    = '← Back',
        onSelect = function() TriggerEvent('rk9:cl:doTrackHuman') end,
    }

    lib.registerContext({
        id      = 'rk9_track_player_picker',
        title   = '👣 ' .. modeTitles[mode] .. ' — Select Target',
        options = opts,
    })
    lib.showContext('rk9_track_player_picker')
end

-- Starts the live coordinate-polling loop for the chosen target and mode.
-- The mode is forwarded to the server so it can include it in the
-- trackingUpdate event, which the client uses to set the correct blip colour.
function RK9_BeginTracking(targetServerId, mode)
    mode = mode or 'nearby'

    RK9TrackingActive = true
    RK9TrackMode      = mode

    local startMessages = {
        nearby  = '🐾 K9 has the scent — tracking nearby suspect.',
        fleeing = '🐾 K9 picked up a trail — tracking fleeing suspect.',
        missing = '🐾 K9 is searching — missing person operation active.',
    }
    exports['ravens_k9']:RK9_Notify(startMessages[mode] or '🐾 Tracking started.', 'inform')

    CreateThread(function()
        while RK9TrackingActive do
            TriggerServerEvent('rk9:sv:trackHuman', targetServerId, mode)
            Wait(RK9Config.TrackingUpdateMs)
        end
        exports['ravens_k9']:RK9_Notify('🐾 Tracking session ended.', 'inform')
        RK9TrackMode = nil
        -- clear any pending timeout if session was stopped manually
        if RK9TrackTimeout then
            ClearTimeout(RK9TrackTimeout)
            RK9TrackTimeout = nil
        end
    end)

    -- Auto-expire the session after the mode-specific timeout
    local timeout = (RK9Config.TrackingTimeout and RK9Config.TrackingTimeout[mode]) or 600000
    RK9TrackTimeout = SetTimeout(timeout, function()
        if RK9TrackingActive then
            RK9TrackingActive = false
            local mins = math.floor(timeout / 60000)
            exports['ravens_k9']:RK9_Notify(
                '🐾 Tracking session expired — ' .. mode .. ' mode limit (' .. mins .. ' min) reached.',
                'warning'
            )
        end
    end)
end

-- Manually stop the active tracking session.
RegisterNetEvent('rk9:cl:stopTracking', function()
    if RK9TrackingActive then
        RK9TrackingActive = false
        if RK9TrackTimeout then
            ClearTimeout(RK9TrackTimeout)
            RK9TrackTimeout = nil
        end
        -- The thread loop will exit on next iteration; timeout cleared above.
    else
        exports['ravens_k9']:RK9_Notify('No active tracking session.', 'inform')
    end
end)

-- Receives a coordinate update from the server and repositions the tracking blip.
-- The mode parameter drives blip colour and label so dispatch can distinguish
-- between an active pursuit (yellow) and a SAR operation (blue).
RegisterNetEvent('rk9:cl:trackingUpdate', function(coords, mode)
    if RK9TrackBlip then RemoveBlip(RK9TrackBlip) end

    local colour = (RK9Config.TrackingBlipColour and RK9Config.TrackingBlipColour[mode]) or 6
    local blipLabels = {
        nearby  = 'K9 — Nearby Suspect',
        fleeing = 'K9 — Fleeing Suspect',
        missing = 'K9 — Missing Person (SAR)',
    }
    local label = blipLabels[mode] or 'K9 Track Target'

    -- use exported helper from core
    RK9TrackBlip = exports['ravens_k9']:RK9_CreateBlip(coords, colour, label)
end)
