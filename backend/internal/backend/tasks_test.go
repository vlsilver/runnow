package backend

import (
	"context"
	"net"
	"testing"
	"time"

	"cloud.google.com/go/cloudtasks/apiv2"
	"cloud.google.com/go/cloudtasks/apiv2/cloudtaskspb"
	"google.golang.org/api/option"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
)

// strictTasks từ chối CreateTask có deadline xa hơn 30s, như Cloud Tasks thật:
// "The deadline cannot be more than 30s in the future."
type strictTasks struct {
	cloudtaskspb.UnimplementedCloudTasksServer
}

func (strictTasks) CreateTask(ctx context.Context, req *cloudtaskspb.CreateTaskRequest) (*cloudtaskspb.Task, error) {
	if d, ok := ctx.Deadline(); ok && time.Until(d) > 30*time.Second {
		return nil, status.Error(codes.InvalidArgument, "The deadline cannot be more than 30s in the future.")
	}
	return req.Task, nil
}

func newStrictTaskPublisher(t *testing.T) *TaskPublisher {
	t.Helper()
	lis, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	srv := grpc.NewServer()
	cloudtaskspb.RegisterCloudTasksServer(srv, strictTasks{})
	go func() { _ = srv.Serve(lis) }()
	t.Cleanup(srv.Stop)
	client, err := cloudtasks.NewClient(context.Background(),
		option.WithEndpoint(lis.Addr().String()),
		option.WithoutAuthentication(),
		option.WithGRPCDialOption(grpc.WithTransportCredentials(insecure.NewCredentials())))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = client.Close() })
	return NewTaskPublisher(client, Config{ProjectID: "p", Region: "r", GameInboundQueue: "game-inbound", BotBaseURL: "https://bot"})
}

// Job game của schedule-tick chạy với timeout 40s. Hẹn game-advance trong đó
// không được hỏng chỉ vì deadline của ctx dài hơn mức Cloud Tasks nhận.
func TestPublishWithLongContextDeadline(t *testing.T) {
	p := newStrictTaskPublisher(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	got, err := p.Publish(ctx, PublishTask{Queue: QueueGameInbound, HandlerPath: "/tasks/game-advance", Payload: map[string]any{"gameId": "g"}})
	if err != nil || got != "created" {
		t.Fatalf("Publish = %q, %v; want created", got, err)
	}
}
