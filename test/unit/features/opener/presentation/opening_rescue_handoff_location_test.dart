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

    expect(message, contains('已複製「延展」'));
    expect(message, contains('貼出去'));
    expect(message, contains('她回覆後'));
    expect(message, contains('分析'));
  });

  test('handoff URL drops partnerId when entry was partner-less', () {
    expect(
      OpeningRescueScreen.handoffLocationFor(),
      '/new?source=opener',
    );
    expect(
      OpeningRescueScreen.handoffLocationFor(partnerId: ''),
      '/new?source=opener',
    );
    expect(
      OpeningRescueScreen.handoffLocationFor(partnerId: '   '),
      '/new?source=opener',
    );
  });

  test('handoff URL carries partnerId when bound to a partner', () {
    final location =
        OpeningRescueScreen.handoffLocationFor(partnerId: 'partner-123');
    final uri = Uri.parse(location);
    expect(uri.path, '/new');
    expect(uri.queryParameters['source'], 'opener');
    expect(uri.queryParameters['partnerId'], 'partner-123');
  });
}
