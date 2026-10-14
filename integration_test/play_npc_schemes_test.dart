// PATH: play_npc_schemes
// In the Play view, a 2nd Sea VILLAIN NPC's info dialog carries a
// Schemes/Intrygi action that opens a two-panel manager (same frame, covers
// the info window). LEFT: Intryga tiles (Settle pays cost×2 into influence,
// Fail is a no-op; both grey + move the tile to the end) + a New-scheme add
// button. RIGHT: purchased Koszty as text + a Buy button (reduces influence).
// Changes persist via the host in gameplay (PlaythroughScreen._updateNpcStats
// -> ProjectsStore.writeSaveDocument), so this runs through a REAL Play
// session (Launch -> Play), not the editor preview.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/create_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void useDesktopView(WidgetTester tester) {
    // Large enough for the two-panel Schemes manager dialog to lay out
    // without needing to scroll every tap into view.
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Directory advDir(CreateHarness h) => Directory('${h.adventuresDir.path}/Pack');

  Directory saveDir(CreateHarness h) =>
      Directory('${h.savesDir.path}/Pack-1.0.0-Team A');

  // A single-scene start, 2nd Sea adventure with one Villain NPC (whose
  // stats hold influence + an unresolved Intryga) and one Brute squad NPC
  // (for BRANCH B4 — no Schemes action), both attached to the scene.
  Future<void> seedPack(CreateHarness harness) async {
    final adv = advDir(harness);
    await adv.create(recursive: true);
    await File('${adv.path}/LivingScroll.json').writeAsString(
      jsonEncode({
        'metadata': {
          'name': 'Pack',
          'system': '2ndsea',
          'version': '1.0.0',
          'author': '',
          'description': '',
        },
        'images': [],
        'audio': [],
        'paths': [],
        'key_events': [],
        'notes': [],
        'gm_notes': [],
        'npcs': [
          {
            'npc_uuid': 'v1',
            'name': 'The Count',
            'description': 'A foe.',
            'stats': {
              'kind': 'villain',
              'strength': 6,
              'influence': 10,
              'schemes': [
                {'type': 'scheme', 'name': 'Plot', 'cost': 4},
              ],
            },
          },
          {
            'npc_uuid': 'b1',
            'name': 'Guards',
            'description': 'A squad.',
            'stats': {'kind': 'brute_squad', 'strength': 8},
          },
        ],
        'scenes': [
          {
            'scene_uuid': 's1',
            'name': 'Hall',
            'description': 'A grand hall.',
            'scene_type': 'start',
            'npcs': ['The Count', 'Guards'],
          },
        ],
      }),
    );
  }

  // A gameplay session persists npcs[].stats via a fire-and-forget file
  // write; runAsync yields to the REAL event loop so it flushes before the
  // test reads it (see library_play_test.dart's settleIO for the rationale).
  Future<void> settleIO(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  // Launches the seeded Pack into a real gameplay session and switches the
  // right column to the NPC grid (the tile the STEPS operate on).
  Future<void> playPack(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('nav.library')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adventure.tile.Pack')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library.adventure.info.play')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('launch.field.group')),
      'Team A',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('launch.play')));
    await tester.pumpAndSettle();
    await settleIO(tester);
    await tester.tap(find.byKey(const ValueKey('nav.play.npc')));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> readNpc(CreateHarness h, String uuid) =>
      (jsonDecode(
                File(
                  '${saveDir(h).path}/LivingScroll.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)['npcs']
          .cast<Map<String, dynamic>>()
          .firstWhere((n) => n['npc_uuid'] == uuid);

  const mk = 'play.npc.info.v1.schemes'; // manager key prefix

  Future<void> tapVisible(WidgetTester tester, Key key) async {
    final f = find.byKey(key);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'play_npc_schemes: open the manager, settle an Intryga, buy a Koszt, '
    'close back to the info window — all persisted via the save',
    (tester) async {
      useDesktopView(tester);
      final harness = CreateHarness();
      await harness.setUp();
      addTearDown(harness.tearDown);
      await seedPack(harness);

      await harness.pumpApp(tester);
      await playPack(tester);

      // STEP 1: open the villain info dialog -> the Schemes manager.
      await tester.tap(find.byKey(const ValueKey('play.npc.tile.v1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('play.npc.info.v1')), findsOneWidget);
      await tapVisible(tester, const ValueKey('play.npc.info.v1.schemes'));
      expect(find.byKey(const ValueKey('$mk.dialog')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('$mk.intrigue.0.label')))
            .data,
        'Plot (4)',
      );

      // STEP 2: SETTLE the Intryga — influence 10 + 4*2 = 18, resolved + moved
      // to the end; the info window's badges update live behind the manager.
      await tapVisible(tester, const ValueKey('$mk.intrigue.0.settle'));
      await settleIO(tester);
      var npc = readNpc(harness, 'v1');
      expect((npc['stats'] as Map)['influence'], 18);
      var schemes = (npc['stats'] as Map)['schemes'] as List;
      expect(schemes.last['name'], 'Plot');
      expect(schemes.last['resolved'], true);

      // STEP 3: BUY a Koszt — influence -= cost; a cost entry is appended and
      // shown on the RIGHT panel.
      await tapVisible(tester, const ValueKey('$mk.buy'));
      expect(
        find.byKey(const ValueKey('play.npc.scheme.buy.dialog')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('play.npc.scheme.buy.dialog.name')),
        'Bribe',
      );
      await tester.enterText(
        find.byKey(const ValueKey('play.npc.scheme.buy.dialog.cost')),
        '3',
      );
      await tester.pump();
      await tapVisible(tester, const ValueKey('play.npc.scheme.buy.dialog.buy'));
      await settleIO(tester);
      // The cost row's key uses the RAW index in stats.schemes (verified in
      // play_screen.dart's `_costs`): the settled "Plot" scheme still occupies
      // index 0 (resolved, not removed), so the newly-bought "Bribe" cost
      // lands at index 1.
      expect(find.byKey(const ValueKey('$mk.cost.1')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('$mk.cost.1'))).data,
        'Bribe (3)',
      );
      npc = readNpc(harness, 'v1');
      expect((npc['stats'] as Map)['influence'], 15);
      schemes = (npc['stats'] as Map)['schemes'] as List;
      expect(schemes.last, {'type': 'cost', 'name': 'Bribe', 'cost': 3});

      // STEP 4: close the manager -> back on the info window.
      await tapVisible(tester, const ValueKey('$mk.close'));
      expect(find.byKey(const ValueKey('$mk.dialog')), findsNothing);
      expect(find.byKey(const ValueKey('play.npc.info.v1')), findsOneWidget);
    },
  );

  testWidgets(
    'BRANCH B1 fail_intryga: FAIL computes nothing but still resolves it',
    (tester) async {
      useDesktopView(tester);
      final harness = CreateHarness();
      await harness.setUp();
      addTearDown(harness.tearDown);
      await seedPack(harness);

      await harness.pumpApp(tester);
      await playPack(tester);
      await tester.tap(find.byKey(const ValueKey('play.npc.tile.v1')));
      await tester.pumpAndSettle();
      await tapVisible(tester, const ValueKey('play.npc.info.v1.schemes'));

      await tapVisible(tester, const ValueKey('$mk.intrigue.0.fail'));
      await settleIO(tester);

      final npc = readNpc(harness, 'v1');
      expect((npc['stats'] as Map)['influence'], 10); // unchanged
      final schemes = (npc['stats'] as Map)['schemes'] as List;
      expect(schemes.last['name'], 'Plot');
      expect(schemes.last['resolved'], true);
    },
  );

  testWidgets(
    'BRANCH B2 new_scheme: adding a scheme from the manager reuses the game '
    'New-scheme dialog',
    (tester) async {
      useDesktopView(tester);
      final harness = CreateHarness();
      await harness.setUp();
      addTearDown(harness.tearDown);
      await seedPack(harness);

      await harness.pumpApp(tester);
      await playPack(tester);
      await tester.tap(find.byKey(const ValueKey('play.npc.tile.v1')));
      await tester.pumpAndSettle();
      await tapVisible(tester, const ValueKey('play.npc.info.v1.schemes'));

      await tapVisible(tester, const ValueKey('$mk.new'));
      // The SAME dialog as in the game editor's NPC form.
      expect(
        find.byKey(const ValueKey('npc.2ndsea.scheme.dialog')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('npc.2ndsea.scheme.dialog.name')),
        'Ambush',
      );
      await tester.enterText(
        find.byKey(const ValueKey('npc.2ndsea.scheme.dialog.cost')),
        '3',
      );
      await tester.pump();
      await tapVisible(
        tester,
        const ValueKey('npc.2ndsea.scheme.dialog.add'),
      );
      await settleIO(tester);

      final npc = readNpc(harness, 'v1');
      final schemes = (npc['stats'] as Map)['schemes'] as List;
      expect(schemes.last, {
        'type': 'scheme',
        'name': 'Ambush',
        'cost': 3,
        'resolved': false,
      });
    },
  );

  testWidgets(
    'BRANCH B3 buy_over_influence_blocked: buying more than the available '
    'influence is blocked',
    (tester) async {
      useDesktopView(tester);
      final harness = CreateHarness();
      await harness.setUp();
      addTearDown(harness.tearDown);
      await seedPack(harness);

      await harness.pumpApp(tester);
      await playPack(tester);
      await tester.tap(find.byKey(const ValueKey('play.npc.tile.v1')));
      await tester.pumpAndSettle();
      await tapVisible(tester, const ValueKey('play.npc.info.v1.schemes'));

      await tapVisible(tester, const ValueKey('$mk.buy'));
      await tester.enterText(
        find.byKey(const ValueKey('play.npc.scheme.buy.dialog.name')),
        'Big',
      );
      // Available influence is 10 (nothing settled/bought yet); ask for more.
      await tester.enterText(
        find.byKey(const ValueKey('play.npc.scheme.buy.dialog.cost')),
        '99',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('play.npc.scheme.buy.dialog.buy')),
            )
            .enabled,
        isFalse,
      );
    },
  );

  testWidgets(
    'BRANCH B4 brute_no_schemes: a Brute NPC info dialog has NO Schemes action',
    (tester) async {
      useDesktopView(tester);
      final harness = CreateHarness();
      await harness.setUp();
      addTearDown(harness.tearDown);
      await seedPack(harness);

      await harness.pumpApp(tester);
      await playPack(tester);
      await tester.tap(find.byKey(const ValueKey('play.npc.tile.b1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('play.npc.info.b1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('play.npc.info.b1.schemes')),
        findsNothing,
      );
    },
  );
}
