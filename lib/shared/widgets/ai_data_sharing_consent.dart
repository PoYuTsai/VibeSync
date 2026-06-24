import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/link_launch_service.dart';

class AiDataSharingConsent {
  static const _acceptedKey = 'ai_data_sharing_consent_20260527_v2';
  static const acceptedKeyForTesting = _acceptedKey;
  static const _privacyUrl = 'https://vibesyncai.app/privacy';
  static const _termsUrl = 'https://vibesyncai.app/terms';
  static const _defaultDestinationLabel = 'Anthropic Claude API';

  /// AI 實戰練習室走 DeepSeek（非 Claude），須與 Claude 功能各自獨立同意。
  static const practiceConsentKey =
      'ai_data_sharing_consent_practice_20260624_v1';
  static const practiceDestinationLabel = 'DeepSeek API';

  static Future<bool> hasAccepted({String consentKey = _acceptedKey}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(consentKey) == true;
  }

  static Future<bool> ensure(
    BuildContext context, {
    required String featureLabel,
    String consentKey = _acceptedKey,
    String destinationLabel = _defaultDestinationLabel,
  }) async {
    if (await hasAccepted(consentKey: consentKey)) return true;
    if (!context.mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AiDataSharingConsentDialog(
        featureLabel: featureLabel,
        privacyUrl: _privacyUrl,
        termsUrl: _termsUrl,
        destinationLabel: destinationLabel,
      ),
    );

    if (accepted != true) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(consentKey, true);
    return true;
  }
}

class _AiDataSharingConsentDialog extends StatefulWidget {
  const _AiDataSharingConsentDialog({
    required this.featureLabel,
    required this.privacyUrl,
    required this.termsUrl,
    required this.destinationLabel,
  });

  final String featureLabel;
  final String privacyUrl;
  final String termsUrl;
  final String destinationLabel;

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
            const _ConsentBullet(
              text: '可能包含：聊天文字、上傳的聊天或個人檔案截圖、對方名稱、你填寫的情境或草稿，以及本次結果所需的對話脈絡。',
            ),
            const _ConsentBullet(
              text: '用途：只用來產生你按下的分析、截圖辨識、開場建議或 Coach 1:1 回覆。',
            ),
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
              '同意後，這台裝置之後不會重複提醒。',
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
