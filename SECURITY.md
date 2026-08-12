# SECURITY.md

## Secrets policy (non-negotiable)

1. **Never commit:** API keys, PATs, credentials, private keys, `auth.json`, `.env` values, session data.
2. **PATs live outside the LLM's context.** GitHub auth is handled by the `gh` CLI, which stores the token in the OS keyring (`gh auth status` confirms: `Token stored in keyring`). The agent never reads or transmits it.
3. **Least privilege:** GitHub token scopes are limited to `repo`, `read:org`, `gist` — enough for issues/PRs/commits, nothing more.
4. **Secret-bearing files found during maintenance are deleted unread.**
5. **Redaction:** any tool output that might contain secrets is redacted before it appears in reports.
6. **The repo `.gitignore` blocks known secret paths** (`.env`, `auth.json`, `state.db`, caches). If a new secret path appears, add it to `.gitignore` immediately — do not commit.

## Reporting

If a secret is ever suspected of leaking into a commit, treat it as compromised:
rotate the credential immediately, then scrub history. Never attempt to un-commit and continue using it.
