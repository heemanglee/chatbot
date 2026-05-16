# Architecture / Workflow Decision Records (ADR)

이 디렉토리는 chatbot 레포의 작업 방식·아키텍처 결정을 시점별로 누적한다. 룰 자체는 `CLAUDE.md` / `.claude/rules/`에 반영하고, ADR은 **왜 그 룰이 그렇게 정해졌는지**를 박제한다.

## 파일 규칙

- 이름: `NNNN-<kebab-case-slug>.md` (예: `0001-remove-worktree-after-pr.md`)
- 번호: 4자리 zero-pad, 항상 1씩 증가, **결번 금지**
- 한 결정 = 한 파일. 여러 결정이 얽히면 분리한다.
- 결정이 바뀌어도 원본을 삭제하지 않는다. 새 파일을 만들고 원본의 `status`를 `Superseded by NNNN`으로 갱신한다.

## Frontmatter (필수)

```yaml
---
id: 0001
title: "결정 제목"
date: YYYY-MM-DD
status: Accepted          # Proposed | Accepted | Deprecated | Superseded
supersedes: null          # 대체한 ADR id (없으면 null)
superseded_by: null       # 자신을 대체한 ADR id (없으면 null)
tags: []
---
```

## 본문 섹션 순서 (필수)

1. **Context** — 결정이 필요해진 배경, 발견한 제약
2. **Decision** — 정한 룰 (명령형)
3. **Before / After scenarios** — 변경 전·후 동작을 단계별 시나리오로 비교 (필수)
4. **Consequences** — 트레이드오프 (+/− 양쪽)
5. **Alternatives considered** — 검토한 다른 옵션과 기각 사유
6. **References** — 관련 룰 위치, 커밋, 이슈/PR

## 다른 디렉토리와의 역할 분담

| 위치 | 성격 |
|---|---|
| `docs/adr/` | **결정 기록** — A와 B 중 B를 택한 이유, 그 시점의 맥락 |
| `docs/solutions/workflow-issues/` | **사고 회고** — 문제 발생 → 해결 과정 |
| `docs/superpowers/specs/` | **기능 스펙** — 무엇을 만들/바꿀 것인가 |

## 인덱스

- [0001 — PR 생성 직후 worktree 제거](0001-remove-worktree-after-pr.md)
