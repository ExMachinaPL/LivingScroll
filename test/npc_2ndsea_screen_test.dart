import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:living_scroll/l10n/app_localizations.dart';
import 'package:living_scroll/npcs/npcs_controller.dart';
import 'package:living_scroll/npcs/second_sea/second_sea.dart';
import 'package:living_scroll/screens/npc_2ndsea_screen.dart';

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(body: home),
    );

const _uuid = '11111111-1111-1111-1111-111111111111';

NpcsController _base() {
  final c = NpcsController(newId: () => 'new-uuid');
  c.setTemplate(SecondSea.template,
      systemId: SecondSea.systemId, pruneHiddenStats: true);
  return c;
}

/// A controller adding a NEW NPC (starts on the kind page).
NpcsController _controllerNew() {
  final c = _base()..loadFrom({'npcs': []});
  c.beginNew();
  return c;
}

/// A controller EDITING an existing NPC with the given stats (opens on details).
NpcsController _controllerEdit(Map<String, dynamic> stats) {
  final c = _base();
  c.loadFrom({
    'npcs': [
      {
        'name': 'The Count',
        'npc_uuid': _uuid,
        'full_image': 'full',
        'icon_image': 'icon',
        'stats': {...SecondSea.template.defaults(), ...stats},
      }
    ],
  });
  c.beginEdit(_uuid);
  return c;
}

Future<void> _pump(WidgetTester tester, NpcsController c,
    {Locale locale = const Locale('en')}) async {
  await tester.pumpWidget(_app(
      Npc2ndSeaScreen(
        // A per-locale key forces a fresh State when a test pumps twice (Flutter
        // reuses the State of an unkeyed same-type widget across pumpWidget).
        key: ValueKey('npc7s-${locale.languageCode}'),
        controller: c,
        imagesBasePath: '/nowhere',
        onSave: () async => c.save(),
        onCancel: () {},
      ),
      locale: locale));
  await tester.pumpAndSettle();
}

String _step(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('npc.2ndsea.step.indicator')))
    .data!;

Future<void> _pickKind(WidgetTester tester, String kind) async {
  await tester.tap(find.byKey(ValueKey('npc.2ndsea.kind.$kind')));
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('npc.2ndsea.next')));
  await tester.pumpAndSettle();
}

Finder _field(String key) => find.byKey(ValueKey('npc.2ndsea.field.$key'));

void main() {
  void big(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('new NPC — the two-step flow', () {
    testWidgets('opens on the kind page (1/2) with three radio options',
        (tester) async {
      big(tester);
      await _pump(tester, _controllerNew());
      expect(_step(tester), '1/2');
      for (final k in SecondSea.kinds) {
        expect(find.byKey(ValueKey('npc.2ndsea.kind.$k')), findsOneWidget);
      }
      expect(_field('strength'), findsNothing); // no stats on the kind page
    });

    testWidgets('Monster: details page has only the common fields — no stats',
        (tester) async {
      big(tester);
      await _pump(tester, _controllerNew());
      await _pickKind(tester, 'monster');
      await _next(tester);
      expect(_step(tester), '2/2');
      expect(find.byKey(const ValueKey('npc.2ndsea.name')), findsOneWidget);
      expect(find.byKey(const ValueKey('npc.2ndsea.description')), findsOneWidget);
      expect(_field('strength'), findsNothing);
      expect(_field('influence'), findsNothing);
      expect(find.byKey(const ValueKey('npc.2ndsea.derived.villainy_rank')),
          findsNothing);
      expect(find.byKey(const ValueKey('npc.2ndsea.advantage.sorcery')),
          findsNothing);
    });

    testWidgets('Brute squad: shows Strength, hides Influence/Rank/Advantages',
        (tester) async {
      big(tester);
      await _pump(tester, _controllerNew());
      await _pickKind(tester, 'brute_squad');
      await _next(tester);
      expect(_field('strength'), findsOneWidget);
      expect(_field('influence'), findsNothing);
      expect(find.byKey(const ValueKey('npc.2ndsea.derived.villainy_rank')),
          findsNothing);
      expect(find.byKey(const ValueKey('npc.2ndsea.advantage.sorcery')),
          findsNothing);
    });

    testWidgets('Villain: shows Strength, Influence; Rank computes',
        (tester) async {
      big(tester);
      await _pump(tester, _controllerNew());
      await _next(tester); // villain is the default kind
      expect(_field('strength'), findsOneWidget);
      expect(_field('influence'), findsOneWidget);

      await tester.enterText(_field('strength'), '5');
      await tester.pump();
      await tester.enterText(_field('influence'), '3');
      await tester.pump();
      final rank = tester
          .widget<Text>(
              find.byKey(const ValueKey('npc.2ndsea.derived.villainy_rank')))
          .data!;
      expect(rank, '8'); // 5 + 3
    });

    testWidgets('numeric stat is digits-only and capped at 3 digits',
        (tester) async {
      big(tester);
      final c = _controllerNew();
      await _pump(tester, c);
      await _next(tester); // villain -> details
      final str = _field('strength');
      String text() => tester.widget<TextField>(str).controller!.text;

      await tester.enterText(str, 'ab12'); // letters stripped
      await tester.pump();
      expect(text(), '12');
      expect(c.editStats['strength'], 12);

      await tester.enterText(str, '9999'); // 4th digit rejected
      await tester.pump();
      expect(text(), '999');
      expect(c.editStats['strength'], 999);
    });

    testWidgets('nav buttons are grouped together (not split to the edges)',
        (tester) async {
      big(tester);
      await _pump(tester, _controllerNew());
      // Kind page: Cancel + Next. They must sit side by side (a small gap),
      // never Cancel far-left and Next far-right.
      final cancel =
          tester.getRect(find.byKey(const ValueKey('npc.2ndsea.cancel')));
      final next = tester.getRect(find.byKey(const ValueKey('npc.2ndsea.next')));
      expect(cancel.right, lessThan(next.left)); // Cancel precedes Next
      expect(next.left - cancel.right, lessThan(40)); // adjacent, not spread apart
    });

    testWidgets('Villain form has NO Advantages section (EN + PL)',
        (tester) async {
      big(tester);
      await _pump(tester, _controllerNew());
      await _next(tester); // villain
      expect(find.byKey(const ValueKey('npc.2ndsea.advantages.grid')),
          findsNothing);
      expect(find.byKey(const ValueKey('npc.2ndsea.advantage.sorcery')),
          findsNothing);
      expect(find.text('Advantages'), findsNothing);
      expect(find.text('Sorcery'), findsNothing);

      await _pump(tester, _controllerNew(), locale: const Locale('pl'));
      await _next(tester);
      expect(find.text('Atuty'), findsNothing);
      expect(find.text('Magia'), findsNothing);
    });
  });

  group('existing NPC — details only, kind immutable', () {
    testWidgets('editing opens the details page directly (no kind page)',
        (tester) async {
      big(tester);
      await _pump(tester,
          _controllerEdit({'kind': 'villain', 'strength': 5, 'influence': 3}));

      // A single step — details — shown immediately.
      expect(_step(tester), '1/1');
      expect(find.byKey(const ValueKey('npc.2ndsea.name')), findsOneWidget);
      expect(find.byKey(const ValueKey('npc.2ndsea.description')), findsOneWidget);
      // The kind can NEVER be changed: no kind radios, no Next/Back.
      for (final k in SecondSea.kinds) {
        expect(find.byKey(ValueKey('npc.2ndsea.kind.$k')), findsNothing);
      }
      expect(find.byKey(const ValueKey('npc.2ndsea.next')), findsNothing);
      expect(find.byKey(const ValueKey('npc.2ndsea.back')), findsNothing);
      expect(find.byKey(const ValueKey('npc.2ndsea.save')), findsOneWidget);
      // The Villain's own stats are there from the start.
      expect(_field('strength'), findsOneWidget);
      expect(_field('influence'), findsOneWidget);
      expect(find.byKey(const ValueKey('npc.2ndsea.derived.villainy_rank')),
          findsOneWidget);
    });

    testWidgets('editing a legacy Villain with stored advantages shows no '
        'Advantages section', (tester) async {
      big(tester);
      await _pump(
          tester,
          _controllerEdit({
            'kind': 'villain',
            'strength': 5,
            'influence': 3,
            'advantages': ['sorcery'],
          }));
      expect(_field('strength'), findsOneWidget);
      expect(find.byKey(const ValueKey('npc.2ndsea.advantages.grid')),
          findsNothing);
      expect(find.text('Sorcery'), findsNothing);
    });

    testWidgets('editing a Monster opens details with no stat fields',
        (tester) async {
      big(tester);
      await _pump(tester, _controllerEdit({'kind': 'monster'}));
      expect(_step(tester), '1/1');
      expect(find.byKey(const ValueKey('npc.2ndsea.name')), findsOneWidget);
      expect(_field('strength'), findsNothing);
      expect(_field('influence'), findsNothing);
      expect(find.byKey(const ValueKey('npc.2ndsea.advantage.sorcery')),
          findsNothing);
      // Still no way to change the kind.
      for (final k in SecondSea.kinds) {
        expect(find.byKey(ValueKey('npc.2ndsea.kind.$k')), findsNothing);
      }
    });

    testWidgets('editing a Brute squad shows Strength only', (tester) async {
      big(tester);
      await _pump(tester, _controllerEdit({'kind': 'brute_squad', 'strength': 7}));
      expect(_step(tester), '1/1');
      expect(_field('strength'), findsOneWidget);
      expect(_field('influence'), findsNothing);
      expect(find.byKey(const ValueKey('npc.2ndsea.advantage.sorcery')),
          findsNothing);
    });
  });

  testWidgets('image row does not overflow at a narrow window (Finding 4)',
      (tester) async {
    // The fixed-size image row (~464px natural) is wrapped in a
    // FittedBox(scaleDown), so a narrow window scales it instead of overflowing
    // horizontally. Uses the Monster kind (no stats) at a width where the
    // form area (~352px) is narrower than the image row but still fits the nav
    // row — isolating the image-row fix from the other narrow-width concerns.
    tester.view.physicalSize = const Size(480, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(tester, _controllerNew());
    await _pickKind(tester, 'monster');
    await _next(tester); // monster -> details (image row + name + description)
    expect(find.byKey(const ValueKey('npc.2ndsea.full_image')), findsOneWidget);
    expect(_field('strength'), findsNothing); // no stats
    expect(tester.takeException(), isNull);
  });
}
