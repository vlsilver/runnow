package backend

import (
	"strconv"
	"strings"
	"testing"
)

func TestRunCardLooksRequestValid(t *testing.T) {
	s := func(v string) *string { return &v }
	one := func(l RunCardLook) RunCardLooksRequest { return RunCardLooksRequest{Looks: []RunCardLook{l}} }
	many := RunCardLooksRequest{}
	for i := range maxRunCardLooks + 1 {
		many.Looks = append(many.Looks, RunCardLook{ActivityID: "a" + strconv.Itoa(i), Style: s("city.top")})
	}
	cases := []struct {
		name string
		req  RunCardLooksRequest
		want bool
	}{
		{"kiểu và bộ màu", one(RunCardLook{ActivityID: "a1", Style: s("city.top.map"), Skin: s("dark.fire")}), true},
		{"chỉ bỏ bộ màu", one(RunCardLook{ActivityID: "a1", Skin: s("")}), true},
		{"đủ 100 thẻ", RunCardLooksRequest{Looks: many.Looks[:maxRunCardLooks]}, true},
		{"rỗng", RunCardLooksRequest{}, false},
		{"quá 100 thẻ", many, false},
		{"không field nào", one(RunCardLook{ActivityID: "a1"}), false},
		{"thiếu id", one(RunCardLook{Style: s("city.top")}), false},
		{"id có dấu gạch chéo", one(RunCardLook{ActivityID: "a/b", Style: s("city.top")}), false},
		{"style rỗng", one(RunCardLook{ActivityID: "a1", Style: s("")}), false},
		{"style một phần", one(RunCardLook{ActivityID: "a1", Style: s("city")}), false},
		{"style bốn phần", one(RunCardLook{ActivityID: "a1", Style: s("a.b.c.d")}), false},
		{"style có khoảng trắng", one(RunCardLook{ActivityID: "a1", Style: s("city. top")}), false},
		{"style xuống dòng cuối", one(RunCardLook{ActivityID: "a1", Style: s("city.top\n")}), false},
		{"skin ba phần", one(RunCardLook{ActivityID: "a1", Skin: s("dark.fire.x")}), false},
		{"layout", one(RunCardLook{ActivityID: "a1", Style: s("iron.full"), Layout: s("km:30,66,2,b;time:20,80,2,h")}), true},
		{"chỉ bỏ layout", one(RunCardLook{ActivityID: "a1", Layout: s("")}), true},
		{"layout chữ hoa", one(RunCardLook{ActivityID: "a1", Layout: s("KM:30,66,2")}), false},
		{"layout có khoảng trắng", one(RunCardLook{ActivityID: "a1", Layout: s("km: 30,66,2")}), false},
		{"layout 201 ký tự", one(RunCardLook{ActivityID: "a1", Layout: s(strings.Repeat("a", 201))}), false},
		{"trùng id", RunCardLooksRequest{Looks: []RunCardLook{{ActivityID: "a1", Style: s("city.top")}, {ActivityID: "a1", Skin: s("dark.fire")}}}, false},
	}
	for _, c := range cases {
		if got := c.req.valid(); got != c.want {
			t.Errorf("%s: valid = %v, muốn %v", c.name, got, c.want)
		}
	}
}
