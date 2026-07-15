import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/supabase_service.dart';
import '../services/link_launch_service.dart';

class AiDataSharingConsent {
  static const _acceptedKey = 'ai_data_sharing_consent_20260706_v3';
  static const acceptedKeyForTesting = _acceptedKey;
  static const _privacyUrl = 'https://vibesyncai.app/privacy';
  static const _termsUrl = 'https://vibesyncai.app/terms';
  static const _defaultDestinationLabel = 'Anthropic Claude API';
  static const _defaultDataDescription =
      '可能包含：聊天文字、上傳的聊天或個人檔案截圖、對方名稱、你填寫的情境或草稿，以及本次結果所需的對話脈絡。';
  static const _defaultPurposeText = '用途：只用來產生你按下的分析、截圖辨識、開場建議或 Coach 1:1 回覆。';

  /// 「我幫你修」有額外的安全重播暫存，因此使用獨立同意版本；已同意
  /// 其他 AI 功能的帳號仍會在首次潤飾前看到這項具體揭露。
  static const optimizeReplayConsentKey =
      'ai_data_sharing_consent_optimize_replay_20260716_v1';
  static const optimizeReplayDataDescription =
      '可能包含：你的草稿、目前對話、對方名稱與你填寫的情境。這些內容會送至 VibeSync 後端與 Anthropic Claude 產生潤飾結果。';
  static const optimizeReplayPurposeText =
      '用途：產生這次草稿潤飾。為了在回應中斷時恢復同一結果並避免重複扣額度，後端的可用重播資料保留 7 天並每小時清除，只存 AI 產生的潤飾句與理由，不另存原始草稿或完整對話輸入；AI 生成文字仍可能重述或反映你提供的草稿、姓名與對話內容。刪除後的備份副本依 Supabase 的備份與還原週期處理。';

  /// AI 實戰練習室走 DeepSeek（非 Claude），須與 Claude 功能各自獨立同意，
  /// 文案也須準確描述「模擬對象練習對話」而非 Claude 功能用途。
  static const practiceConsentKey =
      'ai_data_sharing_consent_practice_20260706_v2';
  static const practiceDestinationLabel = 'DeepSeek API';
  static const practiceDataDescription = '可能包含：你在練習室輸入的訊息，以及本次練習的對話脈絡。';
  static const practicePurposeText = '用途：只用來在 AI 實戰練習室產生陪練女孩的回覆，以及練習結束後的一張拆解卡。';

  /// 測試 seam：覆寫 userId 解析（回傳 null 模擬未登入）。production 不碰。
  @visibleForTesting
  static String? Function()? debugUserIdOverride;

  /// 同意是帳號級（5.1.1(i)/5.1.2(i)）：登入時 key 綁 userId，
  /// 換帳號各自重新同意；未登入才 fallback 裝置級 key。
  static String _effectiveKey(String consentKey) {
    final resolver = debugUserIdOverride;
    final userId =
        resolver != null ? resolver() : SupabaseService.currentUser?.id;
    if (userId == null || userId.isEmpty) return consentKey;
    return '$consentKey::$userId';
  }

  static Future<bool> hasAccepted({String consentKey = _acceptedKey}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_effectiveKey(consentKey)) == true;
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
    if (prefs.getBool(scopedKey) == true) return true;
    if (!context.mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AiDataSharingConsentDialog(
        featureLabel: featureLabel,
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

    await prefs.setBool(scopedKey, true);
    return true;
  }
}

class _AiDataSharingConsentDialog extends StatefulWidget {
  const _AiDataSharingConsentDialog({
    required this.featureLabel,
    required this.privacyUrl,
    required this.termsUrl,
    required this.destinationLabel,
    required this.dataDescription,
    required this.purposeText,
  });

  final String featureLabel;
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('第三方 AI 資料使用同意'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '使用「${widget.featureLabel}」前，VibeSync 需要先取得你的同意。',
            ),
            const SizedBox(height: 12),
            Text(
              '你主動送出的資料會經由 VibeSync 後端服務（Supabase Edge Functions）傳送至 ${widget.destinationLabel}，用來產生本次 AI 結果。',
            ),
            const SizedBox(height: 12),
            _ConsentBullet(text: widget.dataDescription),
            _ConsentBullet(text: widget.purposeText),
            const _ConsentBullet(
              text: '如果不同意，本次 AI 請求不會送出，也不會扣除本次 AI 額度。',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => LinkLaunchService.open(widget.termsUrl),
                  child: const Text('查看服務條款'),
                ),
                TextButton(
                  onPressed: () => LinkLaunchService.open(widget.privacyUrl),
                  child: const Text('查看隱私權政策'),
                ),
              ],
            ),
            CheckboxListTile(
              value: _hasReviewedAndAgreed,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) {
                setState(() => _hasReviewedAndAgreed = value ?? false);
              },
              title: Text(
                '我已閱讀並同意服務條款與隱私權政策，並同意 VibeSync 將上述資料傳送至 Supabase Edge Functions 與 ${widget.destinationLabel} 以產生本次 AI 結果。',
              ),
            ),
            const Text(
              '同意後，這個帳號之後不會重複提醒。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('不同意'),
        ),
        FilledButton(
          onPressed: _hasReviewedAndAgreed
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('我同意並送出'),
        ),
      ],
    );
  }
}

class _ConsentBullet extends StatelessWidget {
  const _ConsentBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('- '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
