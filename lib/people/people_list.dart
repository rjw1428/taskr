import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskr/people/person_detail.dart';
import 'package:taskr/people/person_form.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';

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
    return Consumer<PeopleProvider>(
      builder: (context, peopleProvider, _) {
        final sortedAndFiltered = _getSortedAndFiltered(peopleProvider.people);

        return Scaffold(
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search people...',
                        prefixIcon: const Icon(FontAwesomeIcons.magnifyingGlass, size: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Sort by:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 12),
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
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  FontAwesomeIcons.users,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isEmpty ? 'No people yet' : 'No results found',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                if (_searchQuery.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Add a person to get started',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: sortedAndFiltered.length,
                            itemBuilder: (context, index) {
                              final person = sortedAndFiltered[index];
                              return ListTile(
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
                              );
                            },
                          ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: Colors.purple,
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
