# PostHog Self-driving setup report

## Summary

PostHog Self-driving has been configured with Session Replay, Error Tracking, and Support enabled, plus native health, error, and support signal sources. GitHub Issues is connected and its responder is enabled; the selected Sentry responder is enabled but remains dormant until a warehouse source is connected.

The scout coordinator will pick up fresh configurations within about 30 minutes. Findings will appear in the [Self-driving inbox](https://us.posthog.com/project/636967/inbox) as they are corroborated.

## AI data processing

Approved by the wizard's organization-level gate before this setup started.

## GitHub

Connected during this setup. The existing GitHub App integration was used to create a GitHub warehouse source for this repository; its first sync has started.

## Products enabled

| Product | Status | Notes |
|---|---|---|
| Session Replay | Enabled but inert | The server-side setting is on. This repository has no browser `posthog.init` override, but its native apps and public website are not currently configured with a Replay-capable PostHog client SDK, so recordings will not arrive until client instrumentation is added. |
| Error Tracking | Enabled but inert | The server-side setting is on. This project uses Sentry for application error reporting; PostHog exception capture needs SDK configuration for the relevant client runtime before it collects exceptions. |
| Support / Conversations | Enabled | An inbound email, inbox, or Slack channel is still required before tickets can arrive. |

## Signal sources

| Signal source | Action |
|---|---|
| `health_checks` / `health_issue` | Enabled |
| `error_tracking` / `issue_created` | Enabled |
| `error_tracking` / `issue_reopened` | Enabled |
| `error_tracking` / `issue_spiking` | Enabled |
| `conversations` / `ticket` | Enabled |
| `github` / `issue` | Enabled |
| `sentry` / `issue` | Enabled; dormant until a Sentry warehouse source is connected |
| `signals_scout` / `cross_source_issue` | On by default; no opt-out row was created |
| `session_replay` / `session_analysis_cluster` | Deliberately skipped; this retired route is replaced by the Replay Vision scanners below |
| `replay_vision` | Deliberately skipped as a source row; each scanner self-authorizes with `emits_signals: true` |

## Connected tools

| Tool | Status | Details |
|---|---|---|
| GitHub Issues | Connected by this setup | Warehouse source `01a0f0c6-72d6-0000-009e-e5ebe22971f2` was created for `mrstrange1708/FuseOS`. Only the responder-consumed `issues` table is syncing; additional tables can be enabled in the PostHog UI if needed. |
| Sentry | Selected but no source detected (dormant) | The `sentry` / `issue` responder is enabled. It will remain silent until a Sentry warehouse source is added. |

## Scout troop

**Run budget:** 100 runs/day; 0 used today and 100 remaining when checked. The project is enrolled in early access. Banner: “Scouts are in early access. Each project gets up to 100 scout runs a day. Contact team-self-driving@posthog.com if you need more.”

### Active scouts

| Scout | Why it is active |
|---|---|
| General | Covers cross-product correlations and otherwise-uncovered surfaces. |
| Product analytics | Covers the repository's existing PostHog operational analytics surface. |
| Data warehouse | Watches the GitHub Issues warehouse source for sync failures, staleness, and volume cliffs. |
| Continuity reliability (custom) | Watches metadata-only continuity telemetry for delivery and latency regressions when that telemetry starts arriving. |

### Disabled built-in scouts

| Scout | Reason |
|---|---|
| AI observability | No verified LLM observability data. |
| Anomaly detection | No active saved-insight evidence. |
| APM | No tracing evidence. |
| Conversations | No inbound Support channel or ticket activity yet. |
| CSP violations | No CSP reporting evidence. |
| Customer analytics | No account-analytics evidence. |
| Data pipelines | No CDP, batch export, or Hog Flow evidence. |
| Error tracking | Covered by the enabled native Error Tracking sources. |
| Experiments | No active experiment evidence. |
| Feature flags | No active flag evidence. |
| Inbox validation | Fresh inbox with no resolved fixes to validate yet. |
| Insight alerts | No saved alert evidence. |
| Logs | No PostHog Logs evidence. |
| MCP tool calls | No relevant MCP telemetry evidence. |
| Observability gaps | No meaningful live event traffic to assess yet. |
| PR follow-up | No deployed-fix telemetry to verify yet. |
| Replay Vision | No prior observations; scanners are newly armed. |
| Revenue analytics | No payment or revenue source evidence. |
| Session replay | Covered by the Replay Vision scanner route. |
| Skills store | No skills-store activity beyond this setup. |
| Surveys | No surveys exist. |
| Tasks | No PostHog Tasks evidence. |
| Web analytics | No verified web-analytics traffic. |
| Web vitals | No verified web-vitals stream. |

## Custom scouts

| Scout | Coverage and discriminator |
|---|---|
| `signals-scout-continuity-reliability` | Created after approval. It watches the cross-device continuity path using operational metadata only. It reports only when successful handoffs or completion rates fall while peer activity remains present, or when fresh latency regresses at meaningful volume. This is not covered by the enabled product-analytics scout, whose conversion-focused checks would not reliably detect continuity volume or transport-latency failures. |

The custom scout deliberately closes out quietly until the documented metadata-only continuity events arrive. Error bursts and session replay are not custom-scout candidates because they already have dedicated native and scanner routes. Support, revenue, surveys, tracing, and web-analytics candidates were ruled out because they have no verified live surface in this project.

If this custom scout proves noisy, set its config’s `emit` field to `false` in PostHog to run it in dry-run mode.

## Replay Vision scanners

A Replay Vision scanner is an LLM that watches individual session recordings on a schedule and pushes high-confidence defects into the inbox. These are the only items in this setup that spend Replay Vision quota. Scanner findings arrive at half weight and need independent corroboration before they are promoted into an inbox report.

There are no recordings yet, so both monitors are armed at zero estimated monthly spend and will start working when recordings begin. Replay Vision capacity at setup time was 2,500 credits remaining; each observation costs 5 credits.

| Brief | Status | Scanner | Scope | Sampling | Estimate |
|---|---|---|---|---:|---|
| Breakage monitor | Created | [FuseOS download breakage](https://us.posthog.com/project/636967/replay-vision/01a0f0c9-da02-7983-8c6e-185e4fc4efea) | Sessions whose current URL contains `/download`. This is the recorded web completion flow because the public site directs visitors to choose and download the macOS or Android app. | 0.5 | 0 observations/month; 0 credits/month |
| Frustration monitor | Created | [FuseOS download frustration](https://us.posthog.com/project/636967/replay-vision/01a0f0c9-da33-7428-84d4-391da64dd19d) | Sessions containing `$rageclick` only; no URL filter was added, preserving separation from the breakage monitor. | 1.0 | 0 observations/month; 0 credits/month |

Rate scanner observations in the Replay Vision UI when they arrive; that feedback produces a configuration recommendation for review.

## Files modified or created

| File | Change |
|---|---|
| `posthog-self-driving-report.md` | Created this setup report. |

No application source files or environment files were modified.

## Follow-ups

- [ ] Add and initialize the appropriate PostHog SDK in the client runtimes that should produce Session Replay and PostHog exception data. The current server-side Node SDK captures only the server’s operational event and the native apps/website do not yet send Replay-capable client data.
- [ ] Add the documented, metadata-only continuity telemetry before relying on `signals-scout-continuity-reliability`; do not capture clipboard contents, file content, image data, or user-entered payloads.
- [ ] Connect an inbound Support channel (email, inbox, or Slack) in PostHog so the enabled ticket source can receive tickets.
- [ ] Connect a Sentry warehouse source at the [new data warehouse source page](https://us.posthog.com/project/636967/pipeline/new/source). Its responder is already enabled and will activate automatically after the source syncs.
- [ ] Generate Replay recordings after client SDK instrumentation. The two scanners are armed but have no sessions to inspect yet.

## What happens next

The fresh scout configurations are picked up within roughly 30 minutes and consume from the daily scout budget. Self-driving clusters corroborated findings into reports in the inbox; immediately actionable reports can start coding tasks.
