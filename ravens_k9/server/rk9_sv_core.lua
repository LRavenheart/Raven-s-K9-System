-- ============================================================
--  Raven's K9 System  |  rk9_sv_core.lua
--  Author: Raven
--  Server core: database initialisation, authority helpers,
--  cert grant/revoke, sniff processing, human tracking,
--  and the expiry notification loop.
-- ============================================================

local QBCore = exports['qb-core']:GetCoreObject()

-- ═══════════════════════════════════════════════════════════════
--  Database Initialisation
-- ═══════════════════════════════════════════════════════════════

CreateThread(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `ravens_k9_certs` (
            `id`             INT          AUTO_INCREMENT PRIMARY KEY,
            `citizenid`      VARCHAR(50)  NOT NULL,
            `cert_type`      VARCHAR(50)  NOT NULL,
            `issued_at`      INT          NOT NULL  COMMENT 'Unix timestamp — issue date',
            `expires_at`     INT          NOT NULL  COMMENT 'Unix timestamp — expiry date',
            `evaluator_id`   VARCHAR(50)  NOT NULL  COMMENT 'CitizenID of issuing evaluator',
            `evaluator_name` VARCHAR(100) NOT NULL  COMMENT 'Full name of issuing evaluator',
            UNIQUE KEY `rk9_unique_cert` (`citizenid`, `cert_type`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Raven K9 — handler certifications'
    ]])

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `ravens_k9_evaluators` (
            `id`          INT          AUTO_INCREMENT PRIMARY KEY,
            `citizenid`   VARCHAR(50)  NOT NULL UNIQUE,
            `name`        VARCHAR(100) NOT NULL,
            `added_by`    VARCHAR(50)  NOT NULL  COMMENT 'CitizenID of admin who added this evaluator',
            `added_at`    INT          NOT NULL  COMMENT 'Unix timestamp'
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Raven K9 — certified evaluators'
    ]])

    print('[Ravens K9] Database tables verified.')
    -- populate evaluator cache from DB
    refreshEvaluatorCache()
end)

-- ═══════════════════════════════════════════════════════════════
--  Authority Helpers  (exported so other server scripts can use)
-- ═══════════════════════════════════════════════════════════════

local function RK9_GetPlayerData(src)
    local player = QBCore.Functions.GetPlayer(src)
    return player and player.PlayerData or nil
end

local function RK9_GetCitizenId(src)
    local pd = RK9_GetPlayerData(src)
    return pd and pd.citizenid or nil
end

local function RK9_IsLEO(src)
    local pd = RK9_GetPlayerData(src)
    if not pd then return false end
    for _, j in ipairs(RK9Config.AllowedJobs) do
        if pd.job and pd.job.name == j then return true end
    end
    return false
end

local function RK9_IsAdmin(src)
    for _, g in ipairs(RK9Config.AdminGroups) do
        if QBCore.Functions.HasPermission(src, g) then return true end
    end
    return false
end

-- cache of evaluator citizenids to avoid repeated queries
local evaluatorCache = {}

local function refreshEvaluatorCache()
    evaluatorCache = {}
    local rows = MySQL.query.await('SELECT citizenid FROM ravens_k9_evaluators', {})
    if rows then
        for _, r in ipairs(rows) do
            evaluatorCache[r.citizenid] = true
        end
    end
end

AddEventHandler('rk9:sv:refreshEvaluatorCache', refreshEvaluatorCache)

local function RK9_IsEvaluator(src)
    if RK9_IsAdmin(src) then return true end
    local cid = RK9_GetCitizenId(src)
    if not cid then return false end
    if evaluatorCache[cid] ~= nil then
        return evaluatorCache[cid]
    end
    local row = MySQL.single.await(
        'SELECT id FROM ravens_k9_evaluators WHERE citizenid = ?', { cid }
    )
    local isEv = row ~= nil
    evaluatorCache[cid] = isEv
    return isEv
end

exports('RK9_IsLEO',         RK9_IsLEO)
exports('RK9_IsAdmin',       RK9_IsAdmin)
exports('RK9_IsEvaluator',   RK9_IsEvaluator)
exports('RK9_GetCitizenId',  RK9_GetCitizenId)
exports('RK9_GetPlayerData', RK9_GetPlayerData)

-- ─── Notification helper ──────────────────────────────────────

local function RK9_Notify(src, msg, ntype)
    TriggerClientEvent('rk9:cl:notify', src, msg, ntype or 'inform')
end

-- ═══════════════════════════════════════════════════════════════
--  Cert Retrieval Events
-- ═══════════════════════════════════════════════════════════════

RegisterNetEvent('rk9:sv:fetchMyCerts', function()
    local src = source
    if not RK9_IsLEO(src) then return end
    local cid  = RK9_GetCitizenId(src)
    local rows = MySQL.query.await(
        'SELECT * FROM ravens_k9_certs WHERE citizenid = ?', { cid }
    )
    TriggerClientEvent('rk9:cl:receiveMyCerts', src, rows or {})
end)

RegisterNetEvent('rk9:sv:requestTargetCerts', function(targetServerId)
    local src = source
    if not RK9_IsLEO(src) then return end
    local targetPlayer = QBCore.Functions.GetPlayer(targetServerId)
    if not targetPlayer then
        RK9_Notify(src, 'Player not found.', 'error') return
    end
    local cid  = targetPlayer.PlayerData.citizenid
    local rows = MySQL.query.await(
        'SELECT * FROM ravens_k9_certs WHERE citizenid = ?', { cid }
    )
    TriggerClientEvent('rk9:cl:receiveTargetCerts', src, cid, rows or {})
end)

-- ═══════════════════════════════════════════════════════════════
--  Grant / Revoke  (by citizenid — used internally)
-- ═══════════════════════════════════════════════════════════════

local function RK9_DoGrantCert(src, targetCid, certType)
    if not RK9_IsEvaluator(src) then
        RK9_Notify(src, 'You are not authorised to grant certifications.', 'error') return
    end
    if not RK9Certs.IsValidType(certType) then
        RK9_Notify(src, 'Invalid certification type: ' .. certType, 'error') return
    end

    local evPd   = RK9_GetPlayerData(src)
    local evName = evPd
        and (evPd.charinfo.firstname .. ' ' .. evPd.charinfo.lastname)
        or  'Unknown'
    local evCid  = RK9_GetCitizenId(src)
    local now    = os.time()
    local expiry = now + (RK9Config.CertExpiryDays * 86400)

    MySQL.query.await([[
        INSERT INTO ravens_k9_certs
            (citizenid, cert_type, issued_at, expires_at, evaluator_id, evaluator_name)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            issued_at      = VALUES(issued_at),
            expires_at     = VALUES(expires_at),
            evaluator_id   = VALUES(evaluator_id),
            evaluator_name = VALUES(evaluator_name)
    ]], { targetCid, certType, now, expiry, evCid, evName })

    -- Issue a cert card item if the target is online
    local targetSrc = QBCore.Functions.GetPlayerByCitizenId(targetCid)
    if targetSrc then
        local tp = QBCore.Functions.GetPlayer(targetSrc)
        if tp then
            tp.Functions.AddItem(RK9Config.CertCardItem, 1, nil, {
                cert_type      = certType,
                issued_at      = now,
                expires_at     = expiry,
                evaluator_name = evName,
                citizenid      = targetCid,
            })
        end
        RK9_Notify(targetSrc,
            'You have been granted: ' .. RK9Certs.GetLabel(certType) .. ' certification.',
            'success'
        )
        -- Refresh the target's cert cache
        local fresh = MySQL.query.await(
            'SELECT * FROM ravens_k9_certs WHERE citizenid = ?', { targetCid }
        )
        TriggerClientEvent('rk9:cl:receiveMyCerts', targetSrc, fresh or {})
    end

    RK9_Notify(src,
        RK9Certs.GetLabel(certType) .. ' granted to CID: ' .. targetCid, 'success'
    )
    print(string.format('[Ravens K9] %s granted cert "%s" to %s', evCid, certType, targetCid))
end

local function RK9_DoRevokeCert(src, targetCid, certType)
    if not RK9_IsEvaluator(src) then
        RK9_Notify(src, 'You are not authorised to revoke certifications.', 'error') return
    end
    MySQL.query.await(
        'DELETE FROM ravens_k9_certs WHERE citizenid = ? AND cert_type = ?',
        { targetCid, certType }
    )
    RK9_Notify(src, RK9Certs.GetLabel(certType) .. ' revoked from ' .. targetCid, 'inform')

    local targetSrc = QBCore.Functions.GetPlayerByCitizenId(targetCid)
    if targetSrc then
        RK9_Notify(targetSrc,
            'Your ' .. RK9Certs.GetLabel(certType) .. ' certification has been revoked.',
            'error'
        )
        local fresh = MySQL.query.await(
            'SELECT * FROM ravens_k9_certs WHERE citizenid = ?', { targetCid }
        )
        TriggerClientEvent('rk9:cl:receiveMyCerts', targetSrc, fresh or {})
    end
end

-- ─── Grant/revoke events by server ID (menu + target flows) ──

RegisterNetEvent('rk9:sv:grantCertByServerId', function(targetServerId, certType)
    local src = source
    local tp  = QBCore.Functions.GetPlayer(targetServerId)
    if not tp then RK9_Notify(src, 'Player not found.', 'error') return end
    RK9_DoGrantCert(src, tp.PlayerData.citizenid, certType)
end)

RegisterNetEvent('rk9:sv:revokeCertByServerId', function(targetServerId, certType)
    local src = source
    local tp  = QBCore.Functions.GetPlayer(targetServerId)
    if not tp then RK9_Notify(src, 'Player not found.', 'error') return end
    RK9_DoRevokeCert(src, tp.PlayerData.citizenid, certType)
end)

-- ─── Grant/revoke events by citizenid (chat commands) ─────────

RegisterNetEvent('rk9:sv:grantCertByCid', function(targetCid, certType)
    RK9_DoGrantCert(source, targetCid, certType)
end)

RegisterNetEvent('rk9:sv:revokeCertByCid', function(targetCid, certType)
    RK9_DoRevokeCert(source, targetCid, certType)
end)

-- ═══════════════════════════════════════════════════════════════
--  Sniff Processing  (server-authoritative item checks)
-- ═══════════════════════════════════════════════════════════════

RegisterNetEvent('rk9:sv:sniffPed', function(targetServerId, certTypes)
    local src          = source
    if not RK9_IsLEO(src) then return end
    local targetPlayer = QBCore.Functions.GetPlayer(targetServerId)
    if not targetPlayer then
        TriggerClientEvent('rk9:cl:sniffResult', src, false, {}) return
    end

    local found = {}
    for _, certType in ipairs(certTypes) do
        local items = RK9Config.DetectableItems[certType]
        if items then
            for _, itemName in ipairs(items) do
                if targetPlayer.Functions.GetItemByName(itemName) then
                    found[#found + 1] = { item = itemName, cert = certType }
                end
            end
        end
    end

    TriggerClientEvent('rk9:cl:sniffResult', src, #found > 0, found)
end)

RegisterNetEvent('rk9:sv:sniffVehicle', function(vehiclePlate, certTypes)
    local src   = source
    if not RK9_IsLEO(src) then return end
    local found = {}

    for _, playerId in ipairs(GetPlayers()) do
        local player = QBCore.Functions.GetPlayer(tonumber(playerId))
        if player then
            local veh = player.PlayerData.vehicle
            if veh and veh.plate == vehiclePlate then
                for _, certType in ipairs(certTypes) do
                    local items = RK9Config.DetectableItems[certType]
                    if items then
                        for _, itemName in ipairs(items) do
                            if player.Functions.GetItemByName(itemName) then
                                found[#found + 1] = { item = itemName, cert = certType }
                            end
                        end
                    end
                end
            end
        end
    end

    TriggerClientEvent('rk9:cl:sniffResult', src, #found > 0, found)
end)

-- ═══════════════════════════════════════════════════════════════
--  Human Tracking
-- ═══════════════════════════════════════════════════════════════

-- When a handler requests a tracking update we no longer attempt to
-- call client-only natives on the server. Instead we send a request to the
-- target player's client, which replies with its current position. The
-- `mode` parameter is echoed back so the client can colour the blip correctly.
RegisterNetEvent('rk9:sv:trackHuman', function(targetServerId, mode)
    local src = source
    if not RK9_IsLEO(src) then return end
    local tgt = tonumber(targetServerId)
    local tp  = QBCore.Functions.GetPlayer(tgt)
    if not tp then
        TriggerClientEvent('rk9:cl:notify', src, 'Could not locate tracking target.', 'error')
        return
    end
    -- ask the target client for its coords
    TriggerClientEvent('rk9:cl:provideTrackCoords', tgt, src, mode)
end)

-- response from target client with actual coordinates
RegisterNetEvent('rk9:sv:trackCoordsResponse', function(requesterSrc, coords, mode)
    if not RK9_IsLEO(requesterSrc) then return end
    if coords and coords.x then
        TriggerClientEvent('rk9:cl:trackingUpdate', requesterSrc, coords, mode)
    end
end)

-- ═══════════════════════════════════════════════════════════════
--  Expiry Warning Loop  (notifies online evaluators)
-- ═══════════════════════════════════════════════════════════════

local function RK9_RunExpiryCheck()
    local evaluators = MySQL.query.await('SELECT citizenid FROM ravens_k9_evaluators', {})
    if not evaluators or #evaluators == 0 then return end

    local now        = os.time()
    local warnBefore = RK9Config.ExpiryWarnDays * 86400

    -- Certs expiring within the warn window
    local expiring = MySQL.query.await([[
        SELECT citizenid, cert_type, expires_at
        FROM ravens_k9_certs
        WHERE expires_at BETWEEN ? AND ?
    ]], { now, now + warnBefore })

    if not expiring or #expiring == 0 then return end

    for _, ev in ipairs(evaluators) do
        local evSrc = QBCore.Functions.GetPlayerByCitizenId(ev.citizenid)
        if evSrc then
            for _, row in ipairs(expiring) do
                local daysLeft = math.max(0, math.floor((row.expires_at - now) / 86400))
                TriggerClientEvent('rk9:cl:notify', evSrc, string.format(
                    '[K9 Expiry] %s — %s expires in %d day(s)',
                    row.citizenid, RK9Certs.GetLabel(row.cert_type), daysLeft
                ), 'warning')
            end
        end
    end
end

CreateThread(function()
    Wait(10000) -- initial delay after resource start
    RK9_RunExpiryCheck()
    while true do
        Wait(21600000) -- every 6 hours
        RK9_RunExpiryCheck()
    end
end)
