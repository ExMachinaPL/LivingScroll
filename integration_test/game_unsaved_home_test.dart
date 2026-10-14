// Integration test for NAVIGATIONS/game_unsaved_home: leaving the game editor
// through its Home destination while a section's form holds unsaved input is
// guarded by the Save / Abandon / Cancel prompt — for EVERY editable section.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/create_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder byKey(String k) => find.byKey(ValueKey(k));

  void bigWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  File docFile(CreateHarness h) =>
      File('${h.projectsDir.path}/Demo/LivingScroll.json');

  Map<String, dynamic> readDoc(CreateHarness h) =>
      jsonDecode(docFile(h).readAsStringSync()) as Map<String, dynamic>;

  Future<CreateHarness> start(WidgetTester tester) async {
    final harness = CreateHarness();
    await harness.setUp();
    addTearDown(harness.tearDown);
    bigWindow(tester);
    final dir = Directory('${harness.projectsDir.path}/Demo');
    await dir.create(recursive: true);
    await docFile(harness).writeAsString(
      jsonEncode({
        'metadata': {
          'name': 'Demo',
          'system': 'basic',
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
        'npcs': [],
        'scenes': [],
      }),
    );
    harness.coverPath = CreateHarness.asset('cover_sample.jpg');
    await harness.pumpApp(tester);
    await tester.tap(byKey('nav.create'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('adventure.tile.Demo'));
    await tester.pumpAndSettle();
    expect(byKey('game.root'), findsOne);
    return harness;
  }

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.tap(byKey(k));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String k, String text) async {
    await tester.enterText(byKey(k), text);
    await tester.pumpAndSettle();
  }

  // Scenes (the start section): a new scene with a typed name.
  Future<void> dirtyScene(WidgetTester tester) async {
    await tapKey(tester, 'scene.new');
    await type(tester, 'game.scenes.edit.field.name', 'Cave');
  }

  /// Home in the game rail; returns whether we landed on the app's Home view.
  bool onHomeView() =>
      byKey('game.root').evaluate().isEmpty &&
      byKey('home.root').evaluate().isNotEmpty;

  testWidgets('STEP 1-2: dirty scene form + Home -> unsaved prompt', (
    tester,
  ) async {
    final h = await start(tester);
    final before = docFile(h).readAsStringSync();
    await dirtyScene(tester);

    await tapKey(tester, 'nav.game.home');
    expect(byKey('settings.unsaved.dialog'), findsOne);
    expect(byKey('settings.unsaved.save'), findsOne);
    expect(byKey('settings.unsaved.abandon'), findsOne);
    expect(byKey('settings.unsaved.cancel'), findsOne);
    expect(byKey('game.root'), findsOne); // navigation suspended
    expect(docFile(h).readAsStringSync(), before);
  });

  testWidgets('BRANCH scene_save: Save writes the scene, then goes Home', (
    tester,
  ) async {
    final h = await start(tester);
    await dirtyScene(tester);
    await tapKey(tester, 'nav.game.home');
    await tapKey(tester, 'settings.unsaved.save');

    expect(onHomeView(), isTrue);
    await waitForDisk(
      tester,
      () => (readDoc(h)['scenes'] as List).single['name'] == 'Cave',
    );
  });

  testWidgets('BRANCH scene_abandon: Abandon goes Home, nothing written', (
    tester,
  ) async {
    final h = await start(tester);
    final before = docFile(h).readAsStringSync();
    await dirtyScene(tester);
    await tapKey(tester, 'nav.game.home');
    await tapKey(tester, 'settings.unsaved.abandon');

    expect(onHomeView(), isTrue);
    expect(docFile(h).readAsStringSync(), before);
  });

  testWidgets('BRANCH scene_cancel: Cancel stays on the form, input intact', (
    tester,
  ) async {
    final h = await start(tester);
    final before = docFile(h).readAsStringSync();
    await dirtyScene(tester);
    await tapKey(tester, 'nav.game.home');
    await tapKey(tester, 'settings.unsaved.cancel');

    expect(byKey('settings.unsaved.dialog'), findsNothing);
    expect(byKey('game.root'), findsOne);
    expect(
      tester
          .widget<TextField>(byKey('game.scenes.edit.field.name'))
          .controller!
          .text,
      'Cave',
    );
    expect(docFile(h).readAsStringSync(), before);
  });

  testWidgets('BRANCH pristine: an untouched new scene goes Home, no prompt', (
    tester,
  ) async {
    final h = await start(tester);
    final before = docFile(h).readAsStringSync();
    await tapKey(tester, 'scene.new');
    await tapKey(tester, 'nav.game.home');

    expect(byKey('settings.unsaved.dialog'), findsNothing);
    expect(onHomeView(), isTrue);
    expect(docFile(h).readAsStringSync(), before);
  });

  // Every other editable section: dirty form + Home -> prompt; Abandon goes
  // Home writing nothing.
  final sections = <String, Future<void> Function(WidgetTester)>{
    'settings': (t) async {
      await tapKey(t, 'nav.game.settings');
      await type(t, 'game.settings.field.title', 'Demo Edited');
    },
    'npcs': (t) async {
      await tapKey(t, 'nav.game.npcs');
      await tapKey(t, 'game.npc.add');
      await type(t, 'npc_basicrpg.field.name', 'Orc');
    },
    'notes': (t) async {
      await tapKey(t, 'nav.game.notes');
      await tapKey(t, 'note.new');
      await type(t, 'game.notes.edit.field.name', 'Hook');
    },
    'keyevents': (t) async {
      await tapKey(t, 'nav.game.keyevents');
      await tapKey(t, 'event.new');
      await type(t, 'game.keyevents.edit.field.name', 'Found the map');
    },
    'images': (t) async {
      await tapKey(t, 'nav.game.images');
      await tapKey(t, 'image.new');
      await tapKey(t, 'game.images.edit.image');
    },
    'paths': (t) async {
      await tapKey(t, 'nav.game.paths');
      await tapKey(t, 'path.tile.green');
      await type(t, 'game.paths.edit.field.name', 'Forest');
    },
  };

  for (final entry in sections.entries) {
    testWidgets('BRANCH ${entry.key}_home: dirty form + Home -> prompt; '
        'Abandon goes Home, nothing written', (tester) async {
      final h = await start(tester);
      final before = docFile(h).readAsStringSync();
      await entry.value(tester);

      await tapKey(tester, 'nav.game.home');
      expect(byKey('settings.unsaved.dialog'), findsOne);
      expect(byKey('game.root'), findsOne);

      await tapKey(tester, 'settings.unsaved.abandon');
      expect(onHomeView(), isTrue);
      expect(docFile(h).readAsStringSync(), before);
    });
  }
}
