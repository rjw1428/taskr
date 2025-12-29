import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/accomplishment.provider.dart';

class AccomplishmentDetailPage extends StatelessWidget {
  final Accomplishment accomplishment;

  const AccomplishmentDetailPage({super.key, required this.accomplishment});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(accomplishment.title),
        actions: [],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              accomplishment.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Date: ${accomplishment.date}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text(
              'Difficulty: ${accomplishment.difficulty.toString().split('.').last}',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            Text(
              accomplishment.description ?? 'No description provided.',
              style: const TextStyle(fontSize: 18),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  label: const Text('Delete'),
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
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
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true && accomplishment.id != null) {
                      Provider.of<AccomplishmentProvider>(context, listen: false)
                          .deleteAccomplishment(accomplishment.id!);
                      Navigator.pop(context); // Pop detail page after deletion
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
