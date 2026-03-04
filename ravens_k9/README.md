# 🐾 Raven's K9 System
**Author:** Raven | **Version:** 1.0.0 | **Framework:** QBCore

> Advanced player-controlled K9 resource with certification management, item detection, human tracking (including Search and Rescue), ox_target integration, and a full evaluator/admin role system.

---

## File Structure

```
ravens_k9/
├── fxmanifest.lua
├── rk9_install.sql
├── shared/
│   ├── rk9_config.lua        ← All server configuration
│   └── rk9_cert_utils.lua    ← Shared cert helpers (client + server)
├── client/
│   ├── rk9_cl_core.lua       ← Player state, base commands, exports
│   ├── rk9_cl_menus.lua      ← All ox_lib context menus
│   ├── rk9_cl_detection.lua  ← Sniff animations, tracking modes and thread
│   └── rk9_cl_target.lua     ← ox_target global hooks
└── server/
    ├── rk9_sv_core.lua       ← DB init, authority helpers, cert logic, sniff, tracking
    ├── rk9_sv_certs.lua      ← ox_lib callbacks (cert data + role checks)
    └── rk9_sv_admin.lua      ← Evaluator management events + chat commands
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

### 1. Place the resource
Drop the `ravens_k9` folder into your `resources/` directory.

### 2. server.cfg load order
```
ensure ox_lib
ensure ox_target
ensure oxmysql
ensure qb-core
ensure ravens_k9
```

### 3. Database
Tables are created automatically on first resource start.
To create them manually, run `rk9_install.sql` on your database.

### 4. Add the cert card item to QBCore
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

> **Note:** `sar` builds on `humantrack`. A handler must hold both certifications to access Missing Person mode. `humantrack` alone grants Nearby and Fleeing Suspect modes only.

---

## Human Tracking Modes

| Mode | Cert Required | Player Pool | Blip | Timeout |
|---|---|---|---|---|
| ⬜ Nearby Suspect | `humantrack` | Within 50m | Grey | 10 min |
| 🟡 Fleeing Suspect | `humantrack` | Within 50m | Yellow | 20 min |
| 🔵 Missing Person | `humantrack` + `sar` | All online players | Blue | 60 min |

- **Nearby Suspect** — standard patrol tracking for players in close range.
- **Fleeing Suspect** — active pursuit mode. Same proximity scope as Nearby but with a longer timeout to accommodate a chase in progress.
- **Missing Person** — Search and Rescue operations only. Server-wide player pool regardless of distance. Locked to handlers who hold the `sar` cert. If the cert is not held, the option is shown as locked with a description rather than hidden entirely.

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
| `/k9grantcert [serverID] [certType]` | Grant a certification |
| `/k9revokecert [serverID] [certType]` | Revoke a certification |

### Admin
| Command | Description |
|---|---|
| `/k9addevaluator [serverID]` | Add a player as evaluator |
| `/k9removeevaluator [serverID]` | Remove evaluator status |

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

> When selecting **K9 Track Person** via ox_target, a mode picker appears. Missing Person is shown as locked with an explanation if the handler does not hold the `sar` cert.

### On vehicles (LEO job required; K9 actions require active K9 unit)
| Label | Access |
|---|---|
| 🐾 K9 Sniff Vehicle | Active K9 unit |

---

## Role System

| Role | How Assigned | Capabilities |
|---|---|---|
| **Handler** | QBCore job + active Handler cert | View nearby K9 certs only |
| **K9 Player** | QBCore job + active Patrol cert (default) | Menu, sniff, track, view certs |
| **Evaluator** | Admin in-game or via DB | All handler actions + grant/revoke certs |
| **Admin** | QBCore permission group | All evaluator actions + add/remove evaluators |

Evaluators are stored in `ravens_k9_evaluators` by **CitizenID** — they retain the role even if offline or change jobs.

---

## Certification Notes

- Certs are stored against a player's **CitizenID**, not their job. They persist through job changes.
- Expired certifications are treated as inactive for gated features (for example detection and human tracking checks).
- Online evaluators receive in-game warnings when any cert is within `RK9Config.ExpiryWarnDays` (default: 30) days of expiry. Regular handlers are not notified.
- The expiry check runs at resource start and every 6 hours.
- Each cert record stores: issue date, expiry date, evaluator CitizenID, and evaluator full name.
- A physical `rk9_cert_card` inventory item is issued to the handler on certification.

---

*Raven's K9 System © Raven — All rights reserved.*
