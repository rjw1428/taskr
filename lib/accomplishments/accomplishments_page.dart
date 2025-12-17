import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskr/accomplishments/add_accomplishment.dart';
import 'package:taskr/accomplishments/edit_accomplishment.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/bottom_nav.dart';

class AccomplishmentsPage extends StatelessWidget {
  const AccomplishmentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accomplishments'),
      ),
      body: Consumer<AccomplishmentProvider>(
        builder: (context, provider, child) {
          if (provider.accomplishments.isEmpty) {
            return const Center(
              child: Text('No accomplishments yet.'),
            );
          }
          return ListView.builder(
            itemCount: provider.accomplishments.length,
            itemBuilder: (context, index) {
              final accomplishment = provider.accomplishments[index];
              return ListTile(
                title: Text(accomplishment.title),
                subtitle: Text(accomplishment.description ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditAccomplishmentPage(accomplishment: accomplishment),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        provider.deleteAccomplishment(accomplishment.id!);
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddAccomplishmentPage(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: const BottomNavBar(
        selectedIndex: 2,
      ),
    );
  }
}
