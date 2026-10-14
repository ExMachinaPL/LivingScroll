// Integration test for NAVIGATIONS/app_close_unsaved_changes: closing the
// application window (desktop) and the system back action (Android back button /
// gesture) are guarded by the SAME isDirty prompts as the navigation rail — the
// game editor's sections, the create-for-scene sub-forms, the Settings form and
// the new-adventure form. The window's close is held natively
// (window_manager setPreventClose) and routed to LivingScrollApp.onWindowClose;
// the test drives that handler directly and observes the injected closer.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:living_scroll/main.dart';
import 'package:window_manager/window_manager.dart';

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

  Future<void> tapKey(WidgetTester tester, String k) async {
    await tester.tap(byKey(k));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String k, String text) async {
    await tester.enterText(byKey(k), text);
    await tester.pumpAndSettle();
  }

  Future<CreateHarness> startApp(WidgetTester tester) async {
    final harness = CreateHarness();
    await harness.setUp();
    addTearDown(harness.tearDown);
    bigWindow(tester);
    await Directory('${harness.projectsDir.path}/Demo').create(recursive: true);
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
    await harness.pumpApp(tester);
    return harness;
  }

  Future<CreateHarness> startGame(WidgetTester tester) async {
    final h = await startApp(tester);
    await tapKey(tester, 'nav.create');
    await tapKey(tester, 'adventure.tile.Demo');
    expect(byKey('game.root'), findsOne);
    return h;
  }

  Future<void> dirtyScene(WidgetTester tester) async {
    await tapKey(tester, 'scene.new');
    await type(tester, 'game.scenes.edit.field.name', 'Cave');
  }

  // Scene editor -> Notes picker -> "new note" sub-form -> typed note name.
  Future<void> dirtyNoteSubForm(WidgetTester tester) async {
    await tapKey(tester, 'game.scenes.edit.notes.add');
    expect(byKey('scene.notes.select.root'), findsOne);
    await tapKey(tester, 'scene.notes.select.new');
    await type(tester, 'game.notes.edit.field.name', 'Hook');
  }

  /// The desktop window's close button (held by setPreventClose).
  Future<void> closeWindow(WidgetTester tester) async {
    final app = tester.state(find.byType(LivingScrollApp)) as WindowListener;
    app.onWindowClose();
    await tester.pumpAndSettle();
  }

  /// The Android system back (button / gesture).
  Future<void> systemBack(WidgetTester tester) async {
    // ignore: invalid_use_of_protected_member
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  // ---- Window close --------------------------------------------------------

  testWidgets('STEP 1: window close with nothing dirty closes at once', (
    tester,
  ) async {
    final h = await startGame(tester);
    await tapKey(tester, 'scene.new'); // pristine form
    await closeWindow(tester);
    expect(byKey('settings.unsaved.dialog'), findsNothing);
    expect(h.windowCloseCount, 1);
  });

  testWidgets(
    'STEP 2: window close with a dirty scene -> prompt; Cancel stays',
    (tester) async {
      final h = await startGame(tester);
      final before = docFile(h).readAsStringSync();
      await dirtyScene(tester);

      await closeWindow(tester);
      expect(byKey('settings.unsaved.dialog'), findsOne);
      expect(h.windowCloseCount, 0); // held until a choice is made

      await tapKey(tester, 'settings.unsaved.cancel');
      expect(h.windowCloseCount, 0);
      expect(byKey('game.scenes.edit.field.name'), findsOne);
      expect(docFile(h).readAsStringSync(), before);
    },
  );

  testWidgets('BRANCH close_save: Save writes the scene, then closes', (
    tester,
  ) async {
    final h = await startGame(tester);
    await dirtyScene(tester);
    await closeWindow(tester);
    await tapKey(tester, 'settings.unsaved.save');

    expect(h.windowCloseCount, 1);
    await waitForDisk(
      tester,
      () => (readDoc(h)['scenes'] as List).single['name'] == 'Cave',
    );
  });

  testWidgets('BRANCH close_abandon: Abandon closes, nothing written', (
    tester,
  ) async {
    final h = await startGame(tester);
    final before = docFile(h).readAsStringSync();
    await dirtyScene(tester);
    await closeWindow(tester);
    await tapKey(tester, 'settings.unsaved.abandon');

    expect(h.windowCloseCount, 1);
    expect(docFile(h).readAsStringSync(), before);
  });

  testWidgets('BRANCH close_subform: a dirty sub-form asks FIRST, then the '
      'dirty scene editor; Cancel on either keeps the app open', (
    tester,
  ) async {
    final h = await startGame(tester);
    final before = docFile(h).readAsStringSync();
    await dirtyScene(tester);
    await dirtyNoteSubForm(tester);

    await closeWindow(tester);
    // 1st prompt: the note sub-form (topmost). Abandon drops the note draft.
    expect(byKey('settings.unsaved.dialog'), findsOne);
    await tapKey(tester, 'settings.unsaved.abandon');
    // 2nd prompt: the scene editor below it. Cancel -> stay, no close.
    expect(byKey('settings.unsaved.dialog'), findsOne);
    await tapKey(tester, 'settings.unsaved.cancel');

    expect(h.windowCloseCount, 0);
    expect(
      byKey('game.notes.edit.field.name'),
      findsNothing,
    ); // sub-form closed
    expect(docFile(h).readAsStringSync(), before);
  });

  testWidgets('BRANCH close_settings: dirty app Settings -> prompt', (
    tester,
  ) async {
    final h = await startApp(tester);
    await tapKey(tester, 'nav.settings');
    await tapKey(tester, 'settings.mode.dark');

    await closeWindow(tester);
    expect(byKey('settings.unsaved.dialog'), findsOne);
    await tapKey(tester, 'settings.unsaved.cancel');
    expect(h.windowCloseCount, 0);

    await closeWindow(tester);
    await tapKey(tester, 'settings.unsaved.abandon');
    expect(h.windowCloseCount, 1);
  });

  testWidgets('BRANCH close_create_new: dirty new-adventure form -> the '
      'two-choice prompt; Abandon closes, nothing created', (tester) async {
    final h = await startApp(tester);
    await tapKey(tester, 'nav.create');
    await tapKey(tester, 'create.new');
    await type(tester, 'create_new.field.title', 'TEST');

    await closeWindow(tester);
    expect(byKey('create_new.unsaved.dialog'), findsOne);
    await tapKey(tester, 'create_new.unsaved.abandon');

    expect(h.windowCloseCount, 1);
    expect(h.projects().map((d) => d.path.split('/').last).toList(), ['Demo']);
  });

  // ---- System back (Android) ----------------------------------------------

  testWidgets('BRANCH back_dirty_scene: back -> prompt; Cancel stays, Abandon '
      'leaves the editor', (tester) async {
    final h = await startGame(tester);
    final before = docFile(h).readAsStringSync();
    await dirtyScene(tester);

    await systemBack(tester);
    expect(byKey('settings.unsaved.dialog'), findsOne);
    await tapKey(tester, 'settings.unsaved.cancel');
    expect(byKey('game.scenes.edit.field.name'), findsOne);

    await systemBack(tester);
    await tapKey(tester, 'settings.unsaved.abandon');
    expect(byKey('game.root'), findsNothing);
    expect(byKey('create.grid'), findsOne); // back where the editor was opened
    expect(docFile(h).readAsStringSync(), before);
  });

  testWidgets(
    'BRANCH back_pristine: back on a pristine editor leaves at once',
    (tester) async {
      await startGame(tester);
      await tapKey(tester, 'scene.new');
      await systemBack(tester);
      expect(byKey('settings.unsaved.dialog'), findsNothing);
      expect(byKey('game.root'), findsNothing);
    },
  );

  testWidgets('BRANCH back_subform: back on a dirty sub-form -> prompt; '
      'Abandon returns to the picker, the scene editor stays dirty', (
    tester,
  ) async {
    final h = await startGame(tester);
    final before = docFile(h).readAsStringSync();
    await dirtyScene(tester);
    await dirtyNoteSubForm(tester);

    await systemBack(tester);
    expect(byKey('settings.unsaved.dialog'), findsOne);
    await tapKey(tester, 'settings.unsaved.abandon');

    expect(byKey('game.notes.edit.field.name'), findsNothing);
    expect(byKey('scene.notes.select.root'), findsOne);
    expect(docFile(h).readAsStringSync(), before);
  });

  testWidgets('BRANCH back_subform_save: Save on the sub-form prompt writes '
      'the note and returns to the picker', (tester) async {
    final h = await startGame(tester);
    await dirtyScene(tester);
    await dirtyNoteSubForm(tester);

    await systemBack(tester);
    await tapKey(tester, 'settings.unsaved.save');

    expect(byKey('scene.notes.select.root'), findsOne);
    await waitForDisk(
      tester,
      () => (readDoc(h)['notes'] as List).single['note_name'] == 'Hook',
    );
  });

  testWidgets('BRANCH back_create_new: back on a dirty new-adventure form -> '
      'two-choice prompt; Cancel stays', (tester) async {
    await startApp(tester);
    await tapKey(tester, 'nav.create');
    await tapKey(tester, 'create.new');
    await type(tester, 'create_new.field.title', 'TEST');

    await systemBack(tester);
    expect(byKey('create_new.unsaved.dialog'), findsOne);
    await tapKey(tester, 'create_new.unsaved.cancel');
    expect(byKey('create_new.field.title'), findsOne);
  });

  testWidgets('BRANCH back_settings: back on dirty app Settings -> prompt', (
    tester,
  ) async {
    await startApp(tester);
    await tapKey(tester, 'nav.settings');
    await tapKey(tester, 'settings.mode.dark');

    await systemBack(tester);
    expect(byKey('settings.unsaved.dialog'), findsOne);
    await tapKey(tester, 'settings.unsaved.cancel');
    expect(byKey('settings.mode.dark'), findsOne);
  });
}
