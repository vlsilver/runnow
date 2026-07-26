package backend

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"regexp"
	"strings"
	"time"

	"cloud.google.com/go/cloudtasks/apiv2"
	"cloud.google.com/go/cloudtasks/apiv2/cloudtaskspb"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type QueueName string

const (
	QueueEvents     QueueName = "strava-events"
	QueueBackfill   QueueName = "strava-backfill"
	QueueDerived    QueueName = "derived-data"
	QueueNotify     QueueName = "notifications"
	QueueBotInbound QueueName = "bot-inbound"
)

type PublishTask struct {
	Queue        QueueName
	HandlerPath  string
	Payload      any
	TaskID       string
	ScheduleTime *time.Time
}
type TaskPublisher struct {
	client                                     *cloudtasks.Client
	project, region, workerURL, serviceAccount string
	queues                                     map[QueueName]string
}

func NewTaskPublisher(client *cloudtasks.Client, c Config) *TaskPublisher {
	return &TaskPublisher{client: client, project: c.ProjectID, region: c.Region, workerURL: c.WorkerBaseURL, serviceAccount: c.TaskInvokerAccount, queues: map[QueueName]string{QueueEvents: c.EventsQueue, QueueBackfill: c.BackfillQueue, QueueDerived: c.DerivedQueue, QueueNotify: c.NotifyQueue, QueueBotInbound: c.BotInboundQueue}}
}
func (p *TaskPublisher) Close() {
	if p.client != nil {
		_ = p.client.Close()
	}
}
func (p *TaskPublisher) Publish(ctx context.Context, input PublishTask) (string, error) {
	body, err := json.Marshal(input.Payload)
	if err != nil {
		return "", err
	}
	parent := "projects/" + p.project + "/locations/" + p.region + "/queues/" + p.queues[input.Queue]
	task := &cloudtaskspb.Task{MessageType: &cloudtaskspb.Task_HttpRequest{HttpRequest: &cloudtaskspb.HttpRequest{HttpMethod: cloudtaskspb.HttpMethod_POST, Url: p.workerURL + "/" + strings.TrimLeft(input.HandlerPath, "/"), Headers: map[string]string{"Content-Type": "application/json"}, Body: body, AuthorizationHeader: &cloudtaskspb.HttpRequest_OidcToken{OidcToken: &cloudtaskspb.OidcToken{ServiceAccountEmail: p.serviceAccount, Audience: p.workerURL}}}}}
	if input.TaskID != "" {
		task.Name = parent + "/tasks/" + sanitizeTaskID(input.TaskID)
	}
	if input.ScheduleTime != nil {
		task.ScheduleTime = timestamppb.New(*input.ScheduleTime)
	}
	_, err = p.client.CreateTask(ctx, &cloudtaskspb.CreateTaskRequest{Parent: parent, Task: task})
	if status.Code(err) == codes.AlreadyExists {
		return "duplicate", nil
	}
	if err != nil {
		return "", err
	}
	return "created", nil
}

var invalidTaskID = regexp.MustCompile(`[^A-Za-z0-9_-]`)

func sanitizeTaskID(v string) string {
	v = invalidTaskID.ReplaceAllString(v, "-")
	if len(v) > 500 {
		return v[:500]
	}
	return v
}
func StableTaskID(prefix string, identity any) string {
	raw, _ := canonicalJSON(identity)
	sum := sha256.Sum256(raw)
	return prefix + "-" + hex.EncodeToString(sum[:])[:40]
}

func canonicalJSON(value any) ([]byte, error) {
	// encoding/json sorts string map keys, which makes task identities stable.
	return json.Marshal(value)
}
