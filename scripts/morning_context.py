#!/usr/bin/env python3
"""Collect last-24h session activity from Hermes state.db for the morning brief.
Emits stable, plain-text context (no timestamps in output body beyond date).
"""
import sqlite3, os, time, sys

DB = os.path.expanduser('~/.hermes/state.db')
NOW = time.time()
DAY = 86400
SINCE = NOW - DAY

def ts(t):
    return time.strftime('%H:%M', time.localtime(t)) if t else '?'

try:
    conn = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
except Exception as e:
    print(f'Morning context unavailable: {e}')
    sys.exit(0)

rows = conn.execute(
    'SELECT id, display_name, source, model, message_count, tool_call_count, '
    'input_tokens, output_tokens, reasoning_tokens, started_at, ended_at, end_reason '
    'FROM sessions WHERE started_at >= ? ORDER BY started_at DESC',
    (SINCE,)).fetchall()

print(f'Sessions started in the last 24h: {len(rows)}')
print('=' * 60)
for r in rows:
    sid, name, src, model, msgs, tools, inp, outp, reas, st, en, reason = r
    display = (name or sid)[:40]
    status = 'ACTIVE' if en is None else f'ended({reason or "?"})'
    print(f'- {display} [{src}] model={model} msgs={msgs} tools={tools}')
    print(f'    tokens: in={inp} out={outp} reasoning={reas} | {ts(st)}-{ts(en)} {status}')

tot = conn.execute(
    'SELECT COUNT(*), COALESCE(SUM(message_count),0), COALESCE(SUM(tool_call_count),0), '
    'COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0) '
    'FROM sessions WHERE started_at >= ?', (SINCE,)).fetchone()

print('=' * 60)
print(f'Totals: {tot[0]} sessions | {tot[1]} msgs | {tot[2]} tool calls | '
      f'{tot[3]} in-tok | {tot[4]} out-tok')

# OpenCode Go subscription quota (dollar-based caps: 5h=$12, 7d=$30, 30d=$60)
# 4-tuples: input, output, cache-read, cache-write ($/1M). Verified 2026-08-15 (skill ref).
GO_RATES = {
    'grok-4.5':         (2.00, 6.00, 0.30, 0.0),
    'grok-4.6':         (2.00, 6.00, 0.30, 0.0),  # GUESS ≈ grok-4.5
    'gpt-5.6-luna':     (0.20, 1.20, 0.02, 0.25),
    'glm-5':            (1.40, 4.40, 0.26, 0.0),
    'glm-5.1':          (1.40, 4.40, 0.26, 0.0),
    'glm-5.2':          (1.40, 4.40, 0.26, 0.0),
    'glm-5.3':          (1.40, 4.40, 0.26, 0.0),  # assumed GLM tier
    'glm-5.3-flash':    (1.40, 4.40, 0.26, 0.0),  # GUESS ≈ glm-5.3 (flash tier; may price lower)
    'kimi-k2.7-code':   (0.95, 4.00, 0.19, 0.0),
    'kimi-k2.6':        (0.95, 4.00, 0.19, 0.0),
    'kimi-k3':          (3.00, 15.00, 0.30, 0.0),
    'mimo-v2.5':        (0.14, 0.28, 0.0028, 0.0),
    'mimo-v2.5-pro':    (0.435, 0.87, 0.003625, 0.0),
    'minimax-m3':       (0.30, 1.20, 0.06, 0.0),
    'minimax-m2.7':     (0.30, 1.20, 0.06, 0.0),
    'minimax-m2.5':     (0.30, 1.20, 0.06, 0.0),
    'muse-spark-1.2':   (0.50, 3.00, 0.05, 0.625),  # GUESS ≈ qwen3.6-plus tier (no official rate; repo 404)
    'muse-spark-1.2-contributor': (0.50, 3.00, 0.05, 0.625),  # GUESS ≈ muse-spark-1.2
    'muse-spark-1.3-contributor': (0.50, 3.00, 0.05, 0.625),  # GUESS ≈ muse-spark-1.2-contributor
    'qwen3.8-max':      (2.00, 6.00, 0.25, 2.50),
    'qwen3.7-max':      (2.50, 7.50, 0.50, 3.125),
    'qwen3.7-plus':     (0.40, 1.60, 0.04, 0.50),
    'qwen3.6-plus':     (0.50, 3.00, 0.05, 0.625),
    'deepseek-v4-pro':  (0.435, 0.87, 0.003625, 0.0),
    'deepseek-v4-flash': (0.14, 0.28, 0.0028, 0.0),
    'deepseek-v4-flash-vision-exp': (0.14, 0.28, 0.0028, 0.0),  # GUESS ≈ deepseek-v4-flash
    'ox-alpha-free': (0.0, 0.0, 0.0, 0.0),  # GUESS: promo free model ("limited time" per opencode.ai/docs/go)
    'hy3':              (0.14, 0.58, 0.035, 0.0),
    'hy3-preview':      (0.14, 0.58, 0.035, 0.0),  # GUESS ≈ hy3
    'hy4-preview':      (0.14, 0.58, 0.035, 0.0),  # GUESS ≈ hy3
    'qwen3.8-flash':    (2.00, 6.00, 0.25, 2.50),  # GUESS ≈ qwen3.8-max (flash tier; may price lower)
    # Added 2026-08-30 by adaptive-monitor (all GUESS by sibling analogy; no official rates)
    'kimi-k2.5':        (0.95, 4.00, 0.19, 0.0),   # GUESS ≈ kimi-k2.6
    'longcat-2.0':      (1.40, 4.40, 0.26, 0.0),   # GUESS ≈ glm-5 tier (no sibling; mid-tier)
    'mimo-v2-omni':     (0.435, 0.87, 0.003625, 0.0),  # GUESS ≈ mimo-v2.5-pro (omni/multimodal)
    'mimo-v2-pro':      (0.435, 0.87, 0.003625, 0.0),  # GUESS ≈ mimo-v2.5-pro
    'qwen3.5-plus':     (0.50, 3.00, 0.05, 0.625), # GUESS ≈ qwen3.6-plus (prev gen)
    # Added 2026-09-04 by adaptive-monitor (VERIFIED from live opencode.ai/docs/go pricing table)
    'omen-alpha':       (0.20, 0.66, 0.04, 0.0),   # official: $0.20/$0.66/$0.04/-, usage $100/mo, 11,600 req/5h
}
G = []
unknown = set()
for span, cap, label in [(5 * 3600, 12.0, '5h'), (7 * DAY, 30.0, '7d'), (30 * DAY, 60.0, '30d')]:
    rows = conn.execute(
        "SELECT model, SUM(api_call_count), SUM(input_tokens), SUM(output_tokens), "
        "SUM(cache_read_tokens), SUM(cache_write_tokens) FROM session_model_usage "
        "WHERE billing_base_url LIKE '%opencode.ai/zen/go%' AND last_seen >= ? "
        "GROUP BY model", (NOW - span,)).fetchall()
    if not rows:
        continue
    cost = 0.0
    for model, c, i, o, r, w in rows:
        rate = GO_RATES.get(model)
        if rate is None:
            unknown.add(model)
            rate = GO_RATES['deepseek-v4-flash']
        cost += (i or 0) / 1e6 * rate[0] + (o or 0) / 1e6 * rate[1] + (r or 0) / 1e6 * rate[2] + (w or 0) / 1e6 * rate[3]
    G.append(f'{label}: ${cost:.4f} of ${cap:.0f} ({cost / cap * 100:.1f}%)')
if unknown:
    print('⚠ Go meter: unknown models ' + ', '.join(sorted(unknown)) + ' — add to GO_RATES')
if G:
    print(f'Go quota: {" | ".join(G)}')
conn.close()
