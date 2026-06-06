# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository role

This is the **orchestration repo** for a LangChain-powered RAG chatbot. It contains no application code itself — `backend/` and `frontend/` are git submodules pinned to specific commits of two private repositories:

- `backend/` → `heemanglee/langchain-chatbot` (FastAPI · LangChain · PostgreSQL+pgvector · Celery)
- `frontend/` → `heemanglee/langchain-chatbot-fe` (Next.js 16 App Router · React 19 · Tailwind v4 · shadcn/ui)

When you make changes, you almost always work **inside a submodule**, not at the parent. The parent repo's job is to record which commit of each submodule is the canonical version of the stack.

## Submodule workflow (the part that's unique to this repo)

### Initial setup

```bash
git clone --recurse-submodules https://github.com/heemanglee/chatbot.git
# or, if already cloned:
git submodule update --init --recursive
```

### Pointer-bump pattern (critical)

The parent repo pins each submodule to a **specific commit hash**. After pushing changes inside a submodule, you MUST also commit the pointer bump in the parent — otherwise other environments will keep checking out the old commit.

```bash
# 1. Work inside the submodule
cd backend
git switch -c feat/some-change
# ... edit / commit / push to origin ...

# 2. Bump the pointer in the parent repo
cd ..
git add backend                      # stages the new submodule SHA, not file contents
git commit                           # see "Commit message convention" below
```

`git add backend` at the parent level stages the submodule's new commit SHA — it does NOT stage the files inside the submodule. If `git status` at the parent shows `modified: backend (new commits)`, that is the pointer drift you need to commit.

### Commit message convention

Pointer-bump commits follow Conventional Commits with the `chore` type. Pick one of two forms based on whether the submodule changes are part of the same logical change.

**Form A — bundled commit** (same feature/PR spans both submodules; typically the same branch name on both sides, e.g. `feat/chat-attachment-composer-ui`):

```
chore(submodule): bump backend, frontend for attachment composer

- backend  c7e9202..75a2488 (#48)
- frontend 5da1ac9..e79453c (#10)
```

**Form B — separate commits** (unrelated changes that happen to land together):

```
chore(backend): bump submodule to pull auth logout fix

c7e9202..75a2488 (#48)
```

```
chore(frontend): bump submodule to pull vitest setup

5da1ac9..e79453c (#8)
```

Rules:

| Field | Rule |
|---|---|
| Type | always `chore` |
| Scope (Form A) | `submodule` |
| Scope (Form B) | submodule name — `backend` or `frontend` |
| Subject | under 50 chars, starts with `bump …`, summarizes what is being pulled in |
| Body | `<name> <oldSHA(7)>..<newSHA(7)> (#PR)` — one line per submodule |
| Breaking change | `chore(submodule)!:` + `BREAKING CHANGE:` footer |

Decision rule (Form A vs B):

- Same feature branch name across both submodules → **Form A**
- One side breaks without the other → **Form A** (keeps rollback atomic)
- Coincidentally merged around the same time, no shared intent → **Form B**
- One is a hotfix, the other is a routine update → **Form B**

### Pulling submodules to their latest origin/main

To fast-forward both submodules to `origin/main` in one step, use `scripts/sync.sh`. It pulls the parent and each submodule with `git pull --ff-only` in sequence, but automatically skips any submodule that is not on `main` or is in detached-HEAD state — no accidental updates while on a feature branch.

```bash
./scripts/sync.sh
```

To force-update regardless of current branch state (moves the submodule to `origin/main` unconditionally — use with caution):

```bash
git submodule update --remote --merge
```

Unlike `scripts/sync.sh`, this command moves the submodule to `origin/main` no matter what state it is in and leaves it in detached-HEAD mode. Do not commit or edit immediately after — always run `git switch <branch>` (or `-c <new>`) inside the submodule before doing any work.

### Common pitfalls

- **Forgetting the pointer bump** — a teammate clones, gets the old commit, can't reproduce your changes. Always check `git status` at the parent after submodule work.
- **Detached HEAD inside a submodule** — `git submodule update` checks out the pinned SHA in detached-HEAD mode. Before editing, always `git switch <branch>` (or `-c <new>`) inside the submodule. Otherwise commits land on no branch and are easy to lose.
- **Private-repo access** — both submodules point to private repos. Users without read access can see `.gitmodules` but `git submodule update --init` will fail at the network step.
- **Sub-repo Claude hooks do not fire from the parent session** — Claude Code only loads `.claude/settings.json` from the session cwd. When you work at the parent, every `PreToolUse` / `SessionStart` / `PostToolUse` hook under `backend/.claude` / `frontend/.claude` is silently bypassed. For that reason, BE / FE commit-time verification is wired through git-native `.githooks/pre-commit` in each sub-repo, not through Claude hooks. When adding a new commit-time guard, check the sub-repo's `.githooks/` first.

## Running the full stack

The submodule CLAUDE.md files document each side's commands. Cross-stack notes that only matter at the orchestration level:

| Service | Host port | Notes |
|---|---|---|
| Frontend (host `npm run dev`) | 3000 | for active dev / debugging |
| Frontend (docker stack) | 3000 | `docker compose up -d` inside `frontend/` — always-on |
| Backend (host uvicorn) | 8000 | `uv run uvicorn app.main:app --reload --port 8000` |
| Backend (full docker stack) | 8001 | `docker compose up -d --build` inside `backend/` |
| pgvector | 5433 | started by `docker compose up -d pgvector` |
| Redis | 6380 | started by `docker compose up -d redis` |

**Frontend `NEXT_PUBLIC_API_BASE_URL` must point at whichever backend you are running** — `:8000` for host uvicorn, `:8001` for full docker stack. The hard-coded fallback in `frontend/src/lib/api-client.ts` is `:8000`, which mismatches the docker stack — if FE requests fail at runtime, suspect a missing `frontend/.env.local` first (per `frontend/CLAUDE.md`).

Frontend E2E (Playwright) requires both FE (`:3000`) and BE (`:8001`) to be up; only the FE dev server is auto-started by `webServer`.

### Per-side test containers

When testing worktree changes, prefer each submodule's `test-container` skill instead of reusing the always-on main containers. Each skill starts only the side it owns and scans a non-main port range so multiple worktrees can run in parallel without colliding with `3000`, `8001`, `5433`, or `6380`.

**Backend changes only**

Run the backend `test-container` skill from the backend checkout or backend worktree. It starts only backend-owned services: FastAPI server, isolated PostgreSQL/pgvector, and isolated Redis. It also seeds `test@test.com` / `testtest`.

```bash
cd backend
python .agents/skills/test-container/scripts/isolated_backend_env.py start
```

Use the emitted `backend_url` for API checks or for a frontend container.

**Frontend changes only**

Run the frontend `test-container` skill from the frontend checkout or frontend worktree. It starts only the Next.js frontend container and points `NEXT_PUBLIC_API_BASE_URL` at an existing backend. The default backend is the main docker backend at `http://localhost:8001`.

```bash
cd frontend
python .agents/skills/test-container/scripts/isolated_frontend_env.py start \
  --backend-url http://localhost:8001
```

Use the emitted `frontend_url` in the browser.

**Both backend and frontend changes**

Start backend first, then pass its emitted `backend_url` into the frontend `test-container` skill.

```bash
cd backend
python .agents/skills/test-container/scripts/isolated_backend_env.py start

cd ../frontend
python .agents/skills/test-container/scripts/isolated_frontend_env.py start \
  --backend-url http://localhost:<backend-port-from-output>
```

Status and cleanup commands:

```bash
cd backend
python .agents/skills/test-container/scripts/isolated_backend_env.py status
python .agents/skills/test-container/scripts/isolated_backend_env.py stop
python .agents/skills/test-container/scripts/isolated_backend_env.py stop --volumes

cd ../frontend
python .agents/skills/test-container/scripts/isolated_frontend_env.py status
python .agents/skills/test-container/scripts/isolated_frontend_env.py stop
python .agents/skills/test-container/scripts/isolated_frontend_env.py stop --volumes
```

### Always-on docker stack

Both submodules ship a `docker-compose.yml` so the stack can run continuously in the background and survive Docker daemon restarts. Each submodule's CLAUDE.md owns the per-side details; the cross-stack picture is:

| Side | Compose project | Container name(s) | Hot reload | Restart policy |
|---|---|---|---|---|
| Frontend (`frontend/`) | `chatbot-frontend` | `langchain-chatbot-frontend` | Yes — bind mount + WATCHPACK polling, ~1s feedback | `unless-stopped` on the FE container |
| Backend (`backend/`) | `backend` | `backend-{pgvector,redis,server,worker,beat}-1` | No — server runs without `--reload`; rebuild via `docker compose up -d --build server` | `unless-stopped` on `beat` only; the other BE services have no explicit policy and rely on Docker Desktop's "start containers on Docker Desktop start" toggle |

- **Laptop reboot survival requires two things.** (1) Each container's restart policy reattaches it when the Docker daemon comes back. (2) Docker Desktop itself must auto-launch at login — toggle in *Docker Desktop → Settings → General → "Start Docker Desktop when you sign in to your computer"*, or install a user-level LaunchAgent that runs `open -a Docker` at login. Without (2), the daemon never starts and nothing reattaches.
- **Persistent BE state** lives in named volume `backend_postgres_data`. Renaming the BE compose project (e.g. via `name: chatbot-backend`) creates a fresh empty volume unless the existing one is pinned with `volumes.postgres_data.name: backend_postgres_data`.
- **`NEXT_PUBLIC_API_BASE_URL` is browser-side.** Even in the all-docker setup it must resolve from the user's browser to the BE's host-published port — `http://localhost:8001`, never a compose service hostname.

## Superpowers cross-stack workflow

When the user runs the Superpowers flow on this repo (brainstorm → spec → plan → implementation → PR), follow these rules for artifact locations and execution order.

### Artifact locations

| Artifact | Location |
|---|---|
| Workflow / orchestration learnings (parent-level) | `docs/solutions/` (parent repo) — documented solutions to past workflow / architecture problems, organized by category (`workflow-issues/`, `architecture-patterns/`, etc.) with YAML frontmatter (`module`, `tags`, `problem_type`). Sub-repo specific learnings live in `backend/docs/solutions/` and `frontend/docs/solutions/`. Relevant when implementing or debugging in documented areas. |
| Cross-stack spec (spans both submodules) | `docs/superpowers/specs/` (parent repo) |
| Backend spec | `backend/docs/superpowers/specs/` |
| Backend implementation plan | `backend/docs/superpowers/plans/` |
| Frontend spec | `frontend/docs/superpowers/specs/` |
| Frontend implementation plan | `frontend/docs/superpowers/plans/` |

- **Specs go in all three places.** The parent holds the cross-stack integration spec; each sub-repo holds its own perspective.
- **Plans go in backend and frontend only.** The parent has no application code to plan against — its only work is pointer-bump commits.

### Each sub-repo's own workflow takes precedence

Each submodule manages its own implementation conventions through `.claude/`. Backend keeps an explicit rules file at `backend/.claude/rules/superpowers/workflow.md` (TDD cadence, review policy, commit policy). Frontend does **not** have an equivalent `.claude/rules/` directory — its automation lives in `frontend/.claude/agents/` (`gsd-*` series), `frontend/.claude/get-shit-done/`, `frontend/.claude/hooks/`, and `frontend/.claude/skills/`. See `frontend/CLAUDE.md` for FE-specific workflow conventions. During implementation, **the sub-repo's own rules win**. The parent's workflow skill covers only the cross-stack entry point, artifact locations, and pointer bumps.

### GitHub issue creation reliability

When the workflow requires GitHub issue creation, prefer the authenticated `gh` CLI over the GitHub connector. The connector can have a narrower installation scope than the CLI token, so a connector "repo not installed / unavailable" result is **not** proof that issue creation is impossible.

Before creating an issue, verify the CLI path explicitly:

```bash
gh auth status
gh api user --jq .login
git remote get-url origin
gh repo view <owner>/<repo> --json nameWithOwner
```

Then create the issue with an explicit repo and assign it to the authenticated user:

```bash
assignee="$(gh api user --jq .login)"
gh issue create --repo heemanglee/langchain-chatbot --assignee "$assignee" ...
gh issue create --repo heemanglee/langchain-chatbot-fe --assignee "$assignee" ...
```

For cross-stack work, create one issue in each affected submodule repository (`backend/` → `heemanglee/langchain-chatbot`, `frontend/` → `heemanglee/langchain-chatbot-fe`). Do not stop at the issue phase merely because the GitHub connector cannot see one of those repositories; first try the explicit `gh issue create --repo ...` command from the affected submodule. Only report a blocker after `gh auth status`, `gh repo view`, and `gh issue create --repo ...` all fail with the current CLI credentials.

### Reference-first UI mockups

When using the Superpowers visual companion or writing an HTML mockup for an existing frontend surface, create a **reference-first mockup** by default.

Before writing any mockup HTML, collect a real UI reference from at least one of these sources:

- A user-provided screenshot
- The running app in Browser or Chrome
- The actual frontend route and component source

The mockup must preserve the existing app shell, page structure, navigation, typography, spacing, color treatment, and surrounding UI. Only the proposed changed area should differ. Do not invent a new dashboard, card layout, navigation model, or visual theme unless the requested feature is explicitly a new surface.

For flow-heavy UI work, prefer an interactive single-file SPA mockup with mock data and hash-based navigation, such as `#/chat`, `#/chat/session-1`, or `#/projects/project-1`. These mockups must not call the backend. Simulate navigation, menus, dialogs, state changes, and empty/loading/error states locally in JavaScript.

Before showing the mockup, self-check:

- Does the page chrome match the real app?
- Is the changed area the only meaningful visual difference?
- Would the user recognize this as the current product screen?
- Are navigation and state transitions simulated without backend communication?

If the target page cannot be verified, ask for a screenshot or start the frontend before creating the mockup.

### Frontend and backend run in parallel

Frontend and backend work in non-overlapping areas, so **dispatch both as parallel implementer subagents**. Never finish one side before starting the other. Synchronization is required only at two points:

1. **FE e2e verification** — the BE server container with the new changes must be running (`docker compose up -d --build server` first).
2. **Parent repo pointer-bump commit** — after both submodule PRs merge, bundle both SHAs into one commit (Form A).

Specs, plans, issues, branches, implementation, and reviews all proceed in BE/FE parallel.

### Worktree rules

During implementation, **always create a worktree branched from `main`** for both backend and frontend (apply the `superpowers:using-git-worktrees` skill). See each sub-repo's CLAUDE.md for the detailed procedure.

Copy worktree changes to the local working directory **only when the user explicitly requests it** (e.g. "로컬로 옮겨줘", "move to local"). Issue / PR creation follows only on a separate explicit request.

### Pre-PR Compound learning capture

When the user explicitly requests PR creation for a Superpowers worktree, run Compound Engineering before the first `git add` / commit / PR creation step. Invoke `compound-engineering:ce-compound` from each affected sub-repo worktree with `mode:headless` and a tight context hint (feature name, issue number, spec/plan paths, changed-file summary, review/test results, and any Phase 8 manual verification notes).

`mode:headless` is the automation-safe version of the Full **recommended** Compound path: it avoids blocking prompts, writes or updates a repo-local `docs/solutions/...` document, and validates the result. Include that learning document in the same sub-repo commit and add a `## 학습 문서` section to the PR body listing the `docs/solutions/...` path. If Compound reports `Documentation skipped`, fails validation, or writes no solution doc, stop PR creation and ask for a narrower context hint or explicit permission to proceed without the learning doc.

When Compound Engineering is run interactively in this repo, treat the complete documentation workflow with agent session-history search as the repo default. If the workflow surfaces prompts for documentation depth or session-history consent, continue with the complete path and include session-history context unless the user explicitly asks for a lighter or no-history run.

**Remove the worktree immediately after PR creation.** Run `git worktree remove <path>` inside the submodule right after `gh pr create` succeeds. Git only allows a branch to be checked out in one worktree at a time — if the worktree keeps holding `feat/foo`, `git switch feat/foo` from the main checkout fails with `fatal: '<branch>' is already checked out at ...`. Once the PR exists, the worktree's job is done; remove it so follow-up review-feedback commits can happen in the main checkout via `git switch <branch>`. Do NOT recreate the worktree for review-feedback work.

## Editing the parent repo

There is very little to edit at the parent level. Realistic parent-only changes:

- Updating `README.md`
- Updating this `CLAUDE.md`
- Adjusting `.gitmodules` (rare — submodule URL change)
- Committing pointer bumps after submodule work
- Writing cross-stack specs under `docs/superpowers/specs/` per the Superpowers cross-stack workflow rules above
- Recording workflow / process / convention changes as ADRs under `docs/adr/` (single source of truth for "how we work" decisions — produced by the `adr-on-workflow-change` skill)

Anything else almost certainly belongs **inside a submodule**, where its own CLAUDE.md and `.claude/rules/` apply.
