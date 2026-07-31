import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskr/people/person_detail.dart';
import 'package:taskr/people/person_form.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/shared/shared.dart';

class PeopleListPage extends StatefulWidget {
  const PeopleListPage({super.key});

  @override
  State<PeopleListPage> createState() => _PeopleListPageState();
}

class _PeopleListPageState extends State<PeopleListPage> {
  String _sortBy = 'name';
  String _searchQuery = '';

  List<Person> _getSortedAndFiltered(List<Person> people) {
    var filtered = people
        .where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    if (_sortBy == 'name') {
      filtered.sort((a, b) => a.name.compareTo(b.name));
    } else if (_sortBy == 'lastUpdated') {
      filtered.sort((a, b) => (b.lastUpdated ?? 0).compareTo(a.lastUpdated ?? 0));
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<PeopleProvider>(
      builder: (context, peopleProvider, _) {
        final sortedAndFiltered = _getSortedAndFiltered(peopleProvider.people);

        return Scaffold(
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(Insets.lg),
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search people...',
                        prefixIcon: const Icon(FontAwesomeIcons.magnifyingGlass, size: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Corners.sm),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 10),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                    const SizedBox(height: Insets.md),
                    Row(
                      children: [
                        Text('Sort by:', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(width: Insets.md),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(label: Text('Name'), value: 'name'),
                            ButtonSegment(label: Text('Recent'), value: 'lastUpdated'),
                          ],
                          selected: {_sortBy},
                          onSelectionChanged: (Set<String> newSelection) {
                            setState(() {
                              _sortBy = newSelection.first;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: peopleProvider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : sortedAndFiltered.isEmpty
                        ? EmptyState(
                            icon: FontAwesomeIcons.users,
                            title: _searchQuery.isEmpty ? 'No people yet' : 'No results found',
                            message: _searchQuery.isEmpty ? 'Add a person to get started' : null,
                          )
                        : ListView.builder(
                            itemCount: sortedAndFiltered.length,
                            itemBuilder: (context, index) {
                              final person = sortedAndFiltered[index];
                              return AppReveal(
                                delay: staggerDelay(index),
                                child: ListTile(
                                  title: Text(person.name),
                                  subtitle: person.job != null ? Text(person.job!) : null,
                                  trailing: const Icon(FontAwesomeIcons.chevronRight, size: 16),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => PersonDetailPage(personId: person.id!),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            child: const Icon(FontAwesomeIcons.plus, size: 20),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PersonFormPage(),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
