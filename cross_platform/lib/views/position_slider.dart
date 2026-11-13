import 'package:flutter/material.dart';

class PositionSlider extends StatefulWidget {
  final Duration position, duration;
  final ValueChanged<Duration> seek;
  const PositionSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.seek,
  });
  @override
  State<PositionSlider> createState() => _PositionSliderState();
}

class _PositionSliderState extends State<PositionSlider> {
  double? dragging;
  String time(double milliseconds) {
    final seconds = milliseconds ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final end = widget.duration.inMilliseconds.toDouble(),
        value = (dragging ?? widget.position.inMilliseconds.toDouble())
            .clamp(0, end)
            .toDouble();
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            time(value),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            max: end > 0 ? end : 1,
            onChangeStart: (v) => setState(() => dragging = v),
            onChanged: end > 0 ? (v) => setState(() => dragging = v) : null,
            onChangeEnd: (v) {
              widget.seek(Duration(milliseconds: v.round()));
              setState(() => dragging = null);
            },
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            time(end),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}
