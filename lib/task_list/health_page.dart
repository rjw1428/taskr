import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

class HealthPage extends StatelessWidget {
  final String date;
  const HealthPage({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Health — $date')),
      body: StreamBuilder<HealthEntry?>(
        stream: HealthService().streamEntry(date),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final entry = snapshot.data;
          if (entry == null || !entry.hasData) {
            return const EmptyState(
              icon: FontAwesomeIcons.heartPulse,
              title: 'No health data for this day',
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.sleepSeconds != null) _sleepCard(context, entry),
                if (entry.bodyBatteryHigh != null) _bodyBatteryCard(context, entry),
                if (entry.stressAvg != null) _stressCard(context, entry),
                if (entry.steps != null || entry.restingHeartRate != null) _activityCard(context, entry),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _duration(int? seconds) {
    if (seconds == null) return '—';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  Widget _card(BuildContext context, String title, IconData icon, Color color, List<Widget> children) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.lg),
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              FaIcon(icon, size: 16, color: color),
              const SizedBox(width: Insets.sm),
              Text(title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: Insets.md),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value, {Color? valueColor}) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold, color: valueColor ?? theme.colorScheme.onSurface)),
          const SizedBox(height: 2),
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.appTokens.textFaint),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _sleepCard(BuildContext context, HealthEntry entry) {
    final stages = <(String, int?, Color)>[
      ('Deep', entry.deepSeconds, Colors.indigo),
      ('Light', entry.lightSeconds, Colors.lightBlue),
      ('REM', entry.remSeconds, Colors.purpleAccent),
      ('Awake', entry.awakeSeconds, Colors.pinkAccent),
    ].where((s) => (s.$2 ?? 0) > 0).toList();
    final totalStaged = stages.fold<int>(0, (sum, s) => sum + s.$2!);

    return _card(context, 'Sleep', FontAwesomeIcons.moon, Colors.indigoAccent, [
      Row(children: [
        _stat(context, 'Score', entry.sleepScore?.toString() ?? '—', valueColor: _scoreColor(entry.sleepScore)),
        _stat(context, 'Duration', _duration(entry.sleepSeconds)),
      ]),
      if (stages.isNotEmpty) ...[
        const SizedBox(height: Insets.lg),
        ClipRRect(
          borderRadius: BorderRadius.circular(Insets.xs),
          child: Row(
            children: stages
                .map((s) => Expanded(
                      flex: s.$2!,
                      child: Container(height: 10, color: s.$3),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.md,
          runSpacing: Insets.xs,
          children: stages
              .map((s) => Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                    const SizedBox(width: Insets.xs),
                    Text('${s.$1} ${_duration(s.$2)} (${(s.$2! * 100 / totalStaged).round()}%)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).appTokens.textFaint)),
                  ]))
              .toList(),
        ),
      ],
    ]);
  }

  Widget _bodyBatteryCard(BuildContext context, HealthEntry entry) {
    return _card(context, 'Body Battery', FontAwesomeIcons.batteryThreeQuarters, Colors.tealAccent, [
      Row(children: [
        _stat(context, 'High', entry.bodyBatteryHigh?.toString() ?? '—', valueColor: Colors.tealAccent),
        _stat(context, 'Low', entry.bodyBatteryLow?.toString() ?? '—'),
        _stat(context, 'Charged', entry.bodyBatteryCharged != null ? '+${entry.bodyBatteryCharged}' : '—'),
        _stat(context, 'Drained', entry.bodyBatteryDrained != null ? '-${entry.bodyBatteryDrained}' : '—'),
      ]),
    ]);
  }

  Widget _stressCard(BuildContext context, HealthEntry entry) {
    return _card(context, 'Stress', FontAwesomeIcons.brain, Colors.orangeAccent, [
      Row(children: [
        _stat(context, 'Average', entry.stressAvg?.toString() ?? '—', valueColor: _stressColor(entry.stressAvg)),
        _stat(context, 'Max', entry.stressMax?.toString() ?? '—'),
      ]),
    ]);
  }

  Widget _activityCard(BuildContext context, HealthEntry entry) {
    return _card(context, 'Activity', FontAwesomeIcons.personWalking, Colors.lightGreenAccent, [
      Row(children: [
        _stat(context, 'Steps', entry.steps?.toString() ?? '—'),
        _stat(context, 'Resting HR', entry.restingHeartRate != null ? '${entry.restingHeartRate} bpm' : '—'),
        _stat(context, 'Floors', entry.floorsClimbed?.toString() ?? '—'),
        _stat(context, 'Active Cal', entry.activeCalories?.toString() ?? '—'),
      ]),
    ]);
  }

  // Status accents for health metrics (data indicators). Null → let the
  // caller fall back to the themed default text color.
  static Color? _scoreColor(int? score) {
    if (score == null) return null;
    if (score >= 80) return Colors.lightGreenAccent;
    if (score >= 60) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  static Color? _stressColor(int? stress) {
    if (stress == null) return null;
    if (stress <= 25) return Colors.lightGreenAccent;
    if (stress <= 50) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}
