// 練習室「模擬社群動態」的一則貼文（display-only）。
//
// 唯一真相源是 Edge `practice-chat` 的 `mode: practice_moments`；貼文是**全域**的
// （同一位角色同一天，所有看得到她的使用者看到同一則），client 純呈現、
// **沒有任何寫入路徑**。v1 不做 Hive 離線快取（D7）：每次進畫面重抓。
import 'practice_moment_image.dart';

class PracticeMomentPost {
  const PracticeMomentPost({
    required this.profileId,
    required this.postDate,
    required this.slot,
    required this.dayPart,
    required this.postedAt,
    required this.body,
    this.imageId,
  });

  /// 發文的角色（practice_girl_NNN），對照 client 內建 catalog。
  final String profileId;

  /// 台北日（YYYY-MM-DD）；與 [slot] 共同構成 server 端的貼文主鍵。
  final String postDate;

  /// 當天第幾則（0-based）。
  final int slot;

  /// server 的時段桶（morning／afternoon／evening／late_night…），純標記用。
  final String dayPart;

  /// server 算出的發文時刻（UTC）；畫面自己轉成本地相對時間。
  final DateTime postedAt;

  /// 貼文內文（server 已過守門與繁中轉換）。
  final String body;

  /// 配圖 id；null＝純文字貼文。**不認得的 id 一律當純文字**，
  /// 見 [resolveMomentImage]（server 先開閘門、client 還沒更新時的向前相容）。
  final String? imageId;

  /// 解析後的配圖來源；null＝純文字（含「id 不認得」的降級）。
  MomentImageSource? get imageSource => resolveMomentImage(imageId);

  /// server 回傳的一則 JSON → entity。任一必要欄位缺失或型別不符回 null
  /// （壞掉的一則不該讓整份 feed 消失）。
  static PracticeMomentPost? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final profileId = raw['profileId'];
    final postDate = raw['postDate'];
    final slot = raw['slot'];
    final dayPart = raw['dayPart'];
    final postedAt = raw['postedAt'];
    final body = raw['body'];
    if (profileId is! String ||
        profileId.trim().isEmpty ||
        postDate is! String ||
        postDate.trim().isEmpty ||
        slot is! num ||
        slot < 0 ||
        dayPart is! String ||
        dayPart.trim().isEmpty ||
        postedAt is! String ||
        body is! String ||
        body.trim().isEmpty) {
      return null;
    }
    final parsedPostedAt = DateTime.tryParse(postedAt);
    if (parsedPostedAt == null) return null;
    final imageId = raw['imageId'];
    return PracticeMomentPost(
      profileId: profileId,
      postDate: postDate,
      slot: slot.toInt(),
      dayPart: dayPart,
      postedAt: parsedPostedAt.toUtc(),
      body: body,
      imageId: imageId is String && imageId.trim().isNotEmpty ? imageId : null,
    );
  }
}
