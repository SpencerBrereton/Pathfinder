# Pathfinder

Pathfinder is the community-facing mobile exploration game. Players explore real-world terrain — rendered from imported geographic data — as a customizable player character on a 2.5D map. They log discoveries (flora, fauna, landmarks, trail conditions) that contribute to a shared, living world: approved discoveries appear as AI-generated 3D assets placed on the map for all players to find and verify.

Think: Pokémon Go meets iNaturalist, with terrain-aware maps, species identification, a gamification layer that rewards real-world exploration, and a world that decays and needs tending.

## Platform

- **Framework**: React Native
- **OS Support**: iOS + Android
- **Users**: Public (community members, hikers, outdoor enthusiasts)

## Core Gameplay Loop

1. Player opens the app and sees their real-world location on a terrain-aware map, represented by their customizable player character
2. They explore — walking a trail, park, neighbourhood, or any outdoor area
3. They discover something (a wildflower, a viewpoint, an unusual rock formation, a bird)
4. They tap to log the discovery: take a photo, review the AI species identification suggestion (confirm or override), add notes
5. The discovery is saved locally with GPS coordinates and timestamp; a placeholder dot appears on the map immediately
6. When connected, the discovery syncs and enters the content moderation + asset generation pipeline
7. Once approved and the canonical 3D asset is ready (or reused from the asset library), the 3D asset is placed in the world and the player receives an in-app notification
8. Other players can find and verify the discovery; discoveries decay over time and need re-verification to stay active on the map

## Map Rendering: 2.5D

The map uses **MapLibre GL** for rendering, providing a 2.5D experience:

- **Terrain elevation**: RGB-encoded elevation tiles deform the map surface — hills rise, valleys sink
- **`fill-extrusion` layers**: Cliffs, rock faces, and buildings are extruded upward as 3D geometry
- **Water**: Rivers and lakes render at their actual elevation, sitting visually in valleys
- **Hillshading**: Shadow layer baked from elevation data gives depth to flat terrain sections

This creates a 3D feel without rendering full geometry on mobile hardware.

## Free vs Pro

The Pro pitch is: **"Free lets you play the game. Pro lets you leave a mark on the world."**

| Feature | Free | Pro |
|---|---|---|
| Terrain map + navigation | ✅ | ✅ |
| Discovery logging | ✅ | ✅ |
| Community map | ✅ | ✅ |
| Basic character | ✅ | ✅ |
| Offline map download | 1 region | Unlimited |
| AI species ID | Basic category guess | Full species-level ID + confidence score |
| 3D discovery assets | Standard quality | High-fidelity + animated variants + priority queue |
| Discovery spotlight on map | ❌ | ✅ (visual elevation, name tag visible to nearby players) |
| Permanent discovery anchoring | ❌ | ✅ (small number of discoveries resist decay) |
| Full character customization | ❌ | ✅ (unique skins, gear, accessories) |
| Explorer profile page | ❌ | ✅ (shareable public profile + discovery gallery) |
| Coverage map | ❌ | ✅ (personal heatmap of explored regions) |
| Species portfolio ("Pokédex") | ❌ | ✅ |
| Decay alerts | ❌ | ✅ |
| Regional leaderboard visibility | View only | ✅ Appears on boards |
| Hike track recording (GPX) | ❌ | ✅ |
| Field Journal stats + export | ❌ | ✅ |
| Enhanced map layers (LiDAR, satellite, contours) | ❌ | ✅ |
| Multi-device journal sync | ❌ | ✅ |

Stats (km hiked, elevation gained, discoveries by category, streaks) are computed and stored for all users. Pro users can see and export them; free users see a teaser with an upgrade prompt.

## Tile Freshness

When online, the app always serves live tiles directly from the CDN — players always see the current world state. Downloaded offline tiles are served from the local MBTiles cache when there is no connection. When the player reconnects, cached tiles are compared against the current version and marked **"out of date"** with a visible indicator if newer tiles have been published for that region.

For terrain elevation tiles used for navigation, the out-of-date indicator is prominent. For discovery overlays, a subtle badge is sufficient.

## Map Data Quality Indicator

The map displays a visual indicator distinguishing community-tier coverage from authoritative-tier coverage. A one-time onboarding disclaimer informs players that community terrain data has GPS accuracy of 5–10m and should not be used as a primary navigation source. This sets honest expectations and provides meaningful liability protection.

## Offline-First

Hikers frequently have no cell service. The app is designed to work fully offline:

- Players pre-download a region's map tiles before heading out
- Free users can have 1 region downloaded at a time; Pro users have no limit
- All discovery logging and hike tracking work offline (stored in local SQLite)
- GPS tracking works without a connection
- Data syncs automatically when connection is restored
- Conflict resolution: last-write-wins for personal data; append-only for discoveries (no conflicts)

## Discovery System

Each discovery includes:

| Field | Type | Notes |
|---|---|---|
| Category | Enum | Flora, Fauna, Landmark, Trail Condition, Fungi, Geological, Other |
| Identified species | Text | Player-confirmed common or scientific name |
| AI suggested species | Text | Raw model output (retained for accuracy tracking) |
| AI confidence | Float | Model confidence score 0–1 |
| Identification source | Enum | `ai_confirmed`, `ai_corrected`, `manual` |
| Photos | Array | Up to 5 images, stored locally + synced |
| GPS coordinates | Point | Recorded at time of logging |
| Elevation | Float | Derived from terrain data |
| Notes | Text | Free-form description |
| Timestamp | DateTime | Time of discovery |
| User | FK | The contributor |
| Visibility | Enum | Public (CC BY) or Private |
| Verification count | Int | Number of independent user confirmations |
| Decay rate | Enum | Derived from category; controls how quickly the discovery ages out |
| Canonical asset ID | FK | Reference to the canonical 3D asset for this species (null until generated) |

Public discoveries enter the content moderation + asset generation pipeline on sync. A placeholder dot appears on the map immediately on submission; the canonical 3D asset replaces it once moderation passes and generation completes.

### AI Species Identification

When a player submits a photo, the app runs AI-assisted species identification before the player finalises the submission:

- The model returns a suggested species name and confidence score
- The player can confirm the suggestion, correct it, or enter a manual text response
- The player always retains the right to override the AI — their confirmed identification is what gets stored

Free users receive a basic category-level guess. Pro users receive full species-level identification with confidence score.

The `ai_suggested_species` field is retained regardless of what the player confirms, enabling model accuracy tracking and improvement over time.

### Canonical 3D Assets

Each unique identified species maps to one canonical 3D asset in the platform's asset library:

- When a discovery is approved and no asset exists for the identified species, a generation job is queued to Meshy
- If a canonical asset already exists for that species, it is reused immediately
- Assets are placed in the world at the discovery's GPS coordinates once ready
- The player receives an in-app notification when their discovery goes live on the map

Asset generation is fully asynchronous — the player sees a placeholder dot immediately on submission and never waits for a render.

Pro users receive higher-fidelity renders and animated asset variants. Free users receive standard quality.

### Discovery Verification

Verification is category-aware — friction is proportional to how much data quality matters for each type:

| Category | Verification Type | Decay Reset |
|---|---|---|
| Trail Condition | Structured question ("Still present?", severity) | Full reset |
| Flora / Fauna | Optional photo re-submission or proximity confirm | Photo = full reset; confirm = partial |
| Landmark / Geological | Proximity confirm | Full reset |
| Fungi / Specialist | Photo re-submission required | Full reset |

Confirming earns XP and increments the discovery's `verification_count`. Verified discoveries carry more weight in community data and count toward the Pathfinder Lab access threshold. Photo re-submissions re-enter the AI identification pipeline, which can flag ID corrections.

### Discovery Decay

All discoveries decay over time. Decay rate varies by category:

| Category | Decay Rate | Rationale |
|---|---|---|
| Trail Condition | Fast (weeks) | Conditions change constantly |
| Flora (seasonal) | Medium (months, seasonal) | Relevance tied to bloom/season |
| Fauna | Medium | Animals move, populations shift |
| Landmark / Geological | Slow | Physical features are stable |
| Terrain capture | Very slow / permanent | LiDAR data remains valid long-term |

Decayed discoveries are removed from the active world map. Players are incentivised to re-verify discoveries before they decay — preserving their contributions and earning XP. Pro users receive decay alerts before their discoveries expire.

Discoveries cannot be "anchored" to permanently resist decay by Free users. Pro users can anchor a small number of their best discoveries.

## Hike Track Recording (Pro)

Pro users can record a continuous GPS track for the duration of their hike:

- Tracks are stored locally as GPX and synced to the backend on reconnect
- Visible in the Field Journal alongside discoveries logged during that hike
- Exportable as GPX for use in other apps

## Gamification

The app is fully gamified. Every meaningful action earns XP and contributes to player progression:

| Action | Reward |
|---|---|
| Log a discovery | XP |
| Discovery verified by another user | Bonus XP |
| Verify another user's discovery | XP |
| Complete a hike track | XP |
| Reach a new region | XP + badge |
| Streak (consecutive days active) | Multiplier |
| Re-verify a decaying discovery | XP |
| Contribute to regional coverage milestone | XP + region badge |

**Levels**: Players progress through levels as XP accumulates. Level is visible on profile.

**Badges**: Awarded for milestones — first discovery, 10 verifications, exploring N different regions, discovering N species, region coverage milestones, etc. Displayed on profile.

**Lab access progress**: A visible progress bar shows how many verified discoveries the player has toward the 100-discovery threshold for Pathfinder Lab access. This acts as a long-term retention mechanic for engaged users.

### Regional Completion

Each region has a live **completion percentage** — a weighted aggregate of active (non-decayed) discoveries and terrain coverage within the region boundary. As discoveries decay and terrain data ages, the percentage ticks down. Players are pulled back to explored regions to keep them alive.

Completion percentage has mechanical consequences:

| Threshold | Consequence |
|---|---|
| 50%+ | Specialist discovery categories unlock (fungi, geological formations, weather events) |
| 75%+ | Rare "Boss" discovery slots open — user-submitted discoveries that require physical presence to find |
| 90% | Region-exclusive cosmetic badge drops for all active contributors |
| High community coverage | Region flagged in Studio as a candidate for professional survey prioritisation |
| Below 30% | Decay rates accelerate; map shows region as "neglected" |

The map visually distinguishes community-tier coverage from authoritative-tier coverage, giving players a visible signal of where professional survey data exists vs. community-mapped areas.

## Social

At launch, social features are intentionally minimal:

- **Friend lists** — players can add friends and see their discoveries highlighted on the map
- **Discovery highlighting** — friends' active discoveries are visually distinguished from strangers' discoveries

Deeper social features (group challenges, comments, co-op exploration goals, regional leaderboard competitions) are deferred to later phases once an active player base justifies the moderation overhead.

## Notifications

Users can configure notification preferences per event type, choosing between push notifications or in-app only:

| Event | Default |
|---|---|
| Discovery verification request (nearby) | Push |
| Your discovery was verified | In-app |
| Your discovery is live on the map (asset placed) | In-app |
| Discovery approaching decay (Pro) | In-app |
| Lab access unlocked | Push |
| New discoveries in a region you've explored | In-app |
| Region coverage milestone reached | In-app |

## Field Journal

Each user has a personal Field Journal — their full history of discoveries and hike tracks, organized by date, region, and category. The journal works as a personal nature log / hike tracker independent of the community layer.

Pro users additionally see:
- Stats dashboard: total km hiked, total elevation gained, discovery count by category, active streak, top regions
- Export: journal entries and hike tracks as GPX or PDF

## Tech Stack

| Layer | Technology |
|---|---|
| App framework | React Native (Expo) |
| Map rendering | MapLibre GL (React Native SDK) |
| Offline storage | SQLite (via WatermelonDB or expo-sqlite) |
| Camera / photos | Expo Camera |
| GPS | Expo Location |
| Push notifications | Expo Notifications (APNs + FCM) |
| Auth | Supabase Auth (JS client) |
| Data sync | Supabase Realtime + REST |
| Tile storage | Local MBTiles cache |

## Related

- [[Pathfinder Overview]]
- [[Architecture]]
- [[Data Pipeline]]
- [[User And Auth Model]]
