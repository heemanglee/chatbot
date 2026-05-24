---
title: Cross-stack nickname validation rejects blank and emoji values
date: 2026-05-24
category: docs/solutions/integration-issues/
module: backend/app/domain/user + frontend/src/components/user
problem_type: integration_issue
component: authentication
symptoms:
  - "Blank or whitespace-only nicknames were not rejected consistently across profile flows"
  - "Emoji nicknames could pass parts of the account profile contract"
  - "The sidebar profile menu displayed email even after onboarding set a nickname"
root_cause: missing_validation
resolution_type: code_fix
severity: medium
tags:
  - nickname-validation
  - user-profile
  - pydantic
  - personalization
  - profile-menu
  - cross-stack
  - emoji
related_components:
  - "backend user update schema"
  - "frontend personalization settings"
  - "frontend nickname onboarding"
  - "frontend profile menu"
---

# Cross-stack nickname validation rejects blank and emoji values

## Problem

Nickname semantics drifted between backend and frontend. Product behavior now treats nickname as required after onboarding, but `PUT /api/v1/users/me` still allowed blank strings to flow into service-layer normalization, and the settings/profile UI did not fully match the onboarding nickname contract.

## Symptoms

- Personalization settings could save an effectively empty nickname when another field made the form dirty.
- Direct API callers could submit `nickname: ""`, `nickname: "   "`, or emoji-containing values unless the Pydantic request schema rejected them.
- The sidebar profile menu showed the email address even after onboarding stored a nickname, so the visible identity did not follow the nickname-first rule.
- Onboarding already used a purple invalid-input blink, but settings did not give the same feedback when users tried to save without a non-space nickname.

## What Didn't Work

- Relying on service-layer empty-string normalization was too broad. It is still useful for nullable profile fields such as `occupation` and `instruction`, but for nickname it made a blank string look like an intentional clear.
- Relying only on frontend sanitization was insufficient. UI code can remove emoji before mutation, but direct API callers still bypass the browser.
- Treating nullable profile fields as proof that the product does not require them was too loose. Mandatory nickname became a product policy even though the database/API shape still allows `null` for intentional reset. (session history)

## Solution

Backend added Pydantic validation to `UserMeUpdateRequest.nickname`, while preserving `None` as the explicit clear/reset path:

```python
if value is None:
    return value
if not value.strip():
    raise ValueError("Nickname must contain at least one non-space character.")
if nickname_contains_emoji(value):
    raise ValueError("Nickname cannot contain emoji.")
return value
```

The API contract is now:

- Missing `nickname` key preserves the current nickname.
- `nickname: null` intentionally clears nickname, which is useful for onboarding reset/test cleanup.
- Blank strings and whitespace-only strings return `422`.
- Emoji-containing strings return `422`.

Frontend settings now normalizes before saving and blocks mutation when no non-space nickname remains:

```tsx
const normalizedNickname = useMemo(() => normalizeNicknameForSave(nickname), [nickname])
const isNicknameValid = normalizedNickname.length >= 1

function handleSave() {
  setErrorMessage(null)
  if (!isNicknameValid) {
    pulseInvalidNickname()
    return
  }
  mutate({ nickname: normalizedNickname, occupation, instruction }, ...)
}
```

The settings input reuses the onboarding invalid animation classes, focuses the nickname input, sets `aria-invalid`, and shows the user-facing hint:

```text
한글·영문·숫자·기호 OK, 이모지는 제외돼요
```

The profile menu now resolves display identity in the same order as the rest of the app:

```tsx
const displayName = me?.nickname?.trim() || me?.email || 'guest'
```

## Why This Works

Pydantic validation runs before the update payload reaches service-layer normalization, so invalid nickname strings never become `None` by accident. The frontend mirrors the same rule before network mutation and gives the same invalid-input feedback as onboarding.

The important cross-stack invariant is:

```text
preserve: nickname key omitted
clear:    nickname is null
reject:   nickname is blank, whitespace-only, or contains emoji
display:  trimmed nickname -> email -> guest
```

## Prevention

- Keep nickname semantics explicit in both backend and frontend tests: omitted preserves, `null` clears, blank rejects, emoji rejects.
- Put backend validation in the request schema for user-controlled fields that have product-policy meaning. Service normalization alone is too late when two fields have different empty-value semantics.
- Reuse the same invalid-input feedback pattern across onboarding and settings when both surfaces enforce the same field contract.
- Add E2E coverage for identity transitions: initial email fallback, nickname saved through onboarding, sidebar/profile display changes to nickname, and email disappears from the trigger once nickname exists.
- Do not infer required-field policy from nullable storage alone. `users.nickname` can remain nullable for reset/import flows while the normal user-facing save path still requires a nonblank nickname. (session history)

## Related Issues

- Backend issue: https://github.com/heemanglee/langchain-chatbot/issues/87
- Backend PR: https://github.com/heemanglee/langchain-chatbot/pull/88
- Frontend issue: https://github.com/heemanglee/langchain-chatbot-fe/issues/92
- Frontend PR: https://github.com/heemanglee/langchain-chatbot-fe/pull/93
- Related backend personalization issue: https://github.com/heemanglee/langchain-chatbot/issues/54
- Related frontend personalization issue: https://github.com/heemanglee/langchain-chatbot-fe/issues/14
- Related frontend onboarding issue: https://github.com/heemanglee/langchain-chatbot-fe/issues/90
- Related onboarding learning: `frontend/docs/solutions/ui-bugs/nickname-onboarding-server-nickname-gate.md`

## Refresh Candidates

- `docs/superpowers/specs/2026-05-08-personalization-settings-design.md` still describes blank strings as a generic clear path. It now needs a nickname-specific exception.
- `backend/docs/superpowers/plans/2026-05-08-personalization-settings.md` still reflects the older optional/blank-normalized nickname behavior.
- `frontend/docs/superpowers/plans/2026-05-08-personalization-settings.md` predates nickname-first profile display and settings-side empty-save blink.
- `frontend/docs/superpowers/plans/2026-05-24-nickname-onboarding.md` has a correct policy note near the top, but later snippets still mention older localStorage/prefill assumptions.
