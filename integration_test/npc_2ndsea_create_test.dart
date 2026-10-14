// PATH: in a 2nd Sea adventure, Add NPC -> the kind-driven form.
// Page 1 picks the kind (Villain / Brute squad / Monster); page 2 shows the
// common NPC fields plus the stats that kind adds (Villain: Strength, Influence,
// a computed Villainy Rank and Schemes — NO Advantages). Save writes only the
// applicable npcs[].stats (hidden fields pruned) + the role PNGs.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

import 'support/create_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Directory demoDir(CreateHarness h) => Directory('${h.projectsDir.path}/Demo');

  void bigWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> seedDemo(
    CreateHarness h, {
    List<Map<String, dynamic>> npcs = const [],
  }) async {
    final dir = demoDir(h);
    await dir.create(recursive: true);
    await File('${dir.path}/LivingScroll.json').writeAsString(
      jsonEncode({
        'metadata': {
          'name': 'Demo',
          'system': '2ndsea',
          'version': '1.0.0',
          'author': 'A',
          'description': 'd',
          'language': 'en',
          'content_warnings': 'none',
          'license': 'x',
        },
        'images': [],
        'audio': [],
        'paths': [],
        'key_events': [],
        'notes': [],
        'gm_notes': [],
        'npcs': npcs,
        'scenes': [],
      }),
    );
  }

  Map<String, dynamic> readDoc(CreateHarness h) =>
      jsonDecode(
            File('${demoDir(h).path}/LivingScroll.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  Future<void> openNpcGrid(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('nav.create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adventure.tile.Demo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav.game.npcs')));
    await tester.pumpAndSettle();
  }

  Future<void> openNpcAdd(WidgetTester tester) async {
    await openNpcGrid(tester);
    await tester.tap(find.byKey(const ValueKey('game.npc.add')));
    await tester.pumpAndSettle();
  }

  Future<void> pickImages(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('npc.2ndsea.full_image')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('npc_2ndsea.full_image.crop.confirm')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('npc_2ndsea.icon_image.crop.confirm')),
    );
    await tester.pumpAndSettle();
  }

  void expectRolePngs(CreateHarness h, Map<String, dynamic> npc) {
    final full = File(
      '${demoDir(h).path}/images/npcs/${npc['full_image']}.png',
    );
    final icon = File(
      '${demoDir(h).path}/images/npcs/${npc['icon_image']}.png',
    );
    final fullImg = img.decodePng(full.readAsBytesSync())!;
    final iconImg = img.decodePng(icon.readAsBytesSync())!;
    expect([fullImg.width, fullImg.height], [1000, 1430]);
    expect([iconImg.width, iconImg.height], [400, 572]);
  }

  testWidgets(
    'npc_2ndsea_create: Villain writes strength/influence, no advantages',
    (tester) async {
      final harness = CreateHarness();
      await harness.setUp();
      addTearDown(harness.tearDown);
      bigWindow(tester);
      await seedDemo(harness);
      harness.coverPath = CreateHarness.asset('cover_sample.jpg');

      await harness.pumpApp(tester);
      await openNpcAdd(tester);

      // Page 1 — kind selector (Villain is the default).
      expect(find.byKey(const ValueKey('npc.2ndsea.form')), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('npc.2ndsea.step.indicator')),
            )
            .data,
        '1/2',
      );
      await tester.tap(find.byKey(const ValueKey('npc.2ndsea.kind.villain')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('npc.2ndsea.next')));
      await tester.pumpAndSettle();

      // Page 2 — details.
      await tester.enterText(
        find.byKey(const ValueKey('npc.2ndsea.name')),
        'The Count',
      );
      await tester.pump();
      await pickImages(tester);
      await tester.enterText(
        find.byKey(const ValueKey('npc.2ndsea.field.strength')),
        '5',
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('npc.2ndsea.field.influence')),
        '3',
      );
      await tester.pump();
      // Villainy Rank is computed = 5 + 3.
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('npc.2ndsea.derived.villainy_rank')),
            )
            .data,
        '8',
      );
      // The Villain form has NO Advantages section.
      expect(
        find.byKey(const ValueKey('npc.2ndsea.advantages.grid')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('npc.2ndsea.advantage.sorcery')),
        findsNothing,
      );

      await tester.ensureVisible(find.byKey(const ValueKey('npc.2ndsea.save')));
      await tester.tap(find.byKey(const ValueKey('npc.2ndsea.save')));
      await tester.pumpAndSettle();

      final npcs = (readDoc(harness)['npcs'] as List)
          .cast<Map<String, dynamic>>();
      expect(npcs.length, 1);
      final npc = npcs.single;
      expect(npc['name'], 'The Count');
      final stats = npc['stats'] as Map<String, dynamic>;
      expect(stats['kind'], 'villain');
      expect(stats['strength'], 5);
      expect(stats['influence'], 3);
      expect(stats.containsKey('advantages'), isFalse);
      expect(
        stats.containsKey('villainy_rank'),
        isFalse,
      ); // derived, never stored
      expectRolePngs(harness, npc);

      expect(find.byKey(const ValueKey('game.npc.grid')), findsOneWidget);
    },
  );

  testWidgets(
    'npc_2ndsea_create: Monster stores only its kind (stats pruned)',
    (tester) async {
      final harness = CreateHarness();
      await harness.setUp();
      addTearDown(harness.tearDown);
      bigWindow(tester);
      await seedDemo(harness);
      harness.coverPath = CreateHarness.asset('cover_sample.jpg');

      await harness.pumpApp(tester);
      await openNpcAdd(tester);

      await tester.tap(find.byKey(const ValueKey('npc.2ndsea.kind.monster')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('npc.2ndsea.next')));
      await tester.pumpAndSettle();

      // Monster has no stat fields on the details page.
      expect(
        find.byKey(const ValueKey('npc.2ndsea.field.strength')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('npc.2ndsea.name')),
        'Kraken',
      );
      await tester.pump();
      await pickImages(tester);
      await tester.tap(find.byKey(const ValueKey('npc.2ndsea.save')));
      await tester.pumpAndSettle();

      final npc = (readDoc(harness)['npcs'] as List)
          .cast<Map<String, dynamic>>()
          .single;
      expect(npc['name'], 'Kraken');
      expect(npc['stats'], {'kind': 'monster'});
      expectRolePngs(harness, npc);
    },
  );

  testWidgets(
    'npc_2ndsea_create: editing an existing NPC opens details directly',
    (tester) async {
      final harness = CreateHarness();
      await harness.setUp();
      addTearDown(harness.tearDown);
      bigWindow(tester);
      // Seed an adventure that already has one Villain NPC.
      await seedDemo(
        harness,
        npcs: [
          {
            'name': 'The Count',
            'npc_uuid': 'v1',
            'stats': {'kind': 'villain', 'strength': 5, 'influence': 3},
          },
        ],
      );

      await harness.pumpApp(tester);
      await openNpcGrid(tester);
      await tester.tap(find.byKey(const ValueKey('game.npc.tile.v1')));
      await tester.pumpAndSettle();

      // The details page opens immediately (a single step); the kind is immutable.
      expect(find.byKey(const ValueKey('npc.2ndsea.form')), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('npc.2ndsea.step.indicator')),
            )
            .data,
        '1/1',
      );
      expect(find.byKey(const ValueKey('npc.2ndsea.name')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('npc.2ndsea.field.strength')),
        findsOneWidget,
      );
      // No kind selector, no step navigation.
      expect(
        find.byKey(const ValueKey('npc.2ndsea.kind.villain')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('npc.2ndsea.kind.monster')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('npc.2ndsea.next')), findsNothing);
      expect(find.byKey(const ValueKey('npc.2ndsea.back')), findsNothing);
    },
  );
}
