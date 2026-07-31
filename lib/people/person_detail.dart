import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:taskr/people/person_form.dart';
import 'package:taskr/people/log_form.dart';
import 'package:taskr/people/person_avatar.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/shared/shared.dart';

class PersonDetailPage extends StatefulWidget {
  final String personId;

  const PersonDetailPage({super.key, required this.personId});

  @override
  State<PersonDetailPage> createState() => _PersonDetailPageState();
}

class _PersonDetailPageState extends State<PersonDetailPage> {
  @override
  Widget build(BuildContext context) {
    return Consumer<PeopleProvider>(
      builder: (context, peopleProvider, _) {
        final person = peopleProvider.people.firstWhere(
          (p) => p.id == widget.personId,
          orElse: () => Person(name: 'Person not found', id: widget.personId),
        );

        if (person.name == 'Person not found') {
          return Scaffold(
            appBar: AppBar(title: const Text('Person')),
            body: const Center(child: Text('Person not found')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(person.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PersonFormPage(person: person),
                      ),
                    );
                  } else if (value == 'delete') {
                    _showDeleteConfirmation(context, person, peopleProvider);
                  }
                },
                itemBuilder: (BuildContext context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPersonInfo(context, person),
                _buildLogsSection(context, person, peopleProvider),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            child: const Icon(FontAwesomeIcons.plus, size: 20),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LogFormPage(personId: person.id!),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPersonInfo(BuildContext context, Person person) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final facts = <Widget>[];
    if (person.age != null) facts.add(_fact(context, 'Age', person.age.toString()));
    if (person.birthday != null) {
      facts.add(_fact(context, 'Birthday', DateFormat('MMM d').format(DateTime.parse(person.birthday!))));
    }
    if (person.spouse != null) facts.add(_fact(context, 'Spouse', person.spouse!));
    if (person.job != null) facts.add(_fact(context, 'Job', person.job!));

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, Insets.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PersonAvatar(name: person.name, size: 52),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(person.name, style: theme.textTheme.titleLarge),
                      if (person.job != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(person.job!,
                              style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (facts.isNotEmpty || person.kids.isNotEmpty) ...[
              const SizedBox(height: Insets.lg),
              Divider(height: 1, color: t.hairline),
              const SizedBox(height: Insets.md),
            ],
            if (facts.isNotEmpty)
              Wrap(spacing: Insets.xl, runSpacing: Insets.md, children: facts),
            if (person.kids.isNotEmpty) ...[
              const SizedBox(height: Insets.md),
              Text('KIDS',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.textFaint, letterSpacing: 1.2)),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: person.kids.map((kid) {
                  final age = _calculateAge(kid);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withAlpha(28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('${kid.name} · $age',
                        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fact(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(color: theme.appTokens.textFaint, letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleSmall),
      ],
    );
  }

  int _calculateAge(Kid kid) {
    if (kid.birthday != null) {
      final birthDate = DateTime.parse(kid.birthday!);
      final now = DateTime.now();
      int age = now.year - birthDate.year;
      if (now.month < birthDate.month || (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }
      return age;
    } else {
      final dateAdded = DateTime.parse(kid.dateAdded);
      final now = DateTime.now();
      int age = kid.age;
      if (now.month > dateAdded.month || (now.month == dateAdded.month && now.day >= dateAdded.day)) {
        age += (now.year - dateAdded.year);
      } else {
        age += (now.year - dateAdded.year - 1);
      }
      return age;
    }
  }

  Widget _buildLogsSection(BuildContext context, Person person, PeopleProvider peopleProvider) {
    final logs = [...person.logs];
    // Newest on top. Sort by date desc; for entries sharing a date (date has no
    // time component), break the tie by createdAt desc so the most recently
    // added still floats to the top.
    logs.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return (b.createdAt ?? 0).compareTo(a.createdAt ?? 0);
    });

    return Padding(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Conversation Log', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: Insets.md),
          if (logs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.xxl),
                child: Text(
                  'No logs yet',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          else
            ...logs.map((log) {
              return _buildLogItem(context, person, log, peopleProvider);
            }),
        ],
      ),
    );
  }

  Widget _buildLogItem(BuildContext context, Person person, ConversationLog log, PeopleProvider peopleProvider) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      child: Padding(
        // Tight left/vertical padding keeps the focus on the message; the small
        // right inset leaves room for the compact menu button.
        padding: const EdgeInsets.fromLTRB(Insets.md, Insets.sm, Insets.xs, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMM d, yyyy').format(DateTime.parse(log.date)),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: t.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(log.entry, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            // Compact menu: a small fixed box so its tap target doesn't inflate
            // the card height the way the default 48px PopupMenuButton did.
            SizedBox(
              height: 28,
              width: 28,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 16,
                tooltip: 'Log options',
                icon: Icon(FontAwesomeIcons.ellipsisVertical, color: t.textFaint),
                onSelected: (value) {
                  if (value == 'edit') {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LogFormPage(
                          personId: person.id!,
                          log: log,
                        ),
                      ),
                    );
                  } else if (value == 'delete') {
                    _showDeleteLogConfirmation(context, person, log, peopleProvider);
                  }
                },
                itemBuilder: (BuildContext context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext pageContext, Person person, PeopleProvider peopleProvider) {
    showDialog(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Person'),
        content: Text('Delete ${person.name} and all their logs?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // Capture navigator/messenger before any async gap; the dialog and
              // page contexts are deactivated once popped, so using them after the
              // await would crash (this was the delete-crash bug).
              final navigator = Navigator.of(pageContext);
              final messenger = ScaffoldMessenger.of(pageContext);
              Navigator.pop(dialogContext); // close the confirmation dialog
              navigator.pop(); // leave the detail page immediately
              try {
                await peopleProvider.deletePerson(person.id!);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Error deleting person: ${e.toString()}')),
                );
              }
            },
            child: Text('Delete', style: TextStyle(color: Theme.of(pageContext).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _showDeleteLogConfirmation(BuildContext pageContext, Person person, ConversationLog log, PeopleProvider peopleProvider) {
    showDialog(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Log'),
        content: const Text('Delete this conversation log?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(pageContext);
              Navigator.pop(dialogContext);
              final logId = log.id;
              if (logId == null) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('This older log has no id and can\'t be removed individually; delete the person to clear it.')),
                );
                return;
              }
              try {
                await peopleProvider.deleteLog(person.id!, logId);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Error deleting log: ${e.toString()}')),
                );
              }
            },
            child: Text('Delete', style: TextStyle(color: Theme.of(pageContext).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}
