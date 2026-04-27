# Monorepo And Tooling

The Pathfinder codebase is a monorepo managed with **pnpm workspaces** and orchestrated by **Turborepo**. The Python GIS microservice lives in `services/gis/` alongside the TypeScript packages.

---

## Package Manager: pnpm

**pnpm** over npm/yarn for three reasons:
- Symlinked `node_modules` — installs are fast and disk-efficient across packages
- Strict dependency isolation — packages can't accidentally use undeclared dependencies
- Native workspace support with `pnpm -F <package>` for per-package commands

---

## Build Orchestrator: Turborepo

**Turborepo** runs build/lint/test tasks across packages in the correct dependency order, with caching so unchanged packages are skipped.

```json
// turbo.json (root)
{
  "pipeline": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**"]
    },
    "lint": {},
    "test": {
      "dependsOn": ["^build"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    }
  }
}
```

---

## Repository Structure

```
pathfinder/
├── packages/
│   ├── shared/           # Shared TypeScript types, Zod schemas, utilities
│   ├── backend/          # Supabase config, migrations, seed data, edge functions
│   ├── studio/           # Electron + React desktop app (Pathfinder Studio)
│   ├── mobile/           # React Native app (Pathfinder game)
│   └── lab/              # React Native app (Pathfinder Lab)
├── services/
│   └── gis/              # Python GIS microservice
├── docker-compose.yml    # Local dev: Supabase stack + GIS service
├── turbo.json
├── pnpm-workspace.yaml
└── package.json
```

---

## Package Details

### `packages/shared`

Consumed by all other TypeScript packages. Contains:
- **TypeScript types** mirroring the database schema (generated via `supabase gen types`)
- **Zod validation schemas** for API request/response payloads
- **Constants** (tile zoom levels, discovery categories, role hierarchy)
- **Utility functions** with no platform-specific dependencies

```json
// packages/shared/package.json
{
  "name": "@pathfinder/shared",
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts"
}
```

All other packages declare `"@pathfinder/shared": "workspace:*"` as a dependency.

### `packages/backend`

Not a runnable application — it holds everything needed to manage the Supabase instance:
- `supabase/migrations/` — SQL migration files (versioned, applied via `supabase db push`)
- `supabase/seed.sql` — development seed data
- `supabase/functions/` — Supabase Edge Functions (Deno, for server-side logic)
- `config.toml` — Supabase project config

```bash
# Apply migrations to local Supabase
pnpm -F backend supabase db push

# Generate TypeScript types from schema → packages/shared/src/database.types.ts
pnpm -F backend supabase gen types typescript --local > ../shared/src/database.types.ts
```

### `packages/studio`

Electron application. Two processes:

| Process | Role |
|---|---|
| **Main** (Node.js) | File system access, GIS microservice HTTP calls, Supabase uploads |
| **Renderer** (Chromium) | React UI, CesiumJS 3D viewer |

```json
// packages/studio/package.json
{
  "name": "@pathfinder/studio",
  "main": "./dist/main/index.js"
}
```

### `packages/mobile`

React Native app (Pathfinder game). Managed with **Expo** for streamlined iOS/Android builds and OTA updates.

```json
{
  "name": "@pathfinder/mobile"
}
```

### `packages/lab`

React Native app (Pathfinder Lab). Also Expo-managed, but with a **native Swift module** for ARKit/LiDAR. Requires Expo's bare workflow (not managed) to support custom native code.

```json
{
  "name": "@pathfinder/lab"
}
```

---

## Python GIS Microservice (`services/gis/`)

The Python service is not a pnpm package — it has its own toolchain.

```
services/gis/
├── app/
│   ├── main.py          # FastAPI entrypoint
│   ├── routes/
│   │   ├── jobs.py      # POST /jobs, GET /jobs/{id}
│   │   └── health.py    # GET /health
│   ├── processors/
│   │   ├── geotiff.py   # GeoTIFF → elevation tiles
│   │   └── lidar.py     # LiDAR → vector tiles + point cloud
│   └── storage.py       # Supabase Storage client
├── requirements.txt
├── Dockerfile
└── .env.example
```

**Framework**: FastAPI (async, fast, automatic OpenAPI docs)
**Key dependencies**: `gdal`, `rasterio`, `pdal`, `rio-cogeo`, `rio-tiler`, `tippecanoe`, `httpx`

---

## Docker Compose (Local Dev)

All local services are wired together in a single `docker-compose.yml` at the repo root.

```yaml
# docker-compose.yml
services:
  supabase-db:
    image: supabase/postgres:15
    # ... (managed by Supabase CLI, referenced here for clarity)

  supabase-studio:
    image: supabase/studio
    ports:
      - "54323:3000"   # Supabase Studio UI

  gis:
    build: ./services/gis
    ports:
      - "8000:8000"    # GIS microservice API
    environment:
      - SUPABASE_URL=http://localhost:54321
      - SUPABASE_SERVICE_KEY=${SUPABASE_SERVICE_KEY}
    volumes:
      - ./services/gis:/app  # hot reload in dev
```

In practice, Supabase's own Docker stack is started via `supabase start` (Supabase CLI), and only the `gis` service is added to `docker-compose.yml`. The two communicate over localhost.

---

## TypeScript Configuration

A root `tsconfig.base.json` defines shared compiler options. Each package extends it.

```json
// tsconfig.base.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true,
    "paths": {
      "@pathfinder/shared": ["./packages/shared/src/index.ts"]
    }
  }
}
```

---

## Local Development Setup

### Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Node.js | 20 LTS | Use `nvm` or `fnm` |
| pnpm | 9.x | `npm install -g pnpm` |
| Docker Desktop | Latest | Required for Supabase + GIS |
| Supabase CLI | Latest | `brew install supabase/tap/supabase` (Mac) or `scoop install supabase` (Windows) |
| Python | 3.11+ | For GIS service local dev (optional — Docker handles it otherwise) |

### First-Time Setup

```bash
# 1. Install Node dependencies
pnpm install

# 2. Start local Supabase (PostgreSQL + Auth + Storage + API)
supabase start

# 3. Apply database migrations
pnpm -F backend supabase db push

# 4. Seed development data
pnpm -F backend supabase db seed

# 5. Generate TypeScript types from schema
pnpm -F backend gen:types

# 6. Start GIS microservice
docker-compose up gis

# 7. Start Pathfinder Studio (Electron)
pnpm -F studio dev

# OR start the mobile app
pnpm -F mobile start
```

### Environment Variables

Each package has a `.env.example` file. Copy to `.env.local` and fill in values from `supabase status`.

```bash
# .env.local (studio, mobile, lab)
SUPABASE_URL=http://localhost:54321
SUPABASE_ANON_KEY=<from supabase status>

# .env.local (services/gis)
SUPABASE_URL=http://localhost:54321
SUPABASE_SERVICE_KEY=<from supabase status>
GIS_PORT=8000
```

---

## Scripts Reference

| Command | What it does |
|---|---|
| `pnpm install` | Install all dependencies |
| `pnpm build` | Build all packages (Turborepo, in order) |
| `pnpm dev` | Start all dev servers in parallel |
| `pnpm lint` | Lint all packages |
| `pnpm test` | Run all tests |
| `pnpm -F studio dev` | Start Studio (Electron) only |
| `pnpm -F mobile start` | Start mobile app (Expo) only |
| `pnpm -F backend gen:types` | Regenerate DB types into `shared` |
| `supabase start` | Start local Supabase stack |
| `supabase db push` | Apply pending migrations |
| `docker-compose up gis` | Start GIS microservice |

---

## Related

- [[Pathfinder Overview]]
- [[Architecture]]
- [[Database Schema]]
- [[GIS Microservice API]]
