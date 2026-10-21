# 3I System Architecture

Tài liệu này là bản nhìn tổng thể của hệ thống 3I: ứng dụng Flutter, Firebase,
backend Go, Strava và các luồng dữ liệu chính.

## 1. System Context

```mermaid
flowchart LR
  runner[Runner / Club member]
  viewer[Club viewer]
  operator[Operator]

  subgraph clients[Client applications]
    mobile[3I Flutter mobile<br/>iOS / Android]
    web[3I Flutter web]
  end

  subgraph firebase[Firebase platform]
    auth[Firebase Authentication]
    firestore[(Cloud Firestore)]
    storage[(Firebase Storage)]
    hosting[Firebase Hosting]
    analytics[Firebase Analytics]
  end

  subgraph gcp[Google Cloud - asia-southeast1]
    api[Cloud Run: runnow-api<br/>public ingress]
    worker[Cloud Run: runnow-worker<br/>private ingress]
    tasks[Cloud Tasks<br/>3 queues]
    scheduler[Cloud Scheduler]
    secrets[Secret Manager]
    registry[Artifact Registry]
    build[Cloud Build]
  end

  subgraph strava[Strava platform]
    oauth[Strava OAuth]
    stravaApi[Strava API]
    webhook[Strava Webhook]
  end

  maps[Map tiles / route rendering]
  gps[Device GPS / Location services]

  runner --> mobile
  viewer --> mobile
  viewer --> web
  operator --> build

  hosting --> web
  mobile --> auth
  web --> auth
  mobile <--> firestore
  web <--> firestore
  mobile --> storage
  mobile --> analytics
  mobile <--> gps
  mobile --> maps
  web --> maps

  mobile -->|Firebase ID token| api
  web -->|Firebase ID token| api
  api --> auth
  api --> firestore
  api --> tasks
  api --> oauth
  webhook --> api

  tasks -->|OIDC| worker
  scheduler -->|OIDC every 6 hours| worker
  worker --> firestore
  worker --> stravaApi
  worker --> tasks
  api --> stravaApi
  api -. reads at runtime .-> secrets
  worker -. reads at runtime .-> secrets

  build --> registry
  registry --> api
  registry --> worker
```

## 2. Runtime And Trust Boundaries

```mermaid
flowchart TB
  subgraph public[Public internet boundary]
    flutter[Flutter mobile / web]
    stravaWebhook[Strava webhook sender]
    api[runnow-api]
  end

  subgraph private[Private service boundary]
    queue[Cloud Tasks]
    worker[runnow-worker]
    scheduler[Cloud Scheduler]
  end

  subgraph data[Trusted data boundary]
    db[(Firestore)]
    files[(Firebase Storage)]
    secret[Secret Manager]
  end

  flutter -->|Firebase ID token| api
  stravaWebhook -->|verify token + subscription ID| api
  api -->|named idempotent tasks| queue
  queue -->|Cloud Run IAM + OIDC| worker
  scheduler -->|Cloud Run IAM + OIDC| worker
  api --> db
  worker --> db
  flutter -->|Firestore / Storage Rules| db
  flutter -->|owner-scoped upload| files
  api --> secret
  worker --> secret
```

Quyền sở hữu được chia như sau:

| Boundary | Owner | Trách nhiệm |
|---|---|---|
| Flutter | Client | UI, Firebase login, GPS sampling, local recovery, live snapshot, upload ảnh |
| `runnow-api` | Backend sync request | Firebase token verification, OAuth callback, webhook intake, enqueue work |
| `runnow-worker` | Backend async | Strava fetch, token refresh, backfill, hydrate, aggregate, reconciliation |
| Firestore Rules | Firebase | Chặn client đọc token/event và giới hạn document user được phép ghi |
| Secret Manager | Platform | Strava client secret và webhook verify token cấp ứng dụng |

## 3. Backend Deployment Topology

```mermaid
flowchart LR
  source[Go source]
  cloudBuild[Cloud Build]
  image[(Artifact Registry<br/>single image)]
  api[runnow-api binary<br/>/api]
  worker[runnow-worker binary<br/>/worker]

  q1[strava-events<br/>fresh events]
  q2[strava-backfill<br/>rate limited]
  q3[derived-data<br/>no Strava calls]

  source --> cloudBuild --> image
  image --> api
  image --> worker
  api --> q1
  api --> q2
  q1 --> worker
  q2 --> worker
  q3 --> worker
  worker --> q2
  worker --> q3
```

Hai service dùng chung image nhưng có service account, ingress, concurrency và
entrypoint riêng. API public không tự thực hiện backfill dài; worker private
không nhận request trực tiếp từ ứng dụng.

## 4. Firestore Data Architecture

```mermaid
flowchart TB
  subgraph clientReadable[Client-readable product data]
    users[(users/{uid})]
    activities[(users/{uid}/activities/{activityId})]
    stats[(users/{uid}/stats/current)]
    profiles[(publicProfiles/{uid})]
    leaderboard[(leaderboardEntries/{uid})]
    contracts[(runContracts/{contractId})]
    claims[(runContractActivityClaims/{claimId})]
    live[(liveSessions/{sessionId})]
    posts[(feedPosts/{postId})]
    goals[(trainingGoalHistory/{goalId})]
  end

  subgraph serverOnly[Backend-only integration data]
    connections[(stravaConnections/{uid})]
    athleteLinks[(stravaAthleteLinks/{athleteId})]
    oauthStates[(oauthStates/{stateHash})]
    events[(integrationEvents/{eventKey})]
    tombstones[(activityTombstones/{uid_activityId})]
  end

  subgraph binaryData[Binary data]
    storage[(Firebase Storage<br/>avatars / activity photos)]
  end

  connections -->|athlete ID| athleteLinks
  connections -->|canonical import| activities
  events -->|worker processing| activities
  tombstones -->|prevents stale resurrection| activities
  activities --> stats
  activities --> leaderboard
  activities --> claims
  claims --> contracts
  live -. ephemeral until Finish .-> activities
  activities --> storage
  users --> profiles
```

### Server-only collections

- `stravaConnections`: access token, refresh token, expiry, scopes và trạng thái.
- `stravaAthleteLinks`: bảo đảm một Strava athlete chỉ thuộc một Firebase UID.
- `oauthStates`: OAuth state dùng một lần, TTL 10 phút.
- `integrationEvents`: idempotency và trạng thái xử lý webhook, TTL 30 ngày.
- `activityTombstones`: chặn event cũ làm sống lại activity đã xóa, TTL 30 ngày.

### Product collections

- `users/{uid}/activities`: nguồn thống nhất cho Strava và session 3I.
- `users/{uid}/stats/current`: aggregate dashboard hiện tại.
- `leaderboardEntries`: snapshot phục vụ bảng xếp hạng, không quét toàn bộ activity.
- `runContracts` và `runContractActivityClaims`: Kèo và lựa chọn session rõ ràng.
- `liveSessions`: vị trí live được throttle; không phải thành tích chính thức.

## 5. Authentication Flow

```mermaid
sequenceDiagram
  actor User
  participant App as Flutter app
  participant Google as Google Sign-In
  participant Auth as Firebase Auth
  participant DB as Firestore

  User->>App: Đăng nhập Google
  App->>Google: Chọn tài khoản
  Google-->>App: Google credential
  App->>Auth: signInWithCredential
  Auth-->>App: Firebase user + ID token
  App->>DB: Listen profile/product data
  DB-->>App: Cached/realtime snapshots
```

Firebase UID là identity chính. Strava athlete ID chỉ là integration identity
được khóa 1-1 với UID, không thay thế Firebase Authentication.

## 6. Connect Strava And Initial Backfill

```mermaid
sequenceDiagram
  actor User
  participant App as Flutter / Web
  participant API as runnow-api
  participant Auth as Firebase Auth
  participant DB as Firestore
  participant Strava as Strava OAuth/API
  participant Tasks as Cloud Tasks
  participant Worker as runnow-worker

  User->>App: Kết nối Strava
  App->>API: POST /v1/strava/authorization + ID token
  API->>Auth: Verify ID token
  API->>DB: Create hashed one-use OAuth state
  API-->>App: Strava authorization URL
  App->>Strava: Authorize activity:read_all
  Strava->>API: GET /v1/strava/callback?code&state
  API->>DB: Consume state transactionally
  API->>Strava: Exchange authorization code
  API->>DB: Enforce UID-athlete uniqueness + store latest tokens
  API->>Tasks: Enqueue backfill page 1
  API-->>App: Redirect connected
  loop Until Strava returns fewer than 100 items
    Tasks->>Worker: /tasks/backfill-page
    Worker->>Strava: GET athlete activities page
    Worker->>DB: Idempotent batch upsert
    Worker->>Tasks: Enqueue next page
  end
  Worker->>Tasks: Enqueue derived-data rebuild
  Tasks->>Worker: /tasks/rebuild-derived-data
  Worker->>DB: Update stats and leaderboard only when changed
  DB-->>App: Firestore snapshot updates UI
```

## 7. New Strava Activity Flow

```mermaid
sequenceDiagram
  participant Strava
  participant API as runnow-api
  participant DB as Firestore
  participant Tasks as Cloud Tasks
  participant Worker as runnow-worker
  participant App as Flutter / Web

  Strava->>API: POST webhook notification
  API->>API: Validate subscription + deterministic event key
  API->>DB: Create integrationEvents/{eventKey}
  API->>Tasks: Enqueue named strava-event task
  API-->>Strava: HTTP 200 quickly
  Tasks->>Worker: /tasks/strava-event
  Worker->>DB: Resolve athlete ID to UID
  Worker->>Strava: Fetch canonical activity using owner token
  Worker->>DB: Upsert activity / write tombstone on delete
  alt Summary changed
    Worker->>Tasks: Enqueue derived rebuild
    Tasks->>Worker: Rebuild current periods
    Worker->>DB: Update stats + leaderboard
  end
  DB-->>App: Realtime activity/stats update
```

Webhook chỉ là tín hiệu. Dữ liệu activity luôn được worker lấy lại từ Strava
trước khi trở thành dữ liệu chuẩn.

## 8. Detail Hydration Flow

```mermaid
sequenceDiagram
  actor User
  participant App
  participant DB as Firestore
  participant API as runnow-api
  participant Tasks as Cloud Tasks
  participant Worker as runnow-worker
  participant Strava

  User->>App: Mở activity detail
  App->>DB: Read cached activity
  alt Detail and streams already hydrated
    DB-->>App: Render immediately
  else Owner requests missing detail
    App->>API: POST /v1/activities/{id}/hydrate
    API->>Tasks: Enqueue 5-minute deduplicated task
    API-->>App: 202 Accepted
    App->>DB: Keep watching activity document
    Tasks->>Worker: /tasks/hydrate-activity
    Worker->>Strava: Fetch detail + streams
    Worker->>DB: Cache normalized streams/route
    DB-->>App: Render charts and map
  end
```

Public viewer chỉ đọc detail đã cache; viewer không dùng token của mình để gọi
thay cho chủ activity.

## 9. Tracking And Live Tracking

```mermaid
sequenceDiagram
  actor Runner
  participant App as Flutter mobile
  participant GPS as Device location
  participant Live as Firestore liveSessions
  participant API as runnow-api (planned finalization)
  participant Activities as Firestore activities
  participant Storage as Firebase Storage

  Runner->>App: Mở màn hình Chạy
  App->>GPS: Request permission + warm up GPS
  GPS-->>App: Location samples
  App->>App: Filter points, calculate distance/pace, persist recovery draft
  opt Live sharing enabled
    App->>Live: Throttled route/status snapshots
  end
  opt Capture photo
    App->>Storage: Upload owner-scoped image
    App->>App: Attach GPS/time metadata
  end
  Runner->>App: Finish
  App->>API: Submit normalized final activity
  API->>Activities: Validate >= 500 m and write official candidate
  API->>Activities: Resolve overlap with nearby Strava runs
  API-->>App: Final state
  App->>Live: Close ephemeral live session
  App->>App: Delete recovery draft after success
```

Đoạn submit/finalize qua API là bước migration tiếp theo. Trong thời gian
cutover, tracking client hiện tại vẫn là implementation đang hoạt động.

## 10. Kèo Claim Flow

```mermaid
sequenceDiagram
  actor Member
  participant App
  participant API as runnow-api (planned)
  participant DB as Firestore
  participant Worker as runnow-worker

  Member->>App: Chọn một session đủ điều kiện
  App->>API: POST /v1/contracts/{id}/claims
  API->>DB: Transaction: validate owner, window, eligibility, uniqueness
  API->>DB: Save explicit activity claim + recalculate participant progress
  DB-->>App: Contract progress update
  alt Claimed 3I session later superseded by Strava
    Worker->>DB: Idempotently migrate claim to Strava activity
    Worker->>DB: Recalculate progress once
  end
```

Không tự động gán activity vào Kèo. Người dùng luôn chọn session áp dụng; backend
chỉ xác thực và bảo vệ tính nhất quán.

## 11. Reconciliation And Recovery

```mermaid
sequenceDiagram
  participant Scheduler as Cloud Scheduler
  participant Worker as runnow-worker
  participant DB as Firestore
  participant Tasks as Cloud Tasks
  participant Strava as Strava API

  Scheduler->>Worker: Every 6 hours, OIDC request
  Worker->>DB: Page active connections, 100 users/page
  loop Each active connection
    Worker->>Tasks: Enqueue recent 10-day backfill
    Tasks->>Worker: Backfill task
    Worker->>Strava: Fetch recent activities
    Worker->>DB: Repair missing/changed records idempotently
  end
```

Reconciliation bù webhook bị lỡ. Nó không chạy khi người dùng mở ứng dụng.

## 12. Current Implementation Status

| Capability | Trạng thái |
|---|---|
| Go API/worker foundation | Implemented, local build/test passed |
| Firebase auth verification | Implemented |
| Backend Strava OAuth and token custody | Implemented, Flutter đã cutover |
| Webhook, backfill, delete, token refresh | Implemented và đã deploy |
| Lazy detail/streams hydration | Implemented backend endpoint |
| Current week/7-day/month aggregate | Implemented backend worker |
| Flutter direct Firestore UI/offline reads | Current production behavior |
| GPS tracking and live snapshots | Current client behavior |
| Backend tracked-activity finalization | Planned |
| Backend Kèo claim/finalization | Planned |
| Client startup sync removal | Implemented |

Flutter không còn giữ hoặc refresh Strava token. Beta users phải reconnect Strava
một lần để backend nhận token; Google logout không làm mất liên kết này.
