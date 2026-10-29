# Closing the ops-drift loop: actionable exit code + explicit reconcile mode (issue #38)

**Date:** 2026-10-14
**Scope:** `scripts/check-ops-drift.sh`, `scripts/test-check-ops-drift.sh`, `scripts/morning_context.py`, `scripts/token_usage_report.py`, `docs/ARCHITECTURE.md`

## What happened

Ops-script reconciliation between the canonical repo `scripts/` and the deployed
`~/.hermes/scripts/` has now been the selected daily-loop task four times (#22 on 2026-09-07,
#28, #36/#37 on 2026-10-13, and again today). Each recurrence had the same shape: a live
writer (the Go adaptive monitor's run, or a manual live edit) changed **only** the deployed
copy, and the repo fell behind by a `GO_RATES` row or two. The recurrence itself is the bug —
`check-ops-drift.sh` detected the drift every time but could not be acted on without manual
`diff`/`cp` work, and its WARN path had **no exit-code effect** (rc stayed 0), so nothing
automated could notice.

Today's instigating drift: the deployed copies held two `GO_RATES` rows absent from the repo,
inserted after the `claude-haiku-5-5` row (repo `morning_context.py:60`,
`token_usage_report.py:36`):

- `'gemini-4-argon-contributor': (0.10, 0.20, 0.002, 0.0)`
- `'ling-3.1-flash-free': (0.0, 0.0, 0.0, 0.0)`

Both ids were checked against the live catalogs before import: `gemini-4-argon` (free,
`zen/v1`) and `gemini-4-argon-contributor` (paid, `zen/go/v1`) exist; **no `ling-*` id exists
on either endpoint** — the row is deliberately retained as legacy so historical usage rows
still price correctly.

## Change

Implemented via `opencode` (spec inlined with `opencode run "$(cat spec)"`), reviewed by hand:

1. **Part A — parity:** the two deployed-only rows were imported into the repo, byte-exact, so
   `check-ops-drift.sh` reports `OK` for both files (`cmp`-identical to the deployed copies).
2. **Part B — make drift actionable:**
   - content drift now exits **3** (was 0), `--help` exists and prints the exit-code table,
     bad usage exits **64**;
   - each `WARN:` line now prints the two exact repair commands;
   - `--reconcile --toward=repo|deployed [--apply]` plans by default (dry run, `PLAN:` lines)
     and only copies when `--apply` is given, then rescans and reports the real rc;
   - guard rails: `--toward` is mandatory in reconcile mode, `--apply` without `--reconcile`
     is rejected, and reconcile refuses empty or `/`-resolving directories.
   - `REPO_SCRIPTS`/`HERMES_SCRIPTS` now use `${VAR-default}` instead of `${VAR:-default}` so an
     explicitly-empty env var (used by the test harness) is honoured rather than silently
     replaced.

## Verification

- `bash scripts/test-check-ops-drift.sh` → **12 passed, 0 failed** (added scenarios for
  `--help`, exit 3, usage error 64 both directions, dry-run no-op, apply both directions,
  no-drift reconcile, missing jobs.json→2).
- `bash scripts/check-ops-drift.sh` → rc **0**, zero WARNs (both `GO_RATES` files `OK`).
- `python3 -m py_compile scripts/morning_context.py scripts/token_usage_report.py` → clean.
- No caller outside the repo depends on the old exit-code contract (grep over
  `~/.hermes/scripts/` and `~/.hermes/cron/jobs.json` found no `check-ops-drift` reference), so
  introducing exit 3 is safe; the scripts themselves are not cron-referenced.

## Lessons

1. **A detector that cannot be acted on is toil.** The drift check was correct for months and
   the same reconcile task kept being selected, because detection had no exit-code signal and
   no one-command repair. When the same chore recurs, automate the repair path — not just the
   observation.
2. **Raise the exit code, but check the callers first.** Changing `0`→`3` for a
   previously-silent warning is a breaking interface change; grep every caller (including
   `jobs.json` `script`/`monitor_script` values) before shipping it.
3. **Dry-run by default, direction mandatory.** A reconcile tool that guesses the direction
   silently corrupts whichever side is wrong. `--toward=` required + `--apply` opt-in + copy
   guard rails keeps the one destructive operation explicit. Direction must follow verified
   truth (this time deployed→repo was correct for the rate rows).
4. **`${VAR:-default}` vs `${VAR-default}` is a testability decision.** The `:-` form makes it
   impossible to test the "empty directory" branch via env override; switching to `-` was
   required for the new guard-rail scenarios.
5. **`opencode` respects `/tmp` permissions strictly.** At the end of the run it tried to clean
   up its own `/tmp/ops-drift-live.out` and was auto-rejected (`permission requested:
   external_directory (/tmp/*); auto-rejecting`) — the task itself had already completed
   (rc 0), so a trailing permission rejection in the log is not a failure.

## Review follow-up

The review hardening is now complete: script-name validation rejects unsafe names; copies are
atomic and checked; the reverse-direction apply test really copies changed content; the exit
contract is restored with hard errors taking precedence over drift; reconcile errors return a
failure; rescans use an in-process-safe resolved path; symlink destinations are refused; dirty
repo worktrees produce a warning; the usage table and `${VAR:-default}` handling are consistent;
and coverage now includes usage, malformed jobs, unsafe names, and error-versus-drift precedence.

One limitation is deliberately accepted: `gemini-4-argon-contributor` has a documented GUESS
price tuple mirroring `muse-spark-1.3-contributor` (verified to be the same tuple), because the
model is absent from the docs pricing table. It must be corrected through the reconcile tool,
not by hand.

`morning_context.py` defines only `GO_RATES`, `GO_MODEL_MONTHLY`, and `MODEL_ALIASES`;
`PER_MODEL_REQ_CAPS`, `DEFAULT_MODEL`, and `CRON_MODEL` exist only in `token_usage_report.py`.
Every rate/cap lookup in both files is `.get()`-defaulted except
`PER_MODEL_REQ_CAPS[DEFAULT_MODEL]`, `PER_MODEL_REQ_CAPS[CRON_MODEL]`, and
`PER_MODEL_REQ_CAPS['deepseek-v4-pro']`; all three keys are defined, so the new rows cannot
raise `KeyError`.

## 2026-10-16 — parity refresh + atomic landing of #39 and #40

The recurrence fired one level deeper on the next run: the 08:02 live writer had put three more
free `GO_RATES` rows into **both** deployed meter scripts — `beam-free`, `glm-5.3-flash-free`,
`ll-alpha-free` (all new 2026-10-16) — and marked `cat-jam-free` as removed from the free/zen/go
catalogs. The repo was behind on both files, so `check-ops-drift.sh` exited **3 against `main`**
before any merge of this branch: exactly the signal the issue asked for, now actionable.

- Repo copies refreshed from the deployed side with the tool this issue added:
  `check-ops-drift.sh --reconcile --toward=repo --apply` → both files `OK`, overall rc **0**,
  `cmp` byte-identical.
- `docs/ARCHITECTURE.md` carries #40's `default` alias row (`deepseek-v4.1-flash`), and the
  deployed copies already contained #40's re-denomination (cap $80 / 34,670 req-5h,
  `DEFAULT_MODEL` / `CRON_MODEL`, `agent-main` alias), so both PRs' content ships in one diff.
- #39 and #40 touch the same two files, so they were landed as **one squash merge** on
  `feat/38-ops-drift-loop`; #40 was closed as superseded by #39 rather than merged separately.

## Lessons (2026-10-16)

1. **The drift source is a live writer on a schedule.** A catalogue job rewrites the deployed
   meter tables at 08:02, so repo→deployed parity is a *daily* chore, not a one-off. That is why
   the repair path (one command, explicit direction, dry run by default) was the right fix.
2. **Two PRs editing the same files cannot be merged atomically on separate branches.** Merging
   #39 first leaves `main` in the exit-3 drift state between the two merges. Landing the pair on a
   single branch and squash-merging once is the only way to avoid a transient red state.
3. **Verify the *live* side before believing a parity claim.** A previous run's "byte-identical"
   sync was already stale hours later; parity must be re-checked against `~/.hermes/scripts/` at
   landing time, not trusted from the branch's commit message.

## 2026-10-29 — issue #41: reconcile hardening nits + parity refresh

The 08:02 catalogue writer fired again (fifth recurrence: `#22`, `#28`, `#36/#37`, `#39`,
2026-10-29), so the checker was already doing its job on `main`: `rc=3` with
`morning_context.py` and `token_usage_report.py` both `WARN`. Same repair path, one command:

```
check-ops-drift.sh --reconcile --toward=repo --apply   # → both OK, rc 0, cmp identical
```

Content reconciled this round (`12 insertions(+), 2 deletions(-)`), independently re-verified
against the live Go pricing table at `https://opencode.ai/docs/go`:

- New rows: `gemini-4-argon` $2.00/$10.00/$0.10 (50%-off promo of $4.00/$20.00/$0.20; $30 monthly
  limit), `kimi-k3.1-pro` $2.00/$10.00/$0.20/$2.00 ($15 limit), `minimax-m3.1-flash`
  $0.15/$0.60/$0.015 (no cache-write; $20 limit), `iceman-contributor-free` — see the finding below.
- `ll-alpha-free` re-commented as REMOVED from the free tier/zen on 2026-10-16 (≈6h lifespan);
  the zero-cost row is retained so historical usage rows still price correctly.

### Nits from the #39 review — outcome

| Nit | Outcome |
| --- | --- |
| 1. `--reconcile --toward=repo --apply` only *warned* on a dirty worktree | **Fixed.** Now refuses with exit 1 and copies nothing; `--force` opts in. Check runs once, hoisted above the copy loop. |
| 2. `--quiet --reconcile` still printed the "nothing to reconcile" INFO | **Fixed.** `--quiet` suppresses `OK:`/`INFO:`; `WARN:`/`ERROR:` always print (a quiet run must never hide a failure). |
| 3. Dirty-worktree check ran once per drifted file | **Fixed** by the same hoist as nit 1. |
| 4. `check-ops-drift.sh` + `test-check-ops-drift.sh` are repo-only | **Deferred, by design.** Nothing references them from cron, so there is no drift risk today. Deploying them is a live-environment write and stays part of the approval-gated follow-up. |
| 5. `gemini-4-argon-contributor` carries a GUESS tuple | **Kept as a documented heuristic.** Still absent from the docs pricing table; it mirrors `muse-spark-1.3-contributor` ($0.10/$0.20/$0.002) because contributor tier is discounted for training rights. Treat as an estimate, not a billed number. |

Harness grew from 18 to 24 assertions, all passing: refusal on a dirty worktree (exit 1, drifted
file byte-unchanged), `--force` on a dirty worktree (exit 0, file equals deployed), `--force`
rejected without a reconcile target (64) and with `--toward=deployed` (64), clean-worktree apply
still succeeding, and `--quiet` reconcile on a clean tree printing no `INFO:`.

### Finding beyond the issue: `iceman-contributor-free` is not a free-tier model

The reconciled row prices it `(0.0, 0.0, 0.0, 0.0)` with the comment "Free / Unlimited (limited
time); also on zen/go paid catalog". Two independent checks disagree:

- `opencode models` lists it **only** as `opencode-go/iceman-contributor-free`; the free tier
  (`opencode/…`) has 8 models and none of them is `iceman`.
- The `https://opencode.ai/docs/go` page does not mention it at all, and the first real request to
  it was rejected with *"This Go model trains on request data. Allow paid endpoints that train on
  request data…"* — i.e. it is a contributor model gated behind the training-privacy setting, the
  same class as the priced `muse-spark-*-contributor` rows.

A `0.0` rate on a model that is probably billed **under-reports** spend, which is the one failure
direction a quota meter must not have. It is deliberately **not** changed here: correcting a live
rate changes reported dollars and therefore model-routing decisions, the same approval-gated class
as the durable writer fix. Filed as a follow-up issue with the evidence above; until it is
resolved, treat `iceman-contributor-free` usage as unpriced (hidden) spend.

### Still blocked on explicit user approval

The durable fix — make the writer repo-aware, or single-source `GO_RATES` so the two meter scripts
cannot diverge from the repo — changes live cron behaviour and is untouched. This note is the
record of the decision needed: **either** teach the 08:02 writer to write through the repo (then
deploy), **or** move `GO_RATES` into one imported module so there is a single copy to reconcile.

