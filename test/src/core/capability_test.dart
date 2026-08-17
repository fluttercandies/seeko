import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('capability sets compose without allocation-prone dynamic collections',
      () {
    const ScrollCapabilities pixel = ScrollCapabilities.pixel;
    const ScrollCapabilities semantic = ScrollCapabilities(
      ScrollCapability.unmountedIndexBit |
          ScrollCapability.stableKeyBit |
          ScrollCapability.semanticSyncBit,
    );
    final ScrollCapabilities combined = pixel | semantic;
    expect(combined.supports(ScrollCapability.pixel), isTrue);
    expect(combined.supports(ScrollCapability.stableKey), isTrue);
    expect(combined.supports(ScrollCapability.twoDimensional), isFalse);
    expect(combined.containsAll(pixel), isTrue);
  });

  test('strict sync is an independent capability bit', () {
    const ScrollCapabilities strict = ScrollCapabilities(
      ScrollCapability.strictSyncBit,
    );

    expect(strict.supports(ScrollCapability.strictSync), isTrue);
    expect(strict.supports(ScrollCapability.semanticSync), isFalse);
    expect(strict.supports(ScrollCapability.singleWriter), isFalse);
  });
}
