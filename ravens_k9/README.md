# 🐾 Raven's K9 System
**Author:** Raven | **Version:** 1.0.0 | **Framework:** QBCore

Advanced player-controlled K9 resource with certification workflows, role-based access, item detection, and server-authoritative human tracking.

---

## What this resource does

Raven’s K9 System supports four practical in-game roles:

- **K9 Player**: performs operational K9 actions (sniff/track) when eligible.
- **Handler**: paperwork/check role (view K9 certs only).
- **Evaluator**: grants/revokes certifications.
- **Admin**: manages evaluators and has full evaluator capability.

By default, operational K9 actions require an active **Patrol** certification (`RequirePatrolCertForK9Actions = true`).

---

## File Structure

```txt
ravens_k9/
├── fxmanifest.lua
├── rk9_install.sql
├── shared/
│   ├── rk9_config.lua        # Main configuration
│   └── rk9_cert_utils.lua    # Shared cert/date/status helpers
├── client/
│   ├── rk9_cl_core.lua       # Player state, command guards, exports
│   ├── rk9_cl_menus.lua      # ox_lib context menus
│   ├── rk9_cl_detection.lua  # Sniff + tracking client logic
│   └── rk9_cl_target.lua     # ox_target interactions
└── server/
    ├── rk9_sv_core.lua       # DB init, role checks, cert + tracking logic
    ├── rk9_sv_certs.lua      # ox_lib callbacks
    └── rk9_sv_admin.lua      # Evaluator/admin command and event flows
```

---

## Dependencies

| Resource | Source |
|---|---|
| `ox_lib` | https://github.com/overextended/ox_lib |
| `ox_target` | https://github.com/overextended/ox_target |
| `oxmysql` | https://github.com/overextended/oxmysql |
| `qb-core` | Standard QBCore installation |

---

## Installation

### 1) Place the resource
Drop `ravens_k9` in your FiveM `resources/` folder.

### 2) Ensure load order (`server.cfg`)
```cfg
ensure ox_lib
ensure ox_target
ensure oxmysql
ensure qb-core
ensure ravens_k9
```

### 3) Database
Tables auto-create on first start. Optionally run `rk9_install.sql` manually.

### 4) Add cert card item
In `qb-core/shared/items.lua`:

```lua
['rk9_cert_card'] = {
    name        = 'rk9_cert_card',
    label       = 'K9 Certification Card',
    weight      = 10,
    type        = 'item',
    image       = 'rk9_cert_card.png',
    unique      = false,
    useable     = true,
    shouldClose = true,
    combinable  = nil,
    description = 'Official K9 Handler Certification Card issued by a certified evaluator.',
},
```

### 5) Configure (`shared/rk9_config.lua`)

- `RK9Config.AllowedJobs` — job names allowed to use this system.
- `RK9Config.AdminGroups` — QBCore permission groups counted as admin.
- `RK9Config.RequirePatrolCertForK9Actions` — if `true`, sniff + tracking require active `patrol` cert.
- `RK9Config.DetectableItems` — item lists used by detection certs.
- `RK9Config.CertExpiryDays` — cert lifespan in days.
- `RK9Config.TrackingRadius` — proximity scan radius for nearby/fleeing modes.
- `RK9Config.ViewNearbyRadius` — max distance for nearby cert viewing.
- `RK9Config.TrackingTimeout` — per-mode tracking timeout.
- `RK9Config.TrackingBlipColour` — per-mode blip colors.

---

## Certification Types

| ID | Label | Purpose |
|---|---|---|
| `handler` | Handler Certification | Cert-check-only role (view nearby K9 certs) |
| `patrol` | Patrol Certification | Core K9 operational baseline |
| `firearms` | Firearms Detection | Weapon/ammo detection |
| `narcotics` | Narcotics Detection | Drug/paraphernalia detection |
| `explosives` | Explosives Detection | Explosives/precursor detection |
| `humantrack` | Human Tracking | Nearby + fleeing suspect tracking |
| `sar` | Search and Rescue | Unlocks server-wide missing person mode |

> SAR builds on Human Tracking. Missing Person mode requires both `humantrack` and `sar`.

---

## Role & Access Model

| Role | Requirements | Access |
|---|---|---|
| **Handler** | Allowed LEO job + active `handler` cert | View nearby K9 certs only |
| **K9 Player** | Allowed LEO job + active `patrol` cert (default policy) | Menu, sniff, track, view certs |
| **Evaluator** | Admin-assigned evaluator OR admin group | All Handler/K9 Player actions + grant/revoke certs |
| **Admin** | QBCore admin group | All evaluator actions + evaluator management |

Evaluators are stored by **CitizenID** in `ravens_k9_evaluators`.

---

## Human Tracking Modes

| Mode | Required Certs | Candidate Pool | Default Timeout |
|---|---|---|---|
| Nearby Suspect | `humantrack` | Players within `TrackingRadius` | 10 min |
| Fleeing Suspect | `humantrack` | Players within `TrackingRadius` | 20 min |
| Missing Person | `humantrack` + `sar` | All online players | 60 min |

### Server-side hardening

Tracking is server-authoritative and hardened by:

- Mode allowlist validation (`nearby`, `fleeing`, `missing`).
- Cert enforcement by mode (`humantrack`, plus `sar` for missing).
- Server-side proximity checks for nearby/fleeing.
- Pending request matching for coordinate responses.
- Lightweight per-request cooldown.
- Request/cooldown cache cleanup on disconnect.

---

## Commands

### K9 Player (active unit)
| Command | Description |
|---|---|
| `/k9menu` | Open main K9 menu |
| `/k9sniffped` | Sniff nearest player |
| `/k9sniffveh` | Sniff nearest vehicle |
| `/k9track` | Open tracking mode picker |
| `/k9stoptrack` | Stop active tracking |
| `/k9viewcerts` | View nearest player certs |

### Handler (view-only)
| Command | Description |
|---|---|
| `/k9menu` | Open menu (cert viewing only) |
| `/k9viewcerts` | View nearest player certs |

### Evaluator/Admin
| Command | Description |
|---|---|
| `/k9grantcert [serverID] [certType]` | Grant certification |
| `/k9revokecert [serverID] [certType]` | Revoke certification |
| `/k9addevaluator [serverID]` | Add evaluator (admin) |
| `/k9removeevaluator [serverID]` | Remove evaluator (admin) |

Valid `certType` values:
`handler` `patrol` `firearms` `narcotics` `explosives` `humantrack` `sar`

---

## ox_target Interactions

### Player peds
| Interaction | Access |
|---|---|
| 🐾 K9 Sniff Person | Active K9 unit |
| 📋 View K9 Certs | Active K9 unit or Handler |
| ✅ Grant K9 Cert | Evaluator/Admin |
| ❌ Revoke K9 Cert | Evaluator/Admin |
| 👣 K9 Track Person | Active K9 unit + `humantrack` |
| ➕ Add as K9 Evaluator | Admin |

### Vehicles
| Interaction | Access |
|---|---|
| 🐾 K9 Sniff Vehicle | Active K9 unit |

---

## Certification Notes

- Certs are stored by **CitizenID**, not by job.
- Expired certs are treated as **inactive** for gated features.
- Evaluators are warned when certs near expiry (`ExpiryWarnDays`).
- Expiry checks run at startup and every 6 hours.
- Granting certs issues `rk9_cert_card` to online recipients.

---

## Migration Notes (from older versions)

If you are upgrading from a version before the Handler role / Patrol gating changes:

1. **Review role policy**
   - Decide who should be **Handler** (view-only) and who should be **K9 Player** (operational).
2. **Grant baseline certs**
   - Grant `handler` to cert-check-only players.
   - Grant `patrol` to players who should run sniff/track operations (when patrol gating is enabled).
3. **Confirm config behavior**
   - `RequirePatrolCertForK9Actions = true` (default) enforces patrol cert for operational actions.
4. **Communicate command expectations**
   - Handler role can still use `/k9menu`, but operational actions are disabled.

---

## Configuration Presets

### Preset A: Strict RP (recommended)
- `RequirePatrolCertForK9Actions = true`
- Use `handler` for cert-check-only personnel.
- Keep `humantrack` and `sar` tightly evaluator-controlled.

### Preset B: Transitional rollout
- Start with `RequirePatrolCertForK9Actions = false` for 1–2 days.
- Grant missing `patrol` certs.
- Switch back to `true` once staff are migrated.

### Preset C: Minimal gate
- `RequirePatrolCertForK9Actions = false`
- Keep only job-based access with certs mainly for tracking/detection specialization.

---

## Security Model (high level)

- **Client proposes, server decides**: clients may request actions, but server validates role/cert/range/mode before effect.
- **Tracking is server-authoritative**: coordinate updates are accepted only for recent pending requests and valid mode/session pairing.
- **Role checks are enforced both client and server side**: client hides options for UX; server remains final authority.

---

## Troubleshooting

### I cannot sniff or track even though I am LEO
- Check your certs: you likely need `patrol` when `RequirePatrolCertForK9Actions = true`.
- Ensure your job is listed in `AllowedJobs`.

### I can open `/k9menu` but sniff/track is disabled
- You are probably in **Handler** role (view-only) or missing `patrol`.

### Missing Person mode is locked
- You need both `humantrack` and `sar` active certs.

### “No player found” or no cert data when viewing
- Ensure target player is in range (`ViewNearbyRadius`) and online.

### Track blip updates are not appearing
- Verify `ox_lib`, `ox_target`, `oxmysql`, and `qb-core` are started before this resource.

---

## Changelog

### 1.0.0+
- Added Handler (view-only) role and cert.
- Added optional Patrol-cert gating for operational K9 actions.
- Hardened server-side tracking request/response validation and anti-spam.
- Refined docs for role/access clarity.

---

*Raven's K9 System © Raven — All rights reserved.*
