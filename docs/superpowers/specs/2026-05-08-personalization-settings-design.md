# 개인 맞춤 설정 (Personalization Settings) 설계 스펙

- **작성일**: 2026-05-08
- **작성자**: heemanglee
- **상태**: Draft (브레인스토밍 완료, 사용자 승인 대기)
- **범위**: cross-stack (backend + frontend)

---

## 1. 배경 / 목적

현재 `User` 모델에는 사용자가 직접 입력한 자유 형식 지침(`instruction`)만 존재하며, 시스템 프롬프트에 한 줄로 주입된다. 이번 작업의 목적은 **사용자가 자신을 LLM에게 소개하는 표준 입력 채널**을 도입하여 응답 개인화 품질을 높이고, 향후 추가될 다른 사용자 단위 설정(알림, 일반)을 받아낼 UI 진입점(중앙 정사각형 설정 모달)을 함께 구축하는 것이다.

**대표 사용자 흐름**

> 닉네임 "이희망", 직업 "백엔드 개발자", 맞춤형 지침 "전문적인 어조로 응답하되 반말로 응답하세요. 기술적인 내용에 대해 물어볼 시 예제 코드와 함께 설명하세요."를 저장하면, 모든 채팅에서 LLM이 "백엔드 개발자에 맞춰서 설명할게."처럼 사용자 프로필을 반영한 반말 응답을 한다.

---

## 2. 범위 / 비범위

### 2.1 In Scope

- `User` 모델에 `nickname`, `occupation` 컬럼 추가 (둘 다 nullable, 길이 제한 50/100자)
- `User.instruction`에 max_length 2000자 제약 신설 (Pydantic 레벨)
- `build_system_prompt()`에서 닉네임·직업·instruction을 자연스러운 절로 합성하여 시스템 프롬프트 끝쪽으로 이동 (캐시 친화 prefix 확보)
- 프론트엔드 사이드바 좌측 하단 프로필을 클릭 시 드롭다운 메뉴(설정·로그아웃)로 동작하도록 변경. 기존 노출되어 있던 로그아웃 버튼은 제거
- "설정" 클릭 시 중앙 정사각형 모달 오픈. 좌측 카테고리 nav(일반·알림·개인 맞춤 설정), 우측 패널. 일반·알림은 `aria-disabled` 처리, 개인 맞춤 설정만 활성화되며 모달 오픈 시 디폴트 선택
- 우측 패널에 맞춤형 지침(textarea), 닉네임(input), 직업(input) 폼. 각 필드 우측에 글자수 카운터(`현재 / 최대`) 노출, 80% 초과 시 amber, 100% 도달 시 destructive 색
- 저장 시 기존 `PUT /api/v1/users/me`를 확장하여 한 번에 업데이트, 성공 시 모달 닫기 + sonner 토스트 + `useMe` 캐시 invalidate
- BE/FE 각각의 unit / integration / e2e 테스트 (BE는 `tests/unit`, `tests/integration`, `tests/e2e` 3계층, FE는 vitest unit + Playwright e2e)

### 2.2 Out of Scope (별도 작업)

- "메모리" 섹션, "내 추가 정보" 필드 (스크린샷에는 있으나 본 작업 범위 외)
- 카테고리 nav의 그 외 항목(앱·일정·데이터 제어·보안·자녀 보호·계정)
- 일반·알림 카테고리의 실제 기능 (이번 작업은 비활성 placeholder)
- 모바일 반응형 다이얼로그 레이아웃
- dirty 상태에서 모달 닫기 시 confirm 다이얼로그
- DB 컬럼 레벨 길이 제약 (검증은 Pydantic에서만 — `instruction`은 `Text` 타입 그대로 유지)
- 사용자별 다국어 응답 강제 (instruction 자유 입력으로 충분히 표현 가능)

---

## 3. 데이터 모델 변경

### 3.1 `User` 모델 (`backend/app/domain/user/models.py`)

```python
class User(Base):
    # 기존 필드 유지
    instruction: Mapped[str | None] = mapped_column(Text, nullable=True)  # 기존
    nickname:   Mapped[str | None] = mapped_column(String(50),  nullable=True)  # 신규
    occupation: Mapped[str | None] = mapped_column(String(100), nullable=True)  # 신규
```

### 3.2 길이 제한 SSoT (단일 진실 원천)

**BE**: `backend/app/domain/user/constants.py` (신규)

```python
NICKNAME_MAX_LENGTH = 50
OCCUPATION_MAX_LENGTH = 100
INSTRUCTION_MAX_LENGTH = 2000
```

`UserMeUpdateRequest`의 `Field(max_length=...)`는 이 상수를 import하여 사용한다.

**FE**: `frontend/src/domains/user/constants.ts` (신규)

```typescript
export const NICKNAME_MAX_LENGTH = 50
export const OCCUPATION_MAX_LENGTH = 100
export const INSTRUCTION_MAX_LENGTH = 2000
```

**Drift 방지**: BE 단위 테스트에서 `UserMeUpdateRequest.model_json_schema()`의 `maxLength`가 위 상수와 일치하는지 assert. FE/BE 상수 불일치는 코드 리뷰로 차단.

### 3.3 마이그레이션

```bash
uv run alembic revision --autogenerate -m "add nickname and occupation to users"
```

생성될 파일 (예: `0010_add_user_personalization_columns.py`):

- `ADD COLUMN nickname VARCHAR(50) NULL`
- `ADD COLUMN occupation VARCHAR(100) NULL`
- `instruction` 타입은 변경하지 않음 (DB 레벨 길이 제약 추가하지 않음, Pydantic 검증만)

마이그레이션 전 다음을 한 번 확인한다 — 기존 `instruction` 데이터 중 2000자를 초과하는 행이 있는지:

```sql
SELECT COUNT(*) FROM users WHERE LENGTH(instruction) > 2000;
```

결과가 0이 아니면 한도 상향 또는 절단 정책을 별도 결정한다.

---

## 4. API 변경

### 4.1 `PUT /api/v1/users/me` 확장

**위치**: `backend/app/domain/user/api.py:89-97`

기존 엔드포인트를 그대로 활용한다 (새 엔드포인트 신설 안 함).

**요청 스키마** (`UserMeUpdateRequest`):

```python
class UserMeUpdateRequest(BaseModel):
    role:        str | None = None  # 기존
    instruction: str | None = Field(default=None, max_length=INSTRUCTION_MAX_LENGTH)  # 길이 제약 신설
    nickname:    str | None = Field(default=None, max_length=NICKNAME_MAX_LENGTH)    # 신규
    occupation:  str | None = Field(default=None, max_length=OCCUPATION_MAX_LENGTH)  # 신규
```

**응답**: 갱신된 `UserMe`(기존 `UserResponse` 스키마에 `nickname`, `occupation` 추가).

**부분 업데이트 (PATCH semantics)** — 다음 두 케이스를 명확히 구분한다:

| 클라이언트 전송 | 서버 동작 |
|---|---|
| 필드 키 자체를 보내지 않음 (`field is None` after Pydantic) | 해당 컬럼 변경하지 않음 (no-op) |
| 필드 키를 보내지만 값이 빈 문자열 또는 공백만 (`""`, `"   "`) | 해당 컬럼을 `NULL`로 클리어 |
| 필드 키를 보내고 정상 값 | 해당 컬럼을 그 값으로 업데이트 |

**검증 / 정규화 순서**: ① Pydantic이 먼저 `max_length` 검증(초과 시 422). ② 통과한 값이 service 레이어로 들어가면 `value.strip()`을 적용하여 `""`이면 `None`으로 정규화. ③ repository는 `None`이 아닌 필드만 UPDATE 대상으로 간주하되, 위 두 케이스를 구분하기 위해 service에서 "키 미전송" 판별을 위해 `payload.model_dump(exclude_unset=True)`로 먼저 분리한 다음 정규화한다. 즉:

```python
provided = payload.model_dump(exclude_unset=True)   # 키 자체가 없는 필드는 dict에서 빠짐
to_update = {
    name: (value.strip() or None) if isinstance(value, str) else value
    for name, value in provided.items()
}
```

**서비스 시그니처 확장** (필수):

```python
# UserService.update_me — 두 인자 추가
async def update_me(
    self,
    *,
    user_id: UUID,
    role: str | None = ...,
    instruction: str | None = ...,
    nickname: str | None = ...,        # 신규
    occupation: str | None = ...,      # 신규
) -> User: ...

# UserRepository.update_profile — 동일하게 두 인자 추가
async def update_profile(
    self,
    user_id: UUID,
    *,
    role: str | None = ...,
    instruction: str | None = ...,
    nickname: str | None = ...,        # 신규
    occupation: str | None = ...,      # 신규
) -> User: ...
```

`Sentinel`(예: `UNSET`) 또는 `Optional[str] | type[_Unset]` 패턴을 도입하여 "키 미전송"과 "값을 None으로 클리어 요청"을 구분한다. 구현 디테일은 plan 단계에서 결정.

**서비스 로깅**: `UserService.update_me()`의 `event=user_profile_updated` 로그(현행 코드 기준 `service.py:149`)에 `changed_fields`로 변경된 필드명 목록을 기록한다. `nickname`/`occupation`/`instruction` **값 자체는 로깅 금지** (개인정보·민감 텍스트 가능성).

### 4.2 검증 실패 응답

422, FastAPI 기본 형식. FE는 422 응답을 받은 경우 폼 상단에 `<Alert variant="destructive">` 인라인 메시지로 노출 (필드별 에러 매핑은 본 작업 외).

---

## 5. 시스템 프롬프트 합성 변경

### 5.1 절 위치 변경 (옵션 A 채택)

**파일**: `backend/app/domain/chat/service.py:76-110`

**기존**:

```
[base + 날짜] + [instruction 절 (있을 때)] + [image clause] + [RAG clause]
```

**변경 후**:

```
[base + 날짜] + [image clause] + [RAG clause] + [profile clauses]
```

`profile clauses`는 닉네임/직업/instruction 절을 채워진 것만 자연스럽게 이어 붙인다.

### 5.2 절 합성 규칙

```python
def _profile_clauses(user: User) -> list[str]:
    nickname   = user.nickname.strip()   if user.nickname   and user.nickname.strip()   else None
    occupation = user.occupation.strip() if user.occupation and user.occupation.strip() else None
    instruction= user.instruction.strip() if user.instruction and user.instruction.strip() else None

    clauses: list[str] = []
    if nickname and occupation:
        clauses.append(f"The user goes by '{nickname}' and works as a {occupation}.")
    elif nickname:
        clauses.append(f"The user goes by '{nickname}'.")
    elif occupation:
        clauses.append(f"The user works as a {occupation}.")

    if instruction:
        clauses.append(f"You must follow the user's instructions: {instruction}")
    return clauses
```

**조립 알고리즘** — 각 파트는 빈 문자열일 수 없도록 사전 필터링한 뒤 `" ".join(...)`으로 결합:

```python
parts = [
    _BASE_SYSTEM_PROMPT,
    date_line,
    _IMAGE_HANDLING_CLAUSE,
    _RAG_HANDLING_CLAUSE,
    *_profile_clauses(user),
]
prompt = " ".join(part for part in parts if part)
```

- 모든 프로필 필드가 비어 있으면 `_profile_clauses`는 빈 리스트 → 시스템 프롬프트는 base + 날짜 + image + RAG 만 포함.
- RAG clause 끝과 첫 profile clause 시작 사이의 경계 역시 `" ".join`이 부여하는 단일 공백으로 일관 처리.
- 모든 절은 마침표로 끝나도록 합성하여 `" "`만으로도 의미 경계가 명확하도록 한다 (예: `"The user goes by 'X'."` 끝의 `.`).

### 5.3 캐시 영향

OpenAI 프롬프트 캐시는 prefix 일치 길이에 비례한다. 안정 prefix(`base + 날짜 + image + RAG`)가 길어져 프로필 변경 후에도 전반 캐시 효율이 유지된다. 단점은 기존 `test_build_system_prompt.py`의 절 순서 검증을 재작성해야 한다는 것 — 작업 항목에 포함.

---

## 6. 프론트엔드 설계

### 6.1 의존성 추가

```bash
cd frontend
npx shadcn@latest add dialog dropdown-menu textarea separator sonner
```

`<Toaster />`는 `frontend/src/app/(main)/layout.tsx` (또는 root layout)에 1회 마운트.

### 6.2 컴포넌트 트리 (신규)

```
src/components/user/
├── profile-menu.tsx           # 사이드바 좌측 하단 프로필 트리거 + DropdownMenu
├── settings-dialog.tsx        # 중앙 정사각형 다이얼로그 (좌: nav, 우: 패널)
├── settings-category-nav.tsx  # 좌측 카테고리 3개 (일반·알림 disabled, 개인 맞춤 설정 active)
└── personalization-panel.tsx  # 우측 패널 — 폼 + 카운터 + 저장/취소
```

### 6.3 변경되는 기존 파일

- `src/components/chat/sidebar.tsx:88-104` 프로필 블록 전체를 `<ProfileMenu />` 한 컴포넌트로 교체. 기존에 노출되어 있던 별도 로그아웃 버튼은 제거.
- `src/domains/user/types.ts` `UserMe`에 `nickname`, `occupation` 추가.
- `src/domains/user/api.ts` `UpdateMeRequest`에 두 필드 추가.
- `src/domains/user/hooks.ts` `useUpdateMe` 시그니처만 확장 (invalidate 로직 그대로).
- `src/app/(main)/layout.tsx` 또는 root layout에 `<Toaster />` 마운트.

### 6.4 UX 디테일

| 항목 | 처리 |
|---|---|
| 프로필 hover | `hover:bg-muted/60 cursor-pointer rounded-md transition-colors` |
| 드롭다운 메뉴 항목 | ① ⚙ 설정 ② 로그아웃(`text-destructive font-medium`) |
| 비활성 카테고리(일반·알림) | `aria-disabled="true"`, `pointer-events-none`, `opacity-50`, `cursor-not-allowed` |
| 활성 카테고리 강조 | `bg-accent` + 좌측 인디케이터(border-l-2) |
| 다이얼로그 크기 | 데스크톱 우선, `max-w-3xl` + 고정 높이 `h-[640px]`로 정사각형 느낌 유지 (실 픽셀은 plan 단계에서 디자인 가이드와 정합 확인) |
| 우측 패널 스크롤 | `overflow-y-auto` (모달 자체는 스크롤하지 않음) |
| 글자수 카운터 | 라벨 우측에 `<span>{value.length} / {MAX}</span>`. 임계 색상은 `length / MAX` 비율로 결정: `< 0.8` `text-muted-foreground`, `>= 0.8 && < 1.0` `text-amber-500`, `>= 1.0` `text-destructive` (boundary는 80% 포함) |
| 글자수 하드캡 | input/textarea의 `maxLength` 속성으로 BE 검증 통과 보장 |
| 저장 버튼 | mutation pending 또는 변경 사항 없음(`isDirty=false`) → disabled |
| 저장 성공 | `mutation.onSuccess` → `setOpen(false)` + `toast.success("설정이 저장되었습니다.")` + `useMe` 캐시 invalidate (이미 `useUpdateMe`에 있음) |
| 저장 실패 | 모달 유지, 폼 상단 `<Alert variant="destructive">` 인라인 메시지 |
| 취소 / Esc / 외부 클릭 | 입력 폐기 즉시 닫힘 (dirty confirm 없음) |
| 모달 마운트 시 초기값 | `useMe()` 반환값의 `nickname`/`occupation`/`instruction` (각각 `null`은 빈 문자열로 표시) |
| `useMe` 로딩 중 다이얼로그 오픈 | 우측 패널을 스켈레톤(또는 disabled) 렌더링 + 저장 버튼 disabled. 데이터 도착 시 자동으로 폼 초기값 세팅 |
| 다시 열 때 폼 상태 | 항상 서버 상태로 리셋 (로컬 변경 잔존 없음) |
| 다시 열 때 카테고리 nav 상태 | 항상 "개인 맞춤 설정"으로 리셋. 마지막 선택 카테고리를 기억하지 않음 |
| 입력 paste 초과 처리 | input/textarea의 `maxLength`로 1차 차단. 그래도 길이 초과가 들어왔다면(브라우저 차이) 카운터는 `length / MAX` 그대로 표기하되 저장 시 BE 422 → 인라인 Alert로 fallback |
| i18n | 한국어 하드코딩 (기존 사이드바 패턴과 동일) |

### 6.5 폼 상태 관리

- `react-hook-form` 도입 안 함 (현재 코드베이스 미사용 + 폼 단순).
- `useState` 3개(`nickname`, `occupation`, `instruction`)와 `isDirty = useMemo(() => 변경 여부, [...])`.
- mutation은 기존 `useUpdateMe` 그대로 사용.

---

## 7. 테스트 전략

### 7.1 백엔드

| 레이어 | 파일 | 케이스 |
|---|---|---|
| unit | `tests/unit/domain/chat/test_build_system_prompt.py` (확장) | 닉네임만 / 직업만 / 둘 다 / 둘 다 빈값 / 공백만(`"  "`) → 무시 / instruction 단독 / 풀 조합 / 절 순서 검증 (image·RAG 다음에 profile clauses) / 모든 프로필 필드 빈 경우 base+날짜+image+RAG만 포함 |
| unit | `tests/unit/domain/user/test_service.py` (확장) | `update_me`가 nickname/occupation 부분 업데이트 / "키 미전송 vs 빈 문자열" PATCH semantics 구분 / 공백 문자열 → None 정규화 / 한 요청에서 일부는 클리어·일부는 set / `event=user_profile_updated` & `changed_fields` 로그 검증 |
| unit | `tests/unit/domain/user/test_request_schema_limits.py` (신규) | `UserMeUpdateRequest.model_json_schema()`의 maxLength가 `constants.py` 값과 일치 (drift 방지) |
| integration | `tests/integration/api/test_user_me_update.py` (신규) | `PUT /users/me` 4필드 부분/전체 조합 → DB 반영, "키 미전송"은 기존 값 보존 vs "빈 문자열"은 NULL로 클리어, 401, max_length 초과 422 |
| e2e | `tests/e2e/test_personalization_flow.py` (신규, gate `RUN_E2E=1`) | 회원가입/로그인 → `PUT /users/me`로 프로필 저장 → 채팅 요청 시 시스템 프롬프트에 닉네임/직업/instruction 절이 들어가는지 (로그 또는 응답 패턴으로 스모크 검증) |

### 7.2 프론트엔드

| 레이어 | 파일 | 케이스 |
|---|---|---|
| unit (vitest) | `tests/unit/components/user/profile-menu.test.tsx` (신규) | 프로필 클릭 → 메뉴 노출 / "설정" 클릭 → 콜백 호출 / 로그아웃 항목 destructive 클래스 적용 |
| unit (vitest) | `tests/unit/components/user/settings-dialog.test.tsx` (신규) | 일반·알림 카테고리 클릭 무반응 / 개인 맞춤 설정 디폴트 선택 / Esc 닫힘 / 다시 열 때 nav 상태가 "개인 맞춤 설정"으로 리셋 / `useMe` 로딩 중에는 패널 스켈레톤 + 저장 disabled |
| unit (vitest) | `tests/unit/components/user/personalization-panel.test.tsx` (신규) | 초기값 렌더 / 글자수 카운터 임계(`>= 80%` amber, `>= 100%` destructive) / max 초과 입력 차단 / paste로 maxLength 초과 시 카운터 표시 + 저장 시 BE 422 fallback / 변경 없을 때 저장 disabled / 저장 성공 시 onClose & toast / 저장 실패 시 인라인 Alert |
| integration (vitest) | `tests/integration/domains/user/update-me.test.ts` (신규) | `updateMe` payload에 nickname/occupation 포함 시 200, 부분 업데이트 OK, 빈 문자열 클리어 시 200 |
| e2e (Playwright) | `tests/e2e/personalization.spec.ts` (신규) | 로그인 → 프로필 클릭 → "설정" → 모달 → 닉네임/직업/지침 입력 → 저장 → 토스트 확인 → 모달 재열기 시 입력값 영속 |

---

## 8. 위험 / 마이그레이션 노트

| 위험 | 대응 |
|---|---|
| 절 위치 변경으로 기존 prompt 단위 테스트가 깨짐 | 작업 항목으로 명시적 재작성 |
| BE/FE 길이 제한 상수 drift | BE constants 모듈 import + `model_json_schema` 단위 테스트 |
| 기존 `instruction`에 2000자 초과 데이터 잠재 | 마이그레이션 전 SQL 체크 (§3.3) |
| 토스트(sonner) 신규 도입 → 다른 화면 미영향성 | root layout `<Toaster />` 1회 마운트, 다른 컴포넌트에 미영향 |
| LangSmith run_name/tags 누락 (BE 룰) | 본 작업은 신규 LLM call 없음. 기존 `chat_model` 호출 경로만 사용 → 영향 없음 |
| Dialog 모바일 레이아웃 답답함 | 데스크톱 우선, 반응형은 별도 작업 — 본 스펙 비범위 |

---

## 9. 작업 분할 (issue / PR 단위)

cross-stack 변경이므로 양쪽 submodule에 각각 issue + PR + parent repo pointer-bump PR(`workflow.md` Form A) 구조.

| Issue 제목 (안) | Repo | 핵심 |
|---|---|---|
| `feat: add user personalization fields (nickname, occupation)` | `backend` | constants 모듈, alembic 0010, schemas/service 확장, build_system_prompt 절 위치 변경, unit/integration/e2e 테스트 |
| `feat: add personalization settings UI (profile menu + settings dialog)` | `frontend` | shadcn 추가, types/api/hooks/constants 확장, ProfileMenu, SettingsDialog/SettingsCategoryNav/PersonalizationPanel, sidebar 프로필 영역 교체, sonner Toaster 마운트, vitest/Playwright 테스트 |
| `chore(submodule): bump backend, frontend for personalization settings` | `chatbot` (parent) | Form A 묶음 pointer bump (양쪽 PR merge 후) |

---

## 10. 결정 사항 요약

| 결정 | 내용 |
|---|---|
| 필드 범위 | 닉네임 / 직업 / 맞춤형 지침 3개만. "내 추가 정보", "메모리" 제외 |
| 카테고리 | 일반·알림·개인 맞춤 설정 3개만. 일반·알림은 비활성 |
| 프로필 메뉴 | 기존 로그아웃 버튼 제거, 클릭 시 드롭다운 (① 설정 ② 로그아웃 — 빨간색) |
| 시스템 프롬프트 합성 | 채워진 필드만 자연어 절로 합침. 절 위치는 image·RAG clause **다음**(끝) |
| BE 단일 진실 원천 | `app/domain/user/constants.py` 길이 상수, Pydantic `Field(max_length)` 적용 |
| `instruction` 길이 제약 | 2000자 (Pydantic 레벨, DB 컬럼 타입은 Text 유지) |
| FE 폼 라이브러리 | 도입 안 함 (`useState` 3개) |
| 저장 동작 | 성공 → 모달 닫힘 + sonner 토스트, 실패 → 인라인 Alert |
| 취소/Esc/외부클릭 | 즉시 닫힘 (dirty confirm 없음) |
| 토스트 라이브러리 | sonner (shadcn 권장) |
| 모바일 반응형 | 본 작업 비범위 |

---

## 11. 다음 단계

1. 본 스펙 사용자 리뷰 후 `superpowers:writing-plans` 단계로 이동.
2. BE/FE 각 submodule의 `docs/superpowers/plans/` 아래 구현 플랜을 sub-agent로 병렬 작성 (`workflow.md` step 3).
3. 각 플랜 사용자 승인 후 TDD 기반 구현(`superpowers:test-driven-development`).
