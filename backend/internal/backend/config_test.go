package backend

import "testing"

// Model học ký ức đi theo GEMINI_MODEL, để đổi model của 3i là đổi luôn task
// học; AGENT_LEARN_MODEL đặt riêng thì thắng.
func TestLoadConfigLearnModelFollowsGeminiModel(t *testing.T) {
	for k, v := range map[string]string{
		"GOOGLE_CLOUD_PROJECT": "p", "PUBLIC_BASE_URL": "https://api", "WORKER_BASE_URL": "https://worker",
		"MOBILE_RETURN_URI": "app://r", "WEB_RETURN_URI": "https://web/r",
		"STRAVA_CLIENT_ID": "1", "STRAVA_CLIENT_SECRET": "s", "STRAVA_WEBHOOK_VERIFY_TOKEN": "v",
		"TASK_INVOKER_SERVICE_ACCOUNT": "sa@p", "GEMINI_MODEL": "m-chat", "AGENT_LEARN_MODEL": "",
	} {
		t.Setenv(k, v)
	}
	c, err := LoadConfig()
	if err != nil || c.AgentLearnModel != "m-chat" {
		t.Fatalf("mặc định = %q, %v", c.AgentLearnModel, err)
	}
	t.Setenv("AGENT_LEARN_MODEL", "m-learn")
	if c, err := LoadConfig(); err != nil || c.AgentLearnModel != "m-learn" {
		t.Fatalf("đặt riêng = %q, %v", c.AgentLearnModel, err)
	}
}
