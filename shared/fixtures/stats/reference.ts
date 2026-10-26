// A line-for-line TypeScript port of the iOS stat code, used only to check
// that the expected values in datasets/ follow definitions.json. Each function
// cites the Swift it ports. If the Swift changes, this file, definitions.json
// and the datasets change in the same PR. The Swift test that reads the
// datasets is #238.

export type SessionRow = {
  id: string;
  start_time: string;
  end_time: string | null;
  status: string;
  buy_in: number;
  rebuys: number;
  add_ons: number;
  cash_out: number;
  tip_rake: number;
  tilt_level: number | null;
  energy_level: number | null;
  focus_level: number | null;
  deleted_at: string | null;
  [column: string]: unknown;
};

export type HandRow = {
  id: string;
  session_id: string;
  played_at: string;
  preflop_action: string;
  faced_3bet: boolean;
  three_bet_response: string | null;
  postflop_result: string | null;
  did_cbet: boolean | null;
  position: string;
  deleted_at: string | null;
  [column: string]: unknown;
};

export type Dataset = {
  now: string;
  time_zone: string;
  sessions: SessionRow[];
  hands: HandRow[];
};

const ms = (iso: string) => Date.parse(iso);
const ratio = (
  num: number,
  den: number,
): number | null => (den === 0 ? null : num / den);

// --- Inputs (design 9.1: tombstoned rows, and hands of a tombstoned session, are never stat inputs) ---

export function liveRows(
  d: Dataset,
): { sessions: SessionRow[]; hands: HandRow[] } {
  const sessions = d.sessions.filter((s) => s.deleted_at === null);
  const live = new Set(sessions.map((s) => s.id));
  const hands = d.hands.filter((h) =>
    h.deleted_at === null && live.has(h.session_id)
  );
  return { sessions, hands };
}

// --- Session (Session.swift:53-77) ---

// Session.status falls back to .active for an unknown raw value (Session.swift:17),
// so only "completed" counts as completed.
const isCompleted = (s: SessionRow) => s.status === "completed";
const invested = (s: SessionRow) => s.buy_in + s.rebuys + s.add_ons;
export const netProfit = (s: SessionRow) => s.cash_out - invested(s);
export const durationHours = (s: SessionRow, now: string) =>
  (ms(s.end_time ?? now) - ms(s.start_time)) / 1000 / 3600.0;
export const sessionHourly = (s: SessionRow, now: string) => {
  const h = durationHours(s, now);
  return h > 0.01 ? netProfit(s) / h : null;
};
export const sessionRoi = (
  s: SessionRow,
) => (invested(s) > 0 ? netProfit(s) / invested(s) : null);

// --- Hand flags (Hand.swift computed properties, Enums.swift PostflopResult) ---

const vpipFlag = (h: HandRow) =>
  h.preflop_action === "call" || h.preflop_action === "raise";
const pfrFlag = (h: HandRow) => h.preflop_action === "raise";
const foldedPreflop = (h: HandRow) =>
  h.preflop_action === "fold" ||
  (h.faced_3bet && h.three_bet_response === "folded");
const sawFlop = (h: HandRow) =>
  h.postflop_result !== null && h.postflop_result !== "wonPreflop";
const wentToShowdown = (h: HandRow) =>
  h.postflop_result === "wonAtShowdown" ||
  h.postflop_result === "lostAtShowdown";
const cbetOpportunity = (h: HandRow) => pfrFlag(h) && sawFlop(h);

// --- StatCalculator.swift ---

export function handStats(hands: HandRow[]) {
  const count = (f: (h: HandRow) => boolean, of = hands) => of.filter(f).length;
  const faced = hands.filter((h) => h.faced_3bet);
  const opps = hands.filter(cbetOpportunity);
  const flops = hands.filter(sawFlop);
  const showdowns = hands.filter(wentToShowdown);
  return {
    total_hands: hands.length,
    hands_folded: count(foldedPreflop),
    vpip: ratio(count(vpipFlag), hands.length),
    pfr: ratio(count(pfrFlag), hands.length),
    fold_to_3bet: ratio(
      count((h) => h.three_bet_response === "folded", faced),
      faced.length,
    ),
    cbet: ratio(count((h) => h.did_cbet === true, opps), opps.length),
    wtsd: ratio(count(wentToShowdown, flops), flops.length),
    wsd: ratio(
      count((h) => h.postflop_result === "wonAtShowdown", showdowns),
      showdowns.length,
    ),
  };
}

export function moneyStats(sessions: SessionRow[], now: string) {
  const completed = sessions.filter(isCompleted);
  const totalProfit = completed.reduce((a, s) => a + netProfit(s), 0.0);
  const totalHours = completed.reduce((a, s) => a + durationHours(s, now), 0.0);
  return {
    total_profit: totalProfit,
    sessions_played: completed.length,
    average_profit_per_session: completed.length > 0
      ? totalProfit / completed.length
      : null,
    hourly_rate: totalHours > 0.01 ? totalProfit / totalHours : null,
    total_hours_played: totalHours,
  };
}

const PLAYABLE = ["SB", "BB", "UTG", "UTG+1", "LJ", "MP", "HJ", "CO", "BTN"];

export function statsByPosition(hands: HandRow[]) {
  return PLAYABLE.flatMap((position) => {
    const at = hands.filter((h) => h.position === position);
    if (at.length === 0) return [];
    const s = handStats(at);
    return [{ position, hand_count: at.length, vpip: s.vpip, pfr: s.pfr }];
  });
}

// PlayStyleLabel.swift:40-67
export function playStyle(
  vpip: number | null,
  pfr: number | null,
): string | null {
  if (vpip === null || pfr === null) return null;
  const aggression = vpip > 0 ? pfr / vpip : 0;
  if (vpip < 0.12) return "Nit";
  if (vpip < 0.18) return aggression > 0.6 ? "Rock" : "Passive";
  if (vpip <= 0.30) return aggression > 0.6 ? "TAG" : "Passive";
  if (vpip <= 0.45) return aggression > 0.5 ? "LAG" : "Fish";
  return pfr > 0.30 ? "Maniac" : "Fish";
}

// --- TrendCalculator.swift ---

export function cumulativeBankroll(sessions: SessionRow[]) {
  const completed = sessions.filter(isCompleted).sort((a, b) =>
    ms(a.start_time) - ms(b.start_time)
  );
  if (completed.length === 0) return [];
  const points = [{
    date: completed[0].start_time,
    cumulative_profit: 0,
    session_index: 0,
  }];
  let cumulative = 0.0;
  completed.forEach((s, i) => {
    cumulative += netProfit(s);
    points.push({
      date: s.end_time ?? s.start_time,
      cumulative_profit: cumulative,
      session_index: i + 1,
    });
  });
  return points;
}

export function rollingVpipPfr(hands: HandRow[], windowSize = 20) {
  const sorted = [...hands].sort((a, b) => ms(a.played_at) - ms(b.played_at));
  if (sorted.length < windowSize) return [];
  const points = [];
  for (let i = windowSize - 1; i < sorted.length; i++) {
    const w = sorted.slice(i - windowSize + 1, i + 1);
    points.push({
      hand_index: i + 1,
      vpip: w.filter(vpipFlag).length / windowSize,
      pfr: w.filter(pfrFlag).length / windowSize,
    });
  }
  return points;
}

const DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export function profitByDayOfWeek(sessions: SessionRow[], timeZone: string) {
  const weekday = (iso: string) => {
    const name = new Intl.DateTimeFormat("en-US", {
      weekday: "short",
      timeZone,
    }).format(new Date(iso));
    return DAY_NAMES.indexOf(name) + 1;
  };
  const profit = new Map<number, number>();
  const count = new Map<number, number>();
  for (const s of sessions.filter(isCompleted)) {
    const d = weekday(s.start_time);
    profit.set(d, (profit.get(d) ?? 0) + netProfit(s));
    count.set(d, (count.get(d) ?? 0) + 1);
  }
  return DAY_NAMES.map((day_name, i) => ({
    day_name,
    day_number: i + 1,
    total_profit: profit.get(i + 1) ?? 0,
    session_count: count.get(i + 1) ?? 0,
  }));
}

export function plDistribution(sessions: SessionRow[], bucketWidth = 100) {
  const profits = sessions.filter(isCompleted).map(netProfit);
  if (profits.length === 0) return [];
  const lower = Math.floor(Math.min(...profits) / bucketWidth) * bucketWidth;
  const upper = Math.ceil(Math.max(...profits) / bucketWidth) * bucketWidth;
  if (!(upper > lower)) {
    return [{ range_label: "$0", lower_bound: 0, count: profits.length }];
  }
  const buckets = [];
  for (let current = lower; current < upper; current += bucketWidth) {
    const next = current + bucketWidth;
    const label = current >= 0
      ? `+$${Math.trunc(current)}`
      : `-$${Math.trunc(Math.abs(current))}`;
    buckets.push({
      range_label: label,
      lower_bound: current,
      count: profits.filter((p) => p >= current && p < next).length,
    });
  }
  return buckets;
}

const METRICS = [["energy", "energy_level"], ["focus", "focus_level"], [
  "tilt",
  "tilt_level",
]] as const;

// Sorted by (metric raw value, level), which puts energy, focus, tilt in that order.
export function mentalCorrelation(sessions: SessionRow[], now: string) {
  const points = [];
  for (const [metric, column] of METRICS) {
    const byLevel = new Map<number, number[]>();
    for (const s of sessions.filter(isCompleted)) {
      const level = s[column];
      const hourly = sessionHourly(s, now);
      if (level === null || hourly === null) continue;
      byLevel.set(level, [...(byLevel.get(level) ?? []), hourly]);
    }
    for (const level of [...byLevel.keys()].sort((a, b) => a - b)) {
      const rates = byLevel.get(level)!;
      points.push({
        metric,
        level,
        average_hourly_rate: rates.reduce((a, b) => a + b, 0) / rates.length,
        session_count: rates.length,
      });
    }
  }
  return points;
}

// DashboardViewModel.swift:73-79
export function mentalInsight(points: ReturnType<typeof mentalCorrelation>) {
  const tilt = points.filter((p) => p.metric === "tilt");
  const calm = tilt.find((p) => p.level === 1);
  const tilted = tilt.find((p) => p.level >= 4);
  if (!calm || !tilted || calm.session_count < 2 || tilted.session_count < 2) {
    return null;
  }
  return {
    calm_rate: calm.average_hourly_rate,
    tilted_rate: tilted.average_hourly_rate,
  };
}

// --- LeakFinder.swift ---

type Range = [number, number];
const PROFILES: Record<
  string,
  Record<string, { ideal: Range; acceptable: Range }>
> = {
  full_ring: {
    vpip: { ideal: [0.15, 0.22], acceptable: [0.12, 0.28] },
    pfr: { ideal: [0.12, 0.18], acceptable: [0.10, 0.22] },
    cbet: { ideal: [0.60, 0.75], acceptable: [0.50, 0.80] },
    fold_to_3bet: { ideal: [0.45, 0.55], acceptable: [0.35, 0.65] },
    wtsd: { ideal: [0.25, 0.32], acceptable: [0.20, 0.38] },
    wsd: { ideal: [0.50, 0.58], acceptable: [0.45, 0.62] },
  },
  six_max: {
    vpip: { ideal: [0.22, 0.30], acceptable: [0.18, 0.35] },
    pfr: { ideal: [0.18, 0.25], acceptable: [0.14, 0.28] },
    cbet: { ideal: [0.55, 0.70], acceptable: [0.45, 0.78] },
    fold_to_3bet: { ideal: [0.40, 0.55], acceptable: [0.30, 0.65] },
    wtsd: { ideal: [0.26, 0.34], acceptable: [0.22, 0.40] },
    wsd: { ideal: [0.50, 0.60], acceptable: [0.45, 0.65] },
  },
};
export const LEAK_PROFILES = PROFILES;
const STAT_KEYS = [
  "vpip",
  "pfr",
  "cbet",
  "fold_to_3bet",
  "wtsd",
  "wsd",
] as const;
const within = (v: number, [lo, hi]: Range) => v >= lo && v <= hi;

export function leakFinder(
  stats: ReturnType<typeof handStats>,
  minimumHands: number,
) {
  if (stats.total_hands < minimumHands) return null;
  const out: Record<string, unknown> = {};
  for (const [profile, ranges] of Object.entries(PROFILES)) {
    const ratings: Record<string, string> = {};
    for (const key of STAT_KEYS) {
      const v = stats[key];
      if (v === null) continue;
      const r = ranges[key];
      ratings[key] = within(v, r.ideal)
        ? "healthy"
        : within(v, r.acceptable)
        ? "borderline"
        : "leak";
    }
    const leaks = Object.values(ratings).filter((r) => r === "leak").length;
    const borderline = Object.values(ratings).filter((r) =>
      r === "borderline"
    ).length;
    const overall = leaks >= 2
      ? "Leaking"
      : leaks >= 1 || borderline >= 2
      ? "Needs Work"
      : "Solid";
    out[profile] = { ratings, overall };
  }
  return out;
}

// --- Home-screen widget (PokerStatsLifetimeWidget.swift:59-85) ---

export function widget(sessions: SessionRow[], now: string) {
  const completed = sessions.filter(isCompleted).sort((a, b) =>
    ms(b.start_time) - ms(a.start_time)
  );
  const m = moneyStats(completed, now);
  let streak = 0;
  for (const s of completed) {
    if (netProfit(s) > 0) streak += 1;
    else break;
  }
  return {
    total_profit: m.total_profit,
    sessions_played: m.sessions_played,
    hourly_rate: m.hourly_rate,
    current_streak: streak,
  };
}

// --- Everything a dataset's "expected" holds ---

export function expectedFor(d: Dataset) {
  const { sessions, hands } = liveRows(d);
  const hs = handStats(hands);
  const lifetime = {
    ...hs,
    ...moneyStats(sessions, d.now),
    fold_percent: hs.total_hands > 0 ? hs.hands_folded / hs.total_hands : null,
    play_style: playStyle(hs.vpip, hs.pfr),
  };
  const perSession = sessions.map((s) => {
    const sh = handStats(hands.filter((h) => h.session_id === s.id));
    return {
      id: s.id,
      counts_toward_money_stats: isCompleted(s),
      net_profit: netProfit(s),
      duration_hours: durationHours(s, d.now),
      hourly_rate: sessionHourly(s, d.now),
      roi: sessionRoi(s),
      ...sh,
      leak_finder: leakFinder(sh, 10),
    };
  });
  const cutoff30 = ms(d.now) - 30 * 86400 * 1000;
  const recentSessions = sessions.filter((s) => ms(s.start_time) >= cutoff30);
  const recentHands = hands.filter((h) => ms(h.played_at) >= cutoff30);
  const trends = (ss: SessionRow[], hh: HandRow[]) => ({
    session_count: ss.filter(isCompleted).length,
    cumulative_bankroll: cumulativeBankroll(ss),
    rolling_vpip_pfr: rollingVpipPfr(hh),
    profit_by_day_of_week: profitByDayOfWeek(ss, d.time_zone),
    pl_distribution: plDistribution(ss),
  });
  const mental = mentalCorrelation(sessions, d.now);
  return {
    lifetime,
    sessions: perSession,
    positions: statsByPosition(hands),
    trends: {
      all_time: trends(sessions, hands),
      last_30_days: trends(recentSessions, recentHands),
    },
    mental_correlation: mental,
    mental_insight: mentalInsight(mental),
    leak_finder: leakFinder(hs, 20),
    widget: widget(sessions, d.now),
  };
}

// --- Display (ComputedStats.swift:191-214, CurrencyFormatter.swift, SessionDetailView.swift:196-203,
// PokerStatsLifetimeWidget.swift:189-196). en_US locale. ---

// Rounds the exact binary value of x to `digits` decimals, ties to even. This is
// what printf "%.1f" does, and NumberFormatter's default rounding mode is half
// even. JavaScript's toFixed breaks ties upward, so it can't be used directly.
export function roundHalfEven(x: number, digits: number): string {
  const exact = Math.abs(x).toFixed(100); // exact for the magnitudes shown here
  const [int, frac] = exact.split(".");
  const keep = BigInt(int + frac.slice(0, digits));
  const rest = frac.slice(digits);
  const half = "5" + "0".repeat(rest.length - 1);
  let n = keep;
  if (rest > half || (rest === half && keep % 2n === 1n)) n += 1n;
  const s = n.toString().padStart(digits + 1, "0");
  const body = digits > 0 ? `${s.slice(0, -digits)}.${s.slice(-digits)}` : s;
  const negative = x < 0 && /[1-9]/.test(body);
  return (negative ? "-" : "") + body;
}

const group = (digits: string) => digits.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
const dollars = (x: number, decimals: number) => {
  const r = roundHalfEven(x, decimals);
  const neg = r.startsWith("-");
  const [i, f] = r.replace("-", "").split(".");
  return `${neg ? "-" : ""}$${group(i)}${f !== undefined ? "." + f : ""}`;
};

export function display(format: string, value: number | null): string {
  switch (format) {
    case "percent": // ComputedStats.formatPercent
      return value === null ? "--" : `${roundHalfEven(value * 100, 1)}%`;
    case "currency": // ComputedStats.formatCurrency, CurrencyFormatter.format
      return dollars(value!, 0);
    case "currency_signed": { // CurrencyFormatter.formatSigned
      const formatted = dollars(Math.abs(value!), 0);
      return value! >= 0 ? `+${formatted}` : `-${formatted}`;
    }
    case "hourly_rate": // ComputedStats.formatHourlyRate
      return value === null ? "--" : `${dollars(value, 2)}/hr`;
    case "roi": { // SessionDetailView: String(format: "%+.1f%%", roi * 100)
      const r = roundHalfEven(value! * 100, 1);
      return `${r.startsWith("-") ? "" : "+"}${r}%`;
    }
    case "widget_currency": { // PokerStatsLifetimeWidget.formatCurrency: Int() truncates
      const whole = Math.trunc(Math.abs(value!));
      return `${value! < 0 ? "-" : "+"}$${
        whole >= 1000 ? group(String(whole)) : whole
      }`;
    }
    default:
      throw new Error(`unknown display format ${format}`);
  }
}
