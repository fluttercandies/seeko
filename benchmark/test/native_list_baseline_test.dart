import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seeko_benchmark/src/benchmark_models.dart';
import 'package:seeko_benchmark/src/native_list_baseline.dart';

void main() {
  testWidgets('native baseline uses a one-million item fixed-extent ListView', (
    WidgetTester tester,
  ) async {
    final BenchmarkScenarioConfiguration configuration =
        BenchmarkScenarioConfiguration(
      itemCount: 1000000,
      itemExtent: 56,
      warmUp: const Duration(seconds: 1),
      minimumRunDuration: const Duration(seconds: 1),
      minimumPresentedFrames: 1,
      runCount: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NativeListBaselineBenchmark(
          metadata: _metadata,
          configuration: configuration,
          autorun: false,
        ),
      ),
    );
    await tester.pump();

    final Finder scrollable = find.byKey(
      const Key('native-list-baseline-list'),
    );
    expect(scrollable, findsOneWidget);
    final ListView list = tester.widget<ListView>(scrollable);
    expect(list.itemExtent, 56);
    expect(list.semanticChildCount, 1000000);
    expect(find.text('Item 000000'), findsOneWidget);

    await tester.drag(scrollable, const Offset(0, -224));
    await tester.pumpAndSettle();
    expect(find.text('Item 000000'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

const BenchmarkQualificationMetadata _metadata = BenchmarkQualificationMetadata(
  device: 'test-device',
  operatingSystem: 'test-os',
  thermalState: 'nominal',
  powerState: 'AC',
  refreshRateHz: 120,
  flutterRevision: '1234567',
  engineRevision: '7654321',
  buildMode: 'profile',
  commit: 'test',
  seed: 24301,
  scenario: 'native-list-view-builder-fixed-extent',
);
