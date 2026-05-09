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

## Superpowers cross-stack workflow

When the user runs the Superpowers flow on this repo (브레인스토밍 → 스펙 → 플랜 → 구현 → PR), 산출물 작성 위치와 실행 방식은 다음 룰을 따른다.

### 산출물 위치

| 산출물 | 작성 위치 |
|---|---|
| Cross-stack spec (양쪽 영향 묶음) | `docs/superpowers/specs/` (parent repo) |
| Backend spec | `backend/docs/superpowers/specs/` |
| Backend implementation plan | `backend/docs/superpowers/plans/` |
| Frontend spec | `frontend/docs/superpowers/specs/` |
| Frontend implementation plan | `frontend/docs/superpowers/plans/` |

- **Spec은 세 곳 모두 작성한다.** parent repo, backend repo, frontend repo 각각에 spec 문서를 둔다. parent에는 cross-stack 관점의 통합 spec, 각 sub-repo에는 그 repo 관점의 spec이 필요하다.
- **Plan은 backend / frontend 두 곳에만 작성한다.** parent repo는 plan을 가지지 않는다 (orchestration repo에는 plan할 application code가 없으며, parent의 작업은 포인터-범프 commit으로 한정된다).

### 각 sub-repo의 자체 workflow를 우선한다

backend / frontend submodule은 각자의 superpowers workflow rules를 갖는다 (예: `backend/.claude/rules/superpowers/workflow.md`, `frontend/.claude/rules/superpowers/workflow.md`). 구현 단계에서는 **각 sub-repo 자신의 룰이 우선**한다. parent의 workflow skill은 cross-stack 진입점·문서 위치·포인터 범프만 담당하고, BE/FE 안의 TDD·리뷰 cadence·commit policy 등은 각 sub-repo 룰을 따른다.

### Frontend와 backend는 병렬 진행

frontend와 backend는 작업 영역이 겹치지 않으므로 **각자의 task를 평행으로 진행한다**. 한 쪽을 끝낸 뒤 다른 쪽을 시작하지 말고, 두 implementer subagent를 동시에 dispatch한다. 동기화가 필요한 시점은 다음 두 곳뿐이다:

1. **FE e2e 검증** — BE 변경이 적용된 server 컨테이너가 떠 있어야 한다 (`docker compose up -d --build server` 후).
2. **parent repo 포인터-범프 commit** — 양쪽 submodule PR이 머지된 후 양쪽 SHA를 묶어 한 commit으로 작성한다 (Form A).

스펙·플랜·issue·branch·구현·리뷰는 모두 BE/FE 병렬로 진행한다.

## Editing the parent repo

There is very little to edit at the parent level. Realistic parent-only changes:

- Updating `README.md`
- Updating this `CLAUDE.md`
- Adjusting `.gitmodules` (rare — submodule URL change)
- Committing pointer bumps after submodule work
- 위의 "Superpowers cross-stack workflow" 룰에 따라 cross-stack spec을 `docs/superpowers/specs/`에 작성하는 작업

Anything else almost certainly belongs **inside a submodule**, where its own CLAUDE.md and `.claude/rules/` apply.
