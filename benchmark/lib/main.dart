import 'package:flutter/material.dart';

import 'src/benchmark_environment.dart';
import 'src/native_list_baseline.dart';

void main() {
  final BenchmarkLaunchConfiguration launch =
      BenchmarkLaunchConfiguration.fromCompileTimeEnvironment();
  runApp(SeekoBenchmarkApp(launch: launch));
}

class SeekoBenchmarkApp extends StatelessWidget {
  const SeekoBenchmarkApp({required this.launch, super.key});

  final BenchmarkLaunchConfiguration launch;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: NativeListBaselineBenchmark(
        metadata: launch.metadata,
        configuration: launch.configuration,
        outputPath: launch.outputPath,
      ),
    );
  }
}
