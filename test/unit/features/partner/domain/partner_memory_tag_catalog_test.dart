import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/domain/services/partner_memory_tag_catalog.dart';

void main() {
  test('六個面向完整且關係進度／回覆狀態不在 catalog', () {
    expect(
      PartnerMemoryTagCatalog.groups.map((group) => group.title),
      <String>[
        '工作／學業',
        '地點／距離',
        '作息／生活',
        '個性／互動',
        '聊天偏好',
        '興趣',
      ],
    );

    final labels = PartnerMemoryTagCatalog.tags.map((tag) => tag.label).toSet();
    expect(
        labels,
        containsAll(<String>{
          '工作忙碌',
          '輪班工作',
          '住不同縣市',
          '休假不固定',
          '重視個人空間',
          '不想聊工作',
          '喜歡寵物',
        }));
    expect(labels, isNot(contains('剛認識')));
    expect(labels, isNot(contains('回覆慢但都會回')));
    expect(labels, isNot(contains('聊得來但還沒約')));
    expect(
      PartnerMemoryTagCatalog.serialize(labels).length,
      lessThanOrEqualTo(300),
      reason: 'Coach partnerHint.note 的 server schema 上限是 300',
    );
  });

  test('舊安全 chips 轉 canonical；舊關係狀態與自由句 fail closed', () {
    final selected = PartnerMemoryTagCatalog.parse(
      '剛認識、輪班、異地、吃貨、愛看劇、想約出來見面',
    );

    expect(
      PartnerMemoryTagCatalog.serialize(selected),
      '輪班工作、住不同縣市、喜歡美食、愛看劇／電影',
    );
    expect(
      PartnerMemoryTagCatalog.sanitizedNote(
        '剛認識、想約出來見面',
      ),
      isNull,
    );
    expect(
      PartnerMemoryTagCatalog.hasUnrecognizedContent(
        '慢熱、想約出來見面',
      ),
      isTrue,
    );
  });

  test('exact token 才成立，不從自由句或子字串猜 tag', () {
    expect(PartnerMemoryTagCatalog.sanitizedNote('她很慢熱'), isNull);
    expect(PartnerMemoryTagCatalog.sanitizedNote('她喜歡寵物玩笑'), isNull);
    expect(PartnerMemoryTagCatalog.sanitizedNote('慢熱'), '慢熱');
  });

  test('讀得懂 repository 舊 merge 前綴，但只留下 allowlisted token', () {
    expect(
      PartnerMemoryTagCatalog.sanitizedNote(
        '愛喝咖啡\n[from Ally] 喜歡寵物\n[from Miya] 想約出來見面',
      ),
      '愛喝咖啡、喜歡寵物',
    );
  });

  test('互斥 chips 後選覆蓋前選，其餘選擇保留', () {
    var selected = <String>{};
    selected = PartnerMemoryTagCatalog.toggle(selected, '住同縣市');
    selected = PartnerMemoryTagCatalog.toggle(selected, '愛喝咖啡');
    selected = PartnerMemoryTagCatalog.toggle(selected, '住海外');

    expect(selected, isNot(contains('住同縣市')));
    expect(selected, containsAll(<String>{'住海外', '愛喝咖啡'}));

    selected = PartnerMemoryTagCatalog.toggle(selected, '住海外');
    expect(selected, isNot(contains('住海外')));
  });

  test('compact summary 顯示前兩顆與剩餘數量', () {
    expect(
      PartnerMemoryTagCatalog.compactSummary(
        <String>{'喜歡寵物', '慢熱', '工作忙碌'},
      ),
      '工作忙碌、慢熱 ＋1',
    );
  });
}
