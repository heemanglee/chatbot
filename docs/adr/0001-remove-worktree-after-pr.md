---
id: 0001
title: "PR 생성 직후 worktree 제거"
date: 2026-05-16
status: Accepted
supersedes: null
superseded_by: null
tags:
  - worktree
  - submodule
  - superpowers-workflow
  - git
---

# 0001. PR 생성 직후 worktree 제거

## Context

chatbot 레포는 backend / frontend submodule 작업 시 `.worktrees/<branch>` 형태의 git worktree를 만들어 격리된 환경에서 작업한다. 표준 흐름은 worktree에서 commit → push → `gh pr create`이다.

git의 근본 제약은 다음과 같다:

> 한 브랜치는 동시에 하나의 worktree에서만 checkout될 수 있다.

따라서 worktree가 `feat/foo`를 점유하는 동안 main checkout에서 `git switch feat/foo`를 시도하면 다음 오류로 차단된다:

```
fatal: 'feat/foo' is already checked out at '/.../.worktrees/feat/foo'
```

리뷰 피드백 대응이나 추가 디버깅을 main checkout(IDE·dev 서버가 묶여 있는 1차 작업공간)에서 진행하고 싶을 때 이 잠금이 작업을 방해한다.

## Decision

`gh pr create`가 성공한 **직후** 다음을 실행한다:

```bash
git worktree remove .worktrees/<branch>
```

이후 동일 브랜치에 대한 모든 추가 작업(리뷰 피드백, fix-up, follow-up commit)은 **main checkout에서 `git switch <branch>` 후 직접** 진행한다. worktree를 다시 만들지 않는다.

이 룰은 backend / frontend submodule 양쪽에 동일하게 적용된다.

## Before / After scenarios

### Before — worktree 유지 정책

```
1. cd backend
2. git worktree add .worktrees/feat/foo -b feat/foo origin/main
3. (worktree에서) 작업 + commit + push
4. (worktree에서) gh pr create
5. PR 리뷰어가 수정 요청 댓글 작성
6. cd /path/to/backend                                  # main checkout으로 이동
7. git switch feat/foo
   → fatal: 'feat/foo' is already checked out at .worktrees/feat/foo   ❌
8. (어쩔 수 없이) cd .worktrees/feat/foo → 수정 → commit → push
9. main checkout은 PR이 merge될 때까지 feature branch에 진입 불가
```

문제 지점:

- main checkout이 1차 작업공간임에도 feature branch에 진입 불가
- worktree 경로를 기억해 매번 `cd` 해야 함
- 여러 worktree가 누적되며 `.worktrees/` 디렉토리가 점점 무거워짐

### After — PR 생성 직후 worktree 제거

```
1. cd backend
2. git worktree add .worktrees/feat/foo -b feat/foo origin/main
3. (worktree에서) 작업 + commit + push
4. (worktree에서) gh pr create
5. cd /path/to/backend                                  # main checkout으로 이동
6. git worktree remove .worktrees/feat/foo              ✅ 새 단계 — 잠금 해제
7. PR 리뷰어가 수정 요청 댓글 작성
8. git switch feat/foo                                  ✅ main checkout에서 정상 진입
9. 수정 → commit → push (main checkout에서 직접)
10. PR merge 후 git switch main && git branch -d feat/foo
```

개선 지점:

- main checkout에서 feature branch에 자유롭게 진입 → IDE·dev 서버·git 도구 일관성
- `.worktrees/` 누적 없음 (PR마다 생성·제거 1회씩)
- 리뷰 피드백 사이클이 main checkout 안에서 닫힘

## Consequences

**Positive**

- main checkout에서 모든 git 동작 가능 — 브랜치 잠금 충돌 제거
- 멀티 worktree 누적으로 인한 디스크·인덱스 비용 감소
- 리뷰 피드백 → 추가 commit 흐름 단순화 (`cd` 불필요)

**Negative**

- worktree의 "다른 브랜치 작업 중에도 격리 유지" 효과가 **PR 생성 시점까지로 한정**된다. 리뷰 단계 이후 main checkout이 feature branch에 묶이므로, 동시에 다른 작업을 하려면 stash 혹은 별도 worktree 재생성이 필요하다.
- 룰을 잊고 worktree를 남기면 잠금 문제가 재발한다 → `CLAUDE.md` / `.claude/rules/superpowers/workflow.md` 룰로 보강.

## Alternatives considered

| 대안 | 기각 사유 |
|---|---|
| worktree 유지, 리뷰 피드백도 worktree에서 처리 | 원 문제(main checkout 잠금)가 그대로 남음. 사용자가 명시적으로 거부. |
| worktree 자체를 쓰지 않고 main checkout에서 feature branch 직접 작업 | 작업 도중 main으로 잠깐 돌아가야 할 때 stash 필요 → 격리 이점 상실. 병렬 implementer subagent 흐름과도 충돌. |
| worktree 제거 시점을 PR merge 이후로 늦춤 | 리뷰 사이클(보통 수 시간~수일) 동안 잠금 문제 지속 → 본 문제 미해결. |
| 같은 ref를 두 worktree에 동시 노출 | git이 해당 기능을 제공하지 않음. |

## References

- 룰 반영 위치
  - `CLAUDE.md` — Worktree rules 섹션
  - `.claude/rules/superpowers/workflow.md` — *Removing the worktree immediately after PR creation* 섹션
- 적용 커밋: `83d41af docs(claude): require worktree removal right after PR creation`
- 관련 메모리: `feedback_worktree_remove_after_pr.md`
