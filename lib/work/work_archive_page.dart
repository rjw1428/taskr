import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/work.service.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/work/work_detail_page.dart';

/// Archived work items, newest archive first. Each opens its detail page.
class WorkArchivePage extends StatefulWidget {
  final WorkService? service;
  const WorkArchivePage({super.key, this.service});

  @override
  State<WorkArchivePage> createState() => _WorkArchivePageState();
}

class _WorkArchivePageState extends State<WorkArchivePage> {
  late final WorkService _service = widget.service ?? WorkService();
  late final Stream<List<WorkItem>> _stream = _service.streamArchived();
  static final _day = DateFormat('MMM d, yyyy');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return Scaffold(
      appBar: AppBar(title: const Text('Archived work')),
      body: StreamBuilder<List<WorkItem>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: ErrorMessage(message: describeError(snapshot.error!)));
          if (!snapshot.hasData) return const LoadingScreen();
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const EmptyState(
              icon: FontAwesomeIcons.boxArchive,
              title: 'Nothing archived',
              message: 'Archived work items keep their full history here.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(Insets.md),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              final done = item.nextActions.where((a) => !a.isOpen).length;
              return Padding(
                padding: const EdgeInsets.only(bottom: Insets.sm),
                child: AppCard(
                  padding: const EdgeInsets.all(Insets.md),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => WorkDetailPage(itemId: item.id!, archived: true, service: _service)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Archived ${_day.format(DateTime.fromMillisecondsSinceEpoch(item.archivedAt ?? 0))}'
                        ' · $done ${done == 1 ? 'step' : 'steps'} done'
                        ' · ${item.updates.length} ${item.updates.length == 1 ? 'update' : 'updates'}',
                        style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
