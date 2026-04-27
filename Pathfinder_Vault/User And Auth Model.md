# User And Auth Model

Pathfinder uses a unified account system across all three applications. Authentication is handled by **Supabase Auth**. A single user account can hold a platform-level role and independently belong to one or more organizations.

## Authentication Methods

| Method | Notes |
|---|---|
| Email + Password | Standard, always available |
| Google OAuth | Social login for convenience |
| Apple Sign-In | Required by Apple App Store rules when any social login is offered on iOS |

All three methods are supported by Supabase Auth out of the box.

## Role Model

Roles are split into two independent concerns:

### Platform Role (`profiles.role`)

Controls access to platform features, independent of org membership.

```sql
CREATE TYPE user_role AS ENUM (
  'community',
  'authorized_mapper',
  'platform_admin'
);
```

| Role | Who | How granted |
|---|---|---|
| `community` | Anyone who signs up | Default |
| `authorized_mapper` | Vetted community contributors | 100 verified discoveries + platform admin approval |
| `platform_admin` | Pathfinder team | Manually set |

### Org Membership (`organization_members.role`)

Controls access within an organization, independent of platform role. A `community` user can be an `org_admin`; an `authorized_mapper` can also be an `org_member`. These are separate concerns.

```sql
CREATE TYPE org_role AS ENUM (
  'org_member',
  'org_admin'
);
```

RLS policies check both `profiles.role` and `organization_members` where needed. A user gains Lab access either through `authorized_mapper` platform role or through org membership — whichever applies.

## User Tiers in Practice

### Community User (default)

Anyone who signs up. Has access to:
- Pathfinder mobile game (full access)
- Personal field journal
- Public discovery map
- Offline map download (1 region at a time)

Cannot access Pathfinder Lab or Pathfinder Studio.

### Pathfinder Pro

A paid subscription available to any user. Unlocks:
- Unlimited offline region downloads
- Hike track recording (GPX)
- Field Journal stats dashboard and export
- Enhanced map layers (LiDAR overlay, high-res satellite, contour customization)
- Multi-device journal sync

Pro status is stored as `profiles.is_pro` (boolean, updated via Stripe webhook). It is independent of platform role and org membership.

### Authorized Mapper

A community user who has been granted access to **Pathfinder Lab**. Requirements:
1. **100 verified discoveries** — the player's logged discoveries must have been confirmed by other users in the field. Progress is visible in-app with a progress bar and milestone badges.
2. **Platform admin approval** — a platform admin reviews the account and grants `authorized_mapper` role.

Authorized mapper submissions go through a **QA review queue** before publishing to the authoritative terrain layer.

#### Mapper Trust Tiers

To prevent the QA queue from becoming a bottleneck at scale, authorized mappers graduate through trust levels based on submission track record:

| `mapper_trust_level` | Who | Review Mode |
|---|---|---|
| `0` (new) | Newly granted authorized mappers | Full manual review on every submission |
| `1` (established) | 5–10 clean submissions | Admin spot-check; most submissions fast-tracked |
| `2` (trusted) | 20+ clean submissions | Auto-approved; periodic audits |

Trust level is stored on `profiles.mapper_trust_level`. Graduation thresholds can be tuned once real submission quality data is available.

### Org Account

An organizational account (trail association, regional park authority, paid commercial client). Org accounts:
- Have direct publish access in Pathfinder Lab (no QA queue)
- Can access aggregated community discovery analytics for their regions
- May have multiple member seats under one organization with `org_member` or `org_admin` roles
- Are assigned a `plan_tier` (small / medium / large) based on their subscription

Org accounts are created and managed by platform admins.

### Platform Admin

Full access to all applications including Pathfinder Studio. Responsible for:
- Reviewing and approving authorized mapper access requests
- Managing org accounts and billing tiers
- Reviewing and approving authorized mapper field capture submissions
- Publishing terrain data
- Content moderation queue

## Pathfinder Lab Access Matrix

A user gains Lab access if **any** of the following are true:

| Condition | Lab Access | Publish Mode |
|---|---|---|
| `profiles.role = 'authorized_mapper'` | ✅ | After QA review |
| Member of any organization | ✅ | Direct publish |
| `profiles.role = 'platform_admin'` | ✅ | Direct publish |

## Access Control Summary

| Feature | Community | Pro | Auth. Mapper | Org Member | Platform Admin |
|---|---|---|---|---|---|
| Pathfinder (game) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Log discoveries | ✅ | ✅ | ✅ | ✅ | ✅ |
| Offline maps (1 region) | ✅ | — | ✅ | ✅ | ✅ |
| Offline maps (unlimited) | ❌ | ✅ | ✅ | ✅ | ✅ |
| Hike track recording | ❌ | ✅ | ✅ | ✅ | ✅ |
| Journal stats + export | ❌ | ✅ | ✅ | ✅ | ✅ |
| Enhanced map layers | ❌ | ✅ | ✅ | ✅ | ✅ |
| Pathfinder Lab | ❌ | ❌ | ✅ | ✅ | ✅ |
| Lab — direct publish | ❌ | ❌ | ❌ | ✅ | ✅ |
| Lab — QA submission | ❌ | ❌ | ✅ | — | — |
| Discovery analytics (org) | ❌ | ❌ | ❌ | ✅ (paid) | ✅ |
| Pathfinder Studio | ❌ | ❌ | ❌ | ❌ | ✅ |
| QA review queue | ❌ | ❌ | ❌ | ❌ | ✅ |
| Content moderation queue | ❌ | ❌ | ❌ | ❌ | ✅ |

## Session Management

Supabase Auth handles JWT-based sessions. Tokens are stored securely in device keychain (iOS) / keystore (Android). The Supabase JS client manages token refresh automatically.

Offline-capable apps (Pathfinder, Pathfinder Lab) cache auth state locally — users remain logged in across sessions and the app functions fully offline once authenticated.

## Related

- [[Pathfinder Overview]]
- [[Architecture]]
- [[Pathfinder]]
- [[Pathfinder Lab]]
- [[Pathfinder Studio]]
- [[Database Schema]]
