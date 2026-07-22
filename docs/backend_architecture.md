# 3I Backend Architecture

Sơ đồ toàn hệ thống, database và các sequence flow nằm tại
[`system_architecture.md`](system_architecture.md).

## Implementation status

The deployable backend in `backend/` owns OAuth, token custody, webhook
ingestion, activity backfill/delete/update, detail hydration, tracked activity
finalization, current leaderboard aggregates, Cloud Tasks, and scheduled
reconciliation. Flutter now submits final tracked activities through the API
and only reads `leaderboardEntries`; Kèo claim/finalization remains client-owned.

## Decision

3I will move Strava ownership and trusted derived data out of Flutter into a
stateless backend deployed on Cloud Run.

Use one Go codebase with two independently deployed Cloud Run services:

- `runnow-api`: public HTTPS entrypoint for Strava OAuth callbacks and webhooks;
  authenticated app endpoints verify Firebase ID tokens.
- `runnow-worker`: private service invoked only by Cloud Tasks and Cloud Scheduler
  using OIDC service-account tokens.

Flutter continues to read Firestore directly for realtime UI. Live tracking can
continue writing throttled snapshots directly to Firestore. Final tracked
activities, Strava data, leaderboard aggregates, and contract state become
backend-owned.

This is simpler and safer than GKE or an always-on worker, while giving webhook,
backfill, retry, and reconciliation workloads more control than putting the
same logic back into Flutter or rebuilding it as many unrelated functions.

## Migration Baseline

The findings below explain why the backend was introduced. Items 1-4 and 6-8
have been addressed by the current backend cutover; Kèo ownership in item 5 is
the remaining major migration boundary.

### Confirmed design problems

1. The Strava client secret is compiled into every Flutter build
   (`lib/src/config.dart`). OAuth exchange, refresh, API reads, and per-user
   tokens are all owned by the client (`lib/src/strava_client.dart`). The web
   flow is therefore both exposed and dependent on browser CORS behavior.
2. App startup automatically starts a Strava sync
   (`lib/src/app.dart`, `_AuthenticatedSessionState`). This makes startup
   latency, rate limits, contract refresh, and UI state depend on Strava.
3. Activity detail hydration also calls Strava from the viewer's device
   (`FirestoreStravaActivityRepository._loadDetail`). A public member viewing an
   activity cannot reliably hydrate it using the owner's credentials.
4. Leaderboard aggregation is client-owned. A refresh reads the user's entire
   activity history and writes `leaderboardEntries/{uid}`. Firestore Rules also
   allow the user to write their own leaderboard entry, so it is not trusted
   competition data.
5. Kèo progress, participant maps, activity claims, finalization, and duplicate
   claim migration are client transactions. This is increasingly difficult to
   make correct under concurrent users and webhook-driven activity updates.
6. `stravaLinks/{athleteId}` is readable by every signed-in user and written by
   clients. Athlete-to-user uniqueness is a server invariant and belongs in a
   server-only collection.
7. Google logout currently marks Strava disconnected. Authentication logout and
   integration revocation are different operations; a user should remain
   connected after logging back into the same Firebase account.
8. Incremental sync stops when a page contains no Firestore changes, even when
   Strava returned a full page. This can skip later pages. The backend migration
   must not carry this termination rule forward.

### External product constraint

Kèo and leaderboard use Strava-derived data in a competitive context. Before a
public rollout, product must obtain Strava Developer Program review and confirm
that the exact Kèo mechanics comply with the current API Agreement. Backend
migration improves technical compliance and quota usage, but does not by itself
approve the product use case.

### What remains correctly owned by Flutter/Firebase clients

- Firebase Authentication and obtaining the Firebase ID token.
- Firestore listeners and cached/offline reads for UI.
- GPS sampling, local draft recovery, and immediate tracking UI.
- Throttled live-location snapshots during a run.
- Direct image upload to Firebase Storage under owner-scoped Storage Rules.
- Explicit user choice of which activity is assigned to a Kèo. The backend
  validates and persists the choice; it must not auto-assign sessions.

## Invariants

1. One Firebase UID may be linked to only its previously locked Strava athlete.
2. One Strava athlete may be linked to at most one Firebase UID.
3. Only the backend stores or refreshes Strava access/refresh tokens.
4. Strava webhook payloads are notifications, not trusted activity data. The
   worker fetches canonical data from Strava before writing activity fields.
5. Event processing is idempotent and safe for duplicates, retries, and
   out-of-order delivery.
6. Strava is authoritative when a Strava run overlaps a 3I tracked session by
   more than the product threshold. Deleting that Strava activity can restore
   the 3I session as official.
7. Activity summary changes may update stats. Hydrating streams/photos must not
   recompute leaderboard or Kèo progress.
8. An activity is never applied to a Kèo without an explicit user claim.
9. Opening the app never starts a Strava poll. Firestore remains available when
   Strava or the backend is temporarily unavailable.

## Runtime Topology

```text
Flutter / Web
  | Firebase ID token
  v
runnow-api (Cloud Run, public ingress)
  |- POST /v1/strava/authorization
  |- GET  /v1/strava/callback
  |- POST /v1/strava/disconnect
  |- POST /v1/strava/webhook
  |- POST /v1/activities/tracked
  |- POST /v1/activities/{id}/hydrate
  `- POST /v1/contracts/{id}/claims
          |
          v
      Cloud Tasks
       |- strava-events       (high priority, rate limited)
       |- strava-backfill     (low priority, rate limited)
       |- derived-data        (no Strava calls)
          |
          v
runnow-worker (Cloud Run, private ingress)
  |- POST /tasks/strava-event
  |- POST /tasks/backfill-page
  |- POST /tasks/hydrate-activity
  |- POST /tasks/rebuild-derived-data
  `- POST /tasks/reconcile-connections
          |
          v
 Firestore / Firebase Storage / Strava API

Cloud Scheduler --OIDC--> runnow-worker reconciliation endpoint
```

Use Cloud Run Jobs only for operator-triggered full migrations or rebuilding
all users. Normal webhook and per-user work belongs in Cloud Tasks because it
needs per-item retries, deduplication, and dispatch-rate control.

## Backend Stack

- Go 1.26 with two small compiled binaries.
- Standard `net/http` routing; the endpoint surface does not justify a framework.
- Firebase Admin SDK for ID-token verification and Firestore/Storage access.
- Typed request structs plus explicit boundary validation.
- Google Cloud Tasks client for durable work dispatch.
- `net/http` wrapped by a dedicated `StravaGateway` with request timeouts.
- Go tests for domain and handler logic; Firestore Emulator for integration tests.
- One Docker image with separate API and worker entrypoints.

NestJS and GKE are not justified for the current team/product size. Cloud
Functions would work technically, but it recreates a deployment model the
project already decided not to own and gives less explicit API/worker
boundaries.

## Data Ownership

### Server-only collections

No client Rules grant access to these collections.

```text
stravaConnections/{uid}
  uid
  athleteId
  accessToken
  refreshToken
  expiresAt
  scopes[]
  status: connecting|backfilling|active|revoked|error
  lastWebhookAt
  lastReconciledAt
  backfillCursor
  tokenVersion

stravaAthleteLinks/{athleteId}
  uid
  linkedAt

integrationEvents/{eventKey}
  provider: strava
  objectType
  objectId
  ownerId
  aspectType
  eventTime
  payloadHash
  status: queued|processing|processed|ignored|failed
  attempts
  lastErrorCode

syncRuns/{runId}
  uid
  type: initial_backfill|webhook|reconcile|manual_rebuild
  status
  counters
  startedAt
  completedAt
```

Per-user tokens belong in server-only Firestore, not Secret Manager. Secret
Manager stores application-level values such as `STRAVA_CLIENT_SECRET`, webhook
verify token, and encryption/KMS configuration. Creating one Secret Manager
secret per athlete would add cost and operational complexity without improving
the product invariant.

### User activity documents

Keep the existing path so Flutter migration is small:

```text
users/{uid}/activities/{activityId}
  source: strava|runnow
  sourceActivityId
  summary fields
  detail/streams hydration state
  sourceEventTime
  officialState: official|below_minimum|superseded|deleted
  supersededByActivityId
  aggregateVersion
  updatedBy: backend|tracking_client
```

Strava deletes should normally become tombstones before eventual retention
cleanup. A tombstone prevents an older delayed `create` event from resurrecting
the activity.

### Derived data

```text
users/{uid}/stats/current
  rollingSevenDays
  currentWeek
  currentMonth
  lifetime
  records
  period keys
  sourceRevision

users/{uid}/statsPeriods/{periodKey}
  type: week|month
  summary
  sourceRevision

leaderboardEntries/{uid}
  public profile snapshot
  rollingSevenDays
  currentWeek
  currentMonth
  sourceRevision
```

The dashboard should read one stats document plus a paginated recent-activity
query. It should no longer stream 500 activities to calculate all cards.
`leaderboardEntries` becomes backend-write-only.

Kèo stays in `runContracts/{contractId}` initially, but all mutations that
change participants, claims, progress, or final status move behind API
transactions. Large participant/activity histories should later move out of the
single contract document into subcollections; this is not required for the
current small Club.

## Critical Flows

### Connect Strava

1. Flutter calls `POST /v1/strava/authorization` with a Firebase ID token.
2. API verifies the token, creates a random one-use OAuth state with a short
   TTL, and returns the Strava authorization URL.
3. Strava redirects to the HTTPS backend callback, not directly to Flutter.
4. API consumes the OAuth state transactionally and exchanges the code.
5. In one Firestore transaction, enforce both UID-to-athlete lock and
   athlete-to-UID uniqueness, then persist the latest returned refresh token.
6. Set connection state to `backfilling`, enqueue page 1, and redirect to an
   allowlisted app/web return URL.
7. Backfill tasks page through Strava until the API returns fewer than the page
   size. An unchanged page is not a termination condition.
8. Mark `active`, enqueue derived-data rebuild, and let Firestore update UI.

### Webhook

1. Validation GET checks the verify token and echoes `hub.challenge`.
2. Event POST validates schema and expected subscription ID.
3. Build a deterministic event key from subscription, owner, object, aspect,
   event time, and update hash.
4. Create a named Cloud Task. Existing task/event is treated as success.
5. Return HTTP 200 within Strava's two-second requirement.
6. Worker maps `owner_id` to UID, refreshes token under transaction/version
   control, and processes create/update/delete/deauthorization.
7. Worker writes normalized activity data and enqueues derived-data work only
   when summary fields that affect official eligibility or stats changed.

Multiple refresh workers must not overwrite a newer rotated refresh token.
Use a Firestore transaction with `tokenVersion`; retry the Strava request with
the winning token when a concurrent refresh loses the transaction.

### Reconciliation

Webhook delivery is not a complete historical synchronization protocol.
Cloud Scheduler invokes a private endpoint every six hours:

- enqueue connected users in bounded batches;
- fetch a small recent Strava window;
- repair missing creates/updates/deletes where detectable;
- refresh stale period keys;
- record a `syncRun` for operator visibility.

Manual "repair sync" is an authenticated backend operation. It is not executed
automatically on app startup.

### Activity details and streams

- Webhook create/update fetches canonical activity detail once.
- Initial backfill stores summary/detail without fetching every historical
  stream.
- `POST /v1/activities/{id}/hydrate` deduplicates a hydration task. Flutter
  receives `202` and watches the existing Firestore document.
- Only the owner can request new Strava hydration. Public viewers may read
  already-hydrated Firestore data but cannot consume the owner's Strava quota.
- Streams/photos hydration never updates stats or leaderboard revisions.

### 3I tracked activities and overlap

The tracking screen remains local-first. On Finish:

1. Flutter persists its recovery draft until submission succeeds.
2. Flutter submits the normalized final activity to the authenticated backend.
3. Backend validates owner, minimum distance, timestamps, and payload limits.
4. Backend queries nearby Strava intervals and assigns `officialState`.
5. A later Strava webhook may supersede the 3I session; a Strava delete may
   restore it. Both paths enqueue the same derived-data recalculation.
6. Flutter uploads photos directly, then submits photo metadata tied to the
   activity and nearest accepted route point.

Live tracking remains a separate ephemeral path and is not used as official
activity data until Finish succeeds.

### Kèo

- New activities only become selectable candidates; they are never
  automatically claimed.
- `POST /v1/contracts/{id}/claims` transactionally enforces one activity -> one
  Kèo per user and recalculates that participant's progress.
- If a claimed 3I activity is superseded by Strava, backend migrates the claim
  idempotently and recalculates progress.
- Scheduler finalizes due Kèo after the grace period. Opening the app is not a
  finalization trigger.

## Failure and Retry Rules

- `2xx`: task complete or safely ignored.
- `400/404` from validated task data: terminal, record failure, return `2xx` to
  stop poison retries.
- `401` from Strava: refresh once; repeated failure marks connection `error` or
  `revoked` and stops retries.
- `429`: return retryable response and honor rate-limit/reset headers; keep
  webhook and backfill queues separate so backfill cannot starve fresh events.
- `5xx`/network: retry with exponential backoff and bounded attempts.
- Exhausted tasks write a terminal event status and emit an alertable metric.
- Every handler logs JSON fields: `requestId`, `taskName`, `eventKey`, `uid`,
  `athleteId`, `activityId`, `attempt`, `latencyMs`, and result code. Never log
  tokens or full Strava payloads.

## Security Boundary

- Flutter sends `Authorization: Bearer <Firebase ID token>`; API verifies it
  with Firebase Admin and derives UID from the verified token.
- Worker endpoints require Cloud Run IAM and OIDC from dedicated task/scheduler
  service accounts.
- API and worker use separate least-privilege service accounts.
- OAuth `state` is random, one-use, short-lived, and bound to UID plus an
  allowlisted return target.
- The webhook has no activity trust: validate subscription ID, rate-limit the
  endpoint, deduplicate, then fetch canonical data from Strava.
- Remove client write access to leaderboard aggregates and athlete-link maps as
  each backend phase takes ownership.
- Rotate the currently exposed Strava client secret after backend cutover. Do
  not merely remove it from the latest Git commit; it has already shipped and
  may exist in Git history/build artifacts.

## Migration Plan

### Phase 0 - Foundation, no product behavior change

1. Add `backend/` Go module, Dockerfile, emulator configuration, CI,
   structured logging, and environment validation.
2. Deploy API and private worker in the same region as Firestore.
3. Create task queues, service accounts, Secret Manager values, and Scheduler.
4. Add server-only Rules and indexes before writing new documents.

### Phase 1 - Move connection ownership

1. Implement backend OAuth and one-to-one linking.
2. Release Flutter using backend connection status and callback flow.
3. Require existing internal-beta users to reconnect once. Do not run client
   and backend token refresh in parallel because Strava refresh-token rotation
   lets them invalidate each other.
4. Change Google logout to leave the Strava connection intact. Keep an explicit
   "Disconnect Strava" backend operation.
5. After all testers reconnect, remove the client secret, token storage, token
   exchange, and direct refresh code; then rotate the Strava secret.

### Phase 2 - Webhook, backfill, and Firestore-only startup

1. Register one Strava webhook subscription for the application.
2. Implement event, backfill, delete, deauthorization, and reconciliation flows.
3. Remove automatic startup sync from Flutter.
4. Keep a backend repair action in Settings for operators/testers.

### Phase 3 - Details and official activity pipeline

1. Move Strava detail/stream hydration behind backend tasks.
2. Move final 3I activity submission and overlap resolution to backend.
3. Preserve direct live tracking and Storage uploads.

### Phase 4 - Trusted aggregates and Kèo

1. Backfill `stats/current`, period docs, and backend-owned leaderboard entries.
2. Change dashboard/member dashboard to aggregate + paginated recent data.
3. Move Kèo claim/progress/finalize mutations to backend.
4. Tighten Firestore Rules to make these derived documents read-only to clients.

### Phase 5 - Cleanup

1. Remove obsolete `StravaClient` API methods, `SyncController`, startup sync,
   client aggregate refresh, and client athlete-link writes.
2. Add retention for integration events, sync runs, live sessions, and debug
   tracking data.
3. Run a full rebuild job and compare backend results against the existing
   leaderboard/dashboard before deleting legacy fields.

## Acceptance Criteria

- Opening, killing, and reopening the app causes zero Strava API calls.
- A new Strava activity appears without opening 3I.
- Duplicate webhook delivery produces one canonical activity and one aggregate
  revision.
- Out-of-order create/update/delete events cannot resurrect deleted data.
- Two Firebase users cannot connect the same athlete; one user cannot switch
  away from their locked athlete without an explicit support migration.
- Token refresh remains correct with two concurrent worker requests.
- Backfill resumes after worker restart and never stops solely because one page
  was unchanged.
- Public member detail never calls Strava using the viewer's token.
- 3I/Strava overlap updates leaderboard and existing Kèo claim exactly once.
- Google logout/login preserves the Strava connection; explicit disconnect
  revokes it.
- Strava outage leaves cached dashboards/journals usable.
