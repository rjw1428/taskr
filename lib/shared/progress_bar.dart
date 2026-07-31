import 'package:flutter/material.dart';
import 'package:taskr/shared/design/tokens.dart';

class AnimatedProgressbar extends StatelessWidget {
  final double value;
  final double height;

  const AnimatedProgressbar({super.key, required this.value, this.height = 12});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
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
                  color: t.surfaceRaised,
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
                  color: theme.colorScheme.primary,
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
}

class DailyProgress extends StatelessWidget {
  final int numerator;
  final int denominator;

  const DailyProgress({super.key, required this.numerator, required this.denominator});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final progress = _calculateProgress(numerator, denominator);
    final percent = (progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Count and percent live above the bar so nothing overlaps the fill.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("$numerator of $denominator",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              Text("$percent%",
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: t.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        ),
        AnimatedProgressbar(value: progress, height: 8),
      ],
    );
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
