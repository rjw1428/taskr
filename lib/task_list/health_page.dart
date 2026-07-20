import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

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
            return const Center(
              child: Text('No health data for this day', style: TextStyle(color: Colors.white70)),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.sleepSeconds != null) _sleepCard(entry),
                if (entry.bodyBatteryHigh != null) _bodyBatteryCard(entry),
                if (entry.stressAvg != null) _stressCard(entry),
                if (entry.steps != null || entry.restingHeartRate != null) _activityCard(entry),
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

  Widget _card(String title, IconData icon, Color color, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              FaIcon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
            ]),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: valueColor ?? Colors.white)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _sleepCard(HealthEntry entry) {
    final stages = <(String, int?, Color)>[
      ('Deep', entry.deepSeconds, Colors.indigo),
      ('Light', entry.lightSeconds, Colors.lightBlue),
      ('REM', entry.remSeconds, Colors.purpleAccent),
      ('Awake', entry.awakeSeconds, Colors.pinkAccent),
    ].where((s) => (s.$2 ?? 0) > 0).toList();
    final totalStaged = stages.fold<int>(0, (sum, s) => sum + s.$2!);

    return _card('Sleep', FontAwesomeIcons.moon, Colors.indigoAccent, [
      Row(children: [
        _stat('Score', entry.sleepScore?.toString() ?? '—', valueColor: _scoreColor(entry.sleepScore)),
        _stat('Duration', _duration(entry.sleepSeconds)),
      ]),
      if (stages.isNotEmpty) ...[
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: stages
                .map((s) => Expanded(
                      flex: s.$2!,
                      child: Container(height: 10, color: s.$3),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: stages
              .map((s) => Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('${s.$1} ${_duration(s.$2)} (${(s.$2! * 100 / totalStaged).round()}%)',
                        style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  ]))
              .toList(),
        ),
      ],
    ]);
  }

  Widget _bodyBatteryCard(HealthEntry entry) {
    return _card('Body Battery', FontAwesomeIcons.batteryThreeQuarters, Colors.tealAccent, [
      Row(children: [
        _stat('High', entry.bodyBatteryHigh?.toString() ?? '—', valueColor: Colors.tealAccent),
        _stat('Low', entry.bodyBatteryLow?.toString() ?? '—'),
        _stat('Charged', entry.bodyBatteryCharged != null ? '+${entry.bodyBatteryCharged}' : '—'),
        _stat('Drained', entry.bodyBatteryDrained != null ? '-${entry.bodyBatteryDrained}' : '—'),
      ]),
    ]);
  }

  Widget _stressCard(HealthEntry entry) {
    return _card('Stress', FontAwesomeIcons.brain, Colors.orangeAccent, [
      Row(children: [
        _stat('Average', entry.stressAvg?.toString() ?? '—', valueColor: _stressColor(entry.stressAvg)),
        _stat('Max', entry.stressMax?.toString() ?? '—'),
      ]),
    ]);
  }

  Widget _activityCard(HealthEntry entry) {
    return _card('Activity', FontAwesomeIcons.personWalking, Colors.lightGreenAccent, [
      Row(children: [
        _stat('Steps', entry.steps?.toString() ?? '—'),
        _stat('Resting HR', entry.restingHeartRate != null ? '${entry.restingHeartRate} bpm' : '—'),
        _stat('Floors', entry.floorsClimbed?.toString() ?? '—'),
        _stat('Active Cal', entry.activeCalories?.toString() ?? '—'),
      ]),
    ]);
  }

  static Color _scoreColor(int? score) {
    if (score == null) return Colors.white;
    if (score >= 80) return Colors.lightGreenAccent;
    if (score >= 60) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  static Color _stressColor(int? stress) {
    if (stress == null) return Colors.white;
    if (stress <= 25) return Colors.lightGreenAccent;
    if (stress <= 50) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}
