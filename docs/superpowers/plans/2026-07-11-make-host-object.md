# make_host_object Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `make_host_object` labelled factory so embedders create host objects (methods, accessors, intent-shaped data props, host slots) in one call returning `Value`.

**Architecture:** Thin factory in `factories.mbt` that allocates via `make_object`, then loops existing `install_builtin_*` + `set_host_slot`. Widen `install_builtin_accessor` to accept optional getter for setter-only accessors.

**Tech Stack:** MoonBit, `@js_engine/interpreter/runtime`

**Spec:** `docs/superpowers/specs/2026-07-11-make-host-object-design.md`

## Global Constraints

- Branch from `main` including #522 host-slot API
- No catch-all `~properties`; no builder; string keys only
- No root `@js_engine` facade re-export unless forced
- Prefix moon commands with `NEW_MOON_MOD=0`
- After every file edit: `NEW_MOON_MOD=0 moon check`

## File Structure

| File | Responsibility |
|---|---|
| `interpreter/runtime/builtin_install.mbt` | Widen `install_builtin_accessor` getter to `Value?` |
| `interpreter/runtime/factories.mbt` | Add `make_host_object` |
| `interpreter/runtime/host_object_wbtest.mbt` | Whitebox tests for the factory |
| `interpreter/runtime/pkg.generated.mbti` | Regenerated via `moon info` |

---

### Task 1: Sync + branch

- [ ] Rebase local main onto `origin/main` (picks up #522)
- [ ] Create branch `feat/make-host-object-517`
- [ ] Commit plan doc if not already on branch

### Task 2: Widen `install_builtin_accessor` + failing tests

**Files:**
- Modify: `interpreter/runtime/builtin_install.mbt`
- Create: `interpreter/runtime/host_object_wbtest.mbt`

- [ ] Write failing wbtests for `make_host_object` (name-only, methods, accessors, non_writable/frozen, host_slots, panic `(None,None)`, overwrite)
- [ ] Widen accessor helper: `getter : Value?`; descriptor uses `getter` as-is (`None` allowed)
- [ ] Implement `make_host_object` per spec install order
- [ ] `NEW_MOON_MOD=0 moon check && NEW_MOON_MOD=0 moon test -p interpreter/runtime --filter 'host_object'`
- [ ] `NEW_MOON_MOD=0 moon info && NEW_MOON_MOD=0 moon fmt`
- [ ] Commit

### Task 3: Finish

- [ ] Full `NEW_MOON_MOD=0 moon check && NEW_MOON_MOD=0 moon test -p interpreter/runtime`
- [ ] Hand off for PR
