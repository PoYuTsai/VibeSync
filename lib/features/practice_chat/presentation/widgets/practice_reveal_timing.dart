// 翻牌揭曉 V3 時間軸的單一真相（儀式 widget 與測試共用）。
// 規格：docs/plans/2026-10-15-card-draw-v3-luxury-reveal-spec.md §4；V3.1 第一刀
// （docs/plans/2026-10-17-card-draw-v3-1-polish-spec.md §5.1–§5.3、§5.5–§5.7、§5.9–§5.12、
// §5.15）在同一條時間軸上加光效、改稀有度牌與收卡，節點不動。
//
// 三條有限 controller 各自以起點為 0：
// - drawing：以按下翻牌為 0（[PracticeRevealTiming.intro]／[PracticeRevealTiming.caption]）。
// - revealing：以 R0 為 0＝server 成功回來「且」卡背入場已完成（[PracticeRevealTiming.reveal]）。
// - archiving：以點擊收卡為 0（[PracticeRevealTiming.archive]）。
// 揭曉走完之後是 holding：畫面完全靜止，等使用者點擊，沒有任何計時器。
import 'dart:math' as math;

import 'package:flutter/animation.dart';

import '../../../../core/theme/app_motion.dart';
import '../../domain/entities/practice_girl_rarity.dart';

abstract final class PracticeRevealTiming {
  // ── drawing（以按下翻牌為 0）──
  static const Duration intro = Duration(milliseconds: 500);
  static const double introBackdropEndMs = 300;
  static const double introCardStartMs = 100;
  static const double introCardFadeEndMs = 300;

  /// 等待字樣：server 超過 900 ms 還沒回來才淡入，快的時候根本不出現。
  static const Duration caption = Duration(milliseconds: 1200);
  static const double captionFadeStartMs = 900;

  /// 等待姿態（V3.1 §5.9）：斜放 yaw −10°、pitch 4°，再加左右微擺 ±4°、上下 ±5 px。
  static const double waitingYaw = -10;
  static const double waitingPitch = 4;
  static const double waitingSway = 4;
  static const double waitingBob = 5;

  /// 等待心跳（V3.1 §5.15，以按下翻牌為 0）：卡背入場走完起，每 900 ms 一組兩下（相隔
  /// 140 ms），最多 6 組。每下卡背 60 ms 衝上、90 ms 回落，水平顫動 120 ms。
  static const double heartbeatStartMs = 500;
  static const double heartbeatPeriodMs = 900;
  static const double heartbeatGapMs = 140;
  static const int heartbeatMaxGroups = 6;
  static const double heartbeatRiseMs = 60;
  static const double heartbeatFallMs = 90;
  static const double heartbeatShiverMs = 120;

  // ── revealing（以 R0 為 0）──
  static const Duration reveal = Duration(milliseconds: 2700);

  /// 等待呼吸的位置、縮放、亮度在這段內混到蓄力姿態，避免跳格。
  static const double poseBlendMs = 150;
  static const double captionOutMs = 200;
  static const double chargeEndMs = 600;

  /// 蓄力三下輕震（第一下在 R0）。
  static const double chargeTick1Ms = 200;
  static const double chargeTick2Ms = 400;

  /// 徽記白光（V3.1 §5.2）：三種稀有度都一樣，不洩漏稀有度；600 衝到 0.95、720 退掉。
  static const double whiteFlashStartMs = 560;
  static const double whiteFlashPeakMs = 600;
  static const double whiteFlashEndMs = 720;

  /// 卡背染色只升到真實稀有度。R／SR 第一段：銀 → 電光藍，徽記亮度衝到 1.0。
  static const double dyeBlueMs = 600;
  static const double dyeBlueEndMs = 720;

  /// N 不變色，只做一次銀光脈衝（0.80 → 1.00 → 0.85）。
  static const double silverPulsePeakMs = 700;
  static const double silverPulseEndMs = 800;

  /// SR 第二段：藍 → 香檳金，外框疊上全息彩邊。V3 這一刻的徽記白色爆閃已拿掉：徽記白光
  /// （600）、染金、翻牌三下擠在 1 s 內，就超過閃光上限（V3.1 §3，#107 P2-1）。
  static const double dyeGoldMs = 850;
  static const double dyeGoldEndMs = 1000;
  static const double flipStartMs = 1100;

  /// SR 的 celebrate 三下共 200 ms，提前起手讓第三下重擊落在翻牌峰值。
  static const double srBuildMs = 1150;

  /// 卡片正好側立（yaw 90°）：換面＋光刃＋星塵爆發＋最重的一下觸覺。
  static const double flipPeakMs = 1350;
  static const double flipEndMs = 1800;

  /// 光刃（V3.1 §5.5）：外暈 20 ms 就張開、之後快收；N／R 共 280 ms、SR 350 ms。SR 另加
  /// 一道 400 ms、橫跨整個螢幕的十字光。不慢慢張開：卡面轉開會蓋住後層泛光，外暈晚到就是
  /// 先一暗、光刃再一亮，SR 拿近到 20 cm 會多一次閃光（量實際畫面，V3.1 §3）。
  static const double bladeOpenMs = 20;
  static const double bladeMs = 280;
  static const double bladeSrMs = 350;
  static const double crossMs = 400;

  /// 前層泛光（V3.1 §5.1）：卡片側立前這麼久起亮、側立最亮，之後 [bloomFrontFadeMs] 退掉。
  static const double bloomFrontLeadMs = 50;
  static const double bloomFrontFadeMs = 300;

  /// 翻牌峰值的衝擊波光環（V3.1 §5.6）：R 一圈 400 ms；SR 兩圈各 500 ms、相隔 120 ms。
  static const double shockRMs = 400;
  static const double shockSrMs = 500;
  static const double shockSrGapMs = 120;

  /// 翻牌落定前點擊一律不理；落定後點擊＝快轉到資訊全部落位。
  static const double skipFromMs = 1800;
  static const Duration skip = Duration(milliseconds: 180);
  static const double photoZoomStartMs = 1500;

  /// 全息斜向掃光：光帶從卡片左外側（−120%）掃到右外側（+120%）。
  static const double sheenStartMs = 1700;
  static const double sheenEndMs = 2400;
  static const double infoStartMs = 1850;
  static const double infoEndMs = 2150;

  /// 稀有度牌（V3.1 §5.10 六角牌）：1940 從畫面左上外面出現（在這之前牌根本不存在、
  /// 不先掛別的稀有度），120 ms 內飛到卡片左上角＝2060 落地，再 160 ms 回彈。
  static const double stampStartMs = 1940;
  static const double stampLandMs = 2060;
  static const double stampBounceMs = 160;

  /// SR 牌落地的小光環：以牌為中心，半徑 20 → 60 px、300 ms。
  static const double badgeRingMs = 300;

  /// 星星逐顆點亮（只畫亮星）：第 i 顆從 2150＋80·i 起跳，每顆 220 ms；同時閃一個 250 ms
  /// 的四芒星光、噴 6 顆 300 ms 的小光點（V3.1 §5.11）。
  static const double starsStartMs = 2150;
  static const double starStaggerMs = 80;
  static const double starPopMs = 220;
  static const double starSparkleMs = 250;
  static const double starDotsMs = 300;
  static const int starDotCount = 6;
  static const double hintStartMs = 2400;

  /// NEW 小標（V3.1 規格 §5.14）：只有新卡才有，掛在稀有度牌右邊；牌落地（2060）、回彈
  /// 快結束時浮現（§4 時間軸 2150–2300）。
  static const double newTagStartMs = 2150;
  static const double newTagEndMs = 2300;

  /// 角色第一句話（V3.1 規格 §5.13）：資訊欄浮出後對話框 100 ms 淡入，逐字打到 2650，
  /// 停住前打完。
  static const double introLineStartMs = 2150;
  static const double introLineFadeMs = 100;
  static const double introLineEndMs = 2650;

  // ── archiving（以點擊收卡為 0）──
  static const Duration archive = Duration(milliseconds: 700);

  /// 收卡第一拍：資訊欄、稀有度牌、星星在 80 ms 內淡掉；卡片 0–120 ms 轉向側面（yaw
  /// 180° → 260°）並縮到 0.7 倍、發主題光，看起來收成一條細線（V3.1 §5.12）。
  static const double archiveInfoOutMs = 80;
  static const double archiveLineEndMs = 120;
  static const double archiveLineYaw = 80;
  static const double archiveLineScale = 0.7;

  /// 120–150 ms 細線縮成光球。
  static const double collapseEndMs = 150;
  static const double cardFadeStartMs = 120;
  static const double orbAppearStartMs = 120;
  static const double flightStartMs = 150;

  /// 光球落進圖鑑格：圖鑑頁在這一刻點亮那一格。
  static const double landMs = 450;
  static const double orbVanishMs = 60;
  static const double backdropOutStartMs = 150;
  static const double backdropOutEndMs = 500;
  static const double hintOutEndMs = 150;

  /// 找不到目標格時，光球在原地縮到 0 的結束點。
  static const double implodeEndMs = 350;

  /// 收卡路上灑出的星點：各自向外漂 20 px、300 ms 淡掉。
  static const int sparkleCount = 14;
  static const double sparkleLifeMs = 300;

  /// 光尾：取路徑上 t−0.5 到 t 之間 32 個點連成帶狀，光球端 16 px 漸細到 0。
  static const double tailSpan = 0.5;
  static const int tailPoints = 32;
  static const double tailWidth = 16;

  /// 落位（450–700 ms）：大四芒星爆光 250 ms（規格寫 260，會超出收卡 10 ms，取 250 剛好
  /// 在 700 收完），兩圈光環 450–650、500–700。
  static const double landBurstMs = 250;
  static const double landRing1EndMs = 650;
  static const double landRing2StartMs = 500;

  static double get revealMs => reveal.inMilliseconds.toDouble();
  static double get introMs => intro.inMilliseconds.toDouble();
  static double get captionMs => caption.inMilliseconds.toDouble();
  static double get archiveMs => archive.inMilliseconds.toDouble();

  // ── 曲線（DESIGN.md §6：只用 AppMotion 與 Flutter 內建）──
  static const Curve enter = AppMotion.easeOut;
  static const Curve charge = Curves.easeInOutCubic;

  /// 翻牌前半：等於提案的 cubic-bezier(0.6, -0.28, 0.735, 0.045)，會先往回拉一點再衝。
  static const Curve flipIn = Curves.easeInBack;

  /// 翻牌後半：高阻尼減速；肉眼與提案的 cubic-bezier(0.16, 1, 0.3, 1) 幾乎一樣。
  static const Curve settle = AppMotion.easeOut;

  static const Curve sheen = Curves.easeInOut;
  static const Curve flight = Curves.easeInOutCubic;
}

/// [from]–[to] 區段內的線性進度（0..1）。
double practiceRevealSeg(double ms, double from, double to) =>
    ((ms - from) / (to - from)).clamp(0.0, 1.0);

/// 揭曉卡片姿態，yaw／pitch 單位是度：蓄力縮小後仰（V3.1 §5.9：yaw −15°、pitch 9°、
/// 0.90 倍）→ 翻牌前半加速 → 正好側立 90° → 後半減速落定在 180°（正面朝向使用者）。
({double yaw, double pitch, double scale}) practiceRevealPose(double ms) {
  final charge = PracticeRevealTiming.charge.transform(
    practiceRevealSeg(ms, 0, PracticeRevealTiming.chargeEndMs),
  );
  if (ms < PracticeRevealTiming.flipPeakMs) {
    final flipIn = ms <= PracticeRevealTiming.flipStartMs
        ? 0.0
        : PracticeRevealTiming.flipIn.transform(
            practiceRevealSeg(
              ms,
              PracticeRevealTiming.flipStartMs,
              PracticeRevealTiming.flipPeakMs,
            ),
          );
    // easeInBack 前段略小於 0：卡片先往回拉約 10° 再衝，這是刻意的預備動作。
    return (
      yaw: -15 * charge + 105 * flipIn,
      pitch: 9 * charge,
      scale: 1 - 0.10 * charge,
    );
  }
  final out = PracticeRevealTiming.settle.transform(
    practiceRevealSeg(
      ms,
      PracticeRevealTiming.flipPeakMs,
      PracticeRevealTiming.flipEndMs,
    ),
  );
  return (yaw: 90 + 90 * out, pitch: 9 * (1 - out), scale: 0.90 + 0.10 * out);
}

/// yaw 超過 90° 才畫正面；剛好 90° 卡片側立看不見，由光刃遮住換面。
bool practiceRevealShowsFront(double ms) => practiceRevealPose(ms).yaw > 90;

/// 蓄力亮度（0..1）：蓄力段漸亮，之後維持滿。
double practiceRevealChargeGlow(double ms) =>
    PracticeRevealTiming.charge.transform(
      practiceRevealSeg(ms, 0, PracticeRevealTiming.chargeEndMs),
    );

/// 卡背染色進度：`blue`＝銀 → 電光藍，`gold`＝藍 → 香檳金。只升到真實稀有度：
/// N 兩個都恆 0（全程銀）、R 的 `gold` 恆 0；不做「先金後退回藍」的假動作。
({double blue, double gold}) practiceRevealDye(
  double ms,
  PracticeGirlRarity rarity,
) {
  if (rarity == PracticeGirlRarity.n) return (blue: 0.0, gold: 0.0);
  final blue = PracticeRevealTiming.enter.transform(
    practiceRevealSeg(
      ms,
      PracticeRevealTiming.dyeBlueMs,
      PracticeRevealTiming.dyeBlueEndMs,
    ),
  );
  if (rarity == PracticeGirlRarity.r) return (blue: blue, gold: 0.0);
  final gold = PracticeRevealTiming.enter.transform(
    practiceRevealSeg(
      ms,
      PracticeRevealTiming.dyeGoldMs,
      PracticeRevealTiming.dyeGoldEndMs,
    ),
  );
  return (blue: blue, gold: gold);
}

/// 卡背徽記亮度（0..1）：蓄力 0.35 → 0.80；N 再做一次 0.80 → 1.00 → 0.85 的銀光
/// 脈衝；R／SR 染藍時衝到 1.0 並維持。
double practiceRevealEmblemGlow(double ms, PracticeGirlRarity rarity) {
  final charged = 0.35 + 0.45 * practiceRevealChargeGlow(ms);
  if (ms < PracticeRevealTiming.dyeBlueMs) return charged;
  if (rarity == PracticeGirlRarity.n) {
    if (ms < PracticeRevealTiming.silverPulsePeakMs) {
      return 0.80 +
          0.20 *
              Curves.easeOut.transform(
                practiceRevealSeg(
                  ms,
                  PracticeRevealTiming.dyeBlueMs,
                  PracticeRevealTiming.silverPulsePeakMs,
                ),
              );
    }
    return 1.0 -
        0.15 *
            Curves.easeIn.transform(
              practiceRevealSeg(
                ms,
                PracticeRevealTiming.silverPulsePeakMs,
                PracticeRevealTiming.silverPulseEndMs,
              ),
            );
  }
  return 0.80 +
      0.20 *
          PracticeRevealTiming.enter.transform(
            practiceRevealSeg(
              ms,
              PracticeRevealTiming.dyeBlueMs,
              PracticeRevealTiming.dyeBlueEndMs,
            ),
          );
}

/// 卡片背後環境光的放大倍率：1.00 →（染藍）1.15 →（染金）1.35。
double practiceRevealAmbientScale(double ms, PracticeGirlRarity rarity) {
  final dye = practiceRevealDye(ms, rarity);
  return 1 + 0.15 * dye.blue + 0.20 * dye.gold;
}

/// 光刃總長：N／R 280 ms、SR 350 ms（V3.1 §5.5）。
double practiceRevealBladeMs(PracticeGirlRarity rarity) =>
    rarity == PracticeGirlRarity.sr
        ? PracticeRevealTiming.bladeSrMs
        : PracticeRevealTiming.bladeMs;

/// 光刃外暈寬度（0..1，乘上主題的最寬倍率）：卡片側立後 [PracticeRevealTiming.bladeOpenMs]
/// 張開，之後快收（先快後慢），照片很快露出來。
double practiceRevealBladeWidth(
  double ms, [
  PracticeGirlRarity rarity = PracticeGirlRarity.n,
]) {
  final t = ms - PracticeRevealTiming.flipPeakMs;
  final total = practiceRevealBladeMs(rarity);
  if (t <= 0 || t >= total) return 0;
  if (t < PracticeRevealTiming.bladeOpenMs) {
    return PracticeRevealTiming.enter
        .transform(t / PracticeRevealTiming.bladeOpenMs);
  }
  return 1 -
      Curves.easeOutCubic.transform(
        (t - PracticeRevealTiming.bladeOpenMs) /
            (total - PracticeRevealTiming.bladeOpenMs),
      );
}

/// 光刃白色核心的粗細（px）：3 → 1；光刃時段外回 0。
double practiceRevealBladeCore(
  double ms, [
  PracticeGirlRarity rarity = PracticeGirlRarity.n,
]) {
  final t = ms - PracticeRevealTiming.flipPeakMs;
  final total = practiceRevealBladeMs(rarity);
  if (t < 0 || t >= total) return 0;
  return 3 - 2 * t / total;
}

/// 光刃白色核心的不透明度：最後 50 ms 淡掉，不會一刀切。
double practiceRevealBladeCoreAlpha(
  double ms, [
  PracticeGirlRarity rarity = PracticeGirlRarity.n,
]) {
  final t = ms - PracticeRevealTiming.flipPeakMs;
  final total = practiceRevealBladeMs(rarity);
  if (t < 0 || t >= total) return 0;
  return 1 - practiceRevealSeg(t, total - 50, total);
}

/// SR 的橫向十字光（0..1）：卡片側立起 400 ms 的鐘形（V3.1 §5.5）。N／R 恆 0。
double practiceRevealCross(double ms, PracticeGirlRarity rarity) {
  if (rarity != PracticeGirlRarity.sr) return 0;
  final t =
      (ms - PracticeRevealTiming.flipPeakMs) / PracticeRevealTiming.crossMs;
  if (t <= 0 || t >= 1) return 0;
  return math.sin(math.pi * t);
}

/// 全息掃光的光帶位置（以卡寬為單位，−1.2 → +1.2）。時段外回 null＝不畫。
double? practiceRevealSheenX(double ms) {
  if (ms <= PracticeRevealTiming.sheenStartMs ||
      ms >= PracticeRevealTiming.sheenEndMs) {
    return null;
  }
  return -1.2 +
      2.4 *
          PracticeRevealTiming.sheen.transform(
            practiceRevealSeg(
              ms,
              PracticeRevealTiming.sheenStartMs,
              PracticeRevealTiming.sheenEndMs,
            ),
          );
}

/// 稀有度牌已經出現（在這之前牌不存在）。
bool practiceRevealStamped(double ms) =>
    ms >= PracticeRevealTiming.stampStartMs;

/// 稀有度牌飛入進度（0..1，easeIn）：0＝在畫面左上外面，1＝落在卡片左上角（2060）。
double practiceRevealStampFlight(double ms) => Curves.easeIn.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.stampStartMs,
        PracticeRevealTiming.stampLandMs,
      ),
    );

/// 稀有度牌縮放：飛行中 1.4 → 1.0（落地那一刻剛好 1.0），再 160 ms 回彈 1.0 → 0.95 → 1.0。
double practiceRevealStampScale(double ms) {
  if (ms < PracticeRevealTiming.stampLandMs) {
    return 1.4 - 0.4 * practiceRevealStampFlight(ms);
  }
  final t = practiceRevealSeg(
    ms,
    PracticeRevealTiming.stampLandMs,
    PracticeRevealTiming.stampLandMs + PracticeRevealTiming.stampBounceMs,
  );
  return 1 - 0.05 * math.sin(math.pi * t);
}

/// 第 [index] 顆星的起跳時間。
double practiceRevealStarStartMs(int index) =>
    PracticeRevealTiming.starsStartMs +
    PracticeRevealTiming.starStaggerMs * index;

double _starT(double ms, int index) {
  final start = practiceRevealStarStartMs(index);
  return practiceRevealSeg(ms, start, start + PracticeRevealTiming.starPopMs);
}

/// 第 [index] 顆星的縮放：0 → 1.35（前 60%）→ 1.00（後 40%）；起跳前 0＝不畫。
double practiceRevealStarScale(double ms, int index) {
  final t = _starT(ms, index);
  if (t <= 0) return 0;
  if (t < 0.6) return 1.35 * Curves.easeOut.transform(t / 0.6);
  return 1.35 - 0.35 * Curves.easeInOut.transform((t - 0.6) / 0.4);
}

/// 第 [index] 顆星點亮時的一次發光脈衝（0..1）。
double practiceRevealStarPulse(double ms, int index) {
  final t = _starT(ms, index);
  if (t <= 0 || t >= 1) return 0;
  return math.sin(math.pi * t);
}

/// 照片緩縮倍率：翻開時 1.08，1500 ms 起緩縮到 1.00（揭曉結束）。
double practiceRevealPhotoScale(double ms) =>
    1.08 -
    0.08 *
        Curves.easeOut.transform(
          practiceRevealSeg(
            ms,
            PracticeRevealTiming.photoZoomStartMs,
            PracticeRevealTiming.revealMs,
          ),
        );

/// 資訊欄浮出（0..1）。
double practiceRevealInfoAppear(double ms) =>
    PracticeRevealTiming.enter.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.infoStartMs,
        PracticeRevealTiming.infoEndMs,
      ),
    );

/// NEW 小標浮現（0..1）。
double practiceRevealNewTagAppear(double ms) =>
    PracticeRevealTiming.enter.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.newTagStartMs,
        PracticeRevealTiming.newTagEndMs,
      ),
    );

/// 角色第一句話的對話框淡入（0..1）。
double practiceRevealIntroLineOpacity(double ms) => practiceRevealSeg(
      ms,
      PracticeRevealTiming.introLineStartMs,
      PracticeRevealTiming.introLineStartMs +
          PracticeRevealTiming.introLineFadeMs,
    );

/// 角色第一句話打出來的比例（0..1）：等速逐字，揭曉結束前打完。
double practiceRevealIntroLineTyped(double ms) => practiceRevealSeg(
      ms,
      PracticeRevealTiming.introLineStartMs,
      PracticeRevealTiming.introLineEndMs,
    );

/// 「點擊任意處繼續」淡入（0..1），揭曉結束時正好全亮。
double practiceRevealHintIn(double ms) => PracticeRevealTiming.enter.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.hintStartMs,
        PracticeRevealTiming.revealMs,
      ),
    );

/// drawing：背景暗化進場（0..1）。失敗時 `_intro` 倒轉，暗化跟著退。
double practiceIntroBackdrop(double ms) => PracticeRevealTiming.enter.transform(
      practiceRevealSeg(ms, 0, PracticeRevealTiming.introBackdropEndMs),
    );

/// drawing：卡背入場進度（0..1），驅動 scale 0.85→1 與 translateY 30→0。
double practiceIntroCard(double ms) => PracticeRevealTiming.enter.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.introCardStartMs,
        PracticeRevealTiming.introMs,
      ),
    );

/// drawing：卡背不透明度（0..1）。
double practiceIntroCardOpacity(double ms) => practiceRevealSeg(
      ms,
      PracticeRevealTiming.introCardStartMs,
      PracticeRevealTiming.introCardFadeEndMs,
    );

/// drawing：等待字樣淡入（0..1）。
double practiceCaptionIn(double ms) => practiceRevealSeg(
      ms,
      PracticeRevealTiming.captionFadeStartMs,
      PracticeRevealTiming.captionMs,
    );

/// 收卡：資訊欄、稀有度牌、星星先淡掉（1 → 0）。
double practiceArchiveInfoOpacity(double ms) =>
    1 - practiceRevealSeg(ms, 0, PracticeRevealTiming.archiveInfoOutMs);

/// 收卡：卡面疊上的主題色光（0 → 1）：轉成細線的同時整張卡發光。
double practiceArchiveCardLight(double ms) => Curves.easeInCubic.transform(
      practiceRevealSeg(ms, 0, PracticeRevealTiming.archiveLineEndMs),
    );

/// 收卡：卡片轉向側面多轉的角度（0 → 80°，加在正面的 180° 上），看起來收成一條細線。
double practiceArchiveCardYaw(double ms) =>
    PracticeRevealTiming.archiveLineYaw *
    Curves.easeInCubic.transform(
      practiceRevealSeg(ms, 0, PracticeRevealTiming.archiveLineEndMs),
    );

/// 收卡：卡片縮小倍率：0–120 ms 1 → 0.7（細線），120–150 ms 0.7 → 0.15（縮成光球）。
double practiceArchiveCardScale(double ms) {
  if (ms < PracticeRevealTiming.archiveLineEndMs) {
    return 1 -
        (1 - PracticeRevealTiming.archiveLineScale) *
            Curves.easeInCubic.transform(
              practiceRevealSeg(ms, 0, PracticeRevealTiming.archiveLineEndMs),
            );
  }
  return PracticeRevealTiming.archiveLineScale -
      (PracticeRevealTiming.archiveLineScale - 0.15) *
          practiceRevealSeg(
            ms,
            PracticeRevealTiming.archiveLineEndMs,
            PracticeRevealTiming.collapseEndMs,
          );
}

/// 收卡：卡片本體淡出（1 → 0）。
double practiceArchiveCardOpacity(double ms) =>
    1 -
    practiceRevealSeg(
      ms,
      PracticeRevealTiming.cardFadeStartMs,
      PracticeRevealTiming.collapseEndMs,
    );

/// 收卡：背景暗化退場（1 → 0），底下的圖鑑慢慢清楚。
double practiceArchiveBackdrop(double ms) =>
    1 -
    Curves.easeOut.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.backdropOutStartMs,
        PracticeRevealTiming.backdropOutEndMs,
      ),
    );

/// 收卡：光球沿路徑的參數 t（0..1）。
double practiceArchiveFlightT(double ms) =>
    PracticeRevealTiming.flight.transform(
      practiceRevealSeg(
        ms,
        PracticeRevealTiming.flightStartMs,
        PracticeRevealTiming.landMs,
      ),
    );

/// 收卡：光球核心半徑（px）。120–150 ms 在卡片中心從 14 長到 18，飛行中縮到 10。
double practiceArchiveOrbRadius(double ms) {
  if (ms < PracticeRevealTiming.orbAppearStartMs) return 0;
  if (ms < PracticeRevealTiming.flightStartMs) {
    return 14 +
        4 *
            PracticeRevealTiming.enter.transform(
              practiceRevealSeg(
                ms,
                PracticeRevealTiming.orbAppearStartMs,
                PracticeRevealTiming.flightStartMs,
              ),
            );
  }
  return 18 - 8 * practiceArchiveFlightT(ms);
}

/// 收卡光尾在 [f] 處的寬度（px，V3.1 §5.12）：[f]＝0 是光球端（16 px），1 是尾端（0），
/// 由粗到細。
double practiceArchiveTailWidth(double f) =>
    PracticeRevealTiming.tailWidth * (1 - f.clamp(0.0, 1.0));

/// 收卡沿途第 [index] 顆星點（1..[PracticeRevealTiming.sparkleCount]）在路徑上的位置
/// （路徑參數 t）：平均分布在 0 與 1 之間。
double practiceArchiveSparkleT(int index) =>
    index / (PracticeRevealTiming.sparkleCount + 1);

/// 收卡：第 [index] 顆星點灑出的時間＝光球的路徑參數 t 經過 [practiceArchiveSparkleT] 那一刻。
double practiceArchiveSparkleSpawnMs(int index) {
  final target = practiceArchiveSparkleT(index);
  // 飛行曲線單調遞增：二分法反解線性進度，再換回毫秒。
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (lo + hi) / 2;
    if (PracticeRevealTiming.flight.transform(mid) < target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return PracticeRevealTiming.flightStartMs +
      (PracticeRevealTiming.landMs - PracticeRevealTiming.flightStartMs) *
          ((lo + hi) / 2);
}

/// 收卡沿途星點（第 1..[PracticeRevealTiming.sparkleCount] 顆）灑出的時間表（ms）。
/// 只看 index，先算好；光球 painter 每幀直接查表，不用每幀重跑二分反解。
final List<double> kPracticeArchiveSparkleSpawnMs = List.unmodifiable([
  for (var i = 1; i <= PracticeRevealTiming.sparkleCount; i++)
    practiceArchiveSparkleSpawnMs(i),
]);

/// 收卡弧線（V3.1 §5.12，三次貝茲）的兩個控制點：第一個在卡片左下外側，第二個在目標格
/// 遠離畫面中線的那一側外面，光球繞半圈進那一格。兩點都夾在畫面內縮 24 px 的範圍內，
/// 弧線不會飛出螢幕。
({Offset c1, Offset c2}) practiceArchiveControls(
  Offset origin,
  Rect target,
  Size card,
  Size stage,
) {
  const inset = 24.0;
  Offset clampIn(Offset p) => Offset(
        p.dx.clamp(inset, math.max(inset, stage.width - inset)),
        p.dy.clamp(inset, math.max(inset, stage.height - inset)),
      );
  final c1 = origin + Offset(-0.75 * card.width, 0.55 * card.height);
  final side = target.center.dx >= stage.width / 2 ? 1.0 : -1.0;
  final c2 =
      target.center + Offset(side * 1.1 * target.width, -0.9 * target.height);
  return (c1: clampIn(c1), c2: clampIn(c2));
}

/// 三次貝茲曲線上參數 [t] 的點。
Offset practiceCubicBezier(
  Offset p0,
  Offset p1,
  Offset p2,
  Offset p3,
  double t,
) {
  final u = 1 - t;
  return p0 * (u * u * u) +
      p1 * (3 * u * u * t) +
      p2 * (3 * u * t * t) +
      p3 * (t * t * t);
}

/// 三次貝茲曲線在參數 [t] 的切線方向（未正規化）。
Offset practiceCubicBezierTangent(
  Offset p0,
  Offset p1,
  Offset p2,
  Offset p3,
  double t,
) {
  final u = 1 - t;
  return (p1 - p0) * (3 * u * u) +
      (p2 - p1) * (6 * u * t) +
      (p3 - p2) * (3 * t * t);
}

// ── V3.1 第一刀的光效曲線（規格 docs/plans/2026-10-17-card-draw-v3-1-polish-spec.md §5）──

typedef _Key = ({double ms, double v, Curve curve});

/// 關鍵影格內插：[keys] 依時間排序，兩點之間用後一點的曲線；第一點之前取第一點的值，
/// 最後一點之後取最後一點的值。
double _keyframes(double ms, List<_Key> keys) {
  if (ms <= keys.first.ms) return keys.first.v;
  for (var i = 1; i < keys.length; i++) {
    final b = keys[i];
    if (ms <= b.ms) {
      final a = keys[i - 1];
      return a.v +
          (b.v - a.v) * b.curve.transform(practiceRevealSeg(ms, a.ms, b.ms));
    }
  }
  return keys.last.v;
}

/// 卡片後層泛光的不透明度（V3.1 §5.1）：蓄力 0 → 0.3；R／SR 染藍 120 ms 衝到 0.75 再退到
/// 0.45；SR 染金再衝到 0.9、翻牌前退到 0.5；翻牌峰值 N 0.35、R 0.6、SR 0.9，之後 400 ms
/// 退回 0.3 並停在那裡（停住時靜止）。
double practiceRevealBloomBack(double ms, PracticeGirlRarity rarity) {
  const rest = 0.3;
  if (ms < PracticeRevealTiming.dyeBlueMs) {
    return rest * practiceRevealChargeGlow(ms);
  }
  final (preFlip, peak) = switch (rarity) {
    PracticeGirlRarity.n => (rest, 0.35),
    PracticeGirlRarity.r => (0.45, 0.6),
    PracticeGirlRarity.sr => (0.5, 0.9),
  };
  return _keyframes(ms, [
    (ms: PracticeRevealTiming.dyeBlueMs, v: rest, curve: Curves.linear),
    if (rarity != PracticeGirlRarity.n) ...[
      (
        ms: PracticeRevealTiming.dyeBlueEndMs,
        v: 0.75,
        curve: PracticeRevealTiming.enter,
      ),
      if (rarity == PracticeGirlRarity.sr) ...[
        (ms: PracticeRevealTiming.dyeGoldMs, v: 0.6, curve: Curves.easeOut),
        (
          ms: PracticeRevealTiming.dyeGoldEndMs,
          v: 0.9,
          curve: PracticeRevealTiming.enter,
        ),
      ] else
        (
          ms: PracticeRevealTiming.dyeGoldEndMs,
          v: preFlip,
          curve: Curves.easeOut,
        ),
    ],
    (ms: PracticeRevealTiming.flipStartMs, v: preFlip, curve: Curves.easeOut),
    (ms: PracticeRevealTiming.flipPeakMs, v: peak, curve: Curves.easeIn),
    (ms: PracticeRevealTiming.flipPeakMs + 400, v: rest, curve: Curves.easeOut),
  ]);
}

/// 卡片前層泛光（V3.1 §5.1）：卡片轉到側立前 [PracticeRevealTiming.bloomFrontLeadMs] 才起亮
/// （easeIn，跟著卡片變窄補上徽記變窄的暗），側立（翻牌峰值）最亮，之後 300 ms 退掉；峰值
/// N 0.15、R 0.25、SR 0.35（≤ 0.35，免得蓋掉照片）。不提早亮：疊在亮的卡背上會先把卡面
/// 提亮，卡片側立一暗、光刃再一亮，就多出一次閃光（#107 P2-1）。
double practiceRevealBloomFront(double ms, PracticeGirlRarity rarity) {
  const peakMs = PracticeRevealTiming.flipPeakMs;
  const start = peakMs - PracticeRevealTiming.bloomFrontLeadMs;
  const end = peakMs + PracticeRevealTiming.bloomFrontFadeMs;
  if (ms <= start || ms >= end) return 0;
  final peak = switch (rarity) {
    PracticeGirlRarity.n => 0.15,
    PracticeGirlRarity.r => 0.25,
    PracticeGirlRarity.sr => 0.35,
  };
  if (ms < peakMs) {
    return peak * Curves.easeIn.transform(practiceRevealSeg(ms, start, peakMs));
  }
  return peak *
      (1 - Curves.easeOut.transform(practiceRevealSeg(ms, peakMs, end)));
}

/// 徽記白光（V3.1 §5.2，0..1）：560 → 600 衝到 0.95，720 退掉。三種稀有度都一樣。
double practiceRevealEmblemWhite(double ms) {
  if (ms <= PracticeRevealTiming.whiteFlashStartMs ||
      ms >= PracticeRevealTiming.whiteFlashEndMs) {
    return 0;
  }
  if (ms < PracticeRevealTiming.whiteFlashPeakMs) {
    return 0.95 *
        Curves.easeOut.transform(
          practiceRevealSeg(
            ms,
            PracticeRevealTiming.whiteFlashStartMs,
            PracticeRevealTiming.whiteFlashPeakMs,
          ),
        );
  }
  return 0.95 *
      (1 -
          Curves.easeIn.transform(
            practiceRevealSeg(
              ms,
              PracticeRevealTiming.whiteFlashPeakMs,
              PracticeRevealTiming.whiteFlashEndMs,
            ),
          ));
}

/// 一圈光環在某一刻的樣子：半徑與線寬（px）、不透明度。
typedef PracticeRevealRing = ({double radius, double width, double alpha});

PracticeRevealRing? _ring(
  double ms,
  double start,
  double duration,
  double from,
  double to,
  double widthFrom,
) {
  final t = (ms - start) / duration;
  if (t <= 0 || t >= 1) return null;
  final e = Curves.easeOutCubic.transform(t);
  return (
    radius: from + (to - from) * e,
    width: widthFrom - (widthFrom - 1) * t,
    alpha: 0.85 * (1 - t),
  );
}

/// 翻牌峰值的衝擊波（V3.1 §5.6）：半徑 0.35×卡高起、easeOutCubic 擴到 R 1.1／SR 1.3×卡高，
/// 線寬 12 → 1 px、α 0.85 → 0。N 不加；R 一圈 400 ms；SR 兩圈各 500 ms、相隔 120 ms。
List<PracticeRevealRing> practiceRevealShockwaves(
  double ms,
  PracticeGirlRarity rarity,
  double cardHeight,
) {
  const peak = PracticeRevealTiming.flipPeakMs;
  final from = 0.35 * cardHeight;
  return [
    if (rarity == PracticeGirlRarity.r)
      _ring(
          ms, peak, PracticeRevealTiming.shockRMs, from, 1.1 * cardHeight, 12),
    if (rarity == PracticeGirlRarity.sr) ...[
      _ring(
          ms, peak, PracticeRevealTiming.shockSrMs, from, 1.3 * cardHeight, 12),
      _ring(
        ms,
        peak + PracticeRevealTiming.shockSrGapMs,
        PracticeRevealTiming.shockSrMs,
        from,
        1.3 * cardHeight,
        12,
      ),
    ],
  ].nonNulls.toList();
}

/// SR 牌落地的小光環（V3.1 §5.6）：以牌為中心，半徑 20 → 60 px、300 ms。N／R 回 null。
PracticeRevealRing? practiceRevealBadgeRing(
  double ms,
  PracticeGirlRarity rarity,
) {
  if (rarity != PracticeGirlRarity.sr) return null;
  return _ring(
    ms,
    PracticeRevealTiming.stampLandMs,
    PracticeRevealTiming.badgeRingMs,
    20,
    60,
    6,
  );
}

/// 第 [index] 顆星點亮時的四芒星光（V3.1 §5.11）：250 ms 內 α 0.9 → 0、轉 30°、從 0.6 倍
/// 放大到 1；時段外回 null。
({double alpha, double turnDeg, double scale})? practiceRevealStarSparkle(
  double ms,
  int index,
) {
  final t = (ms - practiceRevealStarStartMs(index)) /
      PracticeRevealTiming.starSparkleMs;
  if (t <= 0 || t >= 1) return null;
  return (
    alpha: 0.9 * (1 - Curves.easeIn.transform(t)),
    turnDeg: 30 * t,
    scale: 0.6 + 0.4 * Curves.easeOut.transform(t),
  );
}

/// 第 [index] 顆星的第 [dot] 顆小光點（0..5）：從星星中心往外噴 14 px、300 ms 淡掉；
/// 時段外回 null。位移相對星星中心。
({Offset offset, double alpha})? practiceRevealStarDot(
  double ms,
  int index,
  int dot,
) {
  final t =
      (ms - practiceRevealStarStartMs(index)) / PracticeRevealTiming.starDotsMs;
  if (t <= 0 || t >= 1) return null;
  final angle =
      dot / PracticeRevealTiming.starDotCount * 2 * math.pi + index * 0.5;
  final distance = 14 * Curves.easeOut.transform(t);
  return (
    offset: Offset(math.cos(angle), math.sin(angle)) * distance,
    alpha: 1 - t,
  );
}

/// 落位大四芒星爆光（V3.1 §5.12）：450 ms 起 250 ms，放大 0.4 → 1.0（乘 1.2×格寬）、
/// α 前 25% 衝滿再退掉；時段外回 null。
({double scale, double alpha})? practiceArchiveLandBurst(double ms) {
  final t =
      (ms - PracticeRevealTiming.landMs) / PracticeRevealTiming.landBurstMs;
  if (t <= 0 || t >= 1) return null;
  return (
    scale: 0.4 + 0.6 * Curves.easeOut.transform(t),
    alpha: t < 0.25 ? t / 0.25 : 1 - (t - 0.25) / 0.75,
  );
}

/// 落位兩圈光環的進度（0..1）：[which]＝0 為 450–650、1 為 500–700；時段外回 null。
double? practiceArchiveLandRing(double ms, int which) {
  final start = which == 0
      ? PracticeRevealTiming.landMs
      : PracticeRevealTiming.landRing2StartMs;
  final end = which == 0
      ? PracticeRevealTiming.landRing1EndMs
      : PracticeRevealTiming.archiveMs;
  final t = practiceRevealSeg(ms, start, end);
  return t <= 0 || t >= 1 ? null : t;
}

/// 等待心跳總共幾下（6 組 × 2）。
const int kPracticeHeartbeatBeats = PracticeRevealTiming.heartbeatMaxGroups * 2;

/// 等待心跳第 [beat] 下（0..11）的時間，以按下翻牌為 0：每組兩下、相隔 140 ms。
double practiceHeartbeatBeatMs(int beat) =>
    PracticeRevealTiming.heartbeatStartMs +
    PracticeRevealTiming.heartbeatPeriodMs * (beat ~/ 2) +
    (beat.isOdd ? PracticeRevealTiming.heartbeatGapMs : 0);

/// 等待心跳在按下翻牌後 [elapsedMs] 的畫面（V3.1 §5.15）：卡背放大（第一下 1.2%、第二下
/// 0.8%，60 ms 衝上、90 ms 回落）、水平顫動 ±0.8 px（25 Hz、120 ms 遞減）、徽記銀光加成
/// （第一下 +0.12、第二下 +0.08）。6 組之後全部歸零。
({double scale, double dx, double emblem}) practiceHeartbeatPulse(
  double elapsedMs,
) {
  const rise = PracticeRevealTiming.heartbeatRiseMs;
  const fall = PracticeRevealTiming.heartbeatFallMs;
  const shiver = PracticeRevealTiming.heartbeatShiverMs;
  var scale = 0.0;
  var dx = 0.0;
  var emblem = 0.0;
  for (var b = 0; b < kPracticeHeartbeatBeats; b++) {
    final t = elapsedMs - practiceHeartbeatBeatMs(b);
    if (t < 0) break; // 心跳時間遞增：後面的都還沒到。
    if (t >= rise + fall) continue;
    final k = t < rise
        ? Curves.easeOut.transform(t / rise)
        : 1 - Curves.easeIn.transform((t - rise) / fall);
    final strong = b.isEven;
    scale += (strong ? 0.012 : 0.008) * k;
    emblem += (strong ? 0.12 : 0.08) * k;
    if (t < shiver) {
      dx += 0.8 * math.sin(2 * math.pi * 25 * t / 1000) * (1 - t / shiver);
    }
  }
  return (scale: 1 + scale, dx: dx, emblem: emblem);
}
