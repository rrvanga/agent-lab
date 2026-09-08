#!/usr/bin/env bash
# Daily skills-vault sync: stage → scrub PII → guard → commit (if changed) → push.
# Cron no_agent contract: EMPTY stdout when nothing changed (silent); non-empty = report;
# non-zero exit = error alert. Never pushes PII (scrubber exits 2 → we abort).
set -uo pipefail

SKILLS_SRC="$HOME/.hermes/skills"
VAULT="$HOME/dev/skills-vault"
STAGE="/tmp/skills-vault-stage"
SCRUB="$HOME/.hermes/scripts/skills_vault_scrub.py"
LOG="$HOME/.hermes/scripts/skills_vault.log"

# 1. stage a fresh copy (rsync excludes stay conservative; scrubber also skips binaries)
rm -rf "$STAGE"
mkdir -p "$STAGE"
rsync -a --exclude '.hub' --exclude '.git' --exclude '.DS_Store' --exclude '*.db' \
      --exclude '*.gpg' --exclude '.env*' --exclude '.curator*' \
      "$SKILLS_SRC/" "$STAGE/skills/"

# 2. redact + guard (exit 2 = PII remains → abort, never push)
if ! "$SCRUB" "$STAGE/skills" "$STAGE/skills-scrubbed"; then
    echo "VAULT HALTED: PII guard failed — nothing synced. Inspect $HOME/.hermes/scripts/skills_vault_pii.txt"
    exit 2
fi

# 3. present the sanitized tree to git
cd "$VAULT" || exit 1
rm -rf skills
mv "$STAGE/skills-scrubbed" skills
rm -rf "$STAGE"

git add -A 2>>"$LOG"

# 4. silent exit if nothing changed
if git diff --cached --quiet; then
    exit 0
fi

# 5. commit + push with a real summary
COUNT=$(git diff --cached --name-only | wc -l)
git commit -q -m "vault sync: $(date -u +%Y-%m-%dT%H:%MZ) — $COUNT file(s)" 2>>"$LOG"
if ! git push -q origin main 2>>"$LOG"; then
    echo "VAULT ALERT: push FAILED — see $LOG"
    exit 1
fi

# name-only relative to skills/ for readability
CHANGED=$(git diff --cached --name-only HEAD~1 2>/dev/null | head -8 || true)
echo "🗂 Skills vault synced (+/-$COUNT file(s))${CHANGED:+: $CHANGED}" | head -c 500
echo ""
echo "   https://github.com/rrvanga/skills-vault"