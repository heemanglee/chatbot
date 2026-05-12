# chatbot

**Orchestration repository** for RAG chatbot service.

The backend (FastAPI) and frontend (Next.js) live in separate private repositories. This repo bundles them as git submodules so the whole stack can be cloned and run from a single entry point.

## Layout

```
chatbot/
├── backend/        # submodule → heemanglee/langchain-chatbot    (private)
├── frontend/       # submodule → heemanglee/langchain-chatbot-fe (private)
└── README.md
```

| Area | Stack | Path |
|---|---|---|
| Backend | FastAPI · LangChain · PostgreSQL + pgvector · Celery | `backend/` |
| Frontend | Next.js 16 (App Router) · React 19 · Tailwind v4 · shadcn/ui | `frontend/` |

Each submodule has its own `README.md` — see those for in-depth details.

> **Submodule access**
>
> `backend/` and `frontend/` point to private repositories. Users without access can see `.gitmodules` but cannot fetch the actual code.

## Getting started

### 1. Clone

Clone with submodules in one shot:

```bash
git clone --recurse-submodules https://github.com/heemanglee/chatbot.git
cd chatbot
```

If you already cloned without submodules:

```bash
git submodule update --init --recursive
```

### 2. Run the backend

```bash
cd backend
cp .env.example .env       # set OPENAI_API_KEY, JWT_SECRET_KEY, S3 settings

# Infrastructure (PostgreSQL + pgvector, Redis)
docker compose up -d pgvector redis

# Dependencies + migrations + server
uv sync --frozen
uv run alembic upgrade head
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

OpenAPI docs: http://localhost:8000/docs

To bring up the full docker stack instead, the server is exposed at `localhost:8001` (`docker compose up -d --build`).

### 3. Run the frontend

```bash
cd frontend
cp .env.example .env.local
# NEXT_PUBLIC_API_BASE_URL=http://localhost:8001 (docker) or 8000 (host)

npm install
npm run dev
```

Open http://localhost:3000.

## Architecture overview

```
┌────────────────┐         ┌────────────────┐         ┌─────────────────┐
│  Next.js (FE)  │ ──HTTP─▶│  FastAPI (BE)  │ ──SQL──▶│ PostgreSQL +    │
│  :3000         │ ◀─SSE── │  :8000 / 8001  │         │ pgvector        │
└────────────────┘         └───────┬────────┘         └─────────────────┘
                                   │
                                   ├── Celery Worker (default, titles queue)
                                   ├── Celery Beat   (singleton scheduler)
                                   ├── Redis         (broker / cache)
                                   └── S3            (image / document attachments)
```

- Chat responses are streamed over **SSE** (`meta` → `delta` → `done`/`error`).
- **RAG pipeline**: PDF / text / Markdown upload → text extraction → token-aware chunking → pgvector embedding → Cohere reranking at chat time.
- **Auth**: access token in memory (Zustand), refresh token in an HttpOnly cookie.
- The frontend's `src/domains/{auth,chat,user}/` mirrors the backend's `app/domain/{auth,chat,user}/` 1:1.

## Working with submodules

### Sync to `origin/main` (recommended)

Use the helper script to fast-forward the parent and both submodules in one shot:

```bash
./scripts/sync.sh
```

It runs `git pull --ff-only` against `origin` for the parent and against `origin/main` for each submodule, but **automatically skips any submodule that is not on `main` or is in detached-HEAD state** — so in-progress feature work is never disturbed.

If you instead want to force-update both submodules to `origin/main` regardless of state, use:

```bash
git submodule update --remote --merge
```

This leaves the submodule in detached-HEAD mode, so run `git switch <branch>` inside the submodule before editing or committing.

### Pointer-bump pattern

```bash
# After making changes inside a submodule
cd backend
git switch -c feat/some-change
# ... edit / commit / push ...

# Back in the parent repo, bump the pointer
cd ..
git add backend
git commit -m "chore(backend): bump submodule to pull <summary>"
```

The parent repo pins each submodule to a **specific commit hash**, so after pushing changes inside a submodule you must also commit the pointer bump in the parent for other environments to reproduce the same version. See [`CLAUDE.md`](CLAUDE.md) for the bundled (Form A) vs. separate (Form B) commit message conventions.

## GitHub Actions

| Workflow | Trigger | Role |
|---|---|---|
| [`auto-submodule-bump.yml`](.github/workflows/auto-submodule-bump.yml) | `*/10 * * * *` cron + manual `workflow_dispatch` | Polls `backend` / `frontend` `origin/main`, opens a bundled pointer-bump PR (both submodules changed) or a single-submodule PR (one changed) following this repo's commit convention, then enables squash auto-merge. |

### Required `SUBMODULE_PAT` secret

The workflow uses a Personal Access Token registered as the `SUBMODULE_PAT` repository secret (Settings → Secrets and variables → Actions). The default `GITHUB_TOKEN` cannot clone the private submodule repositories and cannot trigger downstream workflows on the auto-generated PR, so a PAT is required.

**Fine-grained PAT (recommended)** — limit access to the three repositories below and grant only:

| Repository | Permission |
|---|---|
| `heemanglee/langchain-chatbot` | Contents: Read-only |
| `heemanglee/langchain-chatbot-fe` | Contents: Read-only |
| `heemanglee/chatbot` | Contents: Read & write, Pull requests: Read & write |

`Metadata: Read-only` is auto-enabled by GitHub when any other permission is granted — leave it on.
