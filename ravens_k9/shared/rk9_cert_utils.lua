-- ============================================================
--  Raven's K9 System  |  rk9_cert_utils.lua
--  Author: Raven
--  Shared helpers used by both client and server scripts.
-- ============================================================

RK9Certs = {}

--- Returns the full config table for a cert ID, or nil.
function RK9Certs.GetConfig(certId)
    for _, c in ipairs(RK9Config.CertTypes) do
        if c.id == certId then return c end
    end
    return nil
end

--- Returns the display label for a cert ID.
function RK9Certs.GetLabel(certId)
    local cfg = RK9Certs.GetConfig(certId)
    return cfg and cfg.label or certId
end

--- Returns true if the supplied unix timestamp is in the past.
function RK9Certs.IsExpired(expiresAt)
    if not expiresAt then return false end
    return os.time() > expiresAt
end

--- Returns true if the cert will expire within RK9Config.ExpiryWarnDays.
function RK9Certs.IsExpiringSoon(expiresAt)
    if not expiresAt then return false end
    local remaining = expiresAt - os.time()
    local warnWindow = RK9Config.ExpiryWarnDays * 86400
    return remaining > 0 and remaining <= warnWindow
end

--- Converts a unix timestamp to a YYYY-MM-DD string.
function RK9Certs.FormatDate(ts)
    if not ts then return 'N/A' end
    return os.date('%Y-%m-%d', ts)
end

--- Returns a human-readable status string and colour hint.
function RK9Certs.StatusLabel(expiresAt)
    if RK9Certs.IsExpired(expiresAt) then
        return '⛔ EXPIRED', 'error'
    elseif RK9Certs.IsExpiringSoon(expiresAt) then
        return '⚠️ Expiring Soon', 'warning'
    else
        return '✅ Active', 'success'
    end
end

--- Returns true if a cert ID string is valid per config.
function RK9Certs.IsValidType(certId)
    for _, c in ipairs(RK9Config.CertTypes) do
        if c.id == certId then return true end
    end
    return false
end
