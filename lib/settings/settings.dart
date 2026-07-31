import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/tag.provider.dart';
import 'package:taskr/services/theme.provider.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/task_list/add_tag.dart';

import '../services/services.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService().userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        } else if (snapshot.hasError) {
          return const Center(
            child: ErrorMessage(),
          );
        } else if (snapshot.hasData) {
          // Will be null if user is not logged in
          return SettingsForm(userId: snapshot.data!.uid);
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

class SettingsForm extends StatefulWidget {
  final String userId;
  const SettingsForm({super.key, required this.userId});

  @override
  State<StatefulWidget> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsForm> {
  bool isShowingAll = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var tagProvider = Provider.of<TagProvider>(context);
    var tags = tagProvider.tags;
    return Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
        ),
        body: ListView(
          scrollDirection: Axis.vertical,
          padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.sm),
          children: [
            const SectionHeader('Appearance'),
            const _ThemeModeRow(),
            const SizedBox(height: Insets.sm),
            const SectionHeader('Google Calendar'),
            _GoogleCalendarRow(userId: widget.userId),
            const SizedBox(height: Insets.sm),
            SectionHeader(
              'Tags',
              trailing: TextButton.icon(
                onPressed: () => _editTag(),
                icon: const Icon(FontAwesomeIcons.plus, size: 12),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.xs, vertical: Insets.xs),
              child: tags.isEmpty
                  ? Text(
                      'No tags yet. Add one to label and group your tasks.',
                      style: theme.textTheme.bodySmall,
                    )
                  : Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.xs,
                      children: tags
                          .map((tag) => InputChip(
                                avatar: Icon(FontAwesomeIcons.tag, size: 11, color: theme.colorScheme.primary),
                                label: Text(tag.label),
                                onPressed: () => _editTag(tag),
                                onDeleted: () => _confirmDeleteTag(tag, tagProvider),
                                deleteIcon: const Icon(FontAwesomeIcons.xmark, size: 12),
                                deleteButtonTooltipMessage: 'Delete "${tag.label}"',
                                tooltip: 'Edit "${tag.label}"',
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    ),
            ),
            const SizedBox(height: Insets.xl),
          ],
        ));
  }

  void _editTag([Tag? tag]) {
    showDialog(context: context, builder: (_) => AddTagScreen(tag: tag));
  }

  Future<void> _confirmDeleteTag(Tag tag, TagProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tag?'),
        content: Text('Remove "${tag.label}"? It will no longer be available to tag tasks.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await provider.deleteTag(tag.id);
      messenger.showSnackBar(SnackBar(content: Text('Deleted "${tag.label}"')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete tag: $e')));
    }
  }
}

class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow();

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.xs, vertical: Insets.sm),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
                value: ThemeMode.system, label: Text('System'), icon: Icon(FontAwesomeIcons.mobileScreen, size: 14)),
            ButtonSegment(
                value: ThemeMode.light, label: Text('Light'), icon: Icon(FontAwesomeIcons.sun, size: 14)),
            ButtonSegment(
                value: ThemeMode.dark, label: Text('Dark'), icon: Icon(FontAwesomeIcons.moon, size: 14)),
          ],
          selected: {themeProvider.mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => context.read<ThemeProvider>().setMode(selection.first),
        ),
      ),
    );
  }
}

class _GoogleCalendarRow extends StatefulWidget {
  final String userId;
  const _GoogleCalendarRow({required this.userId});

  @override
  State<_GoogleCalendarRow> createState() => _GoogleCalendarRowState();
}

class _GoogleCalendarRowState extends State<_GoogleCalendarRow> {
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await CalendarService().connect();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google Calendar connected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Google Calendar?'),
        content: const Text('Sync will stop. Tasks already on your calendar will remain there.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await CalendarService().disconnect();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google Calendar disconnected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not disconnect: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return StreamBuilder<bool>(
      stream: CalendarService().watchConnected(widget.userId),
      builder: (context, snapshot) {
        final connected = snapshot.data ?? false;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.xs, vertical: Insets.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  connected ? 'Connected' : 'Not connected',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: connected ? theme.colorScheme.primary : t.textMuted,
                  ),
                ),
              ),
              if (_busy)
                SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary))
              else if (connected)
                SecondaryButton('Disconnect', onPressed: _disconnect)
              else
                PrimaryButton('Connect', onPressed: _connect, expand: false),
            ],
          ),
        );
      },
    );
  }
}
