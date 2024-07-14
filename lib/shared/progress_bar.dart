import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';

class AnimatedProgressbar extends StatelessWidget {
  final double value;
  final double height;

  const AnimatedProgressbar({super.key, required this.value, this.height = 12});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      // Unknown width
      builder: (BuildContext context, BoxConstraints box) {
        return Container(
          padding: const EdgeInsets.all(10),
          width: box.maxWidth,
          child: Stack(
            children: [
              Container(
                height: height,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.all(
                    Radius.circular(height),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                height: height,
                width: box.maxWidth * _floor(value),
                decoration: BoxDecoration(
                  color: _colorGen(value),
                  borderRadius: BorderRadius.all(
                    Radius.circular(height),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _floor(double value, [min = 0.0]) {
    return value.sign <= min ? min : value;
  }

  _colorGen(double value) {
    int rbg = (value * 255).toInt();
    return Colors.deepOrange.withGreen(rbg).withRed(255 - rbg);
  }
}

class DailyProgress extends StatelessWidget {
  final int numberator;
  final int denominator;

  const DailyProgress({super.key, required this.numberator, required this.denominator});

  @override
  Widget build(BuildContext context) {
    return AnimatedProgressbar(value: _calculateProgress(numberator, denominator), height: 8);
  }

  double _calculateProgress(int num, int denom) {
    try {
      if (denom == 0) {
        return 0;
      }
      return num / denom;
    } catch (err) {
      return 0.0;
    }
  }
}
