package backend

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"time"
)

// voiceTokenTTL chỉ giới hạn lúc kết nối: vào phòng rồi thì server LiveKit tự
// gia hạn, nên token ngắn không làm rớt người đang nói.
const voiceTokenTTL = 10 * time.Minute

var errVoiceOff = &HTTPError{Status: http.StatusServiceUnavailable, Code: "voice_unavailable", Message: "Chưa bật nói chuyện trong phòng."}

// VoiceTokens ký token vào phòng thoại trên server LiveKit tự host. Token là
// JWT HS256 theo access token của LiveKit (protocol/auth/grants.go): iss là
// API key, sub là uid, quyền nằm trong claim "video".
type VoiceTokens struct {
	URL    string
	Key    string
	Secret string
}

func (v VoiceTokens) Enabled() bool {
	return v.URL != "" && v.Key != "" && v.Secret != ""
}

type voiceGrant struct {
	Room              string   `json:"room"`
	RoomJoin          bool     `json:"roomJoin"`
	CanPublish        bool     `json:"canPublish"`
	CanSubscribe      bool     `json:"canSubscribe"`
	CanPublishData    bool     `json:"canPublishData"`
	CanPublishSources []string `json:"canPublishSources"`
}

type voiceClaims struct {
	Iss   string     `json:"iss"`
	Sub   string     `json:"sub"`
	Name  string     `json:"name,omitempty"`
	Nbf   int64      `json:"nbf"`
	Exp   int64      `json:"exp"`
	Video voiceGrant `json:"video"`
}

// Token cho uid vào phòng thoại của phòng chạy roomID: nghe mọi người và nói
// bằng micro, không phát video, màn hình hay data.
func (v VoiceTokens) Token(roomID, uid, name string, now time.Time) (string, error) {
	claims, err := json.Marshal(voiceClaims{
		Iss:  v.Key,
		Sub:  uid,
		Name: name,
		Nbf:  now.Unix(),
		Exp:  now.Add(voiceTokenTTL).Unix(),
		Video: voiceGrant{
			Room:              "run-room-" + roomID,
			RoomJoin:          true,
			CanPublish:        true,
			CanSubscribe:      true,
			CanPublishSources: []string{"microphone"},
		},
	})
	if err != nil {
		return "", err
	}
	enc := base64.RawURLEncoding
	signing := enc.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`)) + "." + enc.EncodeToString(claims)
	mac := hmac.New(sha256.New, []byte(v.Secret))
	mac.Write([]byte(signing))
	return signing + "." + enc.EncodeToString(mac.Sum(nil)), nil
}
