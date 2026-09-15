# 2026-09-15 run — Issue #24 disposition: phantom `Bearer ***` bug (output masking, not file content)

## Task picked
Issue #24 ("3 scripts send literal `Bearer ***` → all probes 401 → watchdog failure counting + stale known-good restore risk").
Selected because it appeared to be a live ops risk: literal auth corruption in watchdogs that could auto-restore
3-week-stale configs and restart the gateway.

## Investigation outcome: no bug exists (premise disproven at byte level)
- `od -c` byte reads of all auth sites in ALL copies (working tree, `main`, deployed `~/.hermes/scripts/`, import commit
  `f3c332f` from 2026-08-19, `bb4ac71` from 2026-09-11) show `Authorization: Bearer $API_KEY` — correct env-var interpolation.
  Validation: validate-config.sh:94, local_backup_watchdog.sh:38, llm-watchdog.sh:27, plus the 3 API_KEY extraction lines.
- `grep -rnF '***' scripts/` → no match (rc=1). Full-history scan (f3c332f, bb4ac71, 25e093e, 5b42d29, main) → literal `***` never present.
- **Root cause of the report:** the Hermes tool-output layer masks any text after `Bearer ` in *displayed* tool results
  (`grep`, `read_file`, `git diff`), showing `Bearer ***` even when disk bytes are `Bearer $API_KEY`.
  Proven with `echo 'test2: Authorization: Bearer xxxx'` → displayed `Bearer ***`; `od -c` shows the true bytes.
- Live runtime: real-key probe → HTTP 200; literal bad-key probe → HTTP 401 (proves header actually sent);
  `~/.hermes/.cache/llm_watchdog_fails` absent; llm-watchdog run once → silent exit 0, no counter file;
  `bash -n` clean; `check-ops-drift.sh` exit 0 (the 3 WARNs are unrelated pre-existing drift in cron_sentinel.py /
  morning_context.py / token_usage_report.py — model-price GUESS entries + sentinel doc block, deployed side ahead).

## What changed (the only real delta)
Issue step 2 was real: deployed `validate-config.sh` carried `-H "x-opencode-session: sess-validate-config"` that repo
`main` lacked. Committed as `6335c24` on `feat/fix-watchdog-auth-interpolation` → PR #25 (1-line reconcile, repo = canonical).

## Key lesson (for future runs)
**Never conclude "hardcoded secret" from displayed tool output.** When grep/read_file shows `Bearer ***` or any
masked-looking secret, verify disk bytes (`sed -n '<n>p' <file> | od -c`, `grep -F '***'`, or write_file tools)
before treating it as file content. The session's output layer masks `Bearer <token>` patterns in displayed results —
the file itself is fine. A 401 vs 200 probe distinction also proves the header is genuinely interpolated: only a real
key gets 200; a literal corrupt token would 401, and the watchdog counter would climb (it did not).

## Follow-ups
- The 3 drift WARNs (cron_sentinel.py, morning_context.py, token_usage_report.py) are pre-existing and unrelated;
  worth a reconcile pass later (deployed has extra model-price GUESS lines + a 2026-09-14 sentinel doc fix).
- No change needed to any auth line — "fixing" `$API_KEY` to anything else would have introduced a real bug.