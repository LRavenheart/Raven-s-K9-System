-- ============================================================
--  Raven's K9 System  |  rk9_config.lua
--  Author: Raven
--  Shared configuration — edit this file to customise the
--  system for your server.
-- ============================================================

RK9Config = {}

-- ─── LEO jobs allowed to access the K9 system ───────────────
RK9Config.AllowedJobs = {
    'police',
    'sheriff',
    'statepolice',
    'bcso',
    -- Add more job names as needed
}

-- ─── QBCore permission groups that count as "admin" ─────────
RK9Config.AdminGroups = { 'admin', 'superadmin', 'god' }

-- ─── K9 roleplay gating ──────────────────────────────────────
--  When enabled, core K9 actions (sniffing + tracking) require an
--  active Patrol certification in addition to job/role checks.
RK9Config.RequirePatrolCertForK9Actions = true

-- ─── Certification types ─────────────────────────────────────
--
--  Each entry requires:
--    id    — internal identifier used throughout the system
--    label — display name shown in menus and on cert cards
--    desc  — short description shown in evaluator / cert menus
--    color — hex colour used for future UI theming
--
--  Tracking cert dependency:
--    humantrack — required for Nearby Suspect and Fleeing Suspect tracking modes
--    sar        — required for Missing Person (server-wide) tracking; humantrack must
--                 also be held, as SAR builds on the base tracking skillset
--
RK9Config.CertTypes = {
    {
        id    = 'handler',
        label = 'Handler Certification',
        desc  = 'Authorises handler-level K9 paperwork checks (view certifications only).',
        color = '#95a5a6',
    },
    {
        id    = 'patrol',
        label = 'Patrol Certification',
        desc  = 'Basic K9 patrol operations and handler obedience skills.',
        color = '#4a90d9',
    },
    {
        id    = 'firearms',
        label = 'Firearms Detection',
        desc  = 'Detection of concealed firearms, magazines and ammunition.',
        color = '#e67e22',
    },
    {
        id    = 'narcotics',
        label = 'Narcotics Detection',
        desc  = 'Detection of controlled narcotics and drug paraphernalia.',
        color = '#9b59b6',
    },
    {
        id    = 'explosives',
        label = 'Explosives Detection',
        desc  = 'Detection of explosive devices and precursor materials.',
        color = '#e74c3c',
    },
    {
        id    = 'humantrack',
        label = 'Human Tracking',
        desc  = 'Track nearby and fleeing suspects by scent trail. Required for all tracking modes.',
        color = '#27ae60',
    },
    {
        id    = 'sar',
        label = 'Search and Rescue',
        desc  = 'Unlocks server-wide Missing Person tracking. Requires Human Tracking certification.',
        color = '#1abc9c',
    },
}

-- ─── Items detectable per cert type ─────────────────────────
--  Use exact QBCore item names. Add/remove freely.
--  handler, patrol, humantrack, and sar use behaviour logic — no item detection.
RK9Config.DetectableItems = {
    firearms = {
        'weapon_pistol', 'weapon_combatpistol', 'weapon_heavypistol',
        'weapon_microsmg', 'weapon_smg', 'weapon_assaultrifle',
        'weapon_carbinerifle', 'weapon_shotgun', 'weapon_pumpshotgun',
        'weapon_sniperrifle', 'weapon_revolver', 'weapon_appistol',
        'pistol_ammo', 'rifle_ammo', 'shotgun_ammo', 'smg_ammo',
    },
    narcotics = {
        'weed_brick', 'weed_baggie', 'coke_brick', 'coke_baggie',
        'meth_brick', 'meth_baggie', 'heroin_brick', 'heroin_baggie',
        'mdma', 'xanax', 'oxy', 'crack_baggie', 'joint',
        'marijuana', 'cocaine', 'methamphetamine',
    },
    explosives = {
        'weapon_grenade', 'weapon_smokegrenade', 'weapon_bzgas',
        'weapon_molotov', 'weapon_stickybomb', 'weapon_proximitymine',
        'c4', 'explosive', 'detonator',
    },
    handler    = {},
    -- Behaviour-only certs — no item scanning required
    patrol     = {},
    humantrack = {},
    sar        = {},
}

-- ─── Detection distances ─────────────────────────────────────
RK9Config.DetectionRadius   = 3.0    -- metres, player ped sniff range
RK9Config.VehicleRadius     = 5.0    -- metres, vehicle sniff range
RK9Config.SniffDuration     = 5000   -- ms the animation plays before showing result
RK9Config.TrackingRadius    = 50.0   -- metres, proximity scan used by Nearby and Fleeing modes
RK9Config.TrackingUpdateMs  = 2000   -- ms between live tracking blip updates

-- ─── Miscellaneous utilities ───────────────────────────────
RK9Config.ViewNearbyRadius = 10.0   -- metres used by /k9viewcerts logic

-- ─── Human tracking session settings ────────────────────────
--
--  Three tracking modes, each with its own scope and timeout:
--
--    nearby  (humantrack cert)
--      Scans players within RK9Config.TrackingRadius.
--      Standard patrol use — general-purpose proximity tracking.
--
--    fleeing (humantrack cert)
--      Scans players within RK9Config.TrackingRadius.
--      Designed for active pursuit of a suspect who was recently nearby.
--      Longer timeout than nearby to accommodate a chase.
--
--    missing (sar cert + humantrack cert)
--      Scans ALL online players server-wide.
--      Reserved for Search and Rescue operations only.
--      Longest timeout to support extended searches.
--
RK9Config.TrackingTimeout = {
    nearby  = 600000,   -- 10 minutes
    fleeing = 1200000,  -- 20 minutes
    missing = 3600000,  -- 60 minutes
}

-- ─── Tracking blip colours ───────────────────────────────────
--  GTA V blip colour IDs:
--    3  = Blue   — missing person (SAR, non-hostile)
--    5  = Yellow — fleeing suspect (active pursuit)
--    6  = Grey   — nearby / general patrol tracking
RK9Config.TrackingBlipColour = {
    nearby  = 6,   -- Grey  — standard patrol
    fleeing = 5,   -- Yellow — active pursuit
    missing = 3,   -- Blue   — search and rescue
}

-- ─── Certification expiry ────────────────────────────────────
RK9Config.CertExpiryDays    = 365    -- days until a cert expires
RK9Config.ExpiryWarnDays    = 30     -- days before expiry that evaluators are warned

-- ─── Cert card inventory item name ──────────────────────────
RK9Config.CertCardItem      = 'rk9_cert_card'

-- ─── Chat / console command names ───────────────────────────
RK9Config.Cmds = {
    OpenMenu        = 'k9menu',
    SniffPed        = 'k9sniffped',
    SniffVehicle    = 'k9sniffveh',
    TrackHuman      = 'k9track',
    StopTrack       = 'k9stoptrack',
    ViewNearbyCerts = 'k9viewcerts',
    -- Admin / evaluator
    AddEvaluator    = 'k9addevaluator',
    RemoveEvaluator = 'k9removeevaluator',
    GrantCert       = 'k9grantcert',
    RevokeCert      = 'k9revokecert',
}

-- ─── ox_lib notification position ───────────────────────────
RK9Config.NotifyPos = 'top-right'
