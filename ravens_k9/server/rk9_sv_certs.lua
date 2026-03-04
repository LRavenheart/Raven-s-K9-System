-- ============================================================
--  Raven's K9 System  |  rk9_sv_certs.lua
--  Author: Raven
--  ox_lib server callbacks used by the client menus to
--  query cert data and role checks without full net events.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()

-- ─── Cert data callbacks ─────────────────────────────────────

--- Fetch all certs for the requesting player's own citizenid.
lib.callback.register('rk9:cb:getMyCerts', function(source)
    if not exports['ravens_k9']:RK9_IsLEO(source) then return {} end
    local cid  = exports['ravens_k9']:RK9_GetCitizenId(source)
    local rows = MySQL.query.await(
        'SELECT * FROM ravens_k9_certs WHERE citizenid = ?', { cid }
    )
    return rows or {}
end)

--- Fetch certs for an arbitrary citizenid.
--- Access is limited to players who can view dog certs
--- (active K9 unit OR Handler role).
lib.callback.register('rk9:cb:getCertsForCid', function(source, citizenid)
    if not exports['ravens_k9']:RK9_CanViewDogCerts(source) then
        return {}
    end
    local rows = MySQL.query.await(
        'SELECT * FROM ravens_k9_certs WHERE citizenid = ?', { citizenid }
    )
    return rows or {}
end)

--- Fetch all registered evaluators (admin-only).
lib.callback.register('rk9:cb:getEvaluators', function(source)
    if not exports['ravens_k9']:RK9_IsAdmin(source) then return {} end
    local rows = MySQL.query.await('SELECT * FROM ravens_k9_evaluators ORDER BY name ASC', {})
    return rows or {}
end)

-- ─── Role check callbacks (used by client canInteract guards) ─

lib.callback.register('rk9:cb:isEvaluator', function(source)
    return exports['ravens_k9']:RK9_IsEvaluator(source)
end)

lib.callback.register('rk9:cb:isAdmin', function(source)
    return exports['ravens_k9']:RK9_IsAdmin(source)
end)

lib.callback.register('rk9:cb:isLeo', function(source)
    return exports['ravens_k9']:RK9_IsLEO(source)
end)
