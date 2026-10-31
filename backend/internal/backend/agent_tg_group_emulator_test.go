//go:build emulator

package backend

import (
	"strconv"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"
)

// groupMsg là tin ở group PSC ngoài topic Phòng bot (General khi thread 0),
// reply tin của replyFrom (0 là không reply). replyIsBot cho biết tin được
// reply là của bot.
func groupMsg(updateID, from int64, thread int64, text string, replyFrom int64, replyIsBot bool, replyText string) map[string]any {
	upd := topicMsg(updateID, from, thread, text)
	if replyFrom != 0 {
		upd["message"].(map[string]any)["reply_to_message"] = map[string]any{
			"message_id": updateID - 50, "text": replyText,
			"from": map[string]any{"id": replyFrom, "is_bot": replyIsBot, "username": "u" + strconv.FormatInt(replyFrom, 10), "first_name": "Ai đó"},
		}
	}
	return upd
}

// MyBot ở group chính: chỉ lên tiếng khi tin reply tin của chính nó hay @nhắc
// nó, bằng bot con của chủ, reply đúng tin đó, đúng topic. Không cần bật Phòng
// bot. Tin thường không vào phòng, 3i không coi tin gọi MyBot là câu hỏi.
func TestEmulatorTelegramGroupAnswersAddressedBot(t *testing.T) {
	e := newMybotEnv(t)
	cuongTok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 10)
	anTok := e.linkBot("an", "5002", 8002, "Sóc", 11)
	e.child(8001, pscMemberUpd(200, 8001, "member"))
	e.child(8002, pscMemberUpd(201, 8002, "member"))
	e.drain()

	// Tin thường và tin reply người không có bot ở PSC: không vào phòng.
	e.manager(groupMsg(300, 5002, 0, "trưa ăn gì", 0, false, ""))
	e.manager(groupMsg(301, 5002, 0, "ok", 5999, false, "đi ăn không"))
	if msgs := e.roomMessages(agentTelegramGroupRoom); len(msgs) != 0 {
		t.Fatalf("tin thường vào phòng group: %v", msgs)
	}

	// An reply tin của Cú Mèo ở General.
	e.llm.script = append(e.llm.script, llmText("Tôi chạy nhanh hơn bạn đấy"))
	e.tick(time.Minute)
	if r := e.manager(groupMsg(302, 5002, 0, "bot gì mà lắm mồm", 8001, true, "Hôm nay Cường chạy 5 km")); r.status != 200 || r.body != nil {
		t.Fatalf("reply bot: %d %s", r.status, r.raw)
	}
	if task := e.botMsgTask(); task.IsQuestion {
		t.Fatalf("3i coi tin gọi MyBot là câu hỏi: %+v", task)
	}
	msgs := e.roomMessages(agentTelegramGroupRoom)
	if len(msgs) != 1 || msgs[0]["uid"] != "an" || msgs[0]["replyToBot"] != "8001" || msgs[0]["tgMessageId"] != int64(302) || msgs[0]["expiresAt"] == nil {
		t.Fatalf("phòng group = %v", msgs)
	}
	e.drain()
	sends := e.tg.CallsBy(cuongTok, "sendMessage")
	if len(sends) != 1 || sends[0].Params["chat_id"] != testPscChat || sends[0].Params["message_thread_id"] != nil || sends[0].Params["text"] != "Tôi chạy nhanh hơn bạn đấy" {
		t.Fatalf("Cú Mèo gửi = %+v", sends)
	}
	if rp, _ := sends[0].Params["reply_parameters"].(map[string]any); rp["message_id"] != float64(302) {
		t.Fatalf("không reply đúng tin: %+v", sends[0].Params)
	}
	if len(e.tg.CallsBy(anTok, "sendMessage")) != 0 || len(e.llm.calls) != 1 {
		t.Fatalf("bot không được gọi vẫn nói: llm=%d", len(e.llm.calls))
	}
	if sys, chat := e.llm.calls[0].system, e.llm.calls[0].contents[0].Parts[0].Text; !strings.Contains(sys, "group Telegram chung") || !strings.Contains(chat, "trả lời tin của Cú Mèo") {
		t.Fatalf("prompt group thiếu luật hay ngữ cảnh reply:\n%s\n---\n%s", sys, chat)
	}

	// @nhắc bot của An trong một topic thường: bot An trả lời trong topic đó.
	e.llm.script = append(e.llm.script, llmText("Có mặt"))
	e.tick(time.Minute)
	e.manager(groupMsg(303, 5001, 5, "@bot_an ra đây", 0, false, ""))
	e.drain()
	if sends := e.tg.CallsBy(anTok, "sendMessage"); len(sends) != 1 || sends[0].Params["message_thread_id"] != float64(5) {
		t.Fatalf("Sóc gửi = %+v", sends)
	}
}

// Có người gọi mà bot đã hết lượt hôm nay: bot không gọi model, mà nhắc nhẹ chủ
// (tag chủ) cần chạy thêm bao nhiêu km để nói tiếp, reply đúng tin đã gọi nó.
// Mỗi ngày chỉ nhắc một lần, gọi tiếp thì im. Bot chỉ tới lượt theo vòng ở
// Phòng bot thì không ai gọi nó, nên không nhắc.
func TestEmulatorTelegramGroupNudgesOwnerOutOfQuota(t *testing.T) {
	e := newMybotEnv(t)
	cuongTok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 10)
	anTok := e.linkBot("an", "5002", 8002, "Sóc", 11)
	e.manager(topicMsg(100, 5002, tgRoomThread, "/phongbot"))
	e.child(8001, pscMemberUpd(200, 8001, "member"))
	e.child(8002, pscMemberUpd(201, 8002, "member"))
	e.drain()
	// Chưa chạy hôm nay: 10 lượt, chạy đủ 1 km mở thêm 5 câu.
	e.merge("agents/cuong", map[string]any{"dmDay": vnDay(e.clock), "dmDayCount": 10})

	// Phòng bot: tới vòng Cú Mèo (uid đứng trước) mà hết lượt thì Sóc nói thay.
	e.llm.script = append(e.llm.script, llmText("Sóc đây"))
	e.manager(topicMsg(300, 5002, tgRoomThread, "chào cả nhà"))
	e.drain()
	if len(e.tg.CallsBy(cuongTok, "sendMessage")) != 0 || len(e.tg.CallsBy(anTok, "sendMessage")) != 1 {
		t.Fatalf("Phòng bot: bot tới vòng mà hết lượt vẫn nhắc chủ, hay Sóc không nói thay")
	}

	e.llm.calls = nil
	e.tick(time.Minute)
	e.manager(groupMsg(302, 5002, 0, "bot gì mà lắm mồm", 8001, true, "Hôm nay Cường chạy 5 km"))
	e.drain()
	if len(e.llm.calls) != 0 {
		t.Fatalf("bot hết lượt vẫn gọi model: %d", len(e.llm.calls))
	}
	sends := e.tg.CallsBy(cuongTok, "sendMessage")
	want := `<a href="tg://user?id=5001">Cường</a> ơi, có người gọi mình mà hôm nay mình hết lượt nói rồi. Chạy hay đi bộ thêm 1 km là mình nói tiếp được 5 câu nữa nha.`
	if len(sends) != 1 || sends[0].Params["text"] != want || sends[0].Params["parse_mode"] != "HTML" || sends[0].Params["message_thread_id"] != nil {
		t.Fatalf("Cú Mèo nhắc chủ = %+v", sends)
	}
	if rp, _ := sends[0].Params["reply_parameters"].(map[string]any); rp["message_id"] != float64(302) {
		t.Fatalf("tin nhắc không reply tin đã gọi bot: %+v", sends[0].Params)
	}
	if got := e.doc("agents/cuong")["dmDayCount"]; got != int64(10) {
		t.Fatalf("tin nhắc trừ lượt của chủ: dmDayCount %v", got)
	}

	e.tick(time.Minute)
	e.manager(groupMsg(303, 5002, 0, "sao im rồi", 8001, true, "Hôm nay Cường chạy 5 km"))
	e.drain()
	if n := len(e.tg.CallsBy(cuongTok, "sendMessage")); n != 1 {
		t.Fatalf("một ngày nhắc chủ %d lần, muốn 1", n)
	}
}

// Người khác reply tin của chủ bot thì bot của chủ đỡ lời, kể cả người chưa
// liên kết 3i Run. Hai bot gọi tên nhau thì nói tiếp, nhưng cả chuỗi tối đa 3
// tin. Chủ tự reply mình, hay tin đang hỏi 3i, thì bot không chen.
func TestEmulatorTelegramGroupDefendsOwner(t *testing.T) {
	e := newMybotEnv(t)
	cuongTok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 10)
	anTok := e.linkBot("an", "5002", 8002, "Sóc", 11)
	e.child(8001, pscMemberUpd(200, 8001, "member"))
	e.child(8002, pscMemberUpd(201, 8002, "member"))
	e.drain()

	e.manager(groupMsg(300, 5001, 0, "nói thêm là mai mưa", 5001, false, "mai chạy 6h"))
	e.manager(groupMsg(301, 5002, 0, "@Run3IBot mai mưa thật không", 5001, false, "mai chạy 6h"))
	if task := e.botMsgTask(); !task.IsQuestion {
		t.Fatalf("tin hỏi 3i không còn là câu hỏi: %+v", task)
	}
	if msgs := e.roomMessages(agentTelegramGroupRoom); len(msgs) != 0 {
		t.Fatalf("bot chen khi chủ tự reply hay khi hỏi 3i: %v", msgs)
	}

	// Người chưa liên kết trêu Cường: Cú Mèo đỡ lời và gọi Sóc, Sóc đáp và gọi
	// lại Cú Mèo, Cú Mèo nói câu thứ ba rồi chuỗi dừng dù vẫn nhắc tên Sóc.
	e.llm.script = append(e.llm.script,
		llmText("Rùa về đích trước thỏ đấy, Sóc thấy đúng không"),
		llmText("Cú Mèo nói chuẩn"),
		llmText("Sóc hiểu chuyện ghê"),
		llmText("không được dùng tới"))
	e.tick(time.Minute)
	e.manager(groupMsg(302, 5999, 0, "Cường chạy chậm như rùa", 5001, false, "mai chạy 6h"))
	msgs := e.roomMessages(agentTelegramGroupRoom)
	if len(msgs) != 1 || msgs[0]["uid"] != "" || msgs[0]["name"] != "Ai đó" || msgs[0]["targetUid"] != "cuong" || msgs[0]["replyText"] != "mai chạy 6h" {
		t.Fatalf("tin trêu chủ trong phòng = %v", msgs)
	}
	e.drain()
	if len(e.llm.calls) != 3 {
		t.Fatalf("chuỗi bot ở group = %d lượt, muốn 3", len(e.llm.calls))
	}
	if chat := e.llm.calls[0].contents[0].Parts[0].Text; !strings.Contains(chat, "Ai đó (người, trả lời tin của") || !strings.Contains(chat, `"mai chạy 6h"`) {
		t.Fatalf("bot không biết người ta trả lời tin nào:\n%s", chat)
	}
	cuongSends, anSends := e.tg.CallsBy(cuongTok, "sendMessage"), e.tg.CallsBy(anTok, "sendMessage")
	if len(cuongSends) != 2 || len(anSends) != 1 {
		t.Fatalf("Cú Mèo gửi %d, Sóc gửi %d; muốn 2 và 1", len(cuongSends), len(anSends))
	}
	// Chỉ tin đầu reply tin trêu; các tin sau của chuỗi nói tiếp trong cùng chỗ.
	if rp, _ := cuongSends[0].Params["reply_parameters"].(map[string]any); rp["message_id"] != float64(302) {
		t.Fatalf("tin đầu không reply tin trêu: %+v", cuongSends[0].Params)
	}
	if anSends[0].Params["reply_parameters"] != nil || cuongSends[1].Params["reply_parameters"] != nil {
		t.Fatalf("tin nói tiếp vẫn reply tin trêu: %+v / %+v", anSends[0].Params, cuongSends[1].Params)
	}

	// Tin thường reply chủ: model nhường lượt thì không ai nói.
	e.llm.script = []*genai.GenerateContentResponse{llmText(agentPass)}
	e.llm.calls = nil
	e.tick(time.Minute)
	e.manager(groupMsg(303, 5002, 0, "ok anh", 5001, false, "mai chạy 6h"))
	e.drain()
	if len(e.llm.calls) != 1 || len(e.tg.CallsBy(cuongTok, "sendMessage")) != 2 {
		t.Fatalf("bot vẫn nói khi model nhường lượt: llm=%d", len(e.llm.calls))
	}
}
