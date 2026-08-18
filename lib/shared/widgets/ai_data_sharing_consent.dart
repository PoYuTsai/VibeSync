import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/keyboard_privacy_purge_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/supabase_service.dart';
import '../services/link_launch_service.dart';
import '../../core/services/app_haptics.dart';

class AiDataSharingConsent {
  static const _acceptedKey = 'ai_data_sharing_consent_20260706_v3';
  static const acceptedKeyForTesting = _acceptedKey;
  static const keyboardScreenshotConsentKey =
      KeyboardScreenshotPrivacyKeys.consent;
  static const keyboardScreenshotConsentAcceptedAtKey =
      KeyboardScreenshotPrivacyKeys.consentAcceptedAt;
  static const keyboardLatestScreenshotDetectionKey =
      KeyboardScreenshotPrivacyKeys.latestScreenshotDetection;
  static const keyboardPartnerContextSharingKey =
      KeyboardScreenshotPrivacyKeys.partnerContextSharing;
  static const keyboardScreenshotDataDescription =
      '啟用後，鍵盤開啟期間新拍的系統截圖會在本機讀取並上傳分析一張，不再逐次詢問；開啟鍵盤前 3 分鐘內的截圖則只在你手動選擇時才送出。可能傳送：一張聊天截圖，內含訊息、顯示名稱與頭像。上傳前會裁掉鍵盤自己佔的區塊，鍵盤上也會顯示用了哪一張。不會自動讀取其他聊天紀錄，你隨時可按 ✕ 收起結果或撤回同意。';
  static const keyboardScreenshotPurposeText =
      '用途：只用來辨識這張截圖並產生本次三個回覆選項。為了在斷線後查回同一結果並避免重複扣額，後端最多 24 小時保留鍵控輸入雜湊與產生結果，不保存截圖或 OCR 逐字稿。對象背景分享是另一個預設關閉、可隨時撤回的設定。';
  static const _privacyUrl = 'https://vibesyncai.app/privacy';
  static const _termsUrl = 'https://vibesyncai.app/terms';
  static const _defaultDestinationLabel = 'Anthropic';
  static const _defaultDataDescription =
      '可能包含聊天文字、截圖、對方名稱，以及你補充的情境或草稿。VibeSync 只會處理你主動送出的內容。';
  static const _defaultPurposeText =
      '我們會結合關係階段、互動節奏與對話脈絡，提供分析、截圖辨識、開場建議或 Coach 1:1 回覆。';

  /// 「我幫你修」與「再調一下」有額外的安全重播暫存，因此使用獨立同意版本；
  /// 已同意其他 AI 功能的帳號仍會在首次使用前看到這項具體揭露。
  ///
  /// 兩者**共用同一把 key**：資料類別、用途、7 天保留期完全相同，走的也是同一條
  /// 重播流程。另開一把只會讓已同意的人為了同一件事再被問一次，不會多揭露任何
  /// 東西。文案則必須同時涵蓋兩個入口——只說「草稿潤飾」會讓從微調進來的人看到
  /// 名不符實的用途說明。
  static const optimizeReplayConsentKey =
      'ai_data_sharing_consent_optimize_replay_20260716_v1';
  static const optimizeReplayDataDescription =
      '可能包含：你的草稿或要微調的那則回覆、你輸入的微調指令、目前對話、對方名稱與你填寫的情境。這些內容會送至 VibeSync 後端與 Anthropic Claude 產生結果。';
  static const optimizeReplayPurposeText =
      '用途：產生這次草稿潤飾或回覆微調。為了在回應中斷時恢復同一結果並避免重複扣額度，後端的可用重播資料保留 7 天並每小時清除，只存 AI 產生的結果句與理由，不另存原始草稿、微調指令或完整對話輸入；AI 生成文字仍可能重述或反映你提供的草稿、指令、姓名與對話內容。刪除後的備份副本依 Supabase 的備份與還原週期處理。';

  /// AI 實戰練習室走 DeepSeek（非 Claude），須與 Claude 功能各自獨立同意，
  /// 文案也須準確描述「模擬對象練習對話」而非 Claude 功能用途。
  static const practiceConsentKey =
      'ai_data_sharing_consent_practice_20260706_v2';
  static const practiceDestinationLabel = 'DeepSeek';
  static const practiceDataDescription = '可能包含：你在練習室輸入的訊息，以及本次練習的對話脈絡。';
  static const practicePurposeText = '用途：只用來在 AI 實戰練習室產生陪練女孩的回覆，以及練習結束後的一張拆解卡。';

  /// 測試 seam：覆寫 userId 解析（回傳 null 模擬未登入）。production 不碰。
  @visibleForTesting
  static String? Function()? debugUserIdOverride;

  /// Storage boundary seam used to deterministically exercise write failures
  /// and account-switch races in widget tests.
  @visibleForTesting
  static Future<bool> Function(
    SharedPreferences preferences,
    String key,
    bool value,
  )? debugSetConsentBoolOverride;

  @visibleForTesting
  static Future<bool> Function(
    SharedPreferences preferences,
    String key,
    String value,
  )? debugSetConsentStringOverride;

  /// 同意是帳號級（5.1.1(i)/5.1.2(i)）：登入時 key 綁 userId，
  /// 換帳號各自重新同意；未登入才 fallback 裝置級 key。
  static String _scopedKey(String consentKey, String? userId) {
    if (userId == null || userId.isEmpty) return consentKey;
    return '$consentKey::$userId';
  }

  static String _effectiveKey(String consentKey) {
    final resolver = debugUserIdOverride;
    final userId =
        resolver != null ? resolver() : SupabaseService.currentUser?.id;
    return _scopedKey(consentKey, userId);
  }

  static String _keyboardReceiptKeyForConsentKey(String scopedConsentKey) {
    final scopeSuffix =
        scopedConsentKey.substring(keyboardScreenshotConsentKey.length);
    return '$keyboardScreenshotConsentAcceptedAtKey$scopeSuffix';
  }

  static DateTime? _validKeyboardConsentAcceptedAt(String? raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw)?.toUtc();
    if (parsed == null || parsed.isAfter(DateTime.now().toUtc())) {
      return null;
    }
    return parsed;
  }

  static Future<bool> hasAccepted({String consentKey = _acceptedKey}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_effectiveKey(consentKey)) == true;
  }

  static Future<bool> hasKeyboardScreenshotConsent() async {
    final consentKey = _effectiveKey(keyboardScreenshotConsentKey);
    final receiptKey = _effectiveKey(
      keyboardScreenshotConsentAcceptedAtKey,
    );
    final prefs = await SharedPreferences.getInstance();
    if (_effectiveKey(keyboardScreenshotConsentKey) != consentKey ||
        _effectiveKey(keyboardScreenshotConsentAcceptedAtKey) != receiptKey) {
      return false;
    }
    final accepted = prefs.getBool(consentKey) == true;
    final acceptedAt = prefs.getString(receiptKey);
    return accepted && _validKeyboardConsentAcceptedAt(acceptedAt) != null;
  }

  static Future<DateTime?> keyboardScreenshotConsentAcceptedAt() async {
    final receiptKey = _effectiveKey(
      keyboardScreenshotConsentAcceptedAtKey,
    );
    final prefs = await SharedPreferences.getInstance();
    if (_effectiveKey(keyboardScreenshotConsentAcceptedAtKey) != receiptKey) {
      return null;
    }
    final raw = prefs.getString(receiptKey);
    return _validKeyboardConsentAcceptedAt(raw);
  }

  static Future<bool> hasKeyboardLatestScreenshotDetectionEnabled() {
    return _hasKeyboardCapabilityEnabled(
      keyboardLatestScreenshotDetectionKey,
    );
  }

  static Future<bool> hasKeyboardPartnerContextSharingEnabled() {
    return _hasKeyboardCapabilityEnabled(keyboardPartnerContextSharingKey);
  }

  static Future<bool> _hasKeyboardCapabilityEnabled(
    String capabilityKey,
  ) async {
    final consentKey = _effectiveKey(keyboardScreenshotConsentKey);
    final receiptKey = _effectiveKey(
      keyboardScreenshotConsentAcceptedAtKey,
    );
    final settingKey = _effectiveKey(capabilityKey);
    final prefs = await SharedPreferences.getInstance();
    if (_effectiveKey(keyboardScreenshotConsentKey) != consentKey ||
        _effectiveKey(keyboardScreenshotConsentAcceptedAtKey) != receiptKey ||
        _effectiveKey(capabilityKey) != settingKey) {
      return false;
    }
    return prefs.getBool(consentKey) == true &&
        _validKeyboardConsentAcceptedAt(prefs.getString(receiptKey)) != null &&
        prefs.getBool(settingKey) == true;
  }

  /// Both optional keyboard capabilities fail closed and cannot be enabled
  /// before the account has accepted the keyboard-specific screenshot consent.
  static Future<bool> setKeyboardLatestScreenshotDetectionEnabled(
    bool enabled,
  ) async {
    final consentKey = _effectiveKey(keyboardScreenshotConsentKey);
    final receiptKey = _effectiveKey(
      keyboardScreenshotConsentAcceptedAtKey,
    );
    final settingKey = _effectiveKey(keyboardLatestScreenshotDetectionKey);
    final prefs = await SharedPreferences.getInstance();
    if (_effectiveKey(keyboardScreenshotConsentKey) != consentKey ||
        _effectiveKey(keyboardLatestScreenshotDetectionKey) != settingKey) {
      return false;
    }
    if (enabled &&
        (prefs.getBool(consentKey) != true ||
            _validKeyboardConsentAcceptedAt(prefs.getString(receiptKey)) ==
                null)) {
      return false;
    }
    final written = await prefs.setBool(settingKey, enabled);
    if (_effectiveKey(keyboardLatestScreenshotDetectionKey) == settingKey) {
      return written;
    }
    await prefs.remove(settingKey);
    return false;
  }

  static Future<bool> setKeyboardPartnerContextSharingEnabled(
    bool enabled,
  ) async {
    final consentKey = _effectiveKey(keyboardScreenshotConsentKey);
    final receiptKey = _effectiveKey(
      keyboardScreenshotConsentAcceptedAtKey,
    );
    final settingKey = _effectiveKey(keyboardPartnerContextSharingKey);
    final prefs = await SharedPreferences.getInstance();
    if (_effectiveKey(keyboardScreenshotConsentKey) != consentKey ||
        _effectiveKey(keyboardPartnerContextSharingKey) != settingKey) {
      return false;
    }
    if (enabled &&
        (prefs.getBool(consentKey) != true ||
            _validKeyboardConsentAcceptedAt(prefs.getString(receiptKey)) ==
                null)) {
      return false;
    }
    final written = await prefs.setBool(settingKey, enabled);
    if (_effectiveKey(keyboardPartnerContextSharingKey) == settingKey) {
      return written;
    }
    await prefs.remove(settingKey);
    return false;
  }

  static Future<void> revokeKeyboardScreenshotConsent({
    String? ownerUserId,
    Future<void> Function()? afterLocalRevocation,
    KeyboardPrivacyPurgeService? privacyPurgeService,
  }) async {
    final resolvedOwner = ownerUserId ??
        (debugUserIdOverride != null
            ? debugUserIdOverride!()
            : SupabaseService.currentUser?.id);
    await (privacyPurgeService ?? KeyboardPrivacyPurgeService.live).purge(
      KeyboardContextPurgeScope.consentRevoked,
      ownerUserId: resolvedOwner,
      nativeOperation: afterLocalRevocation,
    );
  }

  static Future<bool> ensure(
    BuildContext context, {
    required String featureLabel,
    String consentKey = _acceptedKey,
    String destinationLabel = _defaultDestinationLabel,
    String dataDescription = _defaultDataDescription,
    String purposeText = _defaultPurposeText,
  }) async {
    // scope key 只解析一次：dialog 開啟期間身份變動（session 過期／換帳號）
    // 不得把同意寫到別的帳號 key 或放行本次請求。
    final scopedKey = _effectiveKey(consentKey);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(scopedKey) == true) {
      if (consentKey != keyboardScreenshotConsentKey) {
        return true;
      }
      final existingReceiptKey = _keyboardReceiptKeyForConsentKey(scopedKey);
      final scopeStillCurrent = _effectiveKey(consentKey) == scopedKey &&
          _effectiveKey(keyboardScreenshotConsentAcceptedAtKey) ==
              existingReceiptKey;
      final acceptedAt = _validKeyboardConsentAcceptedAt(
        prefs.getString(existingReceiptKey),
      );
      if (scopeStillCurrent && acceptedAt != null) {
        return true;
      }
      await prefs.remove(scopedKey);
      await prefs.remove(existingReceiptKey);
      if (!scopeStillCurrent) {
        return false;
      }
    }
    if (!context.mounted) return false;

    // featureLabel 保留簽名相容（11 個呼叫端）；2026-08 新版稿不在彈窗顯示功能名。
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AiDataSharingConsentDialog(
        privacyUrl: _privacyUrl,
        termsUrl: _termsUrl,
        destinationLabel: destinationLabel,
        dataDescription: dataDescription,
        purposeText: purposeText,
      ),
    );

    if (accepted != true) {
      return false;
    }

    if (_effectiveKey(consentKey) != scopedKey) {
      // 身份已變：本次同意作廢，重新走一次流程才放行。
      return false;
    }

    String? receiptKey;
    if (consentKey == keyboardScreenshotConsentKey) {
      receiptKey = _keyboardReceiptKeyForConsentKey(scopedKey);
      if (_effectiveKey(consentKey) != scopedKey ||
          _effectiveKey(keyboardScreenshotConsentAcceptedAtKey) != receiptKey) {
        await prefs.remove(scopedKey);
        await prefs.remove(receiptKey);
        return false;
      }
      final now = DateTime.now().toUtc();
      final receiptValue = DateTime.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String();
      final receiptWriter = debugSetConsentStringOverride;
      final receiptWritten = receiptWriter != null
          ? await receiptWriter(prefs, receiptKey, receiptValue)
          : await prefs.setString(receiptKey, receiptValue);
      if (!receiptWritten ||
          _effectiveKey(consentKey) != scopedKey ||
          _effectiveKey(keyboardScreenshotConsentAcceptedAtKey) != receiptKey) {
        await prefs.remove(scopedKey);
        await prefs.remove(receiptKey);
        return false;
      }
    }
    if (_effectiveKey(consentKey) != scopedKey ||
        (receiptKey != null &&
            _effectiveKey(keyboardScreenshotConsentAcceptedAtKey) !=
                receiptKey)) {
      await prefs.remove(scopedKey);
      if (receiptKey != null) {
        await prefs.remove(receiptKey);
      }
      return false;
    }
    final writer = debugSetConsentBoolOverride;
    final written = writer != null
        ? await writer(prefs, scopedKey, true)
        : await prefs.setBool(scopedKey, true);
    final scopeStillCurrent = _effectiveKey(consentKey) == scopedKey &&
        (receiptKey == null ||
            _effectiveKey(keyboardScreenshotConsentAcceptedAtKey) ==
                receiptKey);
    if (!written || !scopeStillCurrent) {
      await prefs.remove(scopedKey);
      if (receiptKey != null) {
        await prefs.remove(receiptKey);
      }
      return false;
    }
    return true;
  }
}

class _AiDataSharingConsentDialog extends StatefulWidget {
  const _AiDataSharingConsentDialog({
    required this.privacyUrl,
    required this.termsUrl,
    required this.destinationLabel,
    required this.dataDescription,
    required this.purposeText,
  });

  final String privacyUrl;
  final String termsUrl;
  final String destinationLabel;
  final String dataDescription;
  final String purposeText;

  @override
  State<_AiDataSharingConsentDialog> createState() =>
      _AiDataSharingConsentDialogState();
}

class _AiDataSharingConsentDialogState
    extends State<_AiDataSharingConsentDialog> {
  bool _hasReviewedAndAgreed = false;
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => LinkLaunchService.open(widget.termsUrl);
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()
    ..onTap = () => LinkLaunchService.open(widget.privacyUrl);

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  /// 各功能的 purposeText 常數以「用途：」開頭（合規揭露單一來源不動）；
  /// 新版稿此段標題是「VibeSync 如何幫你」，只在呈現層剝掉前綴。
  String get _purposeBody {
    const prefix = '用途：';
    return widget.purposeText.startsWith(prefix)
        ? widget.purposeText.substring(prefix.length)
        : widget.purposeText;
  }

  @override
  Widget build(BuildContext context) {
    // 2026-08-18 換版（夥伴稿，Codex 審過）：三段圖標式揭露＋圓形勾選框。
    // 勾選框與按鈕仍釘在捲動區外，小螢幕上縮的是揭露內文；per-feature
    // 的 dataDescription／purposeText／destinationLabel 參數化不變，
    // 所有入口（分析／開場／Coach／練習室／鍵盤／潤飾微調）共用這一版。
    final colorScheme = Theme.of(context).colorScheme;
    final linkStyle = TextStyle(
      color: colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    return AlertDialog(
      title: const Text('資料使用說明'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '為了理解這段互動，並提供更貼近關係脈絡的建議，VibeSync 需要使用你這次主動提交的內容。',
                    style: TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  _ConsentSection(
                    icon: Icons.description_outlined,
                    header: '你選擇分享的內容',
                    body: widget.dataDescription,
                  ),
                  const _SectionDivider(),
                  _ConsentSection(
                    icon: Icons.chat_bubble_outline,
                    header: 'VibeSync 如何幫你',
                    body: _purposeBody,
                  ),
                  const _SectionDivider(),
                  _ConsentSection(
                    icon: Icons.shield_outlined,
                    header: '資料如何處理',
                    body:
                        '你主動提交的內容會傳送至 VibeSync 雲端處理服務（由 Supabase 提供），並由第三方 AI 服務供應商 ${widget.destinationLabel} 處理，用於產生本次分析與回覆建議。',
                  ),
                ],
              ),
            ),
          ),
          const _SectionDivider(),
          CheckboxListTile(
            value: _hasReviewedAndAgreed,
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: VisualDensity.compact,
            controlAffinity: ListTileControlAffinity.leading,
            checkboxShape: const CircleBorder(),
            onChanged: (value) {
              AppHaptics.tap();
              setState(() => _hasReviewedAndAgreed = value ?? false);
            },
            title: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 12, height: 1.4),
                children: [
                  const TextSpan(text: '我已閱讀並同意'),
                  TextSpan(
                    text: '《服務條款》',
                    style: linkStyle,
                    recognizer: _termsTap,
                  ),
                  const TextSpan(text: '與'),
                  TextSpan(
                    text: '《隱私權政策》',
                    style: linkStyle,
                    recognizer: _privacyTap,
                  ),
                  TextSpan(
                    text:
                        '，並明確同意 VibeSync 將上述內容傳送至 Supabase 與 ${widget.destinationLabel} 進行處理。',
                  ),
                ],
              ),
            ),
          ),
          const Text(
            '若資料用途或服務供應商變更，我們會再次徵求同意。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('暫不同意'),
        ),
        FilledButton(
          onPressed: AppHaptics.onPress(_hasReviewedAndAgreed
              ? () => Navigator.of(context).pop(true)
              : null),
          child: const Text('同意並繼續'),
        ),
      ],
    );
  }
}

/// 揭露單段：左側品牌橘圖標＋右側小標與內文（夥伴稿版式）。
class _ConsentSection extends StatelessWidget {
  const _ConsentSection({
    required this.icon,
    required this.header,
    required this.body,
  });

  final IconData icon;
  final String header;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 26, color: AppColors.brandFlame),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                header,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 24,
      thickness: 0.5,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
    );
  }
}
