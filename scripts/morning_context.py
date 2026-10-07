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
# Go pricing ($ per 1M tokens): input, output, cache_read, cache_write.
# VERIFIED 2026-09-19 from the live Go pricing table (opencode.ai/docs, page
# "Last updated: Sep 19, 2026") - supersedes the 2026-08-11 copy. Corrections that
# mattered: glm-5.3-flash and qwen3.8-flash were priced ~9-13x too HIGH (meter
# overcounted), longcat-2.0 ~4.7x high, muse-spark * ~5x high, hy4-preview ~6x LOW,
# and every DeepSeek model was undercounted (output 2.1x, pro cache-read 6x).
# DeepSeek models now bill PEAK/OFF-PEAK (peak = 01:00-04:00 + 06:00-10:00 UTC,
# Mon-Fri; weekends always off-peak). session_model_usage keeps only first/last_seen
# aggregates, so per-call tiering is impossible: DeepSeek entries below are
# time-weighted blends (0.792 off-peak + 0.208 peak) so the meter
# is neither optimistic nor inflated. Exact pairs are in DS_PEAK_TIERS.
GO_RATES = {
    # --- non-tiered, verified 2026-09-19 ---
    'glm-5.3-flash':    (0.15, 0.50, 0.03, 0.0),      # $60/mo, 6320 req/5h
    'glm-5.3':          (1.40, 4.40, 0.26, 0.0),      # $15/mo, only 220 req/5h
    'glm-5.2':          (1.40, 4.40, 0.26, 0.0),      # $60/mo
    'glm-5.1':          (1.40, 4.40, 0.26, 0.0),      # $60/mo
    'glm-5':            (1.40, 4.40, 0.26, 0.0),      # GUESS ~ glm-5.1
    'kimi-k3':          (3.00, 15.00, 0.30, 0.0),     # $15/mo, only 110 req/5h
    'kimi-k2.7-code':   (0.95, 4.00, 0.19, 0.0),      # $60/mo
    'kimi-k2.6':        (0.95, 4.00, 0.16, 0.0),      # $60/mo
    'kimi-k2.5':        (0.95, 4.00, 0.16, 0.0),      # GUESS ~ kimi-k2.6
    'longcat-2.0':      (0.30, 1.20, 0.006, 0.0),     # $60/mo, 11400 req/5h
    'longcat-2.5-preview-free': (0.0, 0.0, 0.0, 0.0),   # free preview 09-26; gated 403 outside OpenCode; also on zen/go paid catalog
    'mimo-v2.5':        (0.14, 0.28, 0.0028, 0.0),    # $60/mo, 30100 req/5h
    'mimo-v2.5-pro':    (0.435, 0.87, 0.003625, 0.0), # $15/mo
    'mimo-v2.6-flash':   (0.14, 0.28, 0.0028, 0.0),    # verified 09-22 live docs; ~mimo-v2.5; $60/mo, 30100 req/5h
    'mimo-v2.6-pro':     (0.435, 0.87, 0.003625, 0.0), # verified 09-22 live docs; ~mimo-v2.5-pro; $15/mo
    'mimo-v2-pro':      (0.435, 0.87, 0.003625, 0.0), # GUESS ~ mimo-v2.5-pro
    'mimo-v2-omni':     (0.435, 0.87, 0.003625, 0.0), # GUESS ~ mimo-v2.5-pro
    'minimax-m3':       (0.30, 1.20, 0.06, 0.0),      # $60/mo
    'minimax-m2.7':     (0.30, 1.20, 0.06, 0.375),    # $60/mo
    'minimax-m2.5':     (0.30, 1.20, 0.06, 0.375),    # $60/mo
    'muse-spark-1.3-contributor': (0.10, 0.20, 0.002, 0.0),  # $60/mo, 45300 req/5h; trains on your data
    'muse-spark-1.2-contributor': (0.10, 0.20, 0.002, 0.0),  # $60/mo; trains on your data
    'qwen3.8-max':      (2.00, 6.00, 0.25, 2.50),     # $15/mo
    'qwen3.8-flash':    (0.15, 0.47, 0.016, 0.20),    # $30/mo, 5400 req/5h
    'qwen3.7-max':      (2.50, 7.50, 0.50, 3.125),    # $30/mo
    'qwen3.7-plus':     (0.40, 1.60, 0.04, 0.50),     # $60/mo; >256K tokens: 1.20 / 4.80 / 0.12 / 1.50
    'qwen3.6-plus':     (0.50, 3.00, 0.05, 0.625),    # $60/mo
    'qwen3.5-plus':     (0.50, 3.00, 0.05, 0.625),    # GUESS ~ qwen3.6-plus
    'hy3':              (0.14, 0.58, 0.035, 0.0),     # $60/mo
    'hy3-preview':      (0.14, 0.58, 0.035, 0.0),     # GUESS ~ hy3
    'hy4-preview':      (0.834, 2.501, 0.042, 0.0),   # $30/mo
    'gpt-5.6-luna':     (0.20, 1.20, 0.02, 0.25),     # <=272K tier; >272K tokens: 0.40 / 1.80 / 0.04 / 0.50; $15/mo
    'gpt-6-luna':       (0.10, 0.50, 0.01, 0.125),    # <=272K: 0.10/0.50/0.01/0.125; >272K: 0.20/0.75/0.02/0.25; $15/mo
    'grok-4.6':         (2.00, 6.00, 0.50, 0.0),      # <=200K tier; >200K tokens: 4.00 / 12.00 / 1.00; $15/mo
    'grok-4.7':         (2.00, 6.00, 0.50, 0.0),      # verified 09-22 live docs; <=200K tier; >200K tokens: 4.00 / 12.00 / 1.00; $15/mo, 169 req/5h
    'grok-4.5':         (2.00, 6.00, 0.50, 0.0),      # GUESS ~ grok-4.6; legacy: absent from live catalog 2026-10-06, kept for historical rows
    'omen-alpha':       (0.20, 0.66, 0.04, 0.0),      # promo model, not on the pricing table
    'union-alpha':      (0.20, 0.66, 0.04, 0.0),      # GUESS ~ omen-alpha
    'ox-alpha-free':    (0.0, 0.0, 0.0, 0.0),         # promo free
    'space-bunny-free': (0.0, 0.0, 0.0, 0.0),         # free (limited time), 09-23 docs; also on zen/go paid catalog
    # --- DeepSeek: peak/off-peak blend (see DS_PEAK_TIERS for exact pairs) ---
    'deepseek-v4-flash':            (0.18125, 0.725, 0.003625, 0.0),   # $30/mo, 13000 req/5h
    'deepseek-v4.1-flash':          (0.18125, 0.725, 0.003625, 0.0),   # $60/mo, 26000 req/5h — verified 2026-10-06 (promo EXTENDED; old note expected drop to $15 on 09-20)
    'deepseek-flash':               (0.18125, 0.725, 0.003625, 0.0),   # GUESS ~ deepseek-v4-flash; legacy: absent from live catalog 2026-10-06, kept for historical rows
    'deepseek-v4-flash-vision-exp': (0.18125, 0.725, 0.003625, 0.0),   # $15/mo
    'deepseek-v4-pro':              (0.7975, 2.3925, 0.026583, 0.0),   # $15/mo, 1050 req/5h
}

# Exact DeepSeek tiers: model -> (off_peak, peak), each (input, output, cache_read).
DS_PEAK_TIERS = {
    'deepseek-v4-flash':            ((0.15, 0.60, 0.003), (0.30, 1.20, 0.006)),
    'deepseek-v4.1-flash':          ((0.15, 0.60, 0.003), (0.30, 1.20, 0.006)),
    'deepseek-v4-flash-vision-exp': ((0.15, 0.60, 0.003), (0.30, 1.20, 0.006)),
    'deepseek-v4-pro':              ((0.66, 1.98, 0.022), (1.32, 3.96, 0.044)),
}

# Per-model monthly usage limits (USD), verified 2026-10-06. NOTE: the old single
# pool ($12/5h, $30/7d, $60/30d) is no longer how Go works - each model has its own
# limit, split 20% / 5h, 50% / 7d, 100% / 30d. The bucket math below still uses the
# legacy pool line for continuity; the per-model read-out at the end uses THIS table.
# Go Plus ($40/mo, higher per-model limits) exists; these limits are the base Go $10/mo plan.
GO_MODEL_MONTHLY = {
    'glm-5.3-flash': 60, 'glm-5.3': 15, 'glm-5.2': 60,
    'glm-5.1': 60,  # legacy: absent from live catalog 2026-10-06, kept for historical rows
    'kimi-k3': 15, 'kimi-k2.7-code': 60, 'kimi-k2.6': 60,
    'longcat-2.0': 60, 'mimo-v2.5': 60, 'mimo-v2.5-pro': 15, 'mimo-v2.6-flash': 60, 'mimo-v2.6-pro': 15,
    'minimax-m3': 60, 'minimax-m2.7': 60,
    'minimax-m2.5': 60,  # legacy: absent from live catalog 2026-10-06, kept for historical rows
    'muse-spark-1.3-contributor': 60, 'muse-spark-1.2-contributor': 60,
    'qwen3.8-max': 15, 'qwen3.8-flash': 30,
    'qwen3.7-max': 30,  # legacy: absent from live catalog 2026-10-06, kept for historical rows
    'qwen3.7-plus': 60,  # live 2026-10-06
    'qwen3.6-plus': 60,  # legacy: absent from live catalog 2026-10-06, kept for historical rows
    'deepseek-v4.1-flash': 60, 'deepseek-v4-pro': 15,
    'deepseek-v4-flash': 30, 'deepseek-v4-flash-vision-exp': 15,
    'hy4-preview': 30, 'hy3': 60, 'grok-4.6': 15, 'grok-4.7': 15, 'gpt-5.6-luna': 15, 'gpt-6-luna': 15,
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
        model = MODEL_ALIASES.get(model, model)
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


# Per-model read-out (read-only; changes no routing). The pool line above divides by
# the legacy $12/$30/$60 shared bucket, which flatters any lane that is actually near
# its own ceiling - each Go model has its own limit (20% / 5h, 50% / 7d, 100% / 30d).
def _pm_costs(span):
    out = {}
    rows = conn.execute(
        "SELECT model, SUM(api_call_count), SUM(input_tokens), SUM(output_tokens), "
        "SUM(cache_read_tokens), SUM(cache_write_tokens) FROM session_model_usage "
        "WHERE billing_base_url LIKE '%opencode.ai/zen/go%' AND last_seen >= ? "
        "GROUP BY model", (NOW - span,)).fetchall()
    for model, c, i, o, r, w in rows:
        m = MODEL_ALIASES.get(model, model)
        rate = GO_RATES.get(m) or GO_RATES['deepseek-v4-flash']
        out[m] = out.get(m, 0.0) + (i or 0) / 1e6 * rate[0] \
            + (o or 0) / 1e6 * rate[1] + (r or 0) / 1e6 * rate[2] \
            + (w or 0) / 1e6 * rate[3]
    return out


_c30, _c7, _c5 = _pm_costs(30 * DAY), _pm_costs(7 * DAY), _pm_costs(5 * 3600)
lanes = []
for model, cost in _c30.items():
    cap = GO_MODEL_MONTHLY.get(model)
    if not cap:
        continue
    p5 = _c5.get(model, 0.0) / (cap * 0.20) * 100
    p7 = _c7.get(model, 0.0) / (cap * 0.50) * 100
    p30 = cost / cap * 100
    lanes.append((max(p5, p7, p30), model, cost, cap, p5, p7, p30))
if lanes:
    lanes.sort(key=lambda L: -L[0])
    print('Per-model 30d: ' + ' | '.join(
        f'{m} ${c:.2f}/{cap:.0f} ({p30:.1f}%)' for _, m, c, cap, _, _, p30 in lanes))
    worst, m, cost, cap, p5, p7, p30 = lanes[0]
    flag = '🔴' if worst >= 80 else ('⚠️' if worst >= 50 else '·')
    print(f'{flag} nearest ceiling: {m} — 5h {p5:.1f}% | 7d {p7:.1f}% | 30d {p30:.1f}% '
          f'(cap ${cap:.0f}/mo)')
conn.close()
