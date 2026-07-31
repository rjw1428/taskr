import 'package:taskr/accomplishments/accomplishment_form.dart';
import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/shared/shared.dart';

class AccomplishmentDetailPage extends StatelessWidget {
  final Accomplishment accomplishment;

  const AccomplishmentDetailPage({super.key, required this.accomplishment});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Accomplishment>>(
      stream: context.read<AccomplishmentProvider>().getAccomplishments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        } else if (snapshot.hasError) {
          return Center(child: ErrorMessage(message: snapshot.error.toString()));
        } else if (snapshot.hasData) {
          final accomplishments = snapshot.data!;
          final accomplishmentIndex = accomplishments.indexWhere((acc) => acc.id == accomplishment.id);

          if (accomplishmentIndex == -1) {
            // Accomplishment was deleted, pop the page.
            // We need to schedule the pop for after the build is complete.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            });
            return const Scaffold(body: SizedBox.shrink()); // Return an empty scaffold while popping
          }

          final updatedAccomplishment = accomplishments[accomplishmentIndex];

          return _AccomplishmentDetailView(accomplishment: updatedAccomplishment);
        } else {
          return const Center(child: Text('Accomplishment not found.'));
        }
      },
    );
  }
}

class _AccomplishmentDetailView extends StatelessWidget {
  final Accomplishment accomplishment;

  const _AccomplishmentDetailView({required this.accomplishment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return Scaffold(
      appBar: AppBar(
        title: Text(accomplishment.title),
        actions: [],
      ),
      body: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              accomplishment.title,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: Insets.md),
            Text(
              'Date: ${accomplishment.date}',
              style: theme.textTheme.bodyMedium?.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: Insets.md),
            Text(
              'Difficulty: ${accomplishment.difficulty.toString().split('.').last}',
              style: theme.textTheme.bodyMedium?.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: Insets.md),
            Text(
              'Difficulty Score: ${accomplishment.difficultyScore}/10',
              style: theme.textTheme.bodyMedium?.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: Insets.xl),
            Text(
              accomplishment.description ?? 'No description provided.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: Insets.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  label: const Text('Edit'),
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AccomplishmentForm(accomplishment: accomplishment),
                      ),
                    );
                  },
                ),
                const SizedBox(width: Insets.md),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  label: const Text('Delete'),
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final accomplishmentProvider = Provider.of<AccomplishmentProvider>(context, listen: false);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Accomplishment'),
                        content: const Text('Are you sure you want to delete this accomplishment?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true && accomplishment.id != null) {
                      accomplishmentProvider.deleteAccomplishment(accomplishment.id!);
                      if (navigator.canPop()) {
                        navigator.pop(); // Pop detail page after deletion
                      }
                    }
                  },
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
