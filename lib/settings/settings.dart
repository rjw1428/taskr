import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/tag.provider.dart';
import 'package:taskr/shared/error.dart';
import 'package:taskr/shared/loading.dart';
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
    var tagProvider = Provider.of<TagProvider>(context);
    var tags = tagProvider.tags;
    return Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
        ),
        body: ListView(
          scrollDirection: Axis.vertical,
          children: [
            const Text("Google Calendar", style: TextStyle(fontSize: 32)),
            _GoogleCalendarRow(userId: widget.userId),
            const SizedBox(height: 16),
            const Text("Tags", style: TextStyle(fontSize: 32)),
            Container(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: tags.map((Tag tag) {
                  return Row(children: [
                    Text(
                      tag.label,
                    ),
                    IconButton(
                        onPressed: () =>
                            showDialog(context: context, builder: (BuildContext context) => AddTagScreen(tag: tag)),
                        icon: const Icon(FontAwesomeIcons.penToSquare)),
                    IconButton(
                      onPressed: () => tagProvider.deleteTag(tag.id),
                      icon: const Icon(FontAwesomeIcons.trashCan),
                    )
                  ]);
                }).toList(),
              ),
            )
          ],
        ),
        floatingActionButton: FloatingActionButton(
            child: const Icon(FontAwesomeIcons.plus, size: 20),
            onPressed: () => showDialog(context: context, builder: (BuildContext context) => const AddTagScreen())));
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
    return StreamBuilder<bool>(
      stream: CalendarService().watchConnected(widget.userId),
      builder: (context, snapshot) {
        final connected = snapshot.data ?? false;
        return Padding(
          padding: const EdgeInsets.only(left: 16, top: 8, right: 16, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  connected ? 'Connected' : 'Not connected',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if (_busy)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else if (connected)
                TextButton(onPressed: _disconnect, child: const Text('Disconnect'))
              else
                ElevatedButton(onPressed: _connect, child: const Text('Connect')),
            ],
          ),
        );
      },
    );
  }
}
