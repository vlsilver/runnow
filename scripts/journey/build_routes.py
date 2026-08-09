# Generates the *_route.json files under assets/journey/ from hand-picked
# real waypoints (no OSRM road-snapping available), with a sine "wiggle"
# between waypoints to approximate a winding road/trail. Run this, then
# migrate_journey_routes.mjs to push the result to Firestore.
import json
import math
import os

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../assets/journey")


def haversine(a, b):
    lat1, lon1 = a
    lat2, lon2 = b
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    h = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlambda / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def wiggly_segment(a, b, n, amplitude_frac, cycles):
    """n interpolated points strictly between a and b (exclusive), offset
    perpendicular to the a->b line by a damped sine wave — approximates a
    winding mountain road/trail instead of a straight hop, since we don't
    have OSRM road-snapping available. Amplitude tapers to 0 at both ends
    so it still passes exactly through the named waypoints.
    """
    dlat = b[0] - a[0]
    dlon = b[1] - a[1]
    # rough local perpendicular in degree-space (fine for short segments)
    lat_scale = 111320.0
    lon_scale = 111320.0 * math.cos(math.radians((a[0] + b[0]) / 2))
    seg_len_m = haversine(a, b)
    amplitude_deg_lat = 0.0
    amplitude_deg_lon = 0.0
    if seg_len_m > 0:
        amp_m = seg_len_m * amplitude_frac
        # unit perpendicular vector in meter-space
        dx = dlon * lon_scale
        dy = dlat * lat_scale
        norm = math.hypot(dx, dy) or 1.0
        perp_x, perp_y = -dy / norm, dx / norm
        amplitude_deg_lon = (perp_x * amp_m) / lon_scale
        amplitude_deg_lat = (perp_y * amp_m) / lat_scale

    pts = []
    for i in range(1, n + 1):
        f = i / (n + 1)
        taper = math.sin(math.pi * f)  # 0 at ends, 1 at middle
        wave = math.sin(2 * math.pi * cycles * f)
        offset = taper * wave
        lat = a[0] + dlat * f + amplitude_deg_lat * offset
        lon = a[1] + dlon * f + amplitude_deg_lon * offset
        pts.append((lat, lon))
    return pts


def build_route(route_id, name, tagline, waypoints, extra_interp=10,
                 amplitude_frac=0.0, cycles=3):
    """waypoints: list of dicts {name, lat, lon, fact}. Builds a polyline
    through real named waypoints, with optional sine 'wiggle' between them
    to approximate a winding road/trail (we have no OSRM road-snapping
    available for these). totalLengthMeters + milestone cumulativeMeters
    are both computed by walking the actual emitted polyline, so the map
    marker (routePointAtDistance) always lines up with the stated total.
    """
    points = [(waypoints[0]["lat"], waypoints[0]["lon"])]
    milestone_index = [0]  # index into points[] for each waypoint, in order
    prev_coord = points[0]
    for wp in waypoints[1:]:
        coord = (wp["lat"], wp["lon"])
        for ipt in wiggly_segment(prev_coord, coord, extra_interp, amplitude_frac, cycles):
            points.append(ipt)
        points.append(coord)
        milestone_index.append(len(points) - 1)
        prev_coord = coord

    cumulative_at = [0.0] * len(points)
    for i in range(1, len(points)):
        cumulative_at[i] = cumulative_at[i - 1] + haversine(points[i - 1], points[i])

    milestones = []
    for wp, idx in zip(waypoints, milestone_index):
        milestones.append({
            "name": wp["name"],
            "lat": wp["lat"],
            "lon": wp["lon"],
            "cumulativeMeters": round(cumulative_at[idx], 1),
            "fact": wp["fact"],
            "storagePath": None,
        })

    total = cumulative_at[-1]
    data = {
        "id": route_id,
        "name": name,
        "tagline": tagline,
        "totalLengthMeters": round(total, 1),
        "points": [[round(p[0], 6), round(p[1], 6)] for p in points],
        "milestones": milestones,
    }
    path = os.path.join(OUT_DIR, f"{route_id}_route.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{route_id}: {total/1000:.1f} km -> {path}")
    return total


routes = []

# 1. Ta Nang - Phan Dung (target ~55km, hilly trail)
routes.append(build_route(
    "ta_nang_phan_dung",
    "Tà Năng – Phan Dũng",
    "Cung trekking đẹp nhất Việt Nam, băng qua ranh giới Lâm Đồng và Bình Thuận.",
    [
        {"name": "Tà Năng (xuất phát)", "lat": 11.7206, "lon": 108.4231,
         "fact": "Xã Tà Năng, huyện Đức Trọng, Lâm Đồng — điểm bắt đầu cung trekking nổi tiếng nhất Việt Nam, xuất phát từ những đồi thông cao nguyên."},
        {"name": "Cột mốc 3 tỉnh", "lat": 11.6300, "lon": 108.4900,
         "fact": "Nơi ranh giới Lâm Đồng, Ninh Thuận và Bình Thuận gặp nhau trên cung đường, một trong những điểm check-in quen thuộc của dân trekking."},
        {"name": "Sống lưng khủng long", "lat": 11.5100, "lon": 108.5500,
         "fact": "Dải đồi cỏ nhấp nhô nối tiếp nhau như xương sống khủng long — khung cảnh biểu tượng khiến cung Tà Năng – Phan Dũng được mệnh danh đẹp nhất Việt Nam."},
        {"name": "Phan Dũng (kết thúc)", "lat": 11.2950, "lon": 108.6150,
         "fact": "Xã Phan Dũng, huyện Tuy Phong, Bình Thuận — điểm về của hành trình, giáp ranh vùng đồng bằng ven biển Nam Trung Bộ."},
    ],
    extra_interp=10, amplitude_frac=0.03, cycles=3,
))

# 2. Con Dao loop (target ~75km, full-island exploration loop with spurs)
routes.append(build_route(
    "con_dao_loop",
    "Khám phá Côn Đảo",
    "Một vòng quanh đảo Côn Sơn, ghé những bãi biển và di tích lịch sử nổi tiếng.",
    [
        {"name": "Trung tâm Côn Sơn (xuất phát)", "lat": 8.6833, "lon": 106.6094,
         "fact": "Thị trấn Côn Sơn — trung tâm huyện đảo Côn Đảo, Bà Rịa – Vũng Tàu, điểm khởi hành vòng quanh đảo."},
        {"name": "Nghĩa trang Hàng Dương", "lat": 8.6875, "lon": 106.6103,
         "fact": "Nơi an nghỉ của hàng ngàn chiến sĩ cách mạng từng bị giam giữ tại nhà tù Côn Đảo — di tích lịch sử đặc biệt của cả nước."},
        {"name": "Bãi Đầm Trầu", "lat": 8.7325, "lon": 106.6333,
         "fact": "Một trong những bãi biển hoang sơ đẹp nhất Côn Đảo, nằm ngay gần sân bay Cỏ Ống."},
        {"name": "Vịnh Đầm Tre", "lat": 8.7280, "lon": 106.6550,
         "fact": "Vịnh biển yên bình phía Đông Bắc đảo, nơi rùa biển thường lên bãi đẻ trứng vào mùa sinh sản."},
        {"name": "Mũi Cá Mập – Bãi Nhát", "lat": 8.6520, "lon": 106.5850,
         "fact": "Điểm ngắm hoàng hôn nổi tiếng phía Tây Nam đảo, nhìn ra biển và các hòn đảo nhỏ lân cận."},
        {"name": "Bãi Ông Đụng", "lat": 8.6850, "lon": 106.5780,
         "fact": "Bãi biển nằm trong Vườn quốc gia Côn Đảo, nổi tiếng với rạn san hô còn hoang sơ."},
        {"name": "Về trung tâm Côn Sơn", "lat": 8.6833, "lon": 106.6094,
         "fact": "Hoàn tất vòng quanh đảo, trở về trung tâm thị trấn Côn Sơn."},
    ],
    extra_interp=14, amplitude_frac=0.30, cycles=4,
))

# 3. Saigon - Vung Tau (target 100km)
routes.append(build_route(
    "saigon_vung_tau",
    "Sài Gòn – Vũng Tàu",
    "Từ trung tâm thành phố ra tới bãi biển Vũng Tàu theo quốc lộ 51.",
    [
        {"name": "Chợ Bến Thành (xuất phát)", "lat": 10.7724, "lon": 106.6981,
         "fact": "Biểu tượng trung tâm TP.HCM, điểm xuất phát của hành trình hướng ra biển."},
        {"name": "Long Thành", "lat": 10.7860, "lon": 106.9330,
         "fact": "Cửa ngõ phía Đông TP.HCM, nơi quốc lộ 51 bắt đầu hướng về Bà Rịa – Vũng Tàu."},
        {"name": "Phú Mỹ", "lat": 10.5850, "lon": 107.0450,
         "fact": "Thị xã công nghiệp – cảng biển lớn của tỉnh Bà Rịa – Vũng Tàu, nằm ven sông Thị Vải."},
        {"name": "Bà Rịa", "lat": 10.5000, "lon": 107.1700,
         "fact": "Thành phố trung tâm hành chính tỉnh Bà Rịa – Vũng Tàu, chặng gần cuối trước khi ra biển."},
        {"name": "Bãi Sau, Vũng Tàu (kết thúc)", "lat": 10.3306, "lon": 107.0843,
         "fact": "Bãi biển dài và nổi tiếng nhất Vũng Tàu, điểm về của hành trình từ Sài Gòn."},
    ],
    extra_interp=10, amplitude_frac=0.06, cycles=3,
))

# 4. Everest Base Camp round trip (target 130km — real trek is ~65km one way)
ebc_out = [
    {"name": "Lukla (xuất phát)", "lat": 27.6869, "lon": 86.7314,
     "fact": "Sân bay núi nổi tiếng nhất Nepal, cửa ngõ duy nhất bằng đường hàng không để bắt đầu hành trình lên Everest Base Camp."},
    {"name": "Phakding", "lat": 27.7325, "lon": 86.7154,
     "fact": "Làng nhỏ ven sông Dudh Kosi, điểm nghỉ đầu tiên trên đường lên Namche Bazaar."},
    {"name": "Namche Bazaar", "lat": 27.8069, "lon": 86.7140,
     "fact": "Thị trấn Sherpa lớn nhất vùng Khumbu, trung tâm giao thương và điểm nghỉ làm quen độ cao quan trọng."},
    {"name": "Tengboche", "lat": 27.8360, "lon": 86.7642,
     "fact": "Nơi có tu viện Phật giáo Tengboche nổi tiếng, tầm nhìn hướng thẳng về đỉnh Everest và Ama Dablam."},
    {"name": "Dingboche", "lat": 27.8926, "lon": 86.8300,
     "fact": "Làng cao nguyên hơn 4.400m, điểm nghỉ làm quen độ cao thứ hai trước khi tiến sâu vào vùng núi cao."},
    {"name": "Lobuche", "lat": 27.9550, "lon": 86.8090,
     "fact": "Trạm dừng cuối cùng trước Gorak Shep, nằm dọc theo sông băng Khumbu ở độ cao gần 4.940m."},
    {"name": "Gorak Shep", "lat": 28.0026, "lon": 86.8281,
     "fact": "Làng cao nhất trên tuyến, điểm tựa để chinh phục Everest Base Camp và đỉnh Kala Patthar."},
    {"name": "Everest Base Camp", "lat": 28.0026, "lon": 86.8528,
     "fact": "Trại nền chân đỉnh Everest (5.364m) — điểm xuất phát của các đoàn leo núi chinh phục nóc nhà thế giới."},
]
ebc_return = [dict(wp, name=f"{wp['name']} (về)") for wp in reversed(ebc_out[:-1])]
routes.append(build_route(
    "everest_base_camp",
    "Everest Base Camp",
    "Khứ hồi Lukla → Everest Base Camp → Lukla qua vùng núi Khumbu, Nepal.",
    ebc_out + ebc_return,
    extra_interp=8, amplitude_frac=0.20, cycles=2,
))

# 5. Ha Noi - Ha Long (target 170km)
routes.append(build_route(
    "hanoi_ha_long",
    "Hà Nội – Hạ Long",
    "Từ Hồ Gươm tới vịnh Hạ Long qua cao tốc Hà Nội – Hải Phòng – Quảng Ninh.",
    [
        {"name": "Hồ Gươm (xuất phát)", "lat": 21.0285, "lon": 105.8542,
         "fact": "Trái tim của Hà Nội, điểm xuất phát của hành trình hướng về vịnh biển di sản."},
        {"name": "Hải Dương", "lat": 20.9373, "lon": 106.3146,
         "fact": "Thành phố nằm giữa tuyến cao tốc Hà Nội – Hải Phòng, vùng đồng bằng sông Hồng trù phú."},
        {"name": "Hải Phòng", "lat": 20.8449, "lon": 106.6881,
         "fact": "Thành phố cảng biển lớn nhất miền Bắc, nơi giao nhau giữa hành trình đường bộ và cửa ngõ biển."},
        {"name": "Bãi Cháy, Hạ Long (kết thúc)", "lat": 20.9580, "lon": 107.0508,
         "fact": "Khu du lịch ven vịnh Hạ Long — di sản thiên nhiên thế giới với hàng ngàn đảo đá vôi, điểm về của hành trình."},
    ],
    extra_interp=10, amplitude_frac=0.11, cycles=3,
))

# 6. Saigon - Mui Ne (target 220km)
routes.append(build_route(
    "saigon_mui_ne",
    "Sài Gòn – Mũi Né",
    "Từ trung tâm thành phố tới thủ phủ resort ven biển Mũi Né, Phan Thiết.",
    [
        {"name": "Chợ Bến Thành (xuất phát)", "lat": 10.7724, "lon": 106.6981,
         "fact": "Điểm xuất phát của hành trình hướng ra vùng biển Nam Trung Bộ."},
        {"name": "Long Khánh", "lat": 10.9330, "lon": 107.2440,
         "fact": "Thị xã trung tâm vùng cây ăn trái Đồng Nai, chặng giữa trên quốc lộ 1 hướng ra biển."},
        {"name": "Phan Thiết", "lat": 10.9280, "lon": 108.1020,
         "fact": "Thành phố biển của tỉnh Bình Thuận, nổi tiếng với đồi cát và làng chài truyền thống."},
        {"name": "Mũi Né (kết thúc)", "lat": 10.9333, "lon": 108.2833,
         "fact": "Thủ phủ resort và lướt ván diều của Việt Nam, điểm về của hành trình."},
    ],
    extra_interp=10, amplitude_frac=0.10, cycles=3,
))

# 7. Camino Portugues (target 260km, real central route ~243.5km)
routes.append(build_route(
    "camino_portugues",
    "Camino Portugués",
    "Cung đường hành hương cổ từ Porto, Bồ Đào Nha tới Santiago de Compostela, Tây Ban Nha.",
    [
        {"name": "Porto (xuất phát)", "lat": 41.1579, "lon": -8.6291,
         "fact": "Thành phố cảng nổi tiếng miền Bắc Bồ Đào Nha, điểm bắt đầu phổ biến nhất của Camino Portugués."},
        {"name": "Barcelos", "lat": 41.5388, "lon": -8.6151,
         "fact": "Thị trấn cổ nổi tiếng với truyền thuyết 'Con gà Barcelos', biểu tượng văn hoá dân gian Bồ Đào Nha."},
        {"name": "Ponte de Lima", "lat": 41.7700, "lon": -8.5850,
         "fact": "Thị trấn cổ nhất Bồ Đào Nha, có cây cầu La Mã – Trung cổ nổi tiếng bắc qua sông Lima."},
        {"name": "Tui (biên giới Tây Ban Nha)", "lat": 42.0500, "lon": -8.6450,
         "fact": "Thị trấn biên giới nơi khách hành hương vượt sông Minho từ Bồ Đào Nha sang Tây Ban Nha."},
        {"name": "Pontevedra", "lat": 42.4310, "lon": -8.6444,
         "fact": "Thành phố cổ vùng Galicia, một trong những trạm nghỉ lớn trên cung đường hành hương."},
        {"name": "Padrón", "lat": 42.7422, "lon": -8.6600,
         "fact": "Thị trấn gắn liền truyền thuyết Thánh Giacôbê, chặng gần cuối trước khi tới Santiago."},
        {"name": "Santiago de Compostela (kết thúc)", "lat": 42.8782, "lon": -8.5448,
         "fact": "Thánh địa hành hương nổi tiếng thế giới, nơi lưu giữ hài cốt Thánh Giacôbê — điểm về của Camino Portugués."},
    ],
    extra_interp=10, amplitude_frac=0.11, cycles=3,
))

# 8. Saigon - Da Lat (target 310km)
routes.append(build_route(
    "saigon_da_lat",
    "Sài Gòn – Đà Lạt",
    "Từ trung tâm thành phố lên thành phố ngàn hoa Đà Lạt qua Bảo Lộc, Đức Trọng.",
    [
        {"name": "Chợ Bến Thành (xuất phát)", "lat": 10.7724, "lon": 106.6981,
         "fact": "Điểm xuất phát của hành trình lên cao nguyên Lâm Viên."},
        {"name": "Dầu Giây", "lat": 10.9330, "lon": 107.1500,
         "fact": "Ngã ba giao thông quan trọng của Đồng Nai, nơi quốc lộ 1 và quốc lộ 20 lên Đà Lạt gặp nhau."},
        {"name": "Bảo Lộc", "lat": 11.5460, "lon": 107.8090,
         "fact": "Thành phố cao nguyên nổi tiếng với trà và cà phê, chặng giữa trên đường lên Đà Lạt."},
        {"name": "Đức Trọng", "lat": 11.7500, "lon": 108.2600,
         "fact": "Cửa ngõ phía Nam của Đà Lạt, nơi cao nguyên Lâm Viên hiện ra rõ nét."},
        {"name": "Hồ Xuân Hương, Đà Lạt (kết thúc)", "lat": 11.9404, "lon": 108.4400,
         "fact": "Hồ nước giữa trung tâm thành phố Đà Lạt, biểu tượng của thành phố ngàn hoa — điểm về của hành trình."},
    ],
    extra_interp=10, amplitude_frac=0.12, cycles=3,
))

# 9. Vong cung Ha Giang loop (target 350km, very winding mountain road)
hg_out = [
    {"name": "Hà Giang (xuất phát)", "lat": 22.8025, "lon": 104.9784,
     "fact": "Thành phố trung tâm tỉnh Hà Giang, cửa ngõ của cao nguyên đá Đồng Văn."},
    {"name": "Cổng trời Quản Bạ", "lat": 23.0270, "lon": 104.9950,
     "fact": "Điểm dừng chân nổi tiếng với Núi Đôi Quản Bạ, ranh giới bước vào cao nguyên đá."},
    {"name": "Yên Minh", "lat": 23.1200, "lon": 105.2300,
     "fact": "Thị trấn có rừng thông nổi tiếng giữa cao nguyên đá tai mèo Hà Giang."},
    {"name": "Đồng Văn", "lat": 23.2739, "lon": 105.3639,
     "fact": "Phố cổ Đồng Văn hơn 100 năm tuổi, trung tâm văn hoá của cao nguyên đá Đồng Văn."},
    {"name": "Đèo Mã Pí Lèng", "lat": 23.2170, "lon": 105.4100,
     "fact": "Một trong 'tứ đại đỉnh đèo' Việt Nam, nhìn xuống hẻm vực sông Nho Quế hùng vĩ."},
    {"name": "Mèo Vạc", "lat": 23.1236, "lon": 105.4067,
     "fact": "Huyện vùng cao cực Bắc, nơi kết thúc cung đèo Mã Pí Lèng và bắt đầu đường vòng trở lại Hà Giang."},
]
hg_return = [dict(wp, name=f"{wp['name']} (về)") for wp in reversed(hg_out[:-1])]
hg_return.append({"name": "Về Hà Giang (kết thúc)", "lat": 22.8025, "lon": 104.9784,
                   "fact": "Hoàn tất vòng cung Hà Giang, trở lại thành phố xuất phát."})
routes.append(build_route(
    "vong_cung_ha_giang",
    "Vòng cung Hà Giang",
    "Vòng cung huyền thoại Hà Giang → Đồng Văn → Mèo Vạc → Hà Giang qua cao nguyên đá.",
    hg_out + hg_return,
    extra_interp=10, amplitude_frac=0.24, cycles=3,
))

# Ghi chú: cung "dong_nam_a" (Xuyên thủ đô Đông Nam Á) KHÔNG dùng waypoint-wiggle
# ở đây mà bám đường thật qua OSRM — xem scripts/journey/build_dong_nam_a.py.

print("---")
print("Total routes built:", len(routes))
