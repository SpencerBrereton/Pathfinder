# Pathfinder Overview

Pathfinder is an integrated geospatial platform for outdoor exploration, citizen science, and high-fidelity terrain mapping. It ingests real-world geographic data (GeoTIFF, LiDAR) and makes it accessible across three companion applications: a desktop admin tool, a mobile exploration game, and a professional field mapping app.

## Vision

Build the most accurate, community-powered map of the natural world — then put it in everyone's pocket.

## Business Model

### Individual (Consumer) — Primary Revenue Driver

The consumer mobile app is the primary revenue driver. Monetization is through the **Pathfinder Pro** subscription.

- **Free tier**: Full access to the Pathfinder game, discovery logging, community map, offline map downloads (1 region at a time), and basic character customization.
- **Pathfinder Pro** (subscription): The Pro pitch is "free lets you play the game — Pro lets you leave a mark on the world." Unlocks:
  - Enhanced 3D discovery assets (higher-fidelity Meshy renders, animated variants, priority generation queue)
  - Discovery spotlight on the shared map (visual elevation of your contributions)
  - Permanent discovery anchoring (anchor a small number of discoveries to resist decay)
  - Full character customization (unique skins, gear, accessories)
  - Explorer profile page (shareable public profile with discovery gallery and stats)
  - Coverage map (personal heatmap of explored regions)
  - Species/category portfolio (living collection of every type discovered — "Pokédex" style)
  - AI species identification (full species-level ID with confidence score; free users get basic category guess)
  - Decay alerts (notifications when your discoveries approach decay)
  - Hike track recording (GPX), Field Journal stats dashboard and export
  - Enhanced map layers (LiDAR overlay, high-res satellite, contour customization)
  - Multi-device journal sync, unlimited offline region downloads
  - Regional leaderboard visibility (Pro users appear on ranked boards; free users can see them but not appear)

### B2B Commercial — Long-Term Data Flywheel

B2B is a longer-term play built on top of the community data accumulated by the consumer app. The strategy is to accumulate high-quality, community-validated terrain and discovery data from day one, then leverage it as a commercial offering to trail associations and regional park authorities.

- **SaaS platform subscription**: Org accounts get direct-publish access in Pathfinder Lab, aggregated community discovery analytics for their regions (unlocked once regional coverage exceeds a meaningful threshold), and multi-seat org management. Pricing TBD — area-based tiers are a starting point but should be validated against what buyers actually care about.
- **Professional survey service**: Post-Phase 5 consideration. The platform supports upload and processing of professional survey data; Pathfinder acting as the surveyor is an operational capability to develop once B2B demand justifies it.

The commercial value is in the validated, processed output and the hosted service — not the raw community data. Community-contributed data is licensed CC BY and is openly available; clients pay for professional-grade accuracy, QA validation, and the tooling to access and act on it.

**B2B ICP validation is an explicit assumption.** No formal validation with trail associations or park authorities has been conducted yet. This is the highest-priority assumption to test before significant B2B feature investment.

## Data Quality Tiers

Pathfinder maintains two distinct quality tiers in its terrain data:

| Tier | Source | Accuracy | Path to publication |
|---|---|---|---|
| **Community** | iPhone Pro LiDAR via Pathfinder Lab | 5–10m (GPS-limited) | QA review by platform admin |
| **Authoritative** | Professional captures (Mosaic Xplor, drone photogrammetry, government LiDAR) | Sub-10cm | Direct publish (org accounts + admins) or survey service |

Community-tier data is valuable for coverage, feature identification, change detection, and identifying areas that warrant professional survey. Authoritative-tier data is the sellable B2B product.

## Data License

All community-contributed data is licensed under **Creative Commons Attribution (CC BY)**. Contributors know their data is open and shared. Commercial clients pay for the processed, validated output and hosted service — not the raw data itself.

## Components

| App | Platform | Users |
|---|---|---|
| [[Pathfinder Studio]] | Windows / Mac (Electron) | Platform admins |
| [[Pathfinder]] | iOS + Android (React Native) | Community (public) |
| [[Pathfinder Lab]] | iOS-first (React Native + Swift) | Authorized mappers, org accounts |

## Documentation

- [[Architecture]]
- [[Database Schema]]
- [[Monorepo And Tooling]]
- [[GIS Microservice API]]
- [[Pathfinder Studio]]
- [[Pathfinder]]
- [[Pathfinder Lab]]
- [[Data Pipeline]]
- [[User And Auth Model]]
- [[Build Roadmap]]
