-- ============================================================
--  Raven's K9 System  |  rk9_cl_menus.lua
--  Author: Raven
--  All ox_lib context menus: main hub, cert viewer,
--  evaluator panel, admin panel, cert grant/revoke flows.
-- ============================================================

-- ─── Helpers ─────────────────────────────────────────────────

--- Collects all players within the configured radius, sorted by distance.
local function RK9_GetNearbyPlayers(maxDist)
    maxDist = maxDist or RK9Config.ViewNearbyRadius
    local myCoords = GetEntityCoords(PlayerPedId())
    local list     = {}
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local dist = #(myCoords - GetEntityCoords(GetPlayerPed(pid)))
            if dist <= maxDist then
                list[#list + 1] = {
                    playerId = pid,
                    serverId = GetPlayerServerId(pid),
                    name     = GetPlayerName(pid),
                    dist     = dist,
                }
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

local function RK9_Notify(msg, ntype)
    exports['ravens_k9']:RK9_Notify(msg, ntype)
end

-- ─── Main Menu ───────────────────────────────────────────────

function RK9_OpenMainMenu()
    local isEval  = lib.callback.await('rk9:cb:isEvaluator', false)
    local isAdmin = lib.callback.await('rk9:cb:isAdmin',     false)
    local isK9    = exports['ravens_k9']:RK9_IsK9Unit()
    local canView = exports['ravens_k9']:RK9_CanViewDogCerts()

    local opts = {
        {
            title       = '🧭  Operations Console Status',
            description = string.format('Role: %s  |  Active certs: %d', roleLabel, activeCount),
            metadata    = {
                { label = 'K9 Unit', value = isK9 and 'Yes' or 'No' },
                { label = 'Handler', value = isHandler and 'Yes' or 'No' },
                { label = 'Can View Certs', value = canView and 'Yes' or 'No' },
                { label = 'Active Certifications', value = certText },
            },
            -- status card only; intentionally non-interactive
            disabled    = true,
        },
        {
            title       = '🎖️  My Certifications',
            description = 'View your K9 certification cards and statuses.',
            onSelect    = RK9_OpenMyCertsMenu,
        },
        {
            title       = '🔍  K9 Sniff — Person',
            description = 'Command the K9 to sniff a nearby person.',
            disabled    = not isK9,
            onSelect    = function() TriggerEvent('rk9:cl:doSniffPed') end,
        },
        {
            title       = '🚗  K9 Sniff — Vehicle',
            description = 'Command the K9 to sniff a nearby vehicle.',
            disabled    = not isK9,
            onSelect    = function() TriggerEvent('rk9:cl:doSniffVehicle') end,
        },
        {
            title       = '👣  Human Tracking',
            description = 'Track nearby or fleeing suspects (humantrack cert). Missing Person search requires Search and Rescue cert.',
            disabled    = not isK9,
            onSelect    = function()
                if not exports['ravens_k9']:RK9_HasActiveCert('humantrack') then
                    RK9_Notify('Human Tracking certification required.', 'error')
                    return
                end
                TriggerEvent('rk9:cl:doTrackHuman')
            end,
        },
        {
            title       = '📋  View Nearby K9 Certs',
            description = 'View the certifications of a nearby handler.',
            disabled    = not canView,
            onSelect    = function()
                local nearby = RK9_GetNearbyPlayers()
                if #nearby == 0 then
                    RK9_Notify('No nearby players found.', 'error')
                    return
                end
                RK9_OpenPickPlayerMenu(nearby, 'viewcerts', nil)
            end,
        },
    }

    if isEval or isAdmin then
        opts[#opts + 1] = {
            title       = '📝  Evaluator Panel',
            description = 'Grant or revoke K9 certifications.',
            onSelect    = RK9_OpenEvaluatorMenu,
        }
    end

    if isAdmin then
        opts[#opts + 1] = {
            title       = '⚙️   Admin Panel',
            description = 'Manage evaluators.',
            onSelect    = RK9_OpenAdminMenu,
        }
    end

    lib.registerContext({ id = 'rk9_main_menu', title = "🐾 Raven's K9 System", options = opts })
    lib.showContext('rk9_main_menu')
end

-- ─── My Certifications ───────────────────────────────────────

function RK9_OpenMyCertsMenu()
    local myCerts = exports['ravens_k9']:RK9_GetMyCerts()
    local opts    = {}

    if #myCerts == 0 then
        opts[#opts + 1] = {
            title    = 'No certifications on file.',
            description = 'Contact a certified evaluator to obtain certifications.',
            disabled = true,
        }
    else
        for _, cert in ipairs(myCerts) do
            local cfg       = RK9Certs.GetConfig(cert.cert_type)
            local label     = cfg and cfg.label or cert.cert_type
            local status, _ = RK9Certs.StatusLabel(cert.expires_at)
            opts[#opts + 1] = {
                title    = label,
                description = string.format(
                    '%s\nIssued: %s  |  Expires: %s\nEvaluator: %s',
                    status,
                    RK9Certs.FormatDate(cert.issued_at),
                    RK9Certs.FormatDate(cert.expires_at),
                    cert.evaluator_name
                ),
                disabled = true,
            }
        end
    end

    opts[#opts + 1] = { title = '← Back', onSelect = RK9_OpenMainMenu }

    lib.registerContext({ id = 'rk9_my_certs_menu', title = '🎖️ My Certifications', options = opts })
    lib.showContext('rk9_my_certs_menu')
end

-- ─── Target cert view (called from server relay) ─────────────

function RK9_OpenCertViewMenu(targetCid, certs)
    local opts = {}
    if #certs == 0 then
        opts[#opts + 1] = { title = 'No certifications on file.', disabled = true }
    else
        for _, cert in ipairs(certs) do
            local cfg       = RK9Certs.GetConfig(cert.cert_type)
            local label     = cfg and cfg.label or cert.cert_type
            local status, _ = RK9Certs.StatusLabel(cert.expires_at)
            opts[#opts + 1] = {
                title    = label,
                description = string.format(
                    '%s\nIssued: %s  |  Expires: %s\nEvaluator: %s',
                    status,
                    RK9Certs.FormatDate(cert.issued_at),
                    RK9Certs.FormatDate(cert.expires_at),
                    cert.evaluator_name
                ),
                disabled = true,
            }
        end
    end

    lib.registerContext({
        id      = 'rk9_target_cert_view',
        title   = '📋 K9 Certs — Handler #' .. targetCid,
        options = opts,
    })
    lib.showContext('rk9_target_cert_view')
end

-- ─── Evaluator Panel ─────────────────────────────────────────

function RK9_OpenEvaluatorMenu()
    lib.registerContext({
        id    = 'rk9_evaluator_panel',
        title = '📝 Evaluator Panel',
        options = {
            {
                title       = '✅  Grant Certification',
                description = 'Issue a certification to a nearby player.',
                onSelect    = function()
                    local nearby = RK9_GetNearbyPlayers()
                    if #nearby == 0 then
                        RK9_Notify('No nearby players found.', 'error') return
                    end
                    RK9_OpenPickPlayerMenu(nearby, 'selectcert', 'grant')
                end,
            },
            {
                title       = '❌  Revoke Certification',
                description = 'Remove a certification from a nearby player.',
                onSelect    = function()
                    local nearby = RK9_GetNearbyPlayers()
                    if #nearby == 0 then
                        RK9_Notify('No nearby players found.', 'error') return
                    end
                    RK9_OpenPickPlayerMenu(nearby, 'selectcert', 'revoke')
                end,
            },
            { title = '← Back', onSelect = RK9_OpenMainMenu },
        },
    })
    lib.showContext('rk9_evaluator_panel')
end

-- ─── Admin Panel ─────────────────────────────────────────────

function RK9_OpenAdminMenu()
    lib.registerContext({
        id    = 'rk9_admin_panel',
        title = '⚙️ Admin Panel',
        options = {
            {
                title       = '➕  Add Evaluator',
                description = 'Designate a nearby player as a K9 evaluator.',
                onSelect    = function()
                    local nearby = RK9_GetNearbyPlayers()
                    if #nearby == 0 then
                        RK9_Notify('No nearby players found.', 'error') return
                    end
                    RK9_OpenPickPlayerMenu(nearby, 'addevaluator', nil)
                end,
            },
            {
                title       = '➖  Remove Evaluator',
                description = 'Remove evaluator status from a player.',
                onSelect    = RK9_OpenRemoveEvaluatorMenu,
            },
            { title = '← Back', onSelect = RK9_OpenMainMenu },
        },
    })
    lib.showContext('rk9_admin_panel')
end

-- ─── Remove Evaluator ────────────────────────────────────────

function RK9_OpenRemoveEvaluatorMenu()
    local evaluators = lib.callback.await('rk9:cb:getEvaluators', false)
    if not evaluators or #evaluators == 0 then
        RK9_Notify('No evaluators found.', 'inform')
        RK9_OpenAdminMenu()
        return
    end

    local opts = {}
    for _, ev in ipairs(evaluators) do
        local e = ev
        opts[#opts + 1] = {
            title    = e.name,
            description = 'CID: ' .. e.citizenid .. '  |  Added: ' .. RK9Certs.FormatDate(e.added_at),
            onSelect = function()
                local confirmed = lib.alertDialog({
                    header   = 'Remove Evaluator',
                    content  = 'Remove evaluator status from ' .. e.name .. '?',
                    centered = true,
                    cancel   = true,
                })
                if confirmed == 'confirm' then
                    TriggerServerEvent('rk9:sv:removeEvaluatorByCid', e.citizenid)
                end
            end,
        }
    end
    opts[#opts + 1] = { title = '← Back', onSelect = RK9_OpenAdminMenu }

    lib.registerContext({ id = 'rk9_remove_evaluator_menu', title = '➖ Remove Evaluator', options = opts })
    lib.showContext('rk9_remove_evaluator_menu')
end

-- ─── Generic player picker ────────────────────────────────────
--  action: 'viewcerts' | 'selectcert' | 'addevaluator'
--  certAction: 'grant' | 'revoke' | nil

function RK9_OpenPickPlayerMenu(playerList, action, certAction)
    local opts = {}
    for _, p in ipairs(playerList) do
        local pp = p
        opts[#opts + 1] = {
            title    = pp.name,
            description = 'Server ID: ' .. pp.serverId .. '  |  Distance: ' .. math.floor(pp.dist) .. 'm',
            onSelect = function()
                if action == 'viewcerts' then
                    TriggerServerEvent('rk9:sv:requestTargetCerts', pp.serverId)

                elseif action == 'selectcert' then
                    RK9_OpenSelectCertMenu(pp.serverId, pp.name, certAction)

                elseif action == 'addevaluator' then
                    local confirmed = lib.alertDialog({
                        header   = 'Add Evaluator',
                        content  = 'Designate ' .. pp.name .. ' as a K9 Evaluator?',
                        centered = true,
                        cancel   = true,
                    })
                    if confirmed == 'confirm' then
                        TriggerServerEvent('rk9:sv:addEvaluatorByServerId', pp.serverId)
                    end
                end
            end,
        }
    end
    opts[#opts + 1] = { title = '← Back', onSelect = RK9_OpenMainMenu }

    lib.registerContext({
        id      = 'rk9_pick_player_menu',
        title   = action == 'addevaluator' and '➕ Select Player — Add Evaluator'
                  or (certAction == 'grant' and '✅ Select Player — Grant Cert'
                  or (certAction == 'revoke' and '❌ Select Player — Revoke Cert'
                  or '📋 Select Player — View Certs')),
        options = opts,
    })
    lib.showContext('rk9_pick_player_menu')
end

-- ─── Cert type selection ─────────────────────────────────────

function RK9_OpenSelectCertMenu(targetServerId, targetName, action)
    local opts = {}
    for _, certCfg in ipairs(RK9Config.CertTypes) do
        local c = certCfg
        opts[#opts + 1] = {
            title       = c.label,
            description = c.desc,
            onSelect    = function()
                local verb      = action == 'grant' and 'Grant' or 'Revoke'
                local confirmed = lib.alertDialog({
                    header   = verb .. ' Certification',
                    content  = string.format('%s **%s** to/from %s?', verb, c.label, targetName),
                    centered = true,
                    cancel   = true,
                })
                if confirmed ~= 'confirm' then return end

                if action == 'grant' then
                    TriggerServerEvent('rk9:sv:grantCertByServerId', targetServerId, c.id)
                else
                    TriggerServerEvent('rk9:sv:revokeCertByServerId', targetServerId, c.id)
                end
            end,
        }
    end
    opts[#opts + 1] = {
        title    = '← Back',
        onSelect = function() RK9_OpenEvaluatorMenu() end,
    }

    lib.registerContext({
        id      = 'rk9_select_cert_menu',
        title   = (action == 'grant' and '✅ Grant Cert' or '❌ Revoke Cert') .. ' — ' .. targetName,
        options = opts,
    })
    lib.showContext('rk9_select_cert_menu')
end
