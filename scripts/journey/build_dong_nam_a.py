# Dung cung "dong_nam_a" (Xuyen thu do Dong Nam A) bam DUONG THAT qua OSRM,
# tranh cat bien. Point-to-point (khong loop): Ha Noi -> 7 thu do -> Singapore.
# Chay: python3 build_dong_nam_a.py  (can mang, dung OSRM demo server).
# Sau do upload bang uploader Go / migrate_journey_routes.mjs.
import json
import math
import os
import time
import urllib.request

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../assets/journey")
OSRM = "http://router.project-osrm.org/route/v1/driving"

# 7 thu do dat lien Dong Nam A, theo thu tu it backtrack nhat, bat dau Ha Noi.
CAPITALS = [
    {"name": "Hà Nội (xuất phát)", "lat": 21.0285, "lon": 105.8542,
     "fact": "Thủ đô Việt Nam — điểm khởi hành hành trình xuyên qua các thủ đô Đông Nam Á."},
    {"name": "Viêng Chăn (Lào)", "lat": 17.9757, "lon": 102.6331,
     "fact": "Thủ đô Lào yên bình bên bờ sông Mê Kông, chặng đầu ra khỏi biên giới Việt Nam."},
    {"name": "Naypyidaw (Myanmar)", "lat": 19.7450, "lon": 96.1297,
     "fact": "Thủ đô Myanmar — thành phố quy hoạch rộng lớn giữa miền trung đất nước."},
    {"name": "Bangkok (Thái Lan)", "lat": 13.7563, "lon": 100.5018,
     "fact": "Thủ đô Thái Lan — thành phố của những ngôi chùa vàng và kênh rạch sầm uất."},
    {"name": "Phnom Penh (Campuchia)", "lat": 11.5564, "lon": 104.9282,
     "fact": "Thủ đô Campuchia, nơi các nhánh sông Mê Kông và Tonlé Sap gặp nhau."},
    {"name": "Kuala Lumpur (Malaysia)", "lat": 3.1390, "lon": 101.6869,
     "fact": "Thủ đô Malaysia với tháp đôi Petronas biểu tượng."},
    {"name": "Singapore (kết thúc)", "lat": 1.3521, "lon": 103.8198,
     "fact": "Đảo quốc sư tử gần xích đạo — chặng cuối của hành trình xuyên Đông Nam Á."},
]


def haversine(a, b):
    lat1, lon1, lat2, lon2 = a[0], a[1], b[0], b[1]
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    h = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def leg_geometry(a, b):
    url = f"{OSRM}/{a['lon']},{a['lat']};{b['lon']},{b['lat']}?overview=full&geometries=geojson"
    with urllib.request.urlopen(url, timeout=40) as resp:
        data = json.load(resp)
    if data.get("code") != "Ok":
        raise RuntimeError(f"OSRM {a['name']} -> {b['name']}: {data.get('code')}")
    # coords: [[lon,lat],...] -> [(lat,lon),...]
    return [(c[1], c[0]) for c in data["routes"][0]["geometry"]["coordinates"]]


# Downsample: OSRM tra ~65k diem (full duong) -> vuot 1MB/doc Firestore + nang
# app. Giu mat do ~1 diem/3km (giong cac cung khac), luon giu diem thu do.
DOWNSAMPLE_METERS = 3000.0


def downsample(points, keep_idx):
    keep = set(keep_idx)
    out_points = []
    out_keep = []
    last = None
    for i, p in enumerate(points):
        forced = i in keep or i == len(points) - 1
        if last is None or forced or haversine(last, p) >= DOWNSAMPLE_METERS:
            if i in keep:
                out_keep.append(len(out_points))
            out_points.append(p)
            last = p
    return out_points, out_keep


def main():
    points = []               # [(lat,lon)]
    milestone_index = []      # index vao points[] cho moi thu do
    for i in range(len(CAPITALS) - 1):
        seg = leg_geometry(CAPITALS[i], CAPITALS[i + 1])
        if i == 0:
            milestone_index.append(0)
            points.extend(seg)
        else:
            # bo diem dau trung voi diem cuoi leg truoc (deu la thu do noi)
            milestone_index.append(len(points) - 1)
            points.extend(seg[1:])
        time.sleep(1)  # nhe tay voi OSRM demo
    milestone_index.append(len(points) - 1)  # thu do cuoi (Singapore)

    points, milestone_index = downsample(points, milestone_index)

    cumulative = [0.0] * len(points)
    for i in range(1, len(points)):
        cumulative[i] = cumulative[i - 1] + haversine(points[i - 1], points[i])

    # Anh landmark tren Storage (journey/photos/<slug>.jpg) — anh CC0 lay tu
    # Openverse, xem scripts/journey/fetch + assets/journey/capitals/.
    slugs = ["ha_noi", "vientiane", "naypyidaw", "bangkok",
             "phnom_penh", "kuala_lumpur", "singapore"]
    milestones = []
    for cap, idx, slug in zip(CAPITALS, milestone_index, slugs):
        milestones.append({
            "name": cap["name"],
            "lat": points[idx][0],
            "lon": points[idx][1],
            "cumulativeMeters": round(cumulative[idx], 1),
            "fact": cap["fact"],
            "storagePath": f"journey/photos/{slug}.jpg",
        })

    data = {
        "id": "dong_nam_a",
        "name": "Đông Nam Á",
        "tagline": "Từ Hà Nội xuyên qua 7 thủ đô Đông Nam Á — Viêng Chăn, Naypyidaw, Bangkok, Phnom Penh, Kuala Lumpur — về đích Singapore.",
        "totalLengthMeters": round(cumulative[-1], 1),
        "points": [[round(p[0], 6), round(p[1], 6)] for p in points],
        "milestones": milestones,
    }
    path = os.path.join(OUT_DIR, "dong_nam_a_route.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print(f"dong_nam_a: {cumulative[-1]/1000:.1f} km, {len(points)} points, "
          f"{len(milestones)} milestones -> {path}")


if __name__ == "__main__":
    main()
