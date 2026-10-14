// Widget coverage for the PC row (LAYOUTS/replay "PC ROW"): a non-interactive
// row of PC (player-character) name buttons shown directly ABOVE the Key
// events row, sourced from the history snapshot's `available_pc_names`
// (SPECS/Schema.md::history.json). Populated only by [ReplayScreen] — a live
// play/preview never supplies it, so the row is absent there. The end-to-end
// replay scenario (reading the snapshot off a finished session's
// history.json) is covered by integration_test/library_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:living_scroll/l10n/app_localizations.dart';
import 'package:living_scroll/scenes/scene.dart';
import 'package:living_scroll/screens/play_screen.dart';

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: home),
);

Scene _scene() => Scene.fromJson({
  'name': 'Scene',
  'scene_uuid': 's1',
  'scene_type': 'start',
  'description': 'A room.',
  'key_events': ['Met duke'],
});

PlayScreen _play({
  PlayMode mode = PlayMode.replay,
  List<String> historyPcNames = const [],
  List<({String name, bool checked})> keyEvents = const [
    (name: 'Met duke', checked: true),
  ],
}) => PlayScreen(
  scene: _scene(),
  mode: mode,
  keyEvents: keyEvents,
  historyPcNames: historyPcNames,
  nextScenes: const [],
  npcs: const [],
  notes: const [],
  images: const [],
  onExit: () {},
);

Future<void> _pump(WidgetTester tester, PlayScreen play) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(play));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'absent when historyPcNames is empty (the default — live play/preview '
    'never supplies it)',
    (tester) async {
      await _pump(tester, _play(historyPcNames: const []));
      expect(find.byKey(const ValueKey('play.pcnames.row.box')), findsNothing);
      expect(find.byKey(const ValueKey('play.pcnames.row')), findsNothing);
    },
  );

  testWidgets(
    'one NON-CLICKABLE button per PC name when populated',
    (tester) async {
      await _pump(
        tester,
        _play(historyPcNames: const ['Alice', 'Bob']),
      );
      expect(find.byKey(const ValueKey('play.pcnames.row.box')), findsOne);
      expect(find.byKey(const ValueKey('play.pcnames.row')), findsOne);
      final alice = find.byKey(const ValueKey('play.pcname.Alice'));
      final bob = find.byKey(const ValueKey('play.pcname.Bob'));
      expect(alice, findsOne);
      expect(bob, findsOne);
      expect(find.text('Alice'), findsOne);
      expect(find.text('Bob'), findsOne);
      // NON-CLICKABLE: onPressed is null (a disabled FilledButton).
      expect(tester.widget<FilledButton>(alice).onPressed, isNull);
      expect(tester.widget<FilledButton>(bob).onPressed, isNull);
    },
  );

  testWidgets(
    'sits directly ABOVE the Key events row',
    (tester) async {
      await _pump(tester, _play(historyPcNames: const ['Alice']));
      final pcRowBox = tester.getTopLeft(
        find.byKey(const ValueKey('play.pcnames.row.box')),
      );
      final keyEventsRowBox = tester.getTopLeft(
        find.byKey(const ValueKey('play.keyevents.row.box')),
      );
      expect(pcRowBox.dy, lessThan(keyEventsRowBox.dy));
    },
  );
}
