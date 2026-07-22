package backend

import (
	"html/template"
	"net/http"
)

// publicActivityTemplate renders the no-login share page for
// GET /v1/public/activities/{uid}/{activityId} — the link the Telegram
// activity alert's "Xem chi tiết" button points to. Deliberately plain
// server-rendered HTML (no JS, no Flutter web build) so it works for anyone
// with the link, not just people with the app installed and signed in.
var publicActivityTemplate = template.Must(template.New("public-activity").Parse(`<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{.ActivityName}} — 3i</title>
<style>
  body { background:#0e0e12; color:#f5f5f7; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; display:flex; align-items:center; justify-content:center; min-height:100vh; margin:0; padding:24px; box-sizing:border-box; }
  .card { max-width:420px; width:100%; background:#17171d; border-radius:20px; padding:28px; box-shadow:0 12px 40px rgba(0,0,0,.4); }
  .brand { font-size:12px; letter-spacing:1.5px; color:#8f8fa3; text-transform:uppercase; margin-bottom:8px; }
  h1 { font-size:22px; margin:0 0 4px; line-height:1.3; }
  .runner { color:#a0a0b8; font-size:14px; margin-bottom:22px; }
  .stats { display:flex; gap:12px; flex-wrap:wrap; }
  .stat { flex:1; min-width:100px; background:#1f1f28; border-radius:14px; padding:14px; }
  .stat .value { font-size:20px; font-weight:800; }
  .stat .label { font-size:11px; color:#8f8fa3; margin-top:2px; }
</style>
</head>
<body>
  <div class="card">
    <div class="brand">3i · Hoạt động chạy</div>
    <h1>{{.ActivityName}}</h1>
    <div class="runner">{{.DisplayName}}</div>
    <div class="stats">
      <div class="stat"><div class="value">{{.Distance}}</div><div class="label">Quãng đường</div></div>
      <div class="stat"><div class="value">{{.Duration}}</div><div class="label">Thời gian</div></div>
      <div class="stat"><div class="value">{{.Pace}}</div><div class="label">Pace</div></div>
    </div>
  </div>
</body>
</html>
`))

type publicActivityPageData struct {
	ActivityName, DisplayName, Distance, Duration, Pace string
}

func writePublicActivityPage(w http.ResponseWriter, summary *PublicActivitySummary) error {
	activityName := summary.ActivityName
	if activityName == "" {
		activityName = "Hoạt động chạy"
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	return publicActivityTemplate.Execute(w, publicActivityPageData{
		ActivityName: activityName,
		DisplayName:  summary.DisplayName,
		Distance:     formatDistanceKm(summary.Fact.DistanceMeters),
		Duration:     formatDurationHMS(summary.Fact.MovingTimeSeconds),
		Pace:         formatPacePerKm(summary.Fact),
	})
}
