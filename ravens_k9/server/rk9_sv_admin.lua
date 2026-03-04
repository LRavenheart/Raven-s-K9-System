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

local function RK9_AddEvaluator(actorSrc, targetServerId)
    if not exports['ravens_k9']:RK9_IsAdmin(actorSrc) then
        RK9_Notify(actorSrc, 'Only admins can add evaluators.', 'error')
        return false
    end

    local tp = QBCore.Functions.GetPlayer(targetServerId)
    if not tp then
        RK9_Notify(actorSrc, 'Target player not found.', 'error')
        return false
    end

    local pd       = tp.PlayerData
    local cid      = pd.citizenid
    local name     = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
    local adminCid = exports['ravens_k9']:RK9_GetCitizenId(actorSrc)

    MySQL.query.await([[
        INSERT IGNORE INTO ravens_k9_evaluators (citizenid, name, added_by, added_at)
        VALUES (?, ?, ?, ?)
    ]], { cid, name, adminCid, os.time() })

    TriggerEvent('rk9:sv:refreshEvaluatorCache')

    RK9_Notify(actorSrc, name .. ' added as K9 Evaluator.', 'success')
    RK9_Notify(targetServerId, 'You have been designated as a K9 Evaluator.', 'success')
    print(string.format('[Ravens K9] Admin %s added evaluator: %s (%s)', adminCid, name, cid))

    return true
end

local function RK9_RemoveEvaluator(actorSrc, citizenid)
    if not exports['ravens_k9']:RK9_IsAdmin(actorSrc) then
        RK9_Notify(actorSrc, 'Only admins can remove evaluators.', 'error')
        return false
    end

    MySQL.query.await(
        'DELETE FROM ravens_k9_evaluators WHERE citizenid = ?', { citizenid }
    )
    TriggerEvent('rk9:sv:refreshEvaluatorCache')

    RK9_Notify(actorSrc, 'Evaluator removed (CID: ' .. citizenid .. ').', 'inform')

    local targetSrc = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if targetSrc then
        RK9_Notify(targetSrc, 'Your K9 Evaluator status has been removed.', 'error')
    end

    print(string.format('[Ravens K9] Evaluator removed: %s', citizenid))
    return true
end

-- ═══════════════════════════════════════════════════════════════
--  Evaluator Management Events  (menu + target driven)
-- ═══════════════════════════════════════════════════════════════

RegisterNetEvent('rk9:sv:addEvaluatorByServerId', function(targetServerId)
    RK9_AddEvaluator(source, targetServerId)
end)

RegisterNetEvent('rk9:sv:removeEvaluatorByCid', function(citizenid)
    RK9_RemoveEvaluator(source, citizenid)
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
        RK9_AddEvaluator(source, targetSrc)
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
        RK9_RemoveEvaluator(source, cid)
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
        TriggerEvent('rk9:sv:grantCertByServerId', targetSrc, certType, source)
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
        TriggerEvent('rk9:sv:revokeCertByServerId', targetSrc, certType, source)
    end,
    'user'
)
