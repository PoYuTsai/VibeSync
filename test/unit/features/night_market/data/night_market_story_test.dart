import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/night_market/data/night_market_story.dart';
import 'package:vibesync/features/night_market/domain/night_market_scenario.dart';

void main() {
  group('buildNightMarketScenario', () {
    for (final variant in NightMarketRunVariant.values) {
      test('reachable graph has all targets for $variant', () {
        final scenario = buildNightMarketScenario(variant: variant);
        final seen = <String>{};
        final pending = <String>[scenario.initialBeatId];

        while (pending.isNotEmpty) {
          final id = pending.removeLast();
          if (!seen.add(id)) continue;
          final beat = scenario.beatById(id);
          expect(beat, isNotNull, reason: 'missing target $id');
          if (beat!.nextId != null) pending.add(beat.nextId!);
          pending.addAll(beat.choices.map((choice) => choice.nextId));
        }

        final expected = <String>[
          'establish',
          'hesitate',
          'opening',
          'concern',
          'work',
          'craft',
          'tease',
          'call',
          if (variant == NightMarketRunVariant.available) ...[
            'available',
            'date',
          ] else ...[
            'busy',
            'contact',
          ],
          'decline',
          'coach',
        ];
        expect(seen, containsAll(expected));
      });
    }

    test('variant controls time branch before playback', () {
      final available = buildNightMarketScenario(
        variant: NightMarketRunVariant.available,
      );
      final busy =
          buildNightMarketScenario(variant: NightMarketRunVariant.busy);

      expect(available.beatById('call')!.nextId, 'available');
      expect(busy.beatById('call')!.nextId, 'busy');
      expect(available.beatById('available'), isNotNull);
      expect(busy.beatById('busy'), isNotNull);
    });

    test('has three distinct ending routes', () {
      final scenario = buildNightMarketScenario();
      final date = scenario.beatById('date')!;
      final contact = scenario.beatById('contact')!;
      final decline = scenario.beatById('decline')!;

      expect(date.nextId, 'decline');
      expect(contact.nextId, 'coach');
      expect(decline.nextId, 'coach');
      expect(decline.choices, isEmpty);
      expect(scenario.beatById('coach')!.ending, isTrue);
    });

    test('decline cannot invite or request contact', () {
      final scenario = buildNightMarketScenario();
      final decline = scenario.beatById('decline')!;

      expect(decline.choices, isEmpty);
      expect(decline.captions.every((caption) => !caption.text.contains('聯絡')),
          isTrue);
    });

    test('all choice labels and player voice assets are concrete', () {
      final scenario = buildNightMarketScenario();
      for (final beat in scenario.beats) {
        for (final choice in beat.choices) {
          expect(choice.label.trim(), isNotEmpty);
          expect(choice.nextId.trim(), isNotEmpty);
          expect(choice.feedbackTag?.trim(), isNotEmpty);
          if (choice.spokenText!.isEmpty) {
            expect(choice.audioAsset, isNull);
          } else {
            expect(choice.label, choice.spokenText);
            expect(choice.audioAsset, startsWith('assets/audio/night_market/'));
          }
        }
      }
    });

    test('only hesitate and coach carry original sfx cues', () {
      final scenario = buildNightMarketScenario();
      expect(scenario.beatById('hesitate')!.sfxAsset,
          'assets/audio/night_market/hesitate-heartbeat.wav');
      expect(scenario.beatById('coach')!.sfxAsset,
          'assets/audio/night_market/ui-cue.wav');
      expect(
        scenario.beats
            .where((beat) => beat.sfxAsset != null)
            .map((beat) => beat.id),
        containsAll(<String>['hesitate', 'coach']),
      );
    });

    test('all video targets use the 14 bundled asset names', () {
      final scenario = buildNightMarketScenario();
      final assets = scenario.beats.map((beat) => beat.videoAsset).toSet();

      expect(assets.length, 14);
      expect(assets, everyElement(startsWith('assets/videos/night_market/')));
      expect(
        assets,
        containsAll(<String>[
          'assets/videos/night_market/establish.mp4',
          'assets/videos/night_market/hesitate.mp4',
          'assets/videos/night_market/opening.mp4',
          'assets/videos/night_market/concern.mp4',
          'assets/videos/night_market/work.mp4',
          'assets/videos/night_market/craft.mp4',
          'assets/videos/night_market/tease.mp4',
          'assets/videos/night_market/call.mp4',
          'assets/videos/night_market/available.mp4',
          'assets/videos/night_market/date.mp4',
          'assets/videos/night_market/busy.mp4',
          'assets/videos/night_market/contact.mp4',
          'assets/videos/night_market/decline.mp4',
          'assets/videos/night_market/coach.mp4',
        ]),
      );
    });
  });
}
