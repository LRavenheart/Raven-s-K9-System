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

**Optional integration:** `ps-mdt` (if you want K9 alerts/calls pushed to MDT).

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
# Optional, only if you want MDT call integration:
# ensure ps-mdt
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

### 5. Configure
Edit `shared/rk9_config.lua`:
- `RK9Config.AllowedJobs` — add every LEO job name on your server
- `RK9Config.AdminGroups` — match your QBCore permission group names
- `RK9Config.RequirePatrolCertForK9Actions` — require active Patrol cert for core K9 actions (default: true)
- `RK9Config.DetectableItems` — add/remove QBCore item names per cert type
- `RK9Config.CertExpiryDays` — adjust cert lifespan (default: 365 days)
- `RK9Config.TrackingRadius` — proximity range for Nearby and Fleeing modes (default: 50m)
- `RK9Config.ViewNearbyRadius` — radius used by `/k9viewcerts` and context menus when querying nearby handlers (default: 10m)
- `RK9Config.TrackingTimeout` — per-mode session auto-expiry in ms
- `RK9Config.TrackingBlipColour` — GTA blip colour IDs per tracking mode

---

## Certification Types

| ID | Label | Purpose |
|---|---|---|
| `handler` | Handler Certification | View nearby K9 certifications only |
| `patrol` | Patrol Certification | Basic K9 handler/obedience |
| `firearms` | Firearms Detection | Weapons, ammo |
| `narcotics` | Narcotics Detection | Drugs, paraphernalia |
| `explosives` | Explosives Detection | Grenades, C4, detonators |
| `humantrack` | Human Tracking | Nearby and Fleeing Suspect tracking |
| `sar` | Search and Rescue | Unlocks Missing Person (server-wide) tracking |

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

All modes push a live blip to the handler's map every `RK9Config.TrackingUpdateMs` (default: 2 seconds). Tracking is server-authoritative: when a handler requests a location update the server relays the request to the target player's client, which returns its current position; the server then forwards that coordinate (along with the selected mode) back to the handler.

Tracking requests are additionally hardened server-side:
- Mode requests are validated (`nearby`, `fleeing`, `missing`) and cert requirements are enforced (`humantrack` + `sar` for Missing Person).
- Nearby/Fleeing requests are range-validated on the server before coordinate polling is allowed.
- Coordinate responses are accepted only if they match a recent server-issued pending request for that requester/responder pair and mode.
- A lightweight per-request cooldown is applied to reduce spam load.

---

## Commands

### K9 Player (active K9 unit)
| Command | Description |
|---|---|
| `/k9menu` | Open the main K9 menu |
| `/k9sniffped` | Sniff the nearest player |
| `/k9sniffveh` | Sniff the nearest vehicle |
| `/k9track` | Open the tracking mode menu |
| `/k9stoptrack` | Stop the active tracking session |
| `/k9viewcerts` | View the nearest player's K9 certs |

### Handler (cert-check role)
| Command | Description |
|---|---|
| `/k9menu` | Open K9 menu (cert viewing actions only) |
| `/k9viewcerts` | View the nearest player's K9 certs |

### Evaluator
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

**certType values:** `handler` `patrol` `firearms` `narcotics` `explosives` `humantrack` `sar`

---

## ox_target Interactions

### On player peds (LEO job required; K9 actions require active K9 unit)
| Label | Access |
|---|---|
| 🐾 K9 Sniff Person | Active K9 unit |
| 📋 View K9 Certs | Active K9 unit or Handler |
| ✅ Grant K9 Cert | Evaluator / Admin |
| ❌ Revoke K9 Cert | Evaluator / Admin |
| 👣 K9 Track Person | Active K9 unit + `humantrack` cert |
| ➕ Add as K9 Evaluator | Admin only |

---

### On vehicles (LEO job required; K9 actions require active K9 unit)
| Label | Access |
|---|---|
| 🐾 K9 Sniff Vehicle | Active K9 unit |

---

## Migration Notes (from older versions)

| Role | How Assigned | Capabilities |
|---|---|---|
| **Handler** | QBCore job + active Handler cert | View nearby K9 certs only |
| **K9 Player** | QBCore job + active Patrol cert (default) | Menu, sniff, track, view certs |
| **Evaluator** | Admin in-game or via DB | All handler actions + grant/revoke certs |
| **Admin** | QBCore permission group | All evaluator actions + add/remove evaluators |

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

- Certs are stored against a player's **CitizenID**, not their job. They persist through job changes.
- Expired certifications are treated as inactive for gated features (for example detection and human tracking checks).
- Online evaluators receive in-game warnings when any cert is within `RK9Config.ExpiryWarnDays` (default: 30) days of expiry. Regular handlers are not notified.
- The expiry check runs at resource start and every 6 hours.
- Each cert record stores: issue date, expiry date, evaluator CitizenID, and evaluator full name.
- A physical `rk9_cert_card` inventory item is issued to the handler on certification.

---

*Raven's K9 System © Raven — All rights reserved.*
