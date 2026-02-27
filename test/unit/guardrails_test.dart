// test/unit/guardrails_test.dart
import 'package:flutter_test/flutter_test.dart';

/// Tests for guardrails safety patterns
/// Note: The actual guardrails run server-side in Supabase Edge Function
/// These tests verify the pattern matching logic concept

void main() {
  group('Guardrails Safety Patterns', () {
    // Blocked patterns (should be filtered)
    final blockedPatterns = [
      RegExp(r'跟蹤|stalking', caseSensitive: false),
      RegExp(r'不要放棄.*一直', caseSensitive: false),
      RegExp(r'她說不要.*但其實', caseSensitive: false),
      RegExp(r'強迫|逼.*答應', caseSensitive: false),
      RegExp(r'騷擾|harassment', caseSensitive: false),
      RegExp(r'威脅|勒索', caseSensitive: false),
      RegExp(r'死纏爛打', caseSensitive: false),
    ];

    bool containsBlockedPattern(String text) {
      for (final pattern in blockedPatterns) {
        if (pattern.hasMatch(text)) {
          return true;
        }
      }
      return false;
    }

    group('should detect blocked patterns', () {
      test('detects stalking keywords', () {
        expect(containsBlockedPattern('你可以跟蹤她'), isTrue);
        expect(containsBlockedPattern('Try stalking her'), isTrue);
      });

      test('detects persistence after rejection', () {
        expect(containsBlockedPattern('不要放棄，一直試'), isTrue);
      });

      test('detects ignoring consent', () {
        expect(containsBlockedPattern('她說不要，但其實想要'), isTrue);
      });

      test('detects coercion keywords', () {
        expect(containsBlockedPattern('可以強迫她答應'), isTrue);
        expect(containsBlockedPattern('逼她答應'), isTrue);
      });

      test('detects harassment keywords', () {
        expect(containsBlockedPattern('騷擾她'), isTrue);
        expect(containsBlockedPattern('harassment'), isTrue);
      });

      test('detects threat keywords', () {
        expect(containsBlockedPattern('威脅她'), isTrue);
        expect(containsBlockedPattern('勒索她'), isTrue);
      });

      test('detects 死纏爛打', () {
        expect(containsBlockedPattern('死纏爛打'), isTrue);
      });
    });

    group('should allow safe content', () {
      test('allows normal conversation suggestions', () {
        expect(containsBlockedPattern('你可以問她喜歡什麼'), isFalse);
        expect(containsBlockedPattern('試著聊聊她的興趣'), isFalse);
        expect(containsBlockedPattern('可以分享你的故事'), isFalse);
      });

      test('allows flirting suggestions', () {
        expect(containsBlockedPattern('開點小玩笑'), isFalse);
        expect(containsBlockedPattern('適度推拉'), isFalse);
      });

      test('allows respectful communication', () {
        expect(containsBlockedPattern('尊重她的意願'), isFalse);
        expect(containsBlockedPattern('如果她不想聊就算了'), isFalse);
      });
    });
  });

  group('Safe Reply Mapping', () {
    // Safe replies by enthusiasm level
    final safeReplies = {
      'cold': {
        'extend': '可以聊聊最近有什麼有趣的事嗎？',
        'resonate': '我理解，每個人都有自己的步調',
        'tease': '好吧，那我先忙我的囉',
        'humor': '看來今天運氣不太好呢',
        'coldRead': '感覺你現在比較忙？',
      },
      'warm': {
        'extend': '這個話題蠻有趣的，可以多說一點嗎？',
        'resonate': '我懂你的意思',
        'tease': '你這樣說讓我很好奇欸',
        'humor': '哈哈，你很有趣耶',
        'coldRead': '感覺你是個很有想法的人',
      },
      'hot': {
        'extend': '繼續聊這個，我覺得很有意思',
        'resonate': '對啊，我也這麼覺得',
        'tease': '你這樣說，讓我更想認識你了',
        'humor': '跟你聊天很開心耶',
        'coldRead': '我覺得我們蠻合的',
      },
      'very_hot': {
        'extend': '我們可以找時間見面聊',
        'resonate': '真的很開心認識你',
        'tease': '那我們來約個時間吧',
        'humor': '再聊下去我要愛上你了',
        'coldRead': '我有預感我們會很合',
      },
    };

    String getEnthusiasmLevel(int score) {
      if (score <= 30) return 'cold';
      if (score <= 60) return 'warm';
      if (score <= 80) return 'hot';
      return 'very_hot';
    }

    test('maps score 0-30 to cold level', () {
      expect(getEnthusiasmLevel(0), 'cold');
      expect(getEnthusiasmLevel(15), 'cold');
      expect(getEnthusiasmLevel(30), 'cold');
    });

    test('maps score 31-60 to warm level', () {
      expect(getEnthusiasmLevel(31), 'warm');
      expect(getEnthusiasmLevel(45), 'warm');
      expect(getEnthusiasmLevel(60), 'warm');
    });

    test('maps score 61-80 to hot level', () {
      expect(getEnthusiasmLevel(61), 'hot');
      expect(getEnthusiasmLevel(70), 'hot');
      expect(getEnthusiasmLevel(80), 'hot');
    });

    test('maps score 81-100 to very_hot level', () {
      expect(getEnthusiasmLevel(81), 'very_hot');
      expect(getEnthusiasmLevel(90), 'very_hot');
      expect(getEnthusiasmLevel(100), 'very_hot');
    });

    test('safe replies exist for all levels and reply types', () {
      final levels = ['cold', 'warm', 'hot', 'very_hot'];
      final types = ['extend', 'resonate', 'tease', 'humor', 'coldRead'];

      for (final level in levels) {
        expect(safeReplies.containsKey(level), isTrue);
        for (final type in types) {
          expect(safeReplies[level]!.containsKey(type), isTrue);
          expect(safeReplies[level]![type]!.isNotEmpty, isTrue);
        }
      }
    });
  });
}
