// lib/core/theme/app_icons.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

export 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

/// 五種回覆風格的標題 icon（key＝server OPENER_TYPES / ReplyType.name）。
/// 2026-08-17 Eric 拍板：標題 icon 全面改 Tabler icons，不用 iOS emoji。
const replyStyleIcons = <String, IconData>{
  'extend': TablerIcons.refresh,
  'resonate': TablerIcons.message_circle,
  'tease': TablerIcons.mood_wink,
  'humor': TablerIcons.masks_theater,
  'coldRead': TablerIcons.crystal_ball,
};
