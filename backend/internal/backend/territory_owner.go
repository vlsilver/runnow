package backend

import (
	"sort"
	"time"
)

// territoryPass là một lượt qua: một buổi được tính đi qua một ô.
type territoryPass struct {
	UID, ActivityID string
	EndedAt         time.Time
	Meters          int
}

// passLess là thứ tự toàn phần của lượt qua: (endedAt, uid, activityId). Mọi
// chỗ so "trước, sau" và tách hoà đều dùng thứ tự này, để cùng một tập lượt
// luôn ra cùng một kết quả bất kể query trả về theo thứ tự nào.
func passLess(a, b territoryPass) bool {
	if !a.EndedAt.Equal(b.EndedAt) {
		return a.EndedAt.Before(b.EndedAt)
	}
	if a.UID != b.UID {
		return a.UID < b.UID
	}
	return a.ActivityID < b.ActivityID
}

// cellOwner là chủ một ô: người nhiều mét nhất, số mét của họ, và số mét của
// người thứ hai (0 khi chỉ có một người).
type cellOwner struct {
	UID    string
	Meters int
	Second int
}

// ownerOf áp luật giữ ô ở thời điểm at: cộng mét theo từng người của các lượt
// có endedAt trong (at − window, at]; ai nhiều nhất thì giữ. Hoà thì người có
// lượt sớm nhất trong cửa sổ (tức người tới trước) giữ. Không còn lượt nào
// trong cửa sổ thì ô trống (false).
func ownerOf(passes []territoryPass, at time.Time, window time.Duration) (cellOwner, bool) {
	from := at.Add(-window)
	sum := map[string]int{}
	first := map[string]territoryPass{}
	for _, p := range passes {
		if !p.EndedAt.After(from) || p.EndedAt.After(at) {
			continue
		}
		sum[p.UID] += p.Meters
		if f, ok := first[p.UID]; !ok || passLess(p, f) {
			first[p.UID] = p
		}
	}
	if len(sum) == 0 {
		return cellOwner{}, false
	}
	uids := make([]string, 0, len(sum))
	for u := range sum {
		uids = append(uids, u)
	}
	sort.Slice(uids, func(i, j int) bool {
		a, b := uids[i], uids[j]
		if sum[a] != sum[b] {
			return sum[a] > sum[b]
		}
		return passLess(first[a], first[b])
	})
	o := cellOwner{UID: uids[0], Meters: sum[uids[0]]}
	if len(uids) > 1 {
		o.Second = sum[uids[1]]
	}
	return o, true
}

// territoryResult là "+N ô" của một buổi: Gained là ô trống trước buổi mà
// buổi làm chủ nhân được, Taken là ô lấy của từng người. TakenCells ghi ô nào
// lấy của ai, để push lọc người chạy cùng theo từng ô; không lưu xuống DB.
type territoryResult struct {
	Gained     int
	Taken      map[string]int
	TakenCells map[string]string
}

// resultFor tính kết quả của buổi x theo thời điểm của chính nó. Với mỗi ô của
// x: chủ "trước" tính trên các lượt có khoá nhỏ hơn x, chủ "sau" tính thêm x,
// cả hai ở mốc x.EndedAt. Sau là chủ của x mà trước trống: ô mới. Trước là
// người khác: ô lấy của người đó. So theo thời điểm của buổi chứ không suy từ
// trạng thái chunk, nên chủ chạy lại tuyến cũ không có ô mới, và hai buổi của
// cùng một người không bị đếm đôi. others là lượt qua của mọi buổi đã biết ở
// từng ô; bản ghi của chính x trong đó tự bị loại vì không nhỏ hơn x.
func resultFor(x territoryPass, cells map[string]int, others map[string][]territoryPass, window time.Duration) territoryResult {
	res := territoryResult{Taken: map[string]int{}, TakenCells: map[string]string{}}
	for cell, meters := range cells {
		before := make([]territoryPass, 0, len(others[cell]))
		for _, p := range others[cell] {
			if passLess(p, x) {
				before = append(before, p)
			}
		}
		prev, hadOwner := ownerOf(before, x.EndedAt, window)
		self := x
		self.Meters = meters
		next, _ := ownerOf(append(before, self), x.EndedAt, window)
		if next.UID != x.UID {
			continue
		}
		switch {
		case !hadOwner:
			res.Gained++
		case prev.UID != x.UID:
			res.Taken[prev.UID]++
			res.TakenCells[cell] = prev.UID
		}
	}
	return res
}
