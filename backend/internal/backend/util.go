package backend

import (
	"encoding/json"
	"fmt"
	"math"
)

func jsonMarshal(v any) ([]byte, error) { return json.Marshal(v) }
func number(v any) float64 {
	switch n := v.(type) {
	case float64:
		if math.IsNaN(n) || math.IsInf(n, 0) {
			return 0
		}
		return n
	case int:
		return float64(n)
	case int64:
		return float64(n)
	case json.Number:
		f, _ := n.Float64()
		return f
	}
	return 0
}

func falseLike(value any) bool {
	return value == false || fmt.Sprint(value) == "false"
}
