import 'dart:convert';

import 'package:flutter/material.dart';

import 'src/g6_core_benchmark.dart';

void main() {
  runApp(const _G6WebBenchmarkApp());
}

final class _G6WebBenchmarkApp extends StatefulWidget {
  const _G6WebBenchmarkApp();

  @override
  State<_G6WebBenchmarkApp> createState() => _G6WebBenchmarkAppState();
}

final class _G6WebBenchmarkAppState extends State<_G6WebBenchmarkApp> {
  String _result = 'Running G6 core benchmark...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final G6CoreBenchmarkResult result = runG6CoreBenchmark(
        warmUpIterations: 1000,
        measuredIterations: 10000,
        openItemCount: 10000,
      );
      if (mounted) {
        setState(() {
          _result = const JsonEncoder.withIndent('  ').convert(result.toJson());
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Seeko G6 Web Benchmark')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            _result,
            key: const Key('g6-web-benchmark-result'),
          ),
        ),
      ),
    );
  }
}
