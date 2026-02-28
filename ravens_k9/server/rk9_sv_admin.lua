-- ============================================================
--  Raven's K9 System  |  rk9_sv_admin.lua
--  Author: Raven
--  Admin and evaluator management: chat commands and the
--  net events fired by the in-game menus/targets.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()

local function RK9_Notify(src, msg, ntype)
    TriggerClientEvent('rk9:cl:notify', src, msg, ntype or 'inform')
end

-- ═══════════════════════════════════════════════════════════════
--  Evaluator Management Events  (menu + target driven)
-- ═══════════════════════════════════════════════════════════════

RegisterNetEvent('rk9:sv:addEvaluatorByServerId', function(targetServerId)
    local src = source
    if not exports['ravens_k9']:RK9_IsAdmin(src) then
        RK9_Notify(src, 'Only admins can add evaluators.', 'error') return
    end

    local tp = QBCore.Functions.GetPlayer(targetServerId)
    if not tp then
        RK9_Notify(src, 'Target player not found.', 'error') return
    end

    local pd      = tp.PlayerData
    local cid     = pd.citizenid
    local name    = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
    local adminCid = exports['ravens_k9']:RK9_GetCitizenId(src)

    MySQL.query.await([[
        INSERT IGNORE INTO ravens_k9_evaluators (citizenid, name, added_by, added_at)
        VALUES (?, ?, ?, ?)
    ]], { cid, name, adminCid, os.time() })

    -- update in‑memory cache
    TriggerEvent('rk9:sv:refreshEvaluatorCache')

    RK9_Notify(src, name .. ' added as K9 Evaluator.', 'success')
    RK9_Notify(targetServerId, 'You have been designated as a K9 Evaluator.', 'success')
    print(string.format('[Ravens K9] Admin %s added evaluator: %s (%s)', adminCid, name, cid))
end)

RegisterNetEvent('rk9:sv:removeEvaluatorByCid', function(citizenid)
    local src = source
    if not exports['ravens_k9']:RK9_IsAdmin(src) then
        RK9_Notify(src, 'Only admins can remove evaluators.', 'error') return
    end

    MySQL.query.await(
        'DELETE FROM ravens_k9_evaluators WHERE citizenid = ?', { citizenid }
    )
    -- update cache as well
    TriggerEvent('rk9:sv:refreshEvaluatorCache')

    RK9_Notify(src, 'Evaluator removed (CID: ' .. citizenid .. ').', 'inform')

    -- Notify the evaluator if they're online
    local targetSrc = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if targetSrc then
        RK9_Notify(targetSrc, 'Your K9 Evaluator status has been removed.', 'error')
    end

    print(string.format('[Ravens K9] Evaluator removed: %s', citizenid))
end)

-- ═══════════════════════════════════════════════════════════════
--  Chat Commands  (admin / evaluator)
-- ═══════════════════════════════════════════════════════════════

--- /k9addevaluator [id]  — admin only
QBCore.Commands.Add(
    RK9Config.Cmds.AddEvaluator,
    '[K9 Admin] Add a player as a K9 evaluator',
    { { name = 'id', help = 'Target player server ID' } },
    true,
    function(source, args)
        if not exports['ravens_k9']:RK9_IsAdmin(source) then
            RK9_Notify(source, 'Admin permission required.', 'error') return
        end
        local targetSrc = tonumber(args[1])
        if not targetSrc then
            RK9_Notify(source, 'Invalid player ID.', 'error') return
        end
        TriggerEvent('rk9:sv:addEvaluatorByServerId', targetSrc)
        -- Forward with the original source context
        -- (TriggerEvent fires from server scope; wrap properly)
    end,
    'admin'
)

--- /k9removeevaluator [id]  — admin only
QBCore.Commands.Add(
    RK9Config.Cmds.RemoveEvaluator,
    '[K9 Admin] Remove evaluator status from a player',
    { { name = 'id', help = 'Target player server ID' } },
    true,
    function(source, args)
        if not exports['ravens_k9']:RK9_IsAdmin(source) then
            RK9_Notify(source, 'Admin permission required.', 'error') return
        end
        local targetSrc    = tonumber(args[1])
        local targetPlayer = QBCore.Functions.GetPlayer(targetSrc)
        if not targetPlayer then
            RK9_Notify(source, 'Player not found.', 'error') return
        end
        local cid = targetPlayer.PlayerData.citizenid
        MySQL.query.await('DELETE FROM ravens_k9_evaluators WHERE citizenid = ?', { cid })
        -- sync in-memory cache
        TriggerEvent('rk9:sv:refreshEvaluatorCache')
        RK9_Notify(source, 'Evaluator removed.', 'inform')
        RK9_Notify(targetSrc, 'Your K9 Evaluator status has been removed.', 'error')
    end,
    'admin'
)

--- /k9grantcert [id] [certtype]  — evaluator+
QBCore.Commands.Add(
    RK9Config.Cmds.GrantCert,
    '[K9] Grant a K9 certification to a player',
    {
        { name = 'id',   help = 'Target player server ID' },
        { name = 'cert', help = 'patrol | firearms | narcotics | explosives | humantrack' },
    },
    true,
    function(source, args)
        local targetSrc    = tonumber(args[1])
        local certType     = args[2]
        local targetPlayer = QBCore.Functions.GetPlayer(targetSrc)
        if not targetPlayer then
            RK9_Notify(source, 'Player not found.', 'error') return
        end
        TriggerNetEvent('rk9:sv:grantCertByServerId', targetSrc, certType)
        -- Re-trigger so source context is preserved via net event path
    end,
    'user'
)

--- /k9revokecert [id] [certtype]  — evaluator+
QBCore.Commands.Add(
    RK9Config.Cmds.RevokeCert,
    '[K9] Revoke a K9 certification from a player',
    {
        { name = 'id',   help = 'Target player server ID' },
        { name = 'cert', help = 'patrol | firearms | narcotics | explosives | humantrack' },
    },
    true,
    function(source, args)
        local targetSrc    = tonumber(args[1])
        local certType     = args[2]
        local targetPlayer = QBCore.Functions.GetPlayer(targetSrc)
        if not targetPlayer then
            RK9_Notify(source, 'Player not found.', 'error') return
        end
        TriggerNetEvent('rk9:sv:revokeCertByServerId', targetSrc, certType)
    end,
    'user'
)
