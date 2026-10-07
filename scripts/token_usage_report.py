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
    'space-bunny-free': (0.0, 0.0, 0.0, 0.0),         # legacy: absent from live catalog 2026-10-07, kept for historical rows (superseded by paid 'space-bunny')
    'space-bunny':      (0.15, 0.60, 0.03, 0.0),      # PAID, live 2026-10-07 docs: $0.15 in / $0.60 out / $0.03 cache-read per M; $30/mo; 3130 req/5h
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
# limit, split 20% / 5h, 50% / 7d, 100% / 30d. Captured here for the meter redesign;
# Not yet used by the LEGACY shared-pool bucket math below.
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
    'space-bunny': 30,  # live 2026-10-07: $30/mo (base Go), 3130 req/5h
}
GO_CAPS = [(5 * HOUR, 12.0), (7 * DAY, 30.0), (30 * DAY, 60.0)]
GO_DEFAULT_RATE = GO_RATES['deepseek-v4-flash']  # unknown models: priced cheap AND reported

# Per-model request caps (requests / 5 hours) VERIFIED 2026-09-19 against the live
# opencode.ai/docs/go "Estimated requests" table. Three entries were badly wrong
# (they held older/larger figures — flash 63,300 vs the real 13,000, i.e. the meter's
# denominator was 4.9x too generous, which reads as "plenty of headroom" when there
# isn't). Promotional and changeable; still not live-fetched.
PER_MODEL_REQ_CAPS = {
    'glm-5.3-flash': 6320,
    'glm-5.3': 220,
    'glm-5.2': 880,
    'glm-5.1': 880,
    'kimi-k3': 110,
    'kimi-k2.7-code': 1350,
    'kimi-k2.6': 1150,
    'longcat-2.0': 11400,
    'mimo-v2.5': 30100,
    'mimo-v2.5-pro': 3250,
    'mimo-v2.6-flash': 30100,
    'mimo-v2.6-pro': 3250,
    'minimax-m3': 3200,
    'minimax-m2.7': 3400,
    'muse-spark-1.3-contributor': 45300,
    'muse-spark-1.2-contributor': 45300,
    'qwen3.8-max': 160,
    'qwen3.8-flash': 5400,
    'qwen3.7-max': 170,
    'qwen3.7-plus': 4300,
    'qwen3.6-plus': 3300,
    'deepseek-v4.1-flash': 26000,   # $60/mo, 26000 req/5h — verified 2026-10-06 (promo EXTENDED; old note expected drop to 6500)
    'deepseek-v4-pro': 1050,
    'deepseek-v4-flash': 13000,
    'deepseek-v4-flash-vision-exp': 6500,
    'hy4-preview': 1350,
    'hy3': 4300,
    'grok-4.6': 169,
    'grok-4.7': 169,
    'grok-4.5': 169,                # GUESS ~ grok-4.6 (no doc row); legacy: absent from live catalog 2026-10-06, kept for historical rows
    'gpt-5.6-luna': 2050,
    'gpt-6-luna': 4230,
    'space-bunny': 3130,            # live 2026-10-07, base-Go estimated-requests table
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


def per_model_cost(since):
    """{model: implied $} for Go traffic since `since` (aliases applied).

    Go limits are PER MODEL (20% / 5h, 50% / 7d, 100% / 30d of that model's
    monthly figure), not a shared $12/$30/$60 pool — so bucket % under-counts
    whenever traffic concentrates in one lane.
    """
    rows = conn.execute(
        "SELECT model, SUM(api_call_count), SUM(input_tokens), SUM(output_tokens), "
        "SUM(cache_read_tokens), SUM(cache_write_tokens) FROM session_model_usage "
        "WHERE billing_base_url LIKE '%opencode.ai/zen/go%' AND last_seen >= ? "
        "GROUP BY model", (since,)).fetchall()
    costs = {}
    for model, c, i, o, r, w in rows:
        m = MODEL_ALIASES.get(model, model)
        rate = GO_RATES.get(m) or GO_DEFAULT_RATE
        costs[m] = costs.get(m, 0.0) + (i or 0) / 1e6 * rate[0] \
            + (o or 0) / 1e6 * rate[1] + (r or 0) / 1e6 * rate[2] \
            + (w or 0) / 1e6 * rate[3]
    return costs


def per_model_quota_line():
    """Each lane against its OWN cap; names the lane nearest its ceiling.

    Read-out only — changes no routing. Sub-window caps are 20% (5h) and 50%
    (7d) of the monthly figure, per the Go docs.
    """
    months = per_model_cost(NOW - 30 * DAY)
    if not months:
        return None
    h5 = per_model_cost(NOW - 5 * HOUR)
    d7 = per_model_cost(NOW - 7 * DAY)
    uncapped = []
    lanes = []
    for m, cost in months.items():
        cap = GO_MODEL_MONTHLY.get(m)
        if not cap:
            uncapped.append(m)
            continue
        h5v = h5.get(m, 0.0)
        d7v = d7.get(m, 0.0)
        lanes.append({
            'model': m, 'cost': cost, 'cap': cap,
            'p30': cost / cap * 100,
            'p7': d7v / (cap * 0.50) * 100,
            'p5': h5v / (cap * 0.20) * 100,
        })
    if not lanes:
        return None
    for L in lanes:
        L['worst'] = max(L['p5'], L['p7'], L['p30'])
    lanes.sort(key=lambda L: -L['worst'])
    shown = ' · '.join(
        f'{L["model"]} ${L["cost"]:.2f}/{L["cap"]:.0f} ({L["p30"]:.1f}%)' for L in lanes)
    top = lanes[0]
    mark = '🔴' if top['worst'] >= 80 else ('⚠️' if top['worst'] >= 50 else '·')
    head = f'Per-model 30d: {shown}'
    near = (f'  {mark} nearest ceiling: {top["model"]} — 5h {top["p5"]:.1f}% · '
            f'7d {top["p7"]:.1f}% · 30d {top["p30"]:.1f}% (cap ${top["cap"]:.0f}/mo)')
    return head, near, uncapped


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
    """Per-model req/5h burn vs caps, plus a one-line recommendation.

    Returns (line, uncapped): uncapped lists the models whose 5h request burn
    would otherwise be silently dropped for lack of a PER_MODEL_REQ_CAPS entry.
    """
    burn = per_model_req(NOW - 5 * HOUR)
    if not burn:
        return None, []
    shown = []
    uncapped = []
    for m, c in sorted(burn.items(),
                       key=lambda kv: -(kv[1] / PER_MODEL_REQ_CAPS.get(kv[0], 1))):
        cap = PER_MODEL_REQ_CAPS.get(m)
        if not cap:
            uncapped.append(m)
            continue
        pct = c / cap * 100
        shown.append(f'{m}: {c}/{cap} ({pct:.0f}%)')
    if not shown:
        return None, sorted(uncapped)
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
    return 'Req/5h: ' + ', '.join(shown) + f' → {rec}', sorted(uncapped)


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

r, r_uncapped = req_quota_line()
if r:
    out.append(f'  {r}')
if r_uncapped:
    out.append('  ⚠ no req/5h cap known (add to PER_MODEL_REQ_CAPS): '
               + ', '.join(r_uncapped))

pm = per_model_quota_line()
if pm:
    head, near, uncapped = pm
    out.append(f'  {head}')
    out.append(near)
    if uncapped:
        out.append('  ⚠ no monthly cap known (add to GO_MODEL_MONTHLY): '
                   + ', '.join(uncapped))

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
