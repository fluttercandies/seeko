import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'benchmark_models.dart';

final class NativeListBaselineBenchmark extends StatefulWidget {
  const NativeListBaselineBenchmark({
    required this.metadata,
    required this.configuration,
    this.autorun = true,
    this.outputPath,
    this.exitOnComplete = true,
    super.key,
  });

  final BenchmarkQualificationMetadata metadata;
  final BenchmarkScenarioConfiguration configuration;
  final bool autorun;
  final String? outputPath;
  final bool exitOnComplete;

  @override
  State<NativeListBaselineBenchmark> createState() =>
      _NativeListBaselineBenchmarkState();
}

final class _NativeListBaselineBenchmarkState
    extends State<NativeListBaselineBenchmark> {
  final ScrollController _controller = ScrollController();
  final Stopwatch _runWatch = Stopwatch();
  final List<BenchmarkFrameSample> _samples = <BenchmarkFrameSample>[];
  final List<BenchmarkRunResult> _runs = <BenchmarkRunResult>[];
  Completer<void>? _runComplete;
  var _childBuilds = 0;
  var _currentRun = 0;
  var _recording = false;
  var _timingsRegistered = false;
  var _status = 'Ready';

  @override
  void initState() {
    super.initState();
    if (widget.autorun) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        unawaited(_execute());
      });
    }
  }

  @override
  void dispose() {
    if (_timingsRegistered) {
      SchedulerBinding.instance.removeTimingsCallback(_handleTimings);
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _execute() async {
    try {
      _validateRuntime();
      SchedulerBinding.instance.addTimingsCallback(_handleTimings);
      _timingsRegistered = true;
      _setStatus('Warm-up');
      await _warmUp();
      for (var run = 1; run <= widget.configuration.runCount; run += 1) {
        await _captureRun(run);
      }
      final BenchmarkQualificationResult result = BenchmarkQualificationResult(
        metadata: widget.metadata,
        configuration: widget.configuration,
        runs: _runs,
      );
      await _writeResult(result.toJson());
      _setStatus('Complete');
      await SchedulerBinding.instance.endOfFrame;
      if (widget.exitOnComplete) {
        exit(0);
      }
    } on Object catch (error, stackTrace) {
      await _writeFailure(error, stackTrace);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'seeko benchmark',
          context: ErrorDescription('while capturing the native baseline'),
        ),
      );
      if (mounted) {
        _setStatus('Failed: $error');
      }
      if (widget.exitOnComplete) {
        exit(1);
      }
    } finally {
      if (_timingsRegistered) {
        SchedulerBinding.instance.removeTimingsCallback(_handleTimings);
        _timingsRegistered = false;
      }
    }
  }

  void _validateRuntime() {
    final bool expectedMode = switch (widget.metadata.buildMode) {
      'profile' => kProfileMode,
      'release' => kReleaseMode,
      _ => false,
    };
    if (!expectedMode) {
      throw StateError(
        'Benchmark build mode ${widget.metadata.buildMode} does not match '
        'the running Flutter mode.',
      );
    }
    final double actualRefreshRate = View.of(context).display.refreshRate;
    if (!actualRefreshRate.isFinite || actualRefreshRate < 120) {
      throw StateError(
        'A 120 Hz display is required; Flutter reported '
        '$actualRefreshRate Hz.',
      );
    }
    if ((actualRefreshRate - widget.metadata.refreshRateHz).abs() > 0.5) {
      throw StateError(
        'Captured refresh rate ${widget.metadata.refreshRateHz} Hz does not '
        'match Flutter runtime rate $actualRefreshRate Hz.',
      );
    }
    if (widget.outputPath == null || widget.outputPath!.isEmpty) {
      throw StateError('An output path is required for an autorun benchmark.');
    }
    if (!_controller.hasClients || !_controller.position.hasContentDimensions) {
      throw StateError('The native ListView did not complete initial layout.');
    }
  }

  Future<void> _warmUp() async {
    _controller.jumpTo(0);
    await _controller.animateTo(
      _controller.position.maxScrollExtent,
      duration: widget.configuration.warmUp,
      curve: Curves.linear,
    );
    _controller.jumpTo(0);
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  Future<void> _captureRun(int run) async {
    _setStatus('Run $run / ${widget.configuration.runCount}');
    _controller.jumpTo(0);
    await SchedulerBinding.instance.endOfFrame;
    _samples.clear();
    _childBuilds = 0;
    _currentRun = run;
    _runComplete = Completer<void>();
    _runWatch
      ..reset()
      ..start();
    _recording = true;
    final Future<void> drive = _driveUntilRunCompletes();
    await _runComplete!.future;
    _recording = false;
    _runWatch.stop();
    _controller.jumpTo(_controller.offset);
    await drive;
    _runs.add(
      BenchmarkRunResult.fromSamples(
        run: run,
        elapsed: _runWatch.elapsed,
        childBuilds: _childBuilds,
        samples: List<BenchmarkFrameSample>.of(_samples),
      ),
    );
    await SchedulerBinding.instance.endOfFrame;
  }

  Future<void> _driveUntilRunCompletes() async {
    var targetTrailing = true;
    while (_recording) {
      await _controller.animateTo(
        targetTrailing ? _controller.position.maxScrollExtent : 0,
        duration: const Duration(seconds: 60),
        curve: Curves.linear,
      );
      targetTrailing = !targetTrailing;
    }
  }

  void _handleTimings(List<FrameTiming> timings) {
    if (!_recording) {
      return;
    }
    for (final FrameTiming timing in timings) {
      _samples.add(
        BenchmarkFrameSample(
          frameNumber: timing.frameNumber,
          buildMicros: timing.buildDuration.inMicroseconds,
          rasterMicros: timing.rasterDuration.inMicroseconds,
          totalMicros: timing.totalSpan.inMicroseconds,
          vsyncOverheadMicros: timing.vsyncOverhead.inMicroseconds,
          layerCacheCount: timing.layerCacheCount,
          layerCacheBytes: timing.layerCacheBytes,
          pictureCacheCount: timing.pictureCacheCount,
          pictureCacheBytes: timing.pictureCacheBytes,
        ),
      );
    }
    final Completer<void>? completion = _runComplete;
    if (completion != null &&
        !completion.isCompleted &&
        _samples.length >= widget.configuration.minimumPresentedFrames &&
        _runWatch.elapsed >= widget.configuration.minimumRunDuration) {
      completion.complete();
    }
  }

  void _recordChildBuild() {
    if (_recording) {
      _childBuilds += 1;
    }
  }

  Future<void> _writeResult(Map<String, Object?> value) async {
    final File output = File(widget.outputPath!);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(value)}\n',
      flush: true,
    );
  }

  Future<void> _writeFailure(Object error, StackTrace stackTrace) async {
    final String? outputPath = widget.outputPath;
    if (outputPath == null || outputPath.isEmpty) {
      return;
    }
    await _writeResult(<String, Object?>{
      'schemaVersion': 1,
      ...widget.metadata.toJson(),
      'configuration': widget.configuration.toJson(),
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
      'completedRuns': _runs
          .map((BenchmarkRunResult result) => result.toJson())
          .toList(growable: false),
    });
  }

  void _setStatus(String value) {
    if (!mounted) {
      return;
    }
    setState(() => _status = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF081522),
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 48,
            child: ColoredBox(
              color: const Color(0xFF102235),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Native ListView.builder baseline',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    Text(
                      '$_status · run $_currentRun',
                      style: const TextStyle(color: Color(0xFF9DB2C8)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              key: const Key('native-list-baseline-list'),
              controller: _controller,
              itemCount: widget.configuration.itemCount,
              itemExtent: widget.configuration.itemExtent,
              semanticChildCount: widget.configuration.itemCount,
              itemBuilder: (BuildContext context, int index) {
                _recordChildBuild();
                return _BaselineItem(index: index);
              },
            ),
          ),
        ],
      ),
    );
  }
}

final class _BaselineItem extends StatelessWidget {
  const _BaselineItem({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final bool alternate = index.isOdd;
    return ColoredBox(
      color: alternate ? const Color(0xFF0E2032) : const Color(0xFF10263A),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 6,
            child: ColoredBox(
              color: Color(0xFF5DE2C2 + (index % 4) * 0x00050500),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Item ${index.toString().padLeft(6, '0')}',
            style: const TextStyle(
              color: Color(0xFFE8F0F7),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
