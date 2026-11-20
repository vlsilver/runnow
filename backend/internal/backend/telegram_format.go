package backend

import (
	"context"
	"errors"
	"html"
	"regexp"
	"strings"
)

// Model viết theo Markdown (**đậm**, gạch đầu dòng `*`, `#` tiêu đề) dù prompt
// không đòi. Telegram không hiểu Markdown thường: gửi thô thì hiện nguyên dấu
// sao, gửi parse_mode Markdown thì một dấu `_` hay `*` lẻ trong tên người là
// Telegram từ chối cả tin. Nên đổi sang HTML: escape hết rồi mới chèn thẻ, thẻ
// luôn đóng trong cùng dòng, nên text gì cũng ra HTML hợp lệ.

var (
	mdHeading = regexp.MustCompile(`^#{1,6}\s+(.*)$`)
	mdBullet  = regexp.MustCompile(`^(\s*)[*+-]\s+(.*)$`)
	mdRule    = regexp.MustCompile(`^\s*([-*_]\s*){3,}$`)
	mdCode    = regexp.MustCompile("`([^`\n]+)`")
	mdLink    = regexp.MustCompile(`\[([^\]\n]+)\]\((https?://[^\s)]+)\)`)
	mdBold    = regexp.MustCompile(`\*\*(\S(?:[^\n]*?\S)?)\*\*|__(\S(?:[^\n]*?\S)?)__`)
	mdItalic  = regexp.MustCompile(`(^|[\s(])\*([^*\s](?:[^*\n]*[^*\s])?)\*([\s.,!?:;)]|$)`)
)

// modelTextHTML đổi text model sinh sang HTML cho parse_mode HTML.
func modelTextHTML(text string) string {
	return renderModelText(text, true)
}

// modelTextPlain bỏ dấu Markdown, giữ chữ: dùng khi Telegram vẫn từ chối bản
// HTML, để tin không mất.
func modelTextPlain(text string) string {
	return renderModelText(text, false)
}

func renderModelText(text string, asHTML bool) string {
	lines := strings.Split(text, "\n")
	out := make([]string, 0, len(lines))
	inFence := false
	for _, line := range lines {
		if strings.HasPrefix(strings.TrimSpace(line), "```") {
			inFence = !inFence
			if asHTML {
				out = append(out, map[bool]string{true: "<pre>", false: "</pre>"}[inFence])
			}
			continue
		}
		if inFence {
			out = append(out, escapeIf(line, asHTML))
			continue
		}
		switch {
		case mdRule.MatchString(line):
			out = append(out, "")
		case mdHeading.MatchString(line):
			rest := mdHeading.FindStringSubmatch(line)[1]
			rest = strings.NewReplacer("**", "", "__", "").Replace(rest)
			if asHTML {
				out = append(out, "<b>"+mdInline(rest, true)+"</b>")
			} else {
				out = append(out, mdInline(rest, false))
			}
		case mdBullet.MatchString(line):
			m := mdBullet.FindStringSubmatch(line)
			out = append(out, m[1]+"• "+mdInline(m[2], asHTML))
		default:
			out = append(out, mdInline(line, asHTML))
		}
	}
	if inFence && asHTML {
		out = append(out, "</pre>")
	}
	return strings.Join(out, "\n")
}

// mdInline xử lý một dòng: đoạn `code` giữ nguyên chữ, phần còn lại đổi link,
// đậm, nghiêng.
func mdInline(line string, asHTML bool) string {
	var b strings.Builder
	last := 0
	for _, loc := range mdCode.FindAllStringSubmatchIndex(line, -1) {
		b.WriteString(mdSpans(line[last:loc[0]], asHTML))
		code := line[loc[2]:loc[3]]
		if asHTML {
			b.WriteString("<code>" + html.EscapeString(code) + "</code>")
		} else {
			b.WriteString(code)
		}
		last = loc[1]
	}
	b.WriteString(mdSpans(line[last:], asHTML))
	return b.String()
}

func mdSpans(s string, asHTML bool) string {
	s = escapeIf(s, asHTML)
	if asHTML {
		s = mdLink.ReplaceAllString(s, `<a href="$2">$1</a>`)
		s = mdBold.ReplaceAllString(s, "<b>$1$2</b>")
		return mdItalic.ReplaceAllString(s, "$1<i>$2</i>$3")
	}
	s = mdLink.ReplaceAllString(s, "$1 ($2)")
	s = mdBold.ReplaceAllString(s, "$1$2")
	return mdItalic.ReplaceAllString(s, "$1$2$3")
}

func escapeIf(s string, asHTML bool) string {
	if asHTML {
		return html.EscapeString(s)
	}
	return s
}

// telegramParseRejected: Telegram không parse được entity trong tin HTML.
func telegramParseRejected(status int, body string) bool {
	return status == 400 && strings.Contains(body, "can't parse entities")
}

// sendModelText gửi text model sinh: Markdown đổi sang HTML, Telegram vẫn từ
// chối parse thì gửi lại bản chữ thường.
func sendModelText(ctx context.Context, tg *TelegramService, m TelegramText) (int64, error) {
	raw := m.Text
	m.Text, m.HTML = modelTextHTML(raw), true
	id, err := tg.SendText(ctx, m)
	if !parseRejected(err) {
		return id, err
	}
	m.Text, m.HTML = modelTextPlain(raw), false
	return tg.SendText(ctx, m)
}

// sendModelImage như sendModelText cho chú thích ảnh. Chú thích dài bị cắt có
// thể đứt giữa thẻ, khi đó rơi về bản chữ thường.
func sendModelImage(ctx context.Context, tg *TelegramService, p TelegramPhoto) (int64, error) {
	raw := p.Caption
	p.Caption, p.HTML = modelTextHTML(raw), true
	id, err := tg.SendImage(ctx, p)
	if !parseRejected(err) {
		return id, err
	}
	p.Caption, p.HTML = modelTextPlain(raw), false
	return tg.SendImage(ctx, p)
}

func parseRejected(err error) bool {
	var apiErr *TelegramAPIError
	return errors.As(err, &apiErr) && telegramParseRejected(apiErr.Status, apiErr.Description)
}
