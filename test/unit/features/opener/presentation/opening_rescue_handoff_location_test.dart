import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/opener/presentation/screens/opening_rescue_screen.dart';

void main() {
  test('generated opener result disables another quota-spending generate', () {
    expect(
      OpeningRescueScreen.canStartGeneration(
        isGenerating: false,
        hasResult: false,
      ),
      isTrue,
    );
    expect(
      OpeningRescueScreen.canStartGeneration(
        isGenerating: true,
        hasResult: false,
      ),
      isFalse,
    );
    expect(
      OpeningRescueScreen.canStartGeneration(
        isGenerating: false,
        hasResult: true,
      ),
      isFalse,
    );
  });

  test('paywall return clears quota error only after premium unlock', () {
    expect(
      OpeningRescueScreen.shouldClearPaywallQuotaError(
        hasError: true,
        isPremium: true,
      ),
      isTrue,
    );
    expect(
      OpeningRescueScreen.shouldClearPaywallQuotaError(
        hasError: true,
        isPremium: false,
      ),
      isFalse,
    );
    expect(
      OpeningRescueScreen.shouldClearPaywallQuotaError(
        hasError: false,
        isPremium: true,
      ),
      isFalse,
    );
  });

  test('generate button copy reflects generated-result lock state', () {
    expect(
      OpeningRescueScreen.generateButtonText(hasResult: false),
      '生成開場白',
    );
    expect(
      OpeningRescueScreen.generateButtonText(hasResult: true),
      '已生成開場白',
    );
  });

  test('quota hint reassures generated results do not charge again', () {
    expect(
      OpeningRescueScreen.generationQuotaHint(
        hasResult: false,
        estimatedCost: 3,
      ),
      '將使用 3 則額度',
    );
    expect(
      OpeningRescueScreen.generationQuotaHint(
        hasResult: true,
        estimatedCost: 3,
      ),
      '已生成，不會重複扣額度',
    );
  });

  test('copy snackbar tells user the next opener step', () {
    final message = OpeningRescueScreen.copiedOpenerMessage('延展');

    expect(message, contains('已複製這則開場白'));
    expect(message, contains('貼到交友軟體送出'));
    expect(message, contains('回來回報結果')); // 批2新增
    expect(message, contains('她回覆後'));
    expect(message, contains('點下方「她回覆了，開始分析對話」'));
  });

  group('openerAdviceIdFor', () {
    test('組合 opener:<requestId>:<type>', () {
      expect(
        OpeningRescueScreen.openerAdviceIdFor(
            requestId: 'req-1', type: 'tease'),
        'opener:req-1:tease',
      );
    });

    test('requestId 缺席回 null（不記錄、不渲染晶片條）', () {
      expect(
        OpeningRescueScreen.openerAdviceIdFor(requestId: null, type: 'extend'),
        isNull,
      );
      expect(
        OpeningRescueScreen.openerAdviceIdFor(requestId: '  ', type: 'extend'),
        isNull,
      );
    });
  });

  test('partner-less handoff goes straight to 新增對象', () {
    expect(
      OpeningRescueScreen.handoffLocationFor(),
      '/partner/new',
    );
    expect(
      OpeningRescueScreen.handoffLocationFor(partnerId: ''),
      '/partner/new',
    );
    expect(
      OpeningRescueScreen.handoffLocationFor(partnerId: '   '),
      '/partner/new',
    );
  });

  test('bound-partner handoff returns to that partner, not a new one', () {
    final location =
        OpeningRescueScreen.handoffLocationFor(partnerId: 'partner-123');

    expect(location, '/partner/partner-123');
    expect(location, isNot(contains('/partner/new')));
  });

  group('handoffNavigationFor', () {
    test('已綁定且 pop 得回去＝回到既有對象卡，不再 push 一張', () {
      expect(
        OpeningRescueScreen.handoffNavigationFor(
          partnerId: 'partner-123',
          canPop: true,
        ),
        OpenerHandoffNavigation.popToBoundPartner,
      );
    });

    test('已綁定但沒得 pop（深連結直開）退回 replace', () {
      expect(
        OpeningRescueScreen.handoffNavigationFor(
          partnerId: 'partner-123',
          canPop: false,
        ),
        OpenerHandoffNavigation.replaceWithHandoff,
      );
    });

    test('未綁定一律 replace——開場救星不留在返回路徑上', () {
      for (final partnerId in <String?>[null, '', '   ']) {
        expect(
          OpeningRescueScreen.handoffNavigationFor(
            partnerId: partnerId,
            canPop: true,
          ),
          OpenerHandoffNavigation.replaceWithHandoff,
          reason: 'partnerId=${partnerId ?? 'null'} 應視為未綁定',
        );
      }
    });
  });
}
