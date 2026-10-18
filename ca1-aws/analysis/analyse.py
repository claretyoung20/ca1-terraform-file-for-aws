#!/usr/bin/env python3
"""
CA1 - turn k6 results into report-ready tables and charts.

  # 1) Timeline of one run (any profile): 10-second buckets
  python3 analyse.py timeline ~/results/E-kill-r1
      -> timeline.csv + timeline.png (throughput, latency, errors, which instance served)

  # 2) Per-step table for a STEP run (use the same STEPS / hold as the run)
  python3 analyse.py steps ~/results/A-baseline-1i-r1 --steps 10,25,50,75,100 --hold 180
      -> steps.csv (offered vs achieved rps, p50/p95/p99, error %, per step)

  # 3) Compare several step runs (e.g. 1 vs 2 vs 3 instances)
  python3 analyse.py compare ~/results/A-baseline-1i-r1 ~/results/C-2i-r1 ~/results/C-3i-r1 \
          --labels "1 instance" "2 instances" "3 instances" --out ~/results/compare
      -> compare.csv + compare.png (p95 latency, throughput and error rate vs offered load)

Needs: pip3 install --user pandas matplotlib
"""
import argparse
import sys
from pathlib import Path

import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# Validated categorical palette (first slots, fixed order), light surface
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300"]
INK, INK2, GRID, SURFACE = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"
plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "axes.edgecolor": GRID, "axes.labelcolor": INK2, "axes.titlecolor": INK,
    "axes.titleweight": "bold", "axes.titlesize": 11, "axes.titlelocation": "left",
    "xtick.color": INK2, "ytick.color": INK2, "axes.grid": True, "grid.color": GRID,
    "grid.linewidth": 0.8, "axes.spines.top": False, "axes.spines.right": False,
    "lines.linewidth": 2, "legend.frameon": False, "font.size": 10,
})

METRICS = {"http_reqs", "http_req_duration", "http_req_failed", "dropped_iterations", "served_by"}


def load(run_dir):
    run_dir = Path(run_dir).expanduser()
    f = next((p for p in [run_dir / "raw.csv.gz", run_dir / "raw.csv"] if p.exists()), None)
    if f is None:
        sys.exit(f"No raw.csv(.gz) in {run_dir}")
    parts = []
    cols = ["metric_name", "timestamp", "metric_value", "name", "status", "extra_tags"]
    for chunk in pd.read_csv(f, usecols=lambda c: c in cols, chunksize=500_000, low_memory=False):
        parts.append(chunk[chunk["metric_name"].isin(METRICS)])
    df = pd.concat(parts, ignore_index=True)
    df["timestamp"] = pd.to_numeric(df["timestamp"])
    if df["timestamp"].max() > 1e12:            # milliseconds -> seconds
        df["timestamp"] = df["timestamp"] / 1000
    df["t"] = df["timestamp"] - df["timestamp"].min()
    return run_dir, df


def instance_of(tags):
    if not isinstance(tags, str):
        return "none"
    for kv in tags.split("&"):
        if kv.startswith("instance="):
            return kv.split("=", 1)[1]
    return "none"


def timeline(args):
    run_dir, df = load(args.run)
    b = args.bucket
    df["bucket"] = (df["t"] // b * b).astype(int)
    reqs = df[df.metric_name == "http_reqs"].groupby("bucket").size() / b
    dur = df[df.metric_name == "http_req_duration"].groupby("bucket")["metric_value"]
    fail = df[df.metric_name == "http_req_failed"].groupby("bucket")["metric_value"].mean() * 100
    out = pd.DataFrame({"achieved_rps": reqs, "p50_ms": dur.quantile(0.5), "p95_ms": dur.quantile(0.95),
                        "error_pct": fail}).fillna(0)
    sb = df[df.metric_name == "served_by"].copy()
    sb["instance"] = sb["extra_tags"].map(instance_of)
    per_inst = sb.groupby(["bucket", "instance"]).size().unstack(fill_value=0) / b
    out = out.join(per_inst.add_prefix("rps_"), how="left").fillna(0)
    out.index.name = "t_seconds"
    out.to_csv(run_dir / "timeline.csv", float_format="%.2f")

    fig, ax = plt.subplots(4, 1, figsize=(10, 11), sharex=True)
    ax[0].plot(out.index, out.achieved_rps, color=SERIES[0])
    ax[0].set_title("Throughput (requests/s completed)"); ax[0].set_ylabel("req/s")
    ax[1].plot(out.index, out.p50_ms, color=SERIES[0], label="p50")
    ax[1].plot(out.index, out.p95_ms, color=SERIES[1], label="p95")
    ax[1].set_title("Response time"); ax[1].set_ylabel("ms"); ax[1].legend(loc="upper left")
    if args.logy:
        ax[1].set_yscale("log")
    ax[2].plot(out.index, out.error_pct, color="#e34948")
    ax[2].set_title("Failed requests (non-2xx or timeout)"); ax[2].set_ylabel("% of requests")
    inst_cols = sorted([c for c in out.columns if c.startswith("rps_")], key=lambda c: c == "rps_none")
    if inst_cols:
        colours = [("#b5b3ad" if c == "rps_none" else SERIES[i % len(SERIES)]) for i, c in enumerate(inst_cols)]
        ax[3].stackplot(out.index, *[out[c] for c in inst_cols],
                        labels=[c[4:] if c != "rps_none" else "no response" for c in inst_cols], colors=colours,
                        edgecolor=SURFACE, linewidth=1)
        ax[3].legend(loc="upper left", ncol=3)
    ax[3].set_title("Which instance served the requests (X-Served-By)"); ax[3].set_ylabel("req/s")
    ax[3].set_xlabel("seconds since start of run")
    for e in args.mark or []:
        t, label = (e.split(":", 1) + [""])[:2]
        for a in ax:
            a.axvline(float(t), color=INK2, linestyle="--", linewidth=1)
        ax[0].annotate(label, (float(t), ax[0].get_ylim()[1]), xytext=(4, -12),
                       textcoords="offset points", color=INK, fontsize=9)
    fig.suptitle(args.title or run_dir.name, x=0.01, ha="left", fontweight="bold", color=INK)
    fig.tight_layout()
    fig.savefig(run_dir / "timeline.png", dpi=150)
    print(f"Wrote {run_dir/'timeline.csv'} and {run_dir/'timeline.png'}")


def q95(w, name):
    d = w[(w.metric_name == "http_req_duration") & (w.name == name)]["metric_value"]
    return round(d.quantile(0.95), 1) if len(d) else None


def err(w, name):
    f = w[(w.metric_name == "http_req_failed") & (w.name == name)]["metric_value"]
    return round(f.mean() * 100, 2) if len(f) else None


def step_table(run_dir, df, steps, hold, ramp, skip):
    rows = []
    for i, rate in enumerate(steps):
        start = i * (ramp + hold) + ramp + skip
        end = (i + 1) * (ramp + hold)
        w = df[(df.t >= start) & (df.t < end)]
        d = w[w.metric_name == "http_req_duration"]["metric_value"]
        n = (w.metric_name == "http_reqs").sum()
        dropped = w[w.metric_name == "dropped_iterations"]["metric_value"].sum()
        f = w[w.metric_name == "http_req_failed"]["metric_value"]
        rows.append({"offered_rps": rate, "achieved_rps": round(n / (end - start), 1),
                     "p50_ms": round(d.quantile(0.5), 1) if len(d) else None,
                     "p95_ms": round(d.quantile(0.95), 1) if len(d) else None,
                     "p99_ms": round(d.quantile(0.99), 1) if len(d) else None,
                     "error_pct": round(f.mean() * 100, 2) if len(f) else None,
                     "p95_get_ms": q95(w, "GET /products"), "p95_post_ms": q95(w, "POST /products"),
                     "post_error_pct": err(w, "POST /products"),
                     "dropped_iterations": int(dropped), "window_s": f"{start}-{end}"})
    return pd.DataFrame(rows)


def steps(args):
    run_dir, df = load(args.run)
    table = step_table(run_dir, df, [float(s) for s in args.steps.split(",")], args.hold, args.ramp, args.skip)
    table.to_csv(run_dir / "steps.csv", index=False)
    print(table.to_string(index=False))
    print(f"\nWrote {run_dir/'steps.csv'}")


def compare(args):
    labels = args.labels or [Path(r).name for r in args.runs]
    if len(labels) != len(args.runs):
        sys.exit("--labels must have one label per run")
    frames = []
    for run, label in zip(args.runs, labels):
        run_dir, df = load(run)
        t = step_table(run_dir, df, [float(s) for s in args.steps.split(",")], args.hold, args.ramp, args.skip)
        t.insert(0, "config", label)
        frames.append(t)
    allt = pd.concat(frames, ignore_index=True)
    out = Path(args.out).expanduser(); out.mkdir(parents=True, exist_ok=True)
    allt.to_csv(out / "compare.csv", index=False)
    print(allt.to_string(index=False))

    fig, ax = plt.subplots(1, 3, figsize=(15, 4.6))
    for i, label in enumerate(labels):
        t = allt[allt.config == label]
        kw = dict(color=SERIES[i % len(SERIES)], marker="o", markersize=6, label=label)
        ax[0].plot(t.offered_rps, t.p95_ms, **kw)
        ax[1].plot(t.offered_rps, t.achieved_rps, **kw)
        ax[2].plot(t.offered_rps, t.error_pct, **kw)
    mx = allt.offered_rps.max()
    ax[1].plot([0, mx], [0, mx], color=INK2, linestyle=":", linewidth=1, label="ideal (achieved = offered)")
    ax[0].set_title("p95 response time"); ax[0].set_ylabel("ms")
    ax[1].set_title("Throughput achieved"); ax[1].set_ylabel("req/s")
    ax[2].set_title("Failed requests"); ax[2].set_ylabel("% of requests")
    for a in ax:
        a.set_xlabel("offered load (req/s)")
        a.set_ylim(bottom=0)
    ax[1].legend(loc="upper left")
    fig.suptitle(args.title or "Same workload, different Product capacity", x=0.01, ha="left",
                 fontweight="bold", color=INK)
    fig.tight_layout()
    fig.savefig(out / "compare.png", dpi=150)
    print(f"\nWrote {out/'compare.csv'} and {out/'compare.png'}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    t = sub.add_parser("timeline"); t.add_argument("run")
    t.add_argument("--bucket", type=int, default=10, help="bucket size in seconds")
    t.add_argument("--mark", nargs="*", help='vertical markers, e.g. "180:instance terminated"')
    t.add_argument("--logy", action="store_true", help="log scale for response time (when spikes hide detail)")
    t.add_argument("--title"); t.set_defaults(fn=timeline)

    for name, fn in (("steps", steps), ("compare", compare)):
        p = sub.add_parser(name)
        if name == "steps":
            p.add_argument("run")
        else:
            p.add_argument("runs", nargs="+"); p.add_argument("--labels", nargs="+")
            p.add_argument("--out", default="compare"); p.add_argument("--title")
        p.add_argument("--steps", default="10,25,50,75,100", help="must match the run's STEPS")
        p.add_argument("--hold", type=int, default=180, help="seconds each step was held (STEP_DURATION)")
        p.add_argument("--ramp", type=int, default=15)
        p.add_argument("--skip", type=int, default=30, help="seconds ignored at the start of each step (settling)")
        p.set_defaults(fn=fn)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
