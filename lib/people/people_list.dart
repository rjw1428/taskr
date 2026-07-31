import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskr/people/person_detail.dart';
import 'package:taskr/people/person_form.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/people/person_avatar.dart';
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
    final t = theme.appTokens;
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
                            padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.xxl),
                            itemCount: sortedAndFiltered.length,
                            itemBuilder: (context, index) {
                              final person = sortedAndFiltered[index];
                              final subtitle = person.job ??
                                  (person.logs.isNotEmpty
                                      ? '${person.logs.length} ${person.logs.length == 1 ? 'note' : 'notes'}'
                                      : null);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: Insets.sm),
                                child: AppReveal(
                                  delay: staggerDelay(index),
                                  child: AppCard(
                                    padding: const EdgeInsets.all(Insets.md),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => PersonDetailPage(personId: person.id!),
                                        ),
                                      );
                                    },
                                    child: Row(
                                      children: [
                                        PersonAvatar(name: person.name),
                                        const SizedBox(width: Insets.md),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(person.name, style: theme.textTheme.titleMedium),
                                              if (subtitle != null)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(subtitle,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: theme.textTheme.bodySmall
                                                          ?.copyWith(color: t.textMuted)),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Icon(FontAwesomeIcons.chevronRight, size: 13, color: t.textFaint),
                                      ],
                                    ),
                                  ),
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
