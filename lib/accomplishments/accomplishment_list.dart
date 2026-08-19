import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskr/accomplishments/accomplishment_color.dart';
import 'package:taskr/accomplishments/accomplishment_detail_page.dart';
import 'package:taskr/accomplishments/accomplishment_grouping.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/shared.dart';

/// The full accomplishment log, newest-first.
///
/// Paginates by growing the query's limit rather than by accumulating cursor
/// pages, so the whole loaded window stays a single live query: edits and
/// deletions to anything on screen keep propagating no matter how far back the
/// user has scrolled.
class AccomplishmentListPage extends StatefulWidget {
  const AccomplishmentListPage({super.key});

  @override
  State<AccomplishmentListPage> createState() => _AccomplishmentListPageState();
}

class _AccomplishmentListPageState extends State<AccomplishmentListPage> {
  static const int _pageSize = 20;

  /// How close to the bottom the user must scroll before the next page is
  /// requested. Roughly two rows' worth, so the page lands before they arrive.
  static const double _extendThreshold = 200;

  final ScrollController _controller = ScrollController();

  int _limit = _pageSize;

  /// False once a page comes back shorter than requested — there is no more
  /// history, so stop extending and stop showing the loading footer.
  bool _hasMore = true;

  /// Set when a larger limit has been requested but its first snapshot has not
  /// arrived. Without this the scroll listener fires repeatedly near the
  /// threshold and requests several pages at once.
  bool _extending = false;

  /// Held in state and swapped only when [_limit] changes, so that unrelated
  /// rebuilds don't resubscribe (which would flicker and reset scroll offset).
  Stream<List<Accomplishment>>? _stream;
  int? _streamLimit;

  /// The most recent snapshot, replayed as `initialData` when the stream is
  /// swapped for a wider one. Without it the rebuild would drop to a bare
  /// loading state and the user would lose their place in the list. Null until
  /// the first snapshot arrives, which is what distinguishes "still loading"
  /// from "loaded, and there is nothing here".
  List<Accomplishment>? _loaded;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  Stream<List<Accomplishment>> _streamFor(BuildContext context) {
    if (_stream == null || _streamLimit != _limit) {
      _stream = context.read<AccomplishmentProvider>().getAccomplishments(limit: _limit);
      _streamLimit = _limit;
    }
    return _stream!;
  }

  void _onScroll() {
    if (!_hasMore || _extending || !_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels < position.maxScrollExtent - _extendThreshold) return;

    setState(() {
      _extending = true;
      _limit += _pageSize;
    });
  }

  /// Called on each snapshot to reconcile what actually came back with what was
  /// asked for. A short page means the end of the collection.
  void _onPage(int count) {
    final exhausted = count < _limit;
    if (!_extending && _hasMore == !exhausted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _extending = false;
        _hasMore = !exhausted;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accomplishments')),
      body: StreamBuilder<List<Accomplishment>>(
        stream: _streamFor(context),
        initialData: _loaded,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: ErrorMessage(message: snapshot.error.toString()));
          }
          if (!snapshot.hasData) {
            return const LoadingScreen();
          }

          final accomplishments = snapshot.data!;
          _loaded = accomplishments;
          // Only a live snapshot says anything about how much history exists.
          // While a wider stream connects, `initialData` replays the previous
          // (narrower) list, which would otherwise read as a short page and
          // halt pagination one step early.
          if (snapshot.connectionState == ConnectionState.active) {
            _onPage(accomplishments.length);
          }

          if (accomplishments.isEmpty) {
            return const EmptyState(
              icon: FontAwesomeIcons.trophy,
              title: 'No accomplishments yet',
              message: 'Log a win from the Performance tab and it will show up here.',
            );
          }

          final months = groupByMonth(accomplishments);

          return ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.md, Insets.lg, Insets.xxl),
            // One trailing slot for the loading footer.
            itemCount: months.length + 1,
            itemBuilder: (context, index) {
              if (index == months.length) {
                return _LoadingFooter(visible: _hasMore);
              }
              return _MonthSection(month: months[index]);
            },
          );
        },
      ),
    );
  }
}

class _MonthSection extends StatelessWidget {
  final AccomplishmentMonth month;

  const _MonthSection({required this.month});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Insets.xs, top: Insets.md, bottom: Insets.sm),
          child: Text(month.label, style: theme.textTheme.titleMedium),
        ),
        ...month.accomplishments.map((a) => _AccomplishmentRow(accomplishment: a)),
      ],
    );
  }
}

/// Matches the row treatment used by the Performance tab's summary so the two
/// views read as the same list.
class _AccomplishmentRow extends StatelessWidget {
  final Accomplishment accomplishment;

  const _AccomplishmentRow({required this.accomplishment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final date = DateTime.tryParse(accomplishment.date);
    final formattedDate = date == null
        ? ''
        : '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    final scoreColor = accomplishmentScoreColor(theme, accomplishment.difficultyScore);

    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Corners.md),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AccomplishmentDetailPage(accomplishment: accomplishment),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
          child: Row(
            children: [
              // Score badge, colored by difficulty (1-10).
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scoreColor.withAlpha(38),
                  shape: BoxShape.circle,
                  border: Border.all(color: scoreColor.withAlpha(120)),
                ),
                child: Text('${accomplishment.difficultyScore}',
                    style: theme.textTheme.labelLarge?.copyWith(color: scoreColor, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Text(
                  accomplishment.title,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              Text(formattedDate, style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingFooter extends StatelessWidget {
  final bool visible;

  const _LoadingFooter({required this.visible});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: Insets.lg),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
