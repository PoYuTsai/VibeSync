// lib/shared/widgets/motion/gsap_text_reveal.dart
//
// 文字開場：逐字錯開進場，每次打開隨機抽一種。
//
// 語彙來自 GSAP SplitText + stagger 的經典組合——把一段字拆成單字元，每個字
// 元晚一點點起跑，用同一條 ease 收尾。這裡把「拆字」換成 grapheme cluster
// 切分（emoji／組合字不會被劈開），把 ease 換成 [GsapEase] 那組移植過來的
// GSAP 曲線，動的是原生 widget。
//
// 全部五種變體都**不動文字透明度**——這是全 App 殘影禁令（真機上文字淡入淡出
// 會留殘影，2026-08 已全面拆除）。要讓字「出現」只用位移＋遮罩、縮放、翻轉、
// 換字，一律不用 Opacity。
//
// 紀律：
// - one-shot，`pumpAndSettle` 必收斂；沒有無限 ticker。
// - 關動畫（reduce motion／TickerMode 靜音）直接落在終點。
// - 動畫收尾後塌回單一 [Text]：無障礙樹乾淨、可選取、`find.text()` 照樣找得到，
//   拆字只存在於動畫進行中那幾百毫秒。
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/animation/gsap_ease.dart';
import '../../../core/animation/motion_preference.dart';

/// 開場變體。每種各自對應一條 GSAP ease，手感刻意不一樣。
enum GsapRevealVariant {
  /// 從自己的行框下緣升上來（GSAP SplitText 遮罩式揭示）。`power2.out`
  riseMask,

  /// 從行框上緣落下來。`power3.out`
  dropMask,

  /// 從 0 放大到 1，尾段微微衝過頭再收。`back.out(1.7)`
  popIn,

  /// 沿 X 軸翻正，帶一點透視。`power4.out`
  flipX,

  /// 亂數替身字逐格定位（GSAP ScrambleTextPlugin 的手感）。`power1.out`
  scramble,
}

class GsapTextReveal extends StatefulWidget {
  const GsapTextReveal({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.variant,
    this.random,
    this.charDuration = const Duration(milliseconds: 520),
    this.stagger = const Duration(milliseconds: 55),
    this.maxSplitLength = 12,
    this.animate = true,
    this.onEnd,
  }) : assert(maxSplitLength >= 1);

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// 指定變體；null＝每次掛載隨機抽一種。
  final GsapRevealVariant? variant;

  /// 抽變體用的亂數來源。測試注入固定 seed 就能鎖住結果。
  final math.Random? random;

  /// 單一字元跑完進場要多久。
  final Duration charDuration;

  /// 相鄰字元的起跑時間差。
  final Duration stagger;

  /// 超過這個字數就不拆字、整串一起動——名字太長時逐字錯開會拖太久，
  /// 而且逐字 layout 的成本會開始有感。
  final int maxSplitLength;

  /// false＝跳過開場直接顯示完整文字。給「已經播過一次、不該因為 widget
  /// 被回收重建就重播」的情境用（lazy ListView 捲出 cacheExtent 會回收）。
  final bool animate;

  /// 開場結束（或因 [animate] false／關動畫而直接落地）時呼叫一次。
  final VoidCallback? onEnd;

  /// 抽變體的純決策，抽成 static 是為了能單獨測——State 只負責把參數餵進來。
  ///
  /// [canSplit] false（單一字元或名字太長，整串一起動）時 scramble 沒有東西
  /// 可換，一律退回 popIn，不管是抽到的還是外面指定的。
  @visibleForTesting
  static GsapRevealVariant resolveVariant({
    required GsapRevealVariant? requested,
    required bool canSplit,
    required math.Random random,
  }) {
    if (requested != null) {
      return (requested == GsapRevealVariant.scramble && !canSplit)
          ? GsapRevealVariant.popIn
          : requested;
    }
    final pool = canSplit
        ? GsapRevealVariant.values
        : GsapRevealVariant.values
            .where((v) => v != GsapRevealVariant.scramble)
            .toList();
    return pool[random.nextInt(pool.length)];
  }

  @override
  State<GsapTextReveal> createState() => _GsapTextRevealState();
}

class _GsapTextRevealState extends State<GsapTextReveal>
    with SingleTickerProviderStateMixin {
  /// GSAP 預設字集是 upperCase；名字只有單一字元時才會用到。
  static const _fallbackScrambleSet = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'X', 'Y', 'Z', //
  ];

  late final List<String> _chars = widget.text.characters.toList();
  late final bool _split =
      _chars.length > 1 && _chars.length <= widget.maxSplitLength;
  late final int _slots = _split ? _chars.length : 1;
  late final GsapRevealVariant _variant = _resolveVariant();
  late final List<String> _scrambleSet = _buildScrambleSet();
  late final Duration _total =
      widget.charDuration + widget.stagger * (_slots - 1);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  )..addStatusListener(_onStatus);

  /// 是否已決定過要不要播。State 一生只決定一次，rebuild 不重播。
  bool _decided = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // 不能寫成建構子 assert：那會讓 const GsapTextReveal(...) 無法常數求值。
    assert(
      widget.charDuration.inMilliseconds > 0,
      'charDuration 至少要 1ms，否則逐字進度會除以 0',
    );
  }

  GsapRevealVariant _resolveVariant() => GsapTextReveal.resolveVariant(
        requested: widget.variant,
        canSplit: _split,
        random: widget.random ?? math.Random(),
      );

  List<String> _buildScrambleSet() {
    // 替身字只從名字自己的字元裡挑：一定畫得出來（不會變豆腐），而且
    // 中日韓全形字寬度一致，跑動時不會每格抖一次。
    final unique = _chars.toSet().toList();
    return unique.length >= 2 ? unique : _fallbackScrambleSet;
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted && !_done) {
      setState(() => _done = true);
      widget.onEnd?.call();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (!widget.animate || motionDisabled(context)) {
      _controller.value = 1;
      _done = true;
      widget.onEnd?.call();
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant GsapTextReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && !_done) {
      // 開場演到一半被改名（對象設定存檔）：拆字用的是舊字元，繼續演會演錯字。
      // 直接落地收工。
      _controller.stop();
      _controller.value = 1;
      _done = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 第 [index] 個字元自己的 0–1 進度（已扣掉錯開的起跑延遲）。
  double _progressFor(int index) {
    if (_slots == 1) return _controller.value;
    final elapsed = _controller.value * _total.inMilliseconds;
    final start = widget.stagger.inMilliseconds * index;
    final span = math.max(1, widget.charDuration.inMilliseconds);
    return ((elapsed - start) / span).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return Text(
        widget.text,
        style: widget.style,
        textAlign: widget.textAlign,
      );
    }

    final resolved = DefaultTextStyle.of(context).style.merge(widget.style);
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _buildFrame(resolved),
        ),
      ),
    );
  }

  Widget _buildFrame(TextStyle resolved) {
    if (!_split) {
      return _effect(0, resolved, _plain(widget.text));
    }
    return Wrap(
      alignment: _wrapAlignment(),
      children: [
        for (var i = 0; i < _chars.length; i++)
          _effect(i, resolved, _plain(_charAt(i))),
      ],
    );
  }

  WrapAlignment _wrapAlignment() => switch (widget.textAlign) {
        TextAlign.center => WrapAlignment.center,
        TextAlign.right || TextAlign.end => WrapAlignment.end,
        _ => WrapAlignment.start,
      };

  /// 拆字期間每個字元用同一份 style（含 letterSpacing），總寬度才會跟塌回
  /// 單一 [Text] 之後一致，收尾不會抽動。
  Widget _plain(String value) => Text(value, style: widget.style);

  String _charAt(int index) {
    if (_variant != GsapRevealVariant.scramble) return _chars[index];
    if (_progressFor(index) >= 1) return _chars[index];
    // 每 ~60ms 換一次替身字；跟著 60fps 每格都換會變成雜訊。
    final step = (_controller.value * _total.inMilliseconds / 60).floor();
    return _scrambleSet[(step * 31 + index * 7) % _scrambleSet.length];
  }

  Widget _effect(int index, TextStyle resolved, Widget child) {
    final p = _progressFor(index);
    switch (_variant) {
      case GsapRevealVariant.riseMask:
        return _mask(GsapEase.power2Out.transform(p), resolved, child, 1.0);
      case GsapRevealVariant.dropMask:
        return _mask(GsapEase.power3Out.transform(p), resolved, child, -1.0);
      case GsapRevealVariant.popIn:
        return Transform.scale(
          scale: GsapEase.backOut.transform(p),
          child: child,
        );
      case GsapRevealVariant.flipX:
        final e = GsapEase.power4Out.transform(p);
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateX(-math.pi / 2 * (1 - e)),
          child: child,
        );
      case GsapRevealVariant.scramble:
        // 換的是字，不是透明度／位置——替身字已經在 [_charAt] 換好了。
        return child;
    }
  }

  /// 遮罩式揭示：字元被自己的行框裁掉，從框外滑進來。
  /// [direction] 1＝從下方升上來，-1＝從上方落下來。
  Widget _mask(
    double eased,
    TextStyle resolved,
    Widget child,
    double direction,
  ) {
    // 位移量寧可估多不估少：估少了會露出一條沒被裁掉的字邊。
    final fontSize = resolved.fontSize ?? 14;
    final travel = fontSize * (resolved.height ?? 1.4) * 1.15;
    return ClipRect(
      child: Transform.translate(
        offset: Offset(0, direction * travel * (1 - eased)),
        child: child,
      ),
    );
  }
}
