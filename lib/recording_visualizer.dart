import 'dart:math';
import 'package:flutter/material.dart';

class RecordingVisualizer extends StatefulWidget {
  final bool isRecording;

  const RecordingVisualizer({super.key, required this.isRecording});

  @override
  State<RecordingVisualizer> createState() => _RecordingVisualizerState();
}

class _RecordingVisualizerState extends State<RecordingVisualizer>
    with TickerProviderStateMixin {
  final int _barCount = 9;
  final Random _random = Random();
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  // 中間高兩側低的基礎高度分佈
  final List<double> _baseHeights = [
    0.2,
    0.35,
    0.5,
    0.7,
    1.0,
    0.7,
    0.5,
    0.35,
    0.2,
  ];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_barCount, (i) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 400 + _random.nextInt(300)),
      );
    });

    _animations = List.generate(_barCount, (i) {
      return Tween<double>(
        begin: _baseHeights[i] * 0.3,
        end: _baseHeights[i],
      ).animate(
        CurvedAnimation(parent: _controllers[i], curve: Curves.easeInOut),
      );
    });

    if (widget.isRecording) _startAnimation();
  }

  void _startAnimation() {
    for (int i = 0; i < _barCount; i++) {
      Future.delayed(Duration(milliseconds: i * 40), () {
        if (mounted && widget.isRecording) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  void _stopAnimation() {
    for (final controller in _controllers) {
      controller.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void didUpdateWidget(RecordingVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _startAnimation();
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _stopAnimation();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isRecording
        ? Colors.red
        : Theme.of(context).colorScheme.secondary;

    return SizedBox(
      height: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barCount, (i) {
          return AnimatedBuilder(
            animation: _animations[i],
            builder: (context, child) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 4,
                height: 64 * _animations[i].value,
                decoration: BoxDecoration(
                  color: widget.isRecording
                      ? color.withOpacity(0.4 + 0.6 * _animations[i].value)
                      : color.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
