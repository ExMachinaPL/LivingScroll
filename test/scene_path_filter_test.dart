import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:living_scroll/images/bg_images_controller.dart';
import 'package:living_scroll/images/images_controller.dart';
import 'package:living_scroll/keyevents/key_events_controller.dart';
import 'package:living_scroll/l10n/app_localizations.dart';
import 'package:living_scroll/notes/notes_controller.dart';
import 'package:living_scroll/npcs/npcs_controller.dart';
import 'package:living_scroll/scenes/scenes_controller.dart';
import 'package:living_scroll/screens/scenes_screen.dart';
import 'package:living_scroll/soundtracks/soundtracks_controller.dart';

/// Path-filter of the Scenes list (top bar, right of the search): a disc per USED
/// path + one empty disc. Selecting discs shows only scenes matching a selected
/// path colour, or — for the empty disc — scenes with NO path. Multiple selected
/// discs are OR-ed. No selection => all scenes.
void main() {
  Finder byId(String k) => find.byKey(ValueKey(k));

  // Three paths (Green is UNUSED); four scenes: s1 red, s2 blue, s3 red+blue,
  // s4 no path.
  Map<String, dynamic> doc() => {
        'paths': [
          {'name': 'Red path', 'color': 'red', 'description': 'd'},
          {'name': 'Blue path', 'color': 'blue', 'description': 'd'},
          {'name': 'Green path', 'color': 'green', 'description': 'd'}, // unused
        ],
        'scenes': [
          {'scene_uuid': 's1', 'name': 'One', 'scene_type': 'standard', 'path_names': ['Red path']},
          {'scene_uuid': 's2', 'name': 'Two', 'scene_type': 'standard', 'path_names': ['Blue path']},
          {'scene_uuid': 's3', 'name': 'Three', 'scene_type': 'standard', 'path_names': ['Red path', 'Blue path']},
          {'scene_uuid': 's4', 'name': 'Four', 'scene_type': 'standard'}, // no path
        ],
      };

  late ScenesController controller;

  Widget host({Future<void> Function()? onPersist}) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: ScenesScreen(
            controller: controller,
            onPersist: onPersist ?? () async {},
            onPreview: (_) {},
            npcs: NpcsController(),
            notes: NotesController(),
            keyEvents: KeyEventsController(),
            images: ImagesController(),
            soundtracks: SoundtracksController(),
            bgImages: BgImagesController(),
            npcsImagesPath: '/tmp/x/npcs',
            imagesOtherPath: '/tmp/x/other',
            bgImagesPath: '/tmp/x/bg',
          ),
        ),
      );

  void expectVisible(Set<String> uuids) {
    for (final u in ['s1', 's2', 's3', 's4']) {
      expect(byId('scene.tile.$u'),
          uuids.contains(u) ? findsOneWidget : findsNothing,
          reason: 'scene $u visibility');
    }
  }

  setUp(() {
    controller = ScenesController()..loadFrom(doc());
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
  }

  testWidgets('shows a disc per USED path + the empty disc; unused path has none',
      (tester) async {
    await pump(tester);
    expect(byId('scene.pathfilter.red'), findsOneWidget);
    expect(byId('scene.pathfilter.blue'), findsOneWidget);
    expect(byId('scene.pathfilter.none'), findsOneWidget);
    // Green path is defined but used by no scene -> no disc.
    expect(byId('scene.pathfilter.green'), findsNothing);
    // No selection -> every scene shows.
    expectVisible({'s1', 's2', 's3', 's4'});
  });

  testWidgets('selecting a path shows only matching scenes; OR across selections',
      (tester) async {
    await pump(tester);

    // Red -> scenes on the red path.
    await tester.tap(byId('scene.pathfilter.red'));
    await tester.pumpAndSettle();
    expectVisible({'s1', 's3'});

    // Red + Blue -> union (red OR blue).
    await tester.tap(byId('scene.pathfilter.blue'));
    await tester.pumpAndSettle();
    expectVisible({'s1', 's2', 's3'});

    // Deselect Red -> only blue.
    await tester.tap(byId('scene.pathfilter.red'));
    await tester.pumpAndSettle();
    expectVisible({'s2', 's3'});
  });

  testWidgets('the empty disc filters to scenes with NO path (OR-ed too)',
      (tester) async {
    await pump(tester);

    // Empty only -> only the no-path scene.
    await tester.tap(byId('scene.pathfilter.none'));
    await tester.pumpAndSettle();
    expectVisible({'s4'});

    // Empty + Blue -> no-path OR blue.
    await tester.tap(byId('scene.pathfilter.blue'));
    await tester.pumpAndSettle();
    expectVisible({'s2', 's3', 's4'});

    // Deselect all -> everything again.
    await tester.tap(byId('scene.pathfilter.none'));
    await tester.pumpAndSettle();
    await tester.tap(byId('scene.pathfilter.blue'));
    await tester.pumpAndSettle();
    expectVisible({'s1', 's2', 's3', 's4'});
  });

  testWidgets('path filter combines (AND) with the search query', (tester) async {
    await pump(tester);

    // "three" matches s3 (name "Three") only.
    await tester.enterText(byId('scene.search'), 'three');
    await tester.pumpAndSettle();
    expectVisible({'s3'});

    // + Red: s3 is on the red path -> still visible.
    await tester.tap(byId('scene.pathfilter.red'));
    await tester.pumpAndSettle();
    expectVisible({'s3'});

    // Search "one" + red path: s1 (red) matches -> only s1.
    await tester.enterText(byId('scene.search'), 'one');
    await tester.pumpAndSettle();
    expectVisible({'s1'});

    // Search "two" + red path: s2 is blue, not red -> nothing.
    await tester.enterText(byId('scene.search'), 'two');
    await tester.pumpAndSettle();
    expectVisible({});
  });

  testWidgets('an active path filter does NOT hide the reorder handles',
      (tester) async {
    await pump(tester);
    expect(byId('scene.tile.s1.reorder'), findsOneWidget);

    await tester.tap(byId('scene.pathfilter.red'));
    await tester.pumpAndSettle();
    // Filtered by path -> the shown tiles keep their drag handles.
    expect(byId('scene.tile.s1.reorder'), findsOneWidget);
    expect(byId('scene.tile.s3.reorder'), findsOneWidget);

    // Empty disc too.
    await tester.tap(byId('scene.pathfilter.red'));
    await tester.tap(byId('scene.pathfilter.none'));
    await tester.pumpAndSettle();
    expect(byId('scene.tile.s4.reorder'), findsOneWidget);
  });

  testWidgets('dragging within a path-filtered list reorders and persists',
      (tester) async {
    var persisted = 0;
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(onPersist: () async => persisted++));
    await tester.pumpAndSettle();

    // Red -> [s1, s3] shown; drag s1 below s3.
    await tester.tap(byId('scene.pathfilter.red'));
    await tester.pumpAndSettle();

    final start = tester.getCenter(byId('scene.tile.s1.reorder'));
    final gesture = await tester.startGesture(start);
    await tester.pump();
    for (var dy = 20.0; dy <= 180; dy += 20) {
      await gesture.moveTo(Offset(start.dx, start.dy + dy));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(persisted, greaterThan(0), reason: 'reorder must persist');
    // s1 lands right AFTER s3 in the full list; hidden s2/s4 keep their order.
    expect(controller.scenes.map((s) => s.uuid).toList(),
        ['s2', 's3', 's1', 's4']);
    // Still filtered + still reorderable.
    expectVisible({'s1', 's3'});
    expect(byId('scene.tile.s1.reorder'), findsOneWidget);
  });

  testWidgets('no paths defined -> the path filter is NOT shown',
      (tester) async {
    controller = ScenesController()
      ..loadFrom({
        'scenes': [
          {'scene_uuid': 's1', 'name': 'One', 'scene_type': 'standard'},
          {'scene_uuid': 's2', 'name': 'Two', 'scene_type': 'standard'},
        ],
      });
    await pump(tester);
    expect(byId('scene.pathfilter'), findsNothing);
    expect(byId('scene.pathfilter.none'), findsNothing);
    // The list is still reorderable.
    expect(byId('scene.tile.s1.reorder'), findsOneWidget);
    expect(byId('scene.tile.s2.reorder'), findsOneWidget);
  });

  testWidgets('the filter container has a FIXED width of 7 disc slots',
      (tester) async {
    await pump(tester);
    // 7 slots × 44px (36 disc + 8 gap) = 308, regardless of how many are used.
    expect(tester.getSize(byId('scene.pathfilter')).width, 7 * 44.0);
  });

  testWidgets('the disc list refreshes on rebuild: an unused path disc vanishes '
      'and its stale selection is dropped', (tester) async {
    await pump(tester);
    await tester.tap(byId('scene.pathfilter.red'));
    await tester.pumpAndSettle();
    expectVisible({'s1', 's3'});

    // Re-load with scenes where NO scene uses the red path (as if re-entering the
    // Scenes view after the graph changed) -> the red disc must disappear and the
    // stale red selection be pruned (so the list is no longer red-filtered).
    controller.loadFrom({
      'paths': [
        {'name': 'Blue path', 'color': 'blue', 'description': 'd'},
      ],
      'scenes': [
        {'scene_uuid': 's2', 'name': 'Two', 'scene_type': 'standard', 'path_names': ['Blue path']},
        {'scene_uuid': 's4', 'name': 'Four', 'scene_type': 'standard'},
      ],
    });
    await tester.pumpAndSettle();

    expect(byId('scene.pathfilter.red'), findsNothing);
    expect(byId('scene.pathfilter.blue'), findsOneWidget);
    // No red filter lingering -> both current scenes show.
    expect(byId('scene.tile.s2'), findsOneWidget);
    expect(byId('scene.tile.s4'), findsOneWidget);
  });
}
