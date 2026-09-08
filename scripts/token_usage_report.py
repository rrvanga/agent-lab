#!/usr/bin/env python3
"""Token usage report from Hermes state.db (session_model_usage) — human-readable.
Zero-LLM cron script: prints a short friendly summary for Telegram delivery.
Empty output = nothing to report.

Quota math: Go subscription is billed in DOLLAR BUCKETS ($12/5h, $30/wk, $60/mo),
enforced server-side with no public quota API. state.db estimated_cost is $0 for Go,
so this script's token->$ math (GO_RATES below) IS the quota meter — keep the rate
table complete! Any model missing here is silently priced at flash rate (~5-20x
undercount) and the bucket %s lie low. See skill reference
ai-coding-subscription-limits/references/opencode-go-quota.md (verified 2026-08-11).
"""
import sqlite3, os, time, sys

DB = os.path.expanduser('~/.hermes/state.db')
NOW = time.time()
DAY = 86400
HOUR = 3600

# Go subscription pricing ($ per 1M tokens): input, output, cache_read, cache_write
# From opencode.ai/docs/go via anomalycha/opencode repo go.mdx (verified 2026-08-11).
# Buckets: 5h=$12, 7d=$30, 30d=$60. 4-tuple: cache_write=0.0 where not charged.
GO_RATES = {
    'grok-4.5':          (2.00, 6.00, 0.30, 0.0),
    'grok-4.6':          (2.00, 6.00, 0.30, 0.0),  # GUESS ≈ grok-4.5
    'gpt-5.6-luna':      (0.20, 1.20, 0.02, 0.25),
    'glm-5':             (1.40, 4.40, 0.26, 0.0),
    'glm-5.1':           (1.40, 4.40, 0.26, 0.0),
    'glm-5.2':           (1.40, 4.40, 0.26, 0.0),
    'glm-5.3':           (1.40, 4.40, 0.26, 0.0),
    'glm-5.3-flash':     (1.40, 4.40, 0.26, 0.0),  # GUESS ≈ glm-5.3 (flash tier; may price lower)
    'kimi-k3':           (3.00, 15.00, 0.30, 0.0),
    'kimi-k2.7-code':    (0.95, 4.00, 0.19, 0.0),
    'kimi-k2.6':         (0.95, 4.00, 0.19, 0.0),
    'mimo-v2.5':         (0.14, 0.28, 0.0028, 0.0),
    'mimo-v2.5-pro':     (0.435, 0.87, 0.003625, 0.0),
    'minimax-m3':        (0.30, 1.20, 0.06, 0.0),
    'minimax-m2.7':      (0.30, 1.20, 0.06, 0.0),
    'minimax-m2.5':      (0.30, 1.20, 0.06, 0.0),
    'muse-spark-1.2':    (0.50, 3.00, 0.05, 0.625),  # GUESS ≈ qwen3.6-plus tier (no official rate; repo 404)
    'muse-spark-1.2-contributor': (0.50, 3.00, 0.05, 0.625),  # GUESS ≈ muse-spark-1.2
    'muse-spark-1.3-contributor': (0.50, 3.00, 0.05, 0.625),  # GUESS ≈ muse-spark-1.2-contributor
    'qwen3.8-max':       (2.00, 6.00, 0.25, 2.50),
    'qwen3.7-max':       (2.50, 7.50, 0.50, 3.125),
    'qwen3.7-plus':      (0.40, 1.60, 0.04, 0.50),
    'qwen3.6-plus':      (0.50, 3.00, 0.05, 0.625),
    'deepseek-v4-pro':   (0.435, 0.87, 0.003625, 0.0),
    'deepseek-v4-flash': (0.14, 0.28, 0.0028, 0.0),
    'deepseek-v4-flash-vision-exp': (0.14, 0.28, 0.0028, 0.0),  # GUESS ≈ deepseek-v4-flash
    'ox-alpha-free': (0.0, 0.0, 0.0, 0.0),  # GUESS: promo free model ("limited time" per opencode.ai/docs/go)
    'hy3':               (0.14, 0.58, 0.035, 0.0),
    'hy3-preview':       (0.14, 0.58, 0.035, 0.0),  # GUESS ≈ hy3
    'hy4-preview':       (0.14, 0.58, 0.035, 0.0),  # GUESS ≈ hy3
    'qwen3.8-flash':     (2.00, 6.00, 0.25, 2.50),  # GUESS ≈ qwen3.8-max (flash tier; may price lower)
    # Added 2026-08-30 by adaptive-monitor (all GUESS by sibling analogy; no official rates)
    'kimi-k2.5':         (0.95, 4.00, 0.19, 0.0),   # GUESS ≈ kimi-k2.6
    'longcat-2.0':       (1.40, 4.40, 0.26, 0.0),   # GUESS ≈ glm-5 tier (no sibling; mid-tier)
    'mimo-v2-omni':      (0.435, 0.87, 0.003625, 0.0),  # GUESS ≈ mimo-v2.5-pro (omni/multimodal)
    'mimo-v2-pro':       (0.435, 0.87, 0.003625, 0.0),  # GUESS ≈ mimo-v2.5-pro
    'qwen3.5-plus':      (0.50, 3.00, 0.05, 0.625), # GUESS ≈ qwen3.6-plus (prev gen)
    # Added 2026-09-04 by adaptive-monitor (VERIFIED from live opencode.ai/docs/go pricing table)
    'omen-alpha':        (0.20, 0.66, 0.04, 0.0),   # official: $0.20/$0.66/$0.04/-, usage $100/mo, 11,600 req/5h
}
GO_CAPS = [(5 * HOUR, 12.0), (7 * DAY, 30.0), (30 * DAY, 60.0)]
GO_DEFAULT_RATE = GO_RATES['deepseek-v4-flash']  # unknown models: priced cheap AND reported

# Per-model request caps (requests / 5 hours) from opencode.ai/go (2026-08-14).
# These are promotional/changeable — not live-fetched. The recommendation only
# watches the default + cron models.
PER_MODEL_REQ_CAPS = {
    'grok-4.5': 120,
    'kimi-k3': 110,
    'qwen3.8-max': 160,
    'glm-5.2': 880,
    'minimax-m3': 3200,
    'deepseek-v4-pro': 3450,
    'gpt-5.6-luna': 4100,
    'qwen3.7-plus': 4300,
    'hy3': 4300,
    'mimo-v2.5': 30100,
    'deepseek-v4-flash': 63300,
}
# Gateway model strings that actually route to the default model (config.yaml aliases).
MODEL_ALIASES = {
    'agent-main': 'deepseek-v4-flash',
    'default': 'deepseek-v4-flash',
    'pro': 'deepseek-v4-pro',
    'code': 'kimi-k2.7-code',
    'glm': 'glm-5.2',
    'max': 'qwen3.8-max',
}
DEFAULT_MODEL = 'deepseek-v4-flash'
CRON_MODEL = 'deepseek-v4-flash'


def ts(t):
    return time.strftime('%a %b %d, %H:%M', time.localtime(t)) if t else '?'


def human(n):
    """1234567 -> '1.2M', 512000 -> '512K', 42 -> '42'."""
    n = n or 0
    if n >= 1e9:
        return f'{n / 1e9:.1f}B'
    if n >= 1e6:
        return f'{n / 1e6:.1f}M'
    if n >= 1e3:
        return f'{n / 1e3:.0f}K'
    return str(int(n))


try:
    conn = sqlite3.connect(f'file:{DB}?mode=ro', uri=True)
except Exception as e:
    print(f'📊 Token usage: unavailable ({e})')
    sys.exit(0)


def summary(since):
    """One line per model (URLs merged): calls, in, out, cached."""
    rows = conn.execute(
        'SELECT model, SUM(api_call_count), SUM(input_tokens), SUM(output_tokens), '
        'SUM(cache_read_tokens), SUM(cache_write_tokens) '
        'FROM session_model_usage WHERE last_seen >= ? '
        'GROUP BY model ORDER BY SUM(api_call_count) DESC',
        (since,)).fetchall()
    if not rows:
        return None
    calls = inp = outp = cached = 0
    models = []
    for m, c, i, o, r, w in rows:
        calls += c or 0
        inp += i or 0
        outp += o or 0
        cached += (r or 0) + (w or 0)
        models.append(m)
    return calls, inp, outp, cached, ', '.join(models)


def go_quota(since):
    """Implied $ cost of Go traffic since `since`, or (None, []).

    Returns (cost, unknown_models): unknown models are priced at flash rate
    and surfaced so GO_RATES can be completed instead of silently undercounting.
    """
    rows = conn.execute(
        "SELECT model, SUM(api_call_count), SUM(input_tokens), SUM(output_tokens), "
        "SUM(cache_read_tokens), SUM(cache_write_tokens) FROM session_model_usage "
        "WHERE billing_base_url LIKE '%opencode.ai/zen/go%' AND last_seen >= ? "
        "GROUP BY model", (since,)).fetchall()
    if not rows:
        return None, []
    cost = 0.0
    unknown = []
    for model, c, i, o, r, w in rows:
        rate = GO_RATES.get(model)
        if rate is None:
            rate = GO_DEFAULT_RATE
            unknown.append(model)
        cost += (i or 0) / 1e6 * rate[0] + (o or 0) / 1e6 * rate[1] \
            + (r or 0) / 1e6 * rate[2] + (w or 0) / 1e6 * rate[3]
    return cost, sorted(set(unknown))


def quota_line():
    """e.g. 'Go quota: 5h: 1.8% · 7d: 12.2% · 30d: 6.1% used' with bucket alarms."""
    parts = []
    unknown_all = set()
    for span, cap in GO_CAPS:
        cost, unknown = go_quota(NOW - span)
        unknown_all |= set(unknown)
        if cost is None:
            continue
        label = '5h' if span == 5 * HOUR else ('7d' if span == 7 * DAY else '30d')
        pct = cost / cap * 100
        if pct < 0.1:
            parts.append(f'{label}: <0.1%')
        else:
            parts.append(f'{label}: {pct:.1f}%')
    if not parts:
        return None, []
    worst = max(float(p.split(': ')[1].rstrip('%').replace('<', '0')) for p in parts)
    line = 'Go quota: ' + ' · '.join(parts) + ' used'
    if worst >= 80:
        line = '🔴 ' + line + ' — NEAR CAP: switch heavy work to flash/free tier'
    elif worst >= 50:
        line = '⚠️ ' + line + ' — easing toward cap'
    return line, sorted(unknown_all)


def per_model_req(since):
    """{canonical_model: api_call_count} for Go traffic since `since`."""
    rows = conn.execute(
        "SELECT model, SUM(api_call_count) FROM session_model_usage "
        "WHERE billing_base_url LIKE '%opencode.ai/zen/go%' AND last_seen >= ? "
        "GROUP BY model", (since,)).fetchall()
    burn = {}
    for m, c in rows:
        m = MODEL_ALIASES.get(m, m)
        burn[m] = burn.get(m, 0) + (c or 0)
    return burn


def req_quota_line():
    """Per-model req/5h burn vs caps, plus a one-line recommendation."""
    burn = per_model_req(NOW - 5 * HOUR)
    if not burn:
        return None
    shown = []
    for m, c in sorted(burn.items(),
                       key=lambda kv: -(kv[1] / PER_MODEL_REQ_CAPS.get(kv[0], 1))):
        cap = PER_MODEL_REQ_CAPS.get(m)
        if not cap:
            continue
        pct = c / cap * 100
        shown.append(f'{m}: {c}/{cap} ({pct:.0f}%)')
    if not shown:
        return None
    dp = burn.get(DEFAULT_MODEL, 0) / PER_MODEL_REQ_CAPS[DEFAULT_MODEL] * 100
    cp = burn.get(CRON_MODEL, 0) / PER_MODEL_REQ_CAPS[CRON_MODEL] * 100
    pp = burn.get('deepseek-v4-pro', 0) / PER_MODEL_REQ_CAPS['deepseek-v4-pro'] * 100
    if dp >= 80:
        rec = f'🔴 flash at {dp:.0f}% — switch to glm-5.2 or wait for 5h window'
    elif dp >= 50:
        rec = f'flash at {dp:.0f}% — lean on glm-5.2 for bulk'
    elif pp >= 50:
        rec = f'pro at {pp:.0f}% — use flash for bulk'
    else:
        rec = f'no change (flash {dp:.0f}%, pro {pp:.0f}%)'
    return 'Req/5h: ' + ', '.join(shown) + f' → {rec}'


out = [f'📊 Token usage · {ts(NOW)}']

for label, span in [('24h', DAY), ('7d', 7 * DAY)]:
    s = summary(NOW - span)
    if s is None:
        out.append(f'  {label}: no usage')
        continue
    calls, inp, outp, cached, models = s
    parts = [f'{human(calls)} calls', f'{human(inp)} in', f'{human(outp)} out']
    if cached:
        parts.append(f'{human(cached)} cached')
    out.append(f'  {label}: ' + ', '.join(parts))

q, unknown = quota_line()
if q:
    out.append(f'  {q}')
    if unknown:
        out.append(f'  ⚠ unknown models priced at flash rate (update GO_RATES): {", ".join(unknown)}')

r = req_quota_line()
if r:
    out.append(f'  {r}')

# Kanban board state (durable task queue). Read-only; one line, silent if empty.
try:
    kconn = sqlite3.connect(f'file:{os.path.expanduser("~/.hermes/kanban.db")}?mode=ro', uri=True)
    counts = dict(kconn.execute(
        "SELECT status, COUNT(*) FROM tasks GROUP BY status").fetchall())
    kconn.close()
    kline = ' · '.join(f'{s} {counts[s]}' for s in
                       ('ready', 'running', 'blocked', 'done') if counts.get(s))
    if kline:
        out.append(f'  🗂 Kanban: {kline}')
except Exception:
    pass  # board unavailable — report stays clean

conn.close()
print('\n'.join(out))
