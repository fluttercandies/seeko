import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/motion_prototype_content.dart';
import 'package:seeko_benchmark/src/motion_prototype_models.dart';

void main() {
  for (final MotionExtentProfile profile in MotionExtentProfile.values) {
    test('$profile offset and index lookup are exact', () {
      final MotionPrototypeContent content = MotionPrototypeContent(profile);

      for (final int index in <int>[0, 1, 63, 64, 999, 500000, 999999]) {
        final double leading = content.offsetForIndex(index);
        expect(content.indexAtOffset(leading), index);
        expect(
          content.indexAtOffset(leading + content.extentForIndex(index) - 0.01),
          index,
        );
      }
    });
  }

  test('visible geometry covers viewport with bounded unique children', () {
    final MotionPrototypeContent content = MotionPrototypeContent(
      MotionExtentProfile.deterministicDynamic,
    );

    final List<MotionPrototypeItemGeometry> items = content.itemsCovering(
      content.offsetForIndex(500000) + 17,
      viewportExtent: 800,
      overscan: 160,
    );

    expect(items.first.leading, lessThanOrEqualTo(-160));
    expect(items.last.trailing, greaterThanOrEqualTo(960));
    expect(
        items.map((MotionPrototypeItemGeometry value) => value.index).toSet(),
        hasLength(items.length));
    expect(items.length, lessThan(40));
  });

  test('invalid content coordinates fail explicitly', () {
    final MotionPrototypeContent content = MotionPrototypeContent(
      MotionExtentProfile.fixed,
    );

    expect(() => content.offsetForIndex(-1), throwsRangeError);
    expect(() => content.indexAtOffset(-1), throwsRangeError);
    expect(
      () => content.itemsCovering(
        0,
        viewportExtent: double.nan,
        overscan: 0,
      ),
      throwsRangeError,
    );
  });
}
