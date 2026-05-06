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

```bash
git submodule update --remote --merge
```

This is the only command that advances the pinned SHAs without going inside the submodule first. Use it when you want to take whatever is on `origin/main` of each submodule.

### Common pitfalls

- **Forgetting the pointer bump** — a teammate clones, gets the old commit, can't reproduce your changes. Always check `git status` at the parent after submodule work.
- **Detached HEAD inside a submodule** — `git submodule update` checks out the pinned SHA in detached-HEAD mode. Before editing, always `git switch <branch>` (or `-c <new>`) inside the submodule. Otherwise commits land on no branch and are easy to lose.
- **Private-repo access** — both submodules point to private repos. Users without read access can see `.gitmodules` but `git submodule update --init` will fail at the network step.

## Running the full stack

The submodule CLAUDE.md files document each side's commands. Cross-stack notes that only matter at the orchestration level:

| Service | Host port | Notes |
|---|---|---|
| Frontend (`npm run dev`) | 3000 | always port 3000 |
| Backend (host uvicorn) | 8000 | `uv run uvicorn app.main:app --reload --port 8000` |
| Backend (full docker stack) | 8001 | `docker compose up -d --build` inside `backend/` |
| pgvector | 5433 | started by `docker compose up -d pgvector` |
| Redis | 6380 | started by `docker compose up -d redis` |

**Frontend `NEXT_PUBLIC_API_BASE_URL` must point at whichever backend you are running** — `:8000` for host uvicorn, `:8001` for full docker stack. The hard-coded fallback in `frontend/src/lib/api-client.ts` is `:8000`, which mismatches the docker stack — if FE requests fail at runtime, suspect a missing `frontend/.env.local` first (per `frontend/CLAUDE.md`).

Frontend E2E (Playwright) requires both FE (`:3000`) and BE (`:8001`) to be up; only the FE dev server is auto-started by `webServer`.

## Editing the parent repo

There is very little to edit at the parent level. Realistic parent-only changes:

- Updating `README.md`
- Updating this `CLAUDE.md`
- Adjusting `.gitmodules` (rare — submodule URL change)
- Committing pointer bumps after submodule work

Anything else almost certainly belongs **inside a submodule**, where its own CLAUDE.md and `.claude/rules/` apply.
