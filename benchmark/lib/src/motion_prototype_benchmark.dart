import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'benchmark_models.dart';
import 'motion_prototype_capture.dart';
import 'motion_prototype_models.dart';
import 'motion_prototype_trajectory.dart';
import 'motion_prototype_viewport.dart';

final class MotionPrototypeBenchmark extends StatefulWidget {
  MotionPrototypeBenchmark({
    required this.metadata,
    required this.repeats,
    Iterable<MotionPrototypeCase>? cases,
    Iterable<MotionPrototypeCandidate> candidates =
        MotionPrototypeCandidate.values,
    this.outputPath,
    this.autorun = true,
    this.exitOnComplete = true,
    super.key,
  })  : cases = List<MotionPrototypeCase>.unmodifiable(
          cases ?? MotionPrototypeMatrix.standard(),
        ),
        candidates = List<MotionPrototypeCandidate>.unmodifiable(candidates) {
    if (this.cases.isEmpty) {
      throw ArgumentError.value(cases, 'cases', 'must not be empty');
    }
    if (this.candidates.isEmpty) {
      throw ArgumentError.value(
        candidates,
        'candidates',
        'must not be empty',
      );
    }
    RangeError.checkValueInInterval(repeats, 1, 5, 'repeats');
  }

  final BenchmarkQualificationMetadata metadata;
  final int repeats;
  final List<MotionPrototypeCase> cases;
  final List<MotionPrototypeCandidate> candidates;
  final String? outputPath;
  final bool autorun;
  final bool exitOnComplete;

  @override
  State<MotionPrototypeBenchmark> createState() =>
      _MotionPrototypeBenchmarkState();
}

final class _MotionPrototypeBenchmarkState
    extends State<MotionPrototypeBenchmark>
    with SingleTickerProviderStateMixin {
  final GlobalKey _viewportKey = GlobalKey();
  final List<BenchmarkFrameSample> _caseSamples = <BenchmarkFrameSample>[];
  late final Ticker _ticker;
  late MotionPrototypeCandidate _candidate;
  late MotionPrototypeCase _testCase;
  late MotionPrototypeTrace _trace;
  late MotionPrototypeFrame _frame;
  MotionPrototypeTrace? _playingTrace;
  Completer<void>? _playCompleter;
  var _frameIndex = 0;
  var _recording = false;
  var _timingsRegistered = false;
  var _childBuilds = 0;
  var _baselineRss = 0;
  var _peakMemoryBytes = 0;
  var _windowGeneration = 0;
  var _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _candidate = widget.candidates.first;
    _testCase = widget.cases.first;
    _trace = MotionPrototypeTrajectory.forCandidate(_candidate).trace(
      _testCase,
      viewportExtent: 800,
    );
    _frame = _trace.frames.first;
    _ticker = createTicker(_handleTick);
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
    _playCompleter?.completeError(
      StateError('Motion prototype benchmark detached during playback.'),
    );
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _execute() async {
    try {
      _validateRuntime();
      SchedulerBinding.instance.addTimingsCallback(_handleTimings);
      _timingsRegistered = true;
      _setStatus('Warm-up');
      await _warmUp();
      final List<MotionPrototypeEvaluationCapture> evaluations =
          <MotionPrototypeEvaluationCapture>[];
      for (final MotionPrototypeCandidate candidate in widget.candidates) {
        final List<MotionPrototypeCapture> captures =
            <MotionPrototypeCapture>[];
        for (final MotionPrototypeCase testCase in widget.cases) {
          for (var repeat = 1; repeat <= widget.repeats; repeat += 1) {
            _setStatus(
              '${candidate.name} · ${testCase.id} · '
              '$repeat/${widget.repeats}',
            );
            captures.add(
              await _captureCase(candidate, testCase),
            );
          }
        }
        evaluations.add(
          MotionPrototypeEvaluationCapture(
            candidate: candidate,
            captures: captures,
          ),
        );
      }
      final MotionPrototypeQualificationResult result =
          MotionPrototypeQualificationResult(
        metadata: widget.metadata,
        evaluations: evaluations,
        requiredBlindReviewers: 5,
        blindReviews: const <MotionPrototypeBlindReview>[],
      );
      await _writeJson(result.toJson());
      _setStatus(
        'Captured · winner ${result.winner.name} · blind review pending',
      );
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
          context: ErrorDescription(
            'while comparing long-distance motion prototypes',
          ),
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
        'Benchmark mode ${widget.metadata.buildMode} does not match runtime.',
      );
    }
    final double runtimeRefreshRate = View.of(context).display.refreshRate;
    if (!runtimeRefreshRate.isFinite || runtimeRefreshRate < 120) {
      throw StateError(
        'A 120 Hz display is required; Flutter reported '
        '$runtimeRefreshRate Hz.',
      );
    }
    if ((runtimeRefreshRate - widget.metadata.refreshRateHz).abs() > 0.5) {
      throw StateError(
        'Host refresh ${widget.metadata.refreshRateHz} Hz does not match '
        'Flutter runtime $runtimeRefreshRate Hz.',
      );
    }
    if (widget.outputPath == null || widget.outputPath!.isEmpty) {
      throw StateError('An output path is required for autorun.');
    }
    final Set<String> requiredCases = MotionPrototypeMatrix.standard()
        .map((MotionPrototypeCase value) => value.id)
        .toSet();
    final Set<String> actualCases =
        widget.cases.map((MotionPrototypeCase value) => value.id).toSet();
    if (requiredCases.length != actualCases.length ||
        !actualCases.containsAll(requiredCases)) {
      throw StateError('Autorun requires the complete frozen 120-case matrix.');
    }
    if (widget.candidates.length != MotionPrototypeCandidate.values.length ||
        !widget.candidates.toSet().containsAll(
              MotionPrototypeCandidate.values,
            )) {
      throw StateError('Autorun requires all three motion candidates.');
    }
    _viewportExtent();
  }

  Future<void> _warmUp() async {
    final MotionPrototypeCase warmUpCase = MotionPrototypeCase(
      distanceViewports: 100,
      extentProfile: MotionExtentProfile.deterministicDynamic,
      direction: MotionDirection.forward,
      refreshRateHz: 120,
      interruptAt: 0.5,
    );
    await _play(
      MotionPrototypeTrajectory.forCandidate(
        MotionPrototypeCandidate.virtualWindowRebase,
      ).trace(warmUpCase, viewportExtent: _viewportExtent()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<MotionPrototypeCapture> _captureCase(
    MotionPrototypeCandidate candidate,
    MotionPrototypeCase testCase,
  ) async {
    final MotionPrototypeTrajectory trajectory =
        MotionPrototypeTrajectory.forCandidate(candidate);
    final double viewportExtent = _viewportExtent();
    final MotionPrototypeTrace uninterrupted = trajectory.trace(
      testCase,
      viewportExtent: viewportExtent,
    );
    final MotionPrototypeTrace interrupted = trajectory.trace(
      testCase,
      viewportExtent: viewportExtent,
      interrupt: true,
    );
    _caseSamples.clear();
    _childBuilds = 0;
    _baselineRss = ProcessInfo.currentRss;
    _peakMemoryBytes = 0;
    _windowGeneration += 1;
    _recording = true;
    await _play(uninterrupted);
    await _play(interrupted);
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _sampleMemory();
    _recording = false;
    if (_caseSamples.isEmpty) {
      throw StateError(
          'No FrameTiming samples were captured for ${testCase.id}.');
    }
    return MotionPrototypeCapture(
      candidate: candidate,
      testCase: testCase,
      uninterrupted: uninterrupted,
      interrupted: interrupted,
      frameSamples: List<BenchmarkFrameSample>.of(_caseSamples),
      childBuilds: _childBuilds,
      peakMemoryBytes: _peakMemoryBytes,
    );
  }

  Future<void> _play(MotionPrototypeTrace trace) async {
    if (_ticker.isActive || _playCompleter != null) {
      throw StateError('A prototype trace is already playing.');
    }
    _candidate = trace.candidate;
    _testCase = trace.testCase;
    _trace = trace;
    _frameIndex = 0;
    _frame = trace.frames.first;
    _playingTrace = trace;
    _playCompleter = Completer<void>();
    if (mounted) {
      setState(() {});
    }
    await SchedulerBinding.instance.endOfFrame;
    unawaited(_ticker.start());
    await _playCompleter!.future;
    _playCompleter = null;
    _playingTrace = null;
    await SchedulerBinding.instance.endOfFrame;
  }

  void _handleTick(Duration elapsed) {
    final MotionPrototypeTrace? trace = _playingTrace;
    if (trace == null) {
      return;
    }
    var nextIndex = _frameIndex;
    while (nextIndex + 1 < trace.frames.length &&
        trace.frames[nextIndex + 1].elapsed <= elapsed) {
      nextIndex += 1;
    }
    if (nextIndex != _frameIndex) {
      _frameIndex = nextIndex;
      _frame = trace.frames[nextIndex];
      if (mounted) {
        setState(() {});
      }
    }
    _sampleMemory();
    if (_frameIndex == trace.frames.length - 1) {
      _ticker.stop();
      final Completer<void>? completion = _playCompleter;
      if (completion != null && !completion.isCompleted) {
        completion.complete();
      }
    }
  }

  void _handleTimings(List<FrameTiming> timings) {
    if (!_recording) {
      return;
    }
    for (final FrameTiming timing in timings) {
      _caseSamples.add(
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
    _sampleMemory();
  }

  void _sampleMemory() {
    if (!_recording) {
      return;
    }
    final int delta = ProcessInfo.currentRss - _baselineRss;
    if (delta > _peakMemoryBytes) {
      _peakMemoryBytes = delta;
    }
  }

  void _recordChildBuild() {
    if (_recording) {
      _childBuilds += 1;
    }
  }

  double _viewportExtent() {
    final RenderObject? renderObject =
        _viewportKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      throw StateError('Motion prototype viewport has not completed layout.');
    }
    final double extent = renderObject.size.height;
    if (!extent.isFinite || extent <= 0) {
      throw StateError('Motion prototype viewport extent is invalid: $extent.');
    }
    return extent;
  }

  Future<void> _writeJson(Map<String, Object?> value) async {
    final File output = File(widget.outputPath!);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(value)}\n',
      flush: true,
    );
  }

  Future<void> _writeFailure(Object error, StackTrace stackTrace) async {
    if (widget.outputPath == null || widget.outputPath!.isEmpty) {
      return;
    }
    await _writeJson(<String, Object?>{
      'schemaVersion': 1,
      'kind': 'motion-prototype-comparison',
      ...widget.metadata.toJson(),
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
  }

  void _setStatus(String value) {
    if (mounted) {
      setState(() => _status = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 52,
            child: ColoredBox(
              color: const Color(0xFF102235),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Seeko motion qualification',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Color(0xFFF8FAFC)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${_candidate.name} · ${_testCase.id} · $_status',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: Color(0xFF9DB2C8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: KeyedSubtree(
              key: const Key('motion-prototype-viewport'),
              child: MotionPrototypeViewport(
                key: _viewportKey,
                candidate: _candidate,
                testCase: _testCase,
                targetPixels: _trace.targetPixels,
                frame: _frame,
                windowGeneration: _windowGeneration,
                onChildBuilt: _recordChildBuild,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
