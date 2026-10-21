package backend

import (
	"context"
	"net/http"
	"strings"

	"cloud.google.com/go/firestore"
)

type ProfileUpdate struct {
	Nickname   string  `json:"nickname"`
	AvatarURL  *string `json:"avatarUrl"`
	Visibility string  `json:"visibility"`
}

type ProfileService struct {
	db    *firestore.Client
	tasks *TaskPublisher
}

func NewProfileService(db *firestore.Client, tasks *TaskPublisher) *ProfileService {
	return &ProfileService{db: db, tasks: tasks}
}

func (s *ProfileService) Update(ctx context.Context, uid string, input ProfileUpdate) error {
	nickname := strings.TrimSpace(input.Nickname)
	if nickname == "" || len([]rune(nickname)) > 40 || (input.Visibility != "public" && input.Visibility != "private") {
		return &HTTPError{Status: http.StatusBadRequest, Code: "invalid_profile", Message: "Profile is invalid"}
	}
	avatar := any(firestore.Delete)
	avatarIdentity := ""
	if input.AvatarURL != nil {
		trimmed := strings.TrimSpace(*input.AvatarURL)
		if len(trimmed) > 2048 {
			return &HTTPError{Status: http.StatusBadRequest, Code: "invalid_profile", Message: "Avatar URL is invalid"}
		}
		if trimmed != "" {
			avatar = trimmed
			avatarIdentity = trimmed
		}
	}
	b := s.db.Batch()
	b.Set(s.db.Collection("users").Doc(uid), map[string]any{
		"nickname": nickname, "displayName": nickname,
		"profileVisibility": input.Visibility, "avatarUrl": avatar,
		"updatedAt": firestore.ServerTimestamp,
	}, firestore.MergeAll)
	b.Set(s.db.Collection("publicProfiles").Doc(uid), map[string]any{
		"uid": uid, "nickname": nickname, "displayName": nickname,
		"profileVisibility": input.Visibility, "avatarUrl": avatar,
		"updatedAt": firestore.ServerTimestamp,
	}, firestore.MergeAll)
	if _, err := b.Commit(ctx); err != nil {
		return err
	}
	_, err := s.tasks.Publish(ctx, PublishTask{
		Queue: QueueDerived, HandlerPath: "/tasks/rebuild-derived-data",
		Payload: map[string]any{"uid": uid, "cause": "profile-update"},
		TaskID:  StableTaskID("profile-derived", map[string]any{"uid": uid, "nickname": nickname, "visibility": input.Visibility, "avatar": avatarIdentity}),
	})
	return err
}
