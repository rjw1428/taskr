import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

class NotificationCenterPage extends StatelessWidget {
  const NotificationCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = NotificationService();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          StreamBuilder<List<AppNotification>>(
            stream: service.streamNotifications(),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <AppNotification>[];
              if (items.isEmpty) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                icon: const Icon(FontAwesomeIcons.ellipsisVertical, size: 18),
                onSelected: (v) {
                  if (v == 'read') service.markAllRead();
                  if (v == 'clear') service.clearAll();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'read', child: Text('Mark all read')),
                  const PopupMenuItem(value: 'clear', child: Text('Clear all')),
                ],
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: service.streamNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? const <AppNotification>[];
          if (items.isEmpty) {
            return const EmptyState(
              icon: FontAwesomeIcons.bell,
              title: 'No notifications',
              message: "Reminders and alerts you receive will show up here.",
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: Insets.sm),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _NotificationTile(
              notification: items[index],
              service: service,
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final NotificationService service;
  const _NotificationTile({required this.notification, required this.service});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final unread = !notification.read;
    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.error.withAlpha(40),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Insets.lg),
        child: Icon(FontAwesomeIcons.trashCan, size: 16, color: theme.colorScheme.error),
      ),
      onDismissed: (_) => service.delete(notification.id!),
      child: ListTile(
        leading: Icon(
          FontAwesomeIcons.solidCircle,
          size: 8,
          color: unread ? theme.colorScheme.primary : Colors.transparent,
        ),
        title: Text(
          notification.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notification.body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(notification.body, style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 4),
            Text(DateService().relativeTime(notification.sentAt),
                style: theme.textTheme.labelSmall?.copyWith(color: t.textFaint)),
          ],
        ),
        onTap: unread ? () => service.markRead(notification.id!) : null,
      ),
    );
  }
}
