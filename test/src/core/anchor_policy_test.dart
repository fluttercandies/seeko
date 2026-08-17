import 'package:flutter_test/flutter_test.dart';
import 'package:seeko/seeko.dart';

void main() {
  test('anchor policies expose deterministic value semantics', () {
    expect(const AnchorPolicy.none(), const AnchorPolicy.none());
    expect(
      const AnchorPolicy.firstVisible(),
      const AnchorPolicy.firstVisible(),
    );
    expect(const AnchorPolicy.nearest(), const AnchorPolicy.nearest());
    expect(AnchorPolicy.explicitKey('message-42').key, 'message-42');
    expect(AnchorPolicy.trailingEdge().followThreshold, 80);
  });

  test('trailing edge threshold must be finite and non-negative', () {
    expect(
      () => AnchorPolicy.trailingEdge(followThreshold: -1),
      throwsRangeError,
    );
    expect(
      () => AnchorPolicy.trailingEdge(followThreshold: double.infinity),
      throwsArgumentError,
    );
  });
}
