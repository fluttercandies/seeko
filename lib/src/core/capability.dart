/// A driver feature represented as one bit in [ScrollCapabilities].
enum ScrollCapability {
  pixel(pixelBit),
  mountedTarget(mountedTargetBit),
  unmountedIndex(unmountedIndexBit),
  stableKey(stableKeyBit),
  visibleItems(visibleItemsBit),
  anchorPreservation(anchorPreservationBit),
  semanticSync(semanticSyncBit),
  dynamicExtentCorrection(dynamicExtentCorrectionBit),
  naturalSyncPhysics(naturalSyncPhysicsBit),
  twoDimensional(twoDimensionalBit),

  /// Basic pixels, metrics, and scrolling-state observation.
  ///
  /// Drivers may expose more precise activity phase and velocity separately;
  /// this bit alone does not promise either.
  observation(observationBit),
  singleWriter(singleWriterBit),
  programmaticResult(programmaticResultBit),
  strictSync(strictSyncBit),
  customTarget(customTargetBit);

  const ScrollCapability(this.bit);

  static const int pixelBit = 1 << 0;
  static const int mountedTargetBit = 1 << 1;
  static const int unmountedIndexBit = 1 << 2;
  static const int stableKeyBit = 1 << 3;
  static const int visibleItemsBit = 1 << 4;
  static const int anchorPreservationBit = 1 << 5;
  static const int semanticSyncBit = 1 << 6;
  static const int dynamicExtentCorrectionBit = 1 << 7;
  static const int naturalSyncPhysicsBit = 1 << 8;
  static const int twoDimensionalBit = 1 << 9;
  static const int observationBit = 1 << 10;
  static const int singleWriterBit = 1 << 11;
  static const int programmaticResultBit = 1 << 12;
  static const int strictSyncBit = 1 << 13;
  static const int customTargetBit = 1 << 14;

  final int bit;
}

/// An allocation-free immutable capability bitset.
final class ScrollCapabilities {
  const ScrollCapabilities(this.bits);

  static const ScrollCapabilities none = ScrollCapabilities(0);
  static const ScrollCapabilities pixel =
      ScrollCapabilities(ScrollCapability.pixelBit);

  final int bits;

  bool supports(ScrollCapability capability) => bits & capability.bit != 0;

  bool containsAll(ScrollCapabilities other) => bits & other.bits == other.bits;

  ScrollCapabilities operator |(ScrollCapabilities other) =>
      ScrollCapabilities(bits | other.bits);

  ScrollCapabilities operator &(ScrollCapabilities other) =>
      ScrollCapabilities(bits & other.bits);

  @override
  bool operator ==(Object other) =>
      other is ScrollCapabilities && other.bits == bits;

  @override
  int get hashCode => bits;
}
