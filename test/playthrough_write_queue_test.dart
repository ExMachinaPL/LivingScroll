import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:living_scroll/create/projects_store.dart';
import 'package:living_scroll/l10n/app_localizations.dart';
import 'package:living_scroll/screens/play_screen.dart';
import 'package:living_scroll/screens/playthrough_screen.dart';
import 'package:living_scroll/settings/settings_overrides.dart';
import 'package:living_scroll/settings/settings_scope.dart';

/// An in-memory save whose writes are SLOW read-modify-writes: each one reads
/// the "disk" document, waits [latency], then writes its modified copy back —
/// exactly the shape of `ProjectsStore.commitSaveProgress`. Two such writes
/// running at the same time lose one update (the later write is based on a
/// stale read), which is the CI race this test pins.
class _SlowSaveStore implements ProjectsStore {
  _SlowSaveStore(this.disk);

  static const latency = Duration(milliseconds: 100);

  Map<String, dynamic> disk;
  final List<String> history = [];

  /// What `finishSave` archived (null until the save is finished).
  Map<String, dynamic>? finishedDoc;
  List<String>? finishedHistory;

  Map<String, dynamic> _copy(Map<String, dynamic> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  @override
  Future<Map<String, dynamic>?> readSave(String saveName) async => _copy(disk);

  @override
  Future<List<String>> readSavePlayers(String saveName) async => const [];

  @override
  Future<Map<String, dynamic>?> readPartyState(String saveName) async => null;

  @override
  Future<String> savePath(String saveName) async => '/nowhere';

  @override
  Future<void> commitSaveProgress(
    String saveName, {
    required Set<String> checkedKeyEvents,
    required String visitedSceneUuid,
    Set<String> inactiveNpcUuids = const {},
    Set<String> seenNoteUuids = const {},
    Set<String> seenImageUuids = const {},
  }) async {
    final doc = _copy(disk); // read
    await Future<void>.delayed(latency);
    for (final s in doc['scenes'] as List) {
      if (s is Map && s['scene_uuid'] == visitedSceneUuid) s['visited'] = true;
    }
    disk = doc; // write
  }

  @override
  Future<void> appendSaveHistory(
    String saveName,
    String sceneUuid, {
    List<String>? availablePcNames,
    List<String>? availableNpcUuids,
    List<String>? availableKeyEventUuids,
    List<String>? availableImageUuids,
    List<String>? availableNoteUuids,
    List<String>? availableGmNoteUuids,
  }) async {
    final h = [...history];
    await Future<void>.delayed(latency);
    history
      ..clear()
      ..addAll([...h, sceneUuid]);
  }

  @override
  Future<void> writePartyState(
    String saveName,
    Map<String, dynamic> json,
  ) async {
    await Future<void>.delayed(latency);
  }

  @override
  Future<String?> finishSave(String saveName) async {
    finishedDoc = _copy(disk);
    finishedHistory = [...history];
    return 'archived';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'Finish right after following a next scene keeps BOTH commits '
    '(save writes are serialized)',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final store = _SlowSaveStore({
        'metadata': {'name': 'Pack', 'system': 'basic'},
        'key_events': [],
        'notes': [],
        'images': [],
        'npcs': [],
        'gm_notes': [],
        'paths': [],
        'scenes': [
          {
            'scene_uuid': 's1',
            'name': 'Opening',
            'description': 'It begins.',
            'scene_type': 'start',
            'next_scenes': ['s2'],
          },
          {
            'scene_uuid': 's2',
            'name': 'Finale',
            'description': 'The end.',
            'scene_type': 'end',
          },
        ],
      });
      var home = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: SettingsScope(
            overrides: const SettingsOverrides(),
            onChanged: (_) async {},
            child: PlaythroughScreen(
              saveName: 'Pack-1.0.0-Team A',
              startSceneUuid: 's1',
              mode: PlayMode.gameplay,
              store: store,
              onHome: () => home++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(); // load + the start scene's history entry

      // Follow the next scene and hit Finish WITHOUT letting the navigation's
      // (slow) commit finish first.
      await tester.tap(find.byKey(const ValueKey('play.nextscene.Finale')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('play.finish')));
      await tester.pump();

      // Let every queued write run to completion.
      for (var i = 0; i < 20 && store.finishedDoc == null; i++) {
        await tester.pump(_SlowSaveStore.latency);
      }
      await tester.pumpAndSettle();

      expect(store.finishedDoc, isNotNull, reason: 'the save was archived');
      Map sceneOf(String uuid) => (store.finishedDoc!['scenes'] as List)
          .cast<Map>()
          .firstWhere((s) => s['scene_uuid'] == uuid);
      // The navigation's commit (s1 left -> visited) was NOT overwritten by
      // Finish's commit (s2 -> visited), and both landed BEFORE the move.
      expect(sceneOf('s1')['visited'], isTrue);
      expect(sceneOf('s2')['visited'], isTrue);
      expect(store.finishedHistory, ['s1', 's2']);
      expect(home, 1);
    },
  );
}
