import 'package:flutter/material.dart';

import 'src/motion_prototype_benchmark.dart';
import 'src/motion_prototype_environment.dart';

void main() {
  final MotionPrototypeLaunchConfiguration launch =
      MotionPrototypeLaunchConfiguration.fromCompileTimeEnvironment();
  runApp(SeekoMotionPrototypeApp(launch: launch));
}

final class SeekoMotionPrototypeApp extends StatelessWidget {
  const SeekoMotionPrototypeApp({required this.launch, super.key});

  final MotionPrototypeLaunchConfiguration launch;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: MotionPrototypeBenchmark(
        metadata: launch.metadata,
        repeats: launch.repeats,
        outputPath: launch.outputPath,
      ),
    );
  }
}
