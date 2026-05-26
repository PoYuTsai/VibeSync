import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/link_launch_service.dart';

class AiDataSharingConsent {
  static const _acceptedKey = 'ai_data_sharing_consent_20260526_v1';
  static const acceptedKeyForTesting = _acceptedKey;
  static const _privacyUrl = 'https://vibesyncai.app/privacy';

  static Future<bool> hasAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_acceptedKey) == true;
  }

  static Future<bool> ensure(
    BuildContext context, {
    required String featureLabel,
  }) async {
    if (await hasAccepted()) return true;
    if (!context.mounted) return false;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('第三方 AI 資料使用同意'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '使用「$featureLabel」前，VibeSync 需要先取得你的同意。',
              ),
              const SizedBox(height: 12),
              const Text(
                '你主動送出的資料會經由 VibeSync 後端服務（Supabase Edge Functions）傳送至 Anthropic Claude API，用來產生本次 AI 結果。',
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
              TextButton(
                onPressed: () => LinkLaunchService.open(_privacyUrl),
                child: const Text('查看隱私權政策'),
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
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('不同意'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('我同意並送出'),
          ),
        ],
      ),
    );

    if (accepted != true) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_acceptedKey, true);
    return true;
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
