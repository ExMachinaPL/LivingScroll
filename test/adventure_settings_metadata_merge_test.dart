import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:living_scroll/create/projects_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Regression coverage: `ProjectsStore.update()` (the Adventure settings
/// Save) must MERGE the form-owned metadata fields (name/system/version/
/// author/description/language/content_warnings/license) into the existing
/// `metadata` object rather than replacing it wholesale — any OTHER metadata
/// field already on disk (e.g. the optional series pair, CLAUDE.md "Series" /
/// SPECS/Schema.md `series_member`/`series_uuid`) must survive a settings
/// Save untouched. Every other top-level collection must also be preserved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = ProjectsStore();
  late Directory support;
  PathProviderPlatform? previous;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('ls_metadata_merge_test');
    previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(support.path);
  });

  tearDown(() async {
    if (previous != null) PathProviderPlatform.instance = previous!;
    if (support.existsSync()) await support.delete(recursive: true);
  });

  Future<Directory> seedProject(
    String slug,
    Map<String, dynamic> metadata,
  ) async {
    final dir = Directory('${support.path}/Projects/$slug');
    await dir.create(recursive: true);
    await File('${dir.path}/LivingScroll.json').writeAsString(
      jsonEncode({'metadata': metadata, 'scenes': const []}),
    );
    return dir;
  }

  Map<String, dynamic> readMetadata(String slug) {
    final f = File('${support.path}/Projects/$slug/LivingScroll.json');
    final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return doc['metadata'] as Map<String, dynamic>;
  }

  test(
    'a field the settings form does not own (series_member/series_uuid) '
    'survives a settings Save',
    () async {
      await seedProject('demo', {
        'name': 'Demo',
        'system': 'basic',
        'version': '1.0.0',
        'author': 'A',
        'description': 'd',
        'language': 'en',
        'content_warnings': '',
        'license': '',
        'series_member': true,
        'series_uuid': 'a1b2c3d4-0000-4000-8000-000000000000',
      });

      await store.update(
        slug: 'demo',
        metadata: {
          'name': 'Demo Renamed',
          'system': 'basic',
          'version': '1.0.1',
          'author': 'A',
          'description': 'updated',
          'language': 'en',
          'content_warnings': '',
          'license': '',
        },
      );

      final metadata = readMetadata('demo');
      expect(metadata['name'], 'Demo Renamed');
      expect(metadata['version'], '1.0.1');
      expect(metadata['description'], 'updated');
      expect(metadata['series_member'], true);
      expect(
        metadata['series_uuid'],
        'a1b2c3d4-0000-4000-8000-000000000000',
      );
    },
  );

  test('every other top-level collection is preserved on update', () async {
    final dir = await seedProject('demo', {
      'name': 'Demo',
      'system': 'basic',
      'version': '1.0.0',
      'author': '',
      'description': '',
      'language': '',
      'content_warnings': '',
      'license': '',
    });
    final f = File('${dir.path}/LivingScroll.json');
    final doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    doc['npcs'] = [
      {'npc_uuid': 'n1'},
    ];
    await f.writeAsString(jsonEncode(doc));

    await store.update(
      slug: 'demo',
      metadata: {
        'name': 'Demo',
        'system': 'basic',
        'version': '1.0.0',
        'author': '',
        'description': '',
        'language': '',
        'content_warnings': '',
        'license': '',
      },
    );

    final updated =
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    expect(updated['npcs'], [
      {'npc_uuid': 'n1'},
    ]);
  });

  test('a document with no prior metadata still writes the form fields', () async {
    final dir = Directory('${support.path}/Projects/fresh');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/LivingScroll.json',
    ).writeAsString(jsonEncode({'scenes': const []}));

    await store.update(
      slug: 'fresh',
      metadata: {
        'name': 'Fresh',
        'system': 'basic',
        'version': '',
        'author': '',
        'description': '',
        'language': '',
        'content_warnings': '',
        'license': '',
      },
    );

    expect(readMetadata('fresh')['name'], 'Fresh');
  });
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._support);

  final String _support;

  @override
  Future<String?> getApplicationSupportPath() async => _support;
}
