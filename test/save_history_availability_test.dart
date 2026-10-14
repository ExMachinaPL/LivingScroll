import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:living_scroll/create/projects_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Unit coverage for `history.json`'s per-scene availability snapshot
/// (SPECS/Schema.md::history.json): `appendSaveHistory` writes, alongside each
/// visited `scene_uuid`, WHICH PCs were present (`available_pc_names`) and
/// which of the scene's NPCs/key events/images/notes
/// were ACTUALLY available (active / still-unchecked / visible) the moment
/// the entry was recorded, and which GM notes existed in the pool at that
/// point; `readSaveHistory`/`parseSaveHistory` read that shape back, and stay
/// backward-compatible with a LEGACY history (a flat list of bare
/// `scene_uuid` strings, or a current-shape entry missing one of the six
/// fields, written before that field existed). `appendGmNoteToLastHistoryEntry`
/// additionally grows the LAST entry's `available_gmnote_uuids` live, for a
/// note authored while its scene is still the current one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = ProjectsStore();
  late Directory support;
  PathProviderPlatform? previous;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('ls_history_test');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(support.path);
  });

  tearDown(() async {
    if (previous != null) PathProviderPlatform.instance = previous!;
    if (support.existsSync()) await support.delete(recursive: true);
  });

  Future<Directory> seedSave(String name) async {
    final dir = Directory('${support.path}/Saves/$name');
    await dir.create(recursive: true);
    return dir;
  }

  List<dynamic> readRawHistory(String saveName) {
    final f = File('${support.path}/Saves/$saveName/history.json');
    return jsonDecode(f.readAsStringSync()) as List<dynamic>;
  }

  group('appendSaveHistory', () {
    test('writes a scene_uuid plus its availability snapshot', () async {
      await seedSave('demo');
      await store.appendSaveHistory(
        'demo',
        's1',
        availableNpcUuids: ['n1'],
        availableKeyEventUuids: ['ke1', 'ke2'],
      );

      final raw = readRawHistory('demo');
      expect(raw, [
        {
          'scene_uuid': 's1',
          'available_npc_uuids': ['n1'],
          'available_key_event_uuids': ['ke1', 'ke2'],
        },
      ]);
    });

    test('an EMPTY snapshot (nothing available) is still recorded, not '
        'omitted', () async {
      await seedSave('demo');
      await store.appendSaveHistory(
        'demo',
        's1',
        availableNpcUuids: [],
        availableKeyEventUuids: [],
      );

      final raw = readRawHistory('demo');
      final entry = raw.single as Map;
      expect(entry['available_npc_uuids'], isEmpty);
      expect(entry['available_key_event_uuids'], isEmpty);
    });

    test('appends in order across multiple calls', () async {
      await seedSave('demo');
      await store.appendSaveHistory(
        'demo',
        's1',
        availableNpcUuids: ['n1'],
        availableKeyEventUuids: [],
      );
      await store.appendSaveHistory(
        'demo',
        's2',
        availableNpcUuids: [],
        availableKeyEventUuids: [],
      );

      final entries = await store.readSaveHistory('demo');
      expect(entries.map((e) => e.sceneUuid), ['s1', 's2']);
    });

    test(
      'also writes the pc-name/image/note/gm-note availability snapshot when given',
      () async {
        await seedSave('demo');
        await store.appendSaveHistory(
          'demo',
          's1',
          availablePcNames: ['Alice', 'Bob'],
          availableNpcUuids: ['n1'],
          availableKeyEventUuids: ['ke1'],
          availableImageUuids: ['i1'],
          availableNoteUuids: ['note1'],
          availableGmNoteUuids: ['g1'],
        );

        final raw = readRawHistory('demo');
        expect(raw, [
          {
            'scene_uuid': 's1',
            'available_pc_names': ['Alice', 'Bob'],
            'available_npc_uuids': ['n1'],
            'available_key_event_uuids': ['ke1'],
            'available_image_uuids': ['i1'],
            'available_note_uuids': ['note1'],
            'available_gmnote_uuids': ['g1'],
          },
        ]);
      },
    );

    test(
      'an EMPTY pc-names snapshot (no split, empty roster) is still recorded, '
      'not omitted',
      () async {
        await seedSave('demo');
        await store.appendSaveHistory('demo', 's1', availablePcNames: []);

        final raw = readRawHistory('demo');
        final entry = raw.single as Map;
        expect(entry['available_pc_names'], isEmpty);
      },
    );
  });

  group('readSaveHistory / parseSaveHistory', () {
    test('reads the current shape back with its snapshot lists', () async {
      await seedSave('demo');
      await store.appendSaveHistory(
        'demo',
        's1',
        availablePcNames: ['Alice', 'Bob'],
        availableNpcUuids: ['n1'],
        availableKeyEventUuids: ['ke1'],
      );

      final entries = await store.readSaveHistory('demo');
      expect(entries, hasLength(1));
      expect(entries.single.sceneUuid, 's1');
      expect(entries.single.availablePcNames, ['Alice', 'Bob']);
      expect(entries.single.availableNpcUuids, ['n1']);
      expect(entries.single.availableKeyEventUuids, ['ke1']);
    });

    test(
      'a LEGACY entry (bare scene_uuid string) decodes with null snapshot '
      'lists — the fallback cue for replay to use the FINAL document state',
      () async {
        final dir = await seedSave('legacy');
        await File(
          '${dir.path}/history.json',
        ).writeAsString(jsonEncode(['s1', 's2']));

        final entries = await store.readSaveHistory('legacy');
        expect(entries.map((e) => e.sceneUuid), ['s1', 's2']);
        for (final e in entries) {
          expect(e.availablePcNames, isNull);
          expect(e.availableNpcUuids, isNull);
          expect(e.availableKeyEventUuids, isNull);
          expect(e.availableImageUuids, isNull);
          expect(e.availableNoteUuids, isNull);
          expect(e.availableGmNoteUuids, isNull);
        }
      },
    );

    test(
      'a current-shape entry missing the pc-names/image/note/gm-note fields '
      '(recorded before they existed) decodes those four as null, '
      'independently of the npc/key-event fields it does carry',
      () async {
        final dir = await seedSave('partial');
        await File('${dir.path}/history.json').writeAsString(
          jsonEncode([
            {
              'scene_uuid': 's1',
              'available_npc_uuids': ['n1'],
              'available_key_event_uuids': [],
            },
          ]),
        );

        final entry = (await store.readSaveHistory('partial')).single;
        expect(entry.availablePcNames, isNull);
        expect(entry.availableNpcUuids, ['n1']);
        expect(entry.availableKeyEventUuids, isEmpty);
        expect(entry.availableImageUuids, isNull);
        expect(entry.availableNoteUuids, isNull);
        expect(entry.availableGmNoteUuids, isNull);
      },
    );

    test('a MIXED file (legacy + current entries) parses each independently', () async {
      final dir = await seedSave('mixed');
      await File('${dir.path}/history.json').writeAsString(
        jsonEncode([
          's1',
          {
            'scene_uuid': 's2',
            'available_pc_names': ['Alice'],
            'available_npc_uuids': <String>[],
            'available_key_event_uuids': ['ke1'],
          },
        ]),
      );

      final entries = await store.readSaveHistory('mixed');
      expect(entries, hasLength(2));
      expect(entries[0].sceneUuid, 's1');
      expect(entries[0].availablePcNames, isNull);
      expect(entries[0].availableNpcUuids, isNull);
      expect(entries[1].sceneUuid, 's2');
      expect(entries[1].availablePcNames, ['Alice']);
      expect(entries[1].availableNpcUuids, isEmpty);
      expect(entries[1].availableKeyEventUuids, ['ke1']);
    });

    test('an absent history.json reads as empty', () async {
      await seedSave('empty');
      expect(await store.readSaveHistory('empty'), isEmpty);
    });
  });

  group('appendGmNoteToLastHistoryEntry', () {
    test(
      'grows the LAST entry\'s available_gmnote_uuids in place, leaving '
      'earlier entries untouched',
      () async {
        await seedSave('demo');
        await store.appendSaveHistory(
          'demo',
          's1',
          availableGmNoteUuids: [],
        );
        await store.appendSaveHistory(
          'demo',
          's2',
          availableGmNoteUuids: ['g1'],
        );

        await store.appendGmNoteToLastHistoryEntry('demo', 'g2');

        final entries = await store.readSaveHistory('demo');
        expect(entries[0].sceneUuid, 's1');
        expect(entries[0].availableGmNoteUuids, isEmpty); // untouched
        expect(entries[1].sceneUuid, 's2');
        expect(entries[1].availableGmNoteUuids, ['g1', 'g2']); // grown
      },
    );

    test(
      'a note authored while its scene is still current shows in THAT scene\'s '
      'own entry, not only the next one — the exact regression reported: '
      'scene 1 must record its own gm note, scene 2 both',
      () async {
        await seedSave('demo');
        // Enter scene 1 (nothing exists yet).
        await store.appendSaveHistory('demo', 's1', availableGmNoteUuids: []);
        // A note authored WHILE STANDING on scene 1.
        await store.appendGmNoteToLastHistoryEntry('demo', 's1-note');
        // Move on to scene 2: its OWN entry seeds from the pool as it now
        // stands (the just-authored note is already in it).
        await store.appendSaveHistory(
          'demo',
          's2',
          availableGmNoteUuids: ['s1-note'],
        );
        await store.appendGmNoteToLastHistoryEntry('demo', 's2-note');

        final entries = await store.readSaveHistory('demo');
        expect(entries[0].availableGmNoteUuids, ['s1-note']);
        expect(entries[1].availableGmNoteUuids, ['s1-note', 's2-note']);
      },
    );

    test('never adds the same uuid twice to an entry', () async {
      await seedSave('demo');
      await store.appendSaveHistory('demo', 's1', availableGmNoteUuids: ['g1']);
      await store.appendGmNoteToLastHistoryEntry('demo', 'g1');

      final entry = (await store.readSaveHistory('demo')).single;
      expect(entry.availableGmNoteUuids, ['g1']);
    });

    test(
      'upgrades a LEGACY (bare-string) last entry to the current shape rather '
      'than dropping the note',
      () async {
        final dir = await seedSave('legacy');
        await File(
          '${dir.path}/history.json',
        ).writeAsString(jsonEncode(['s1']));

        await store.appendGmNoteToLastHistoryEntry('legacy', 'g1');

        final entry = (await store.readSaveHistory('legacy')).single;
        expect(entry.sceneUuid, 's1');
        expect(entry.availableGmNoteUuids, ['g1']);
      },
    );

    test('a missing history.json is a no-op (never crashes)', () async {
      await seedSave('empty');
      await store.appendGmNoteToLastHistoryEntry('empty', 'g1');
      expect(await store.readSaveHistory('empty'), isEmpty);
    });
  });

  group('readFinishedHistory', () {
    test('reads a finished session\'s history with its snapshot', () async {
      final dir = Directory('${support.path}/Finished/Fin1');
      await dir.create(recursive: true);
      await File('${dir.path}/history.json').writeAsString(
        jsonEncode([
          {
            'scene_uuid': 's1',
            'available_npc_uuids': ['n1'],
            'available_key_event_uuids': [],
          },
        ]),
      );

      final entries = await store.readFinishedHistory('Fin1');
      expect(entries.single.sceneUuid, 's1');
      expect(entries.single.availableNpcUuids, ['n1']);
      expect(entries.single.availableKeyEventUuids, isEmpty);
    });

    test('reads the image/note/gm-note snapshot too', () async {
      final dir = Directory('${support.path}/Finished/Fin2');
      await dir.create(recursive: true);
      await File('${dir.path}/history.json').writeAsString(
        jsonEncode([
          {
            'scene_uuid': 's1',
            'available_npc_uuids': [],
            'available_key_event_uuids': [],
            'available_image_uuids': ['i1'],
            'available_note_uuids': ['note1'],
            'available_gmnote_uuids': ['g1'],
          },
        ]),
      );

      final entry = (await store.readFinishedHistory('Fin2')).single;
      expect(entry.availableImageUuids, ['i1']);
      expect(entry.availableNoteUuids, ['note1']);
      expect(entry.availableGmNoteUuids, ['g1']);
    });

    test('reads the pc-names snapshot too', () async {
      final dir = Directory('${support.path}/Finished/Fin3');
      await dir.create(recursive: true);
      await File('${dir.path}/history.json').writeAsString(
        jsonEncode([
          {'scene_uuid': 's1', 'available_pc_names': ['Alice', 'Cara']},
        ]),
      );

      final entry = (await store.readFinishedHistory('Fin3')).single;
      expect(entry.availablePcNames, ['Alice', 'Cara']);
    });
  });

  group('readFinishedPlayers', () {
    test(
      'reads the players[] roster from the finished session\'s group.json',
      () async {
        final dir = Directory('${support.path}/Finished/Fin1');
        await dir.create(recursive: true);
        await File('${dir.path}/group.json').writeAsString(
          jsonEncode({
            'group': 'Team A',
            'players': ['Alice', 'Bob'],
          }),
        );

        expect(await store.readFinishedPlayers('Fin1'), ['Alice', 'Bob']);
      },
    );

    test('an absent group.json reads as an empty roster', () async {
      final dir = Directory('${support.path}/Finished/NoGroup');
      await dir.create(recursive: true);

      expect(await store.readFinishedPlayers('NoGroup'), isEmpty);
    });
  });
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._support);

  final String _support;

  @override
  Future<String?> getApplicationSupportPath() async => _support;
}
