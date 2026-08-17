import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  group('ScrollTarget', () {
    test('accepts each valid target kind', () {
      expect(ScrollTarget.offset(12.5).pixels, 12.5);
      expect(ScrollTarget.index(3).index, 3);
      expect(ScrollTarget.key('message-7').key, 'message-7');
      expect(const ScrollTarget.edge(ScrollEdge.trailing).edge,
          ScrollEdge.trailing);
      expect(ScrollTarget.progress(0.25).value, 0.25);
      expect(ScrollTarget.custom('chapter').value, 'chapter');
    });

    test('rejects invalid numeric targets immediately', () {
      expect(() => ScrollTarget.offset(double.nan), throwsArgumentError);
      expect(() => ScrollTarget.offset(double.infinity), throwsArgumentError);
      expect(() => ScrollTarget.index(-1), throwsRangeError);
      expect(() => ScrollTarget.progress(-0.01), throwsRangeError);
      expect(() => ScrollTarget.progress(1.01), throwsRangeError);
    });

    test('uses structural identity for every persistent target kind', () {
      final ScrollTarget offset = ScrollTarget.offset(12.5);
      final ScrollTarget index = ScrollTarget.index(3);
      final ScrollTarget liveIndex = ScrollTarget.index(
        3,
        tracking: IndexTracking.liveSlot,
      );
      final ScrollTarget key = ScrollTarget.key('message-7');
      const ScrollTarget edge = ScrollTarget.edge(ScrollEdge.trailing);
      final ScrollTarget progress = ScrollTarget.progress(0.25);
      const ScrollTarget custom = ScrollTarget.custom('chapter');

      expect(offset, ScrollTarget.offset(12.5));
      expect(index, ScrollTarget.index(3));
      expect(index, isNot(liveIndex));
      expect(key, ScrollTarget.key('message-7'));
      expect(edge, const ScrollTarget.edge(ScrollEdge.trailing));
      expect(progress, ScrollTarget.progress(0.25));
      expect(custom, const ScrollTarget.custom('chapter'));
      expect(
        <int>{
          offset.hashCode,
          index.hashCode,
          key.hashCode,
          edge.hashCode,
          progress.hashCode,
          custom.hashCode,
        },
        hasLength(6),
      );
      expect(offset.index, isNull);
      expect(index.pixels, isNull);
      expect(key.context, isNull);
      expect(edge.value, isNull);
    });

    testWidgets('captures mounted contexts without retaining element globally',
        (WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext value) {
            context = value;
            return const SizedBox();
          },
        ),
      );
      expect(ScrollTarget.mounted(context).context, same(context));
    });
  });

  group('ScrollPlacement', () {
    test('exposes intuitive presets and exact anchors', () {
      expect(const ScrollPlacement.start().targetAnchor, 0);
      expect(const ScrollPlacement.center().viewportAnchor, 0.5);
      expect(const ScrollPlacement.end().targetAnchor, 1);
      expect(const ScrollPlacement.nearest().mode, ScrollPlacementMode.nearest);
      expect(const ScrollPlacement.visible().mode, ScrollPlacementMode.visible);
      expect(
        ScrollPlacement.exact(
          targetAnchor: 0.25,
          viewportAnchor: 0.75,
          offset: 8,
        ),
        ScrollPlacement.exact(
          targetAnchor: 0.25,
          viewportAnchor: 0.75,
          offset: 8,
        ),
      );
    });

    test('rejects invalid anchors and offsets', () {
      expect(
        () => ScrollPlacement.exact(
          targetAnchor: -0.1,
          viewportAnchor: 0.5,
        ),
        throwsRangeError,
      );
      expect(
        () => ScrollPlacement.exact(
          targetAnchor: 0.5,
          viewportAnchor: 1.1,
        ),
        throwsRangeError,
      );
      expect(
        () => ScrollPlacement.exact(
          targetAnchor: 0.5,
          viewportAnchor: 0.5,
          offset: double.nan,
        ),
        throwsArgumentError,
      );
    });
  });
}
