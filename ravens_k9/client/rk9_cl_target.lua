-- ============================================================
--  Raven's K9 System  |  rk9_cl_target.lua
--  Author: Raven
--  ox_target global entity hooks for players and vehicles.
--  All interactions are restricted to LEO jobs via `groups`.
--  Tracking mode access:
--    Nearby / Fleeing — humantrack cert
--    Missing Person   — humantrack + sar certs
-- ============================================================

CreateThread(function()
    -- Wait until the player is fully loaded
    while not LocalPlayer.state.isLoggedIn do Wait(500) end
    Wait(1000)

    -- ─── Global Player Targets ────────────────────────────────

    exports.ox_target:addGlobalPlayer({

        -- Sniff nearby person
        {
            name     = 'rk9_target_sniff_ped',
            icon     = 'fas fa-dog',
            label    = '🐾 K9 Sniff Person',
            groups   = RK9Config.AllowedJobs,
            onSelect = function(_data)
                TriggerEvent('rk9:cl:doSniffPed')
            end,
        },

        -- View another player's K9 certs
        {
            name     = 'rk9_target_view_certs',
            icon     = 'fas fa-id-card',
            label    = '📋 View K9 Certs',
            groups   = RK9Config.AllowedJobs,
            onSelect = function(data)
                local targetSid = GetPlayerServerId(NetworkGetEntityOwner(data.entity))
                TriggerServerEvent('rk9:sv:requestTargetCerts', targetSid)
            end,
        },

        -- Grant cert (evaluator/admin only — canInteract gates visibility)
        {
            name        = 'rk9_target_grant_cert',
            icon        = 'fas fa-certificate',
            label       = '✅ Grant K9 Cert',
            groups      = RK9Config.AllowedJobs,
            canInteract = function(_entity)
                return lib.callback.await('rk9:cb:isEvaluator', false)
            end,
            onSelect = function(data)
                local pid        = NetworkGetEntityOwner(data.entity)
                local targetSid  = GetPlayerServerId(pid)
                local targetName = GetPlayerName(pid)
                RK9_OpenSelectCertMenu(targetSid, targetName, 'grant')
            end,
        },

        -- Revoke cert (evaluator/admin only)
        {
            name        = 'rk9_target_revoke_cert',
            icon        = 'fas fa-times-circle',
            label       = '❌ Revoke K9 Cert',
            groups      = RK9Config.AllowedJobs,
            canInteract = function(_entity)
                return lib.callback.await('rk9:cb:isEvaluator', false)
            end,
            onSelect = function(data)
                local pid        = NetworkGetEntityOwner(data.entity)
                local targetSid  = GetPlayerServerId(pid)
                local targetName = GetPlayerName(pid)
                RK9_OpenSelectCertMenu(targetSid, targetName, 'revoke')
            end,
        },

        -- Begin human tracking on a player (humantrack cert required).
        -- Missing Person mode additionally requires the SAR cert.
        {
            name        = 'rk9_target_track_human',
            icon        = 'fas fa-shoe-prints',
            label       = '👣 K9 Track Person',
            groups      = RK9Config.AllowedJobs,
            canInteract = function(_entity)
                return exports['ravens_k9']:RK9_HasActiveCert('humantrack')
            end,
            onSelect = function(data)
                local targetSid  = GetPlayerServerId(NetworkGetEntityOwner(data.entity))
                local targetName = GetPlayerName(NetworkGetEntityOwner(data.entity))
                local hasSAR     = exports['ravens_k9']:RK9_HasActiveCert('sar')

                local opts = {
                    {
                        title       = '⬜  Nearby Suspect',
                        description = 'Standard proximity tracking.',
                        onSelect    = function() RK9_BeginTracking(targetSid, 'nearby') end,
                    },
                    {
                        title       = '🟡  Fleeing Suspect',
                        description = 'Active pursuit — extended timeout.',
                        onSelect    = function() RK9_BeginTracking(targetSid, 'fleeing') end,
                    },
                }

                if hasSAR then
                    opts[#opts + 1] = {
                        title       = '🔵  Missing Person',
                        description = 'Search and Rescue — server-wide, maximum timeout.',
                        onSelect    = function() RK9_BeginTracking(targetSid, 'missing') end,
                    }
                else
                    opts[#opts + 1] = {
                        title    = '🔒  Missing Person (Locked)',
                        description = 'Requires Search and Rescue certification.',
                        disabled = true,
                    }
                end

                opts[#opts + 1] = { title = 'Cancel', onSelect = function() end }

                lib.registerContext({
                    id      = 'rk9_target_track_mode',
                    title   = '👣 Track: ' .. targetName,
                    options = opts,
                })
                lib.showContext('rk9_target_track_mode')
            end,
        },

        -- Add as evaluator (admin only)
        {
            name        = 'rk9_target_add_evaluator',
            icon        = 'fas fa-user-shield',
            label       = '➕ Add as K9 Evaluator',
            groups      = RK9Config.AllowedJobs,
            canInteract = function(_entity)
                return lib.callback.await('rk9:cb:isAdmin', false)
            end,
            onSelect = function(data)
                local pid        = NetworkGetEntityOwner(data.entity)
                local targetSid  = GetPlayerServerId(pid)
                local targetName = GetPlayerName(pid)
                local confirmed  = lib.alertDialog({
                    header   = 'Add Evaluator',
                    content  = 'Designate ' .. targetName .. ' as a K9 Evaluator?',
                    centered = true,
                    cancel   = true,
                })
                if confirmed == 'confirm' then
                    TriggerServerEvent('rk9:sv:addEvaluatorByServerId', targetSid)
                end
            end,
        },
    })

    -- ─── Global Vehicle Targets ───────────────────────────────

    exports.ox_target:addGlobalVehicle({
        {
            name     = 'rk9_target_sniff_vehicle',
            icon     = 'fas fa-dog',
            label    = '🐾 K9 Sniff Vehicle',
            groups   = RK9Config.AllowedJobs,
            onSelect = function(_data)
                TriggerEvent('rk9:cl:doSniffVehicle')
            end,
        },
    })
end)
