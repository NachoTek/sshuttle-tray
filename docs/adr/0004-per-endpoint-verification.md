# Effective state is judged per echo endpoint; a Ping Target covers the blind spots

The endpoint research (#3) recommended a 2-of-3 cross-endpoint consensus for the Baseline, assuming all echo endpoints share one network path. Under a scoped Route Set that assumption breaks: an endpoint whose resolved IP falls inside the Route Set reports the office egress while the rest report home. On this box `ifconfig.me` itself resolves to exactly the pushed `/32`, so with the Tunnel working, consensus reads 2-of-3 "still Baseline" and the icon state machine would false-Alert ~30s after every successful start. Decided: capture a **Baseline per endpoint**; the Tunnel is Effective when *any* endpoint's current answer differs from its own Baseline (self-consistent, so a flaky endpoint can only affect its own comparison — the consensus guard becomes unnecessary), and an in-scope endpoint flipping back is Revert. When the Route Set is scoped, no endpoint diverges, and no Ping Target is configured, the Tool shows **On + "unverified"** rather than Alerting — honest blindness. A configured **Ping Target** (a host inside the Route Set, `ping -4 -c1 -W2`, 60s whenever the Tunnel is active — popup open or closed — plus once on popup open, never while off) escalates to Alert after 3 consecutive failures and clears on any success.

## Considered Options

- Keep 2-of-3 consensus — rejected: actively wrong under scoped Route Sets (false Alerts, see above).
- Echo display-only under scoped sets, Ping Target as sole verification — rejected: discards authoritative evidence the endpoints already produce for free (an in-scope endpoint is the outside world confirming routing, the Tool's founding rule).

## Consequences

- The engine must track *which* host answered each sample; per-endpoint comparison replaces the merged consensus value at Baseline capture and Revert watch.
- The Ping Target is a deliberate, bounded divergence from "No-answer never evidence" (#6): sustained *active* probe failure is evidence of a defunct Tunnel; passive echo No-answer remains evidence-free. The Alert cause reads "ping target unreachable" — tunnel-dead, target-down, and office-side fault are indistinguishable unprivileged, and Alert names causes rather than guessing.
- The Remote Gateway is never probed: nothing resolves or fetches its IP (displayed as its alias only).
