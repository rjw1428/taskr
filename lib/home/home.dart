import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/accomplishments/accomplishment_form.dart';
import 'package:taskr/goals/goal_form.dart';
import 'package:taskr/goals/habit_form.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/routing.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/work/work_item_form.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    requestedRoute.addListener(_onRequestedRoute);
    // A request queued before the shell mounted (cold launch from a shortcut).
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRequestedRoute());
  }

  @override
  void dispose() {
    requestedRoute.removeListener(_onRequestedRoute);
    super.dispose();
  }

  /// Selects the tab a quick action or notification asked for, then clears the
  /// request so it cannot fire twice. Unknown routes are ignored.
  void _onRequestedRoute() {
    final route = requestedRoute.value;
    if (route == null || !mounted) return;
    // Before auth resolves there is no inner navigator to push on; leave the
    // request pending and [build] retries once the shell is up.
    if (innerNavigatorKey.currentState == null) return;
    final option = routeConfig[route];
    requestedRoute.value = null;
    if (option == null) return;
    _onItemTapped(option.index);
  }

  void _showDividerDialog(bool isBacklog) async {
    HapticFeedback.mediumImpact();
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Divider'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Label (optional)'),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => Navigator.of(context).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (label == null) return;
    final date = isBacklog ? null : DateService().getString(DateService().getSelectedDate());
    await TaskService().addDivider(label, date);
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) {
      return;
    }
    String route = routeConfig.entries.firstWhere((entry) => entry.value.index == index).key;
    innerNavigatorKey.currentState?.pushReplacementNamed(route);
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showGoalsCreateChooser() {
    showAppSheet(
      context,
      isScrollControlled: false,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(FontAwesomeIcons.bullseye),
              title: const Text('New Goal'),
              subtitle: const Text('AI-generated tasks toward a target'),
              onTap: () {
                Navigator.pop(ctx);
                showAppSheet(
                  context,
                  builder: (_) => const GoalForm(),
                );
              },
            ),
            ListTile(
              leading: const Icon(FontAwesomeIcons.fire),
              title: const Text('New Habit'),
              subtitle: const Text('A recurring routine you build a streak on'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HabitForm()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildFloatingActionButton() {
    switch (_selectedIndex) {
      case 0:
        return GestureDetector(
          onLongPress: () => _showDividerDialog(false),
          child: FloatingActionButton(
            child: const Icon(FontAwesomeIcons.plus, size: 20),
            onPressed: () => showAppSheet(
              context,
              builder: (BuildContext context) => const AddTaskScreen(isBacklog: false),
            ),
          ),
        );
      case 1:
        return FloatingActionButton(
          child: const Icon(FontAwesomeIcons.plus, size: 20),
          onPressed: () => showAppSheet(
            context,
            builder: (BuildContext context) => const WorkItemForm(),
          ),
        );
      case 2:
        return FloatingActionButton(
          child: const Icon(FontAwesomeIcons.plus, size: 20),
          onPressed: () => showAppSheet(
            context,
            builder: (BuildContext context) => const AccomplishmentForm(),
          ),
        );
      case 3:
        return FloatingActionButton(
          onPressed: _showGoalsCreateChooser,
          child: const Icon(FontAwesomeIcons.plus, size: 20),
        );
      case 4:
        return GestureDetector(
          onLongPress: () => _showDividerDialog(true),
          child: FloatingActionButton(
            child: const Icon(FontAwesomeIcons.plus, size: 20),
            onPressed: () => showAppSheet(
              context,
              builder: (BuildContext context) => const AddTaskScreen(isBacklog: true),
            ),
          ),
        );
      // Index 5 (People) supplies its own FloatingActionButton from within
      // PeopleListPage, so the home shell must not add a second one.
      default:
        return null;
    }
  }

  /// The phone tab bar.
  Widget _buildBottomNav(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).appTokens.hairline)),
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        items: routeConfig.values.map((route) {
          return BottomNavigationBarItem(
            icon: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Icon(route.icon, size: 19),
            ),
            label: route.label,
            tooltip: route.label,
          );
        }).toList(),
        onTap: _onItemTapped,
      ),
    );
  }

  /// The wide-screen navigation rail. Same destinations, same order, same
  /// handler as the tab bar; [extended] adds labels beside the icons.
  Widget _buildRail(BuildContext context, {required bool extended}) {
    final theme = Theme.of(context);
    return NavigationRail(
      key: const Key('home-rail'),
      extended: extended,
      minExtendedWidth: 208,
      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      groupAlignment: -1,
      backgroundColor: theme.scaffoldBackgroundColor,
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onItemTapped,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(Insets.sm, Insets.md, Insets.sm, Insets.xl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Corners.sm),
              child: Image.asset('assets/images/logo.png', height: 36, width: 36),
            ),
            if (extended) ...[
              const SizedBox(width: Insets.md),
              Text('Taskr', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
      destinations: routeConfig.values
          .map((route) => NavigationRailDestination(
                icon: Icon(route.icon, size: 19),
                label: Text(route.label),
                padding: const EdgeInsets.symmetric(vertical: Insets.xs),
              ))
          .toList(),
    );
  }

  /// Wide screens have room to surface the two everyday destinations as
  /// buttons; the rest stay in the overflow menu.
  List<Widget> _buildWideActions(BuildContext context) {
    return [
      IconButton(
        key: const Key('home-notifications'),
        tooltip: 'Notifications',
        icon: StreamBuilder<int>(
          stream: NotificationService().unreadCount(),
          builder: (context, snap) {
            final count = snap.data ?? 0;
            return Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: const Icon(FontAwesomeIcons.bell, size: 18),
            );
          },
        ),
        onPressed: () => Navigator.pushNamed(context, '/notifications'),
      ),
      IconButton(
        key: const Key('home-settings'),
        tooltip: 'Settings',
        icon: const Icon(FontAwesomeIcons.gear, size: 18),
        onPressed: () => Navigator.pushNamed(context, '/settings'),
      ),
      _buildOverflowMenu(context, withBadge: false),
      const SizedBox(width: Insets.sm),
    ];
  }

  /// The hamburger menu. On a phone it holds every destination and carries
  /// the unread badge; on wide screens only what the app bar buttons do not.
  Widget _buildOverflowMenu(BuildContext context, {required bool withBadge}) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'notifications') {
          Navigator.pushNamed(context, '/notifications');
        } else if (value == 'settings') {
          Navigator.pushNamed(context, '/settings');
        } else if (value == 'about') {
          Navigator.pushNamed(context, '/about');
        } else if (value == 'logout') {
          AuthService().signOut();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (withBadge) ...const [
          PopupMenuItem<String>(
            value: 'notifications',
            child: Text('Notifications'),
          ),
          PopupMenuItem<String>(
            value: 'settings',
            child: Text('Settings'),
          ),
        ],
        const PopupMenuItem<String>(
          value: 'about',
          child: Text('About'),
        ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Text('Logout'),
        ),
      ],
      icon: withBadge
          ? StreamBuilder<int>(
              stream: NotificationService().unreadCount(),
              builder: (context, snap) {
                final count = snap.data ?? 0;
                return Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(FontAwesomeIcons.bars),
                );
              },
            )
          : const Icon(FontAwesomeIcons.bars),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService().userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        if (snapshot.hasError) {
          return const Center(
            child: ErrorMessage(),
          );
        }

        if (snapshot.hasData == false) {
          return const LoginScreen();
        }

        if (requestedRoute.value != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _onRequestedRoute());
        }
        final currentLabel = routeConfig.values
            .firstWhere((r) => r.index == _selectedIndex, orElse: () => routeConfig['/']!)
            .label;
        final layout = layoutSizeOf(context);
        final page = Scaffold(
          appBar: AppBar(
            title: Text(currentLabel),
            actions: layout.isCompact
                ? [_buildOverflowMenu(context, withBadge: true)]
                : _buildWideActions(context),
          ),
          body: Navigator(
            key: innerNavigatorKey,
            initialRoute: '/',
            onGenerateRoute: (setting) {
              final route = setting.name;
              final page = route == null
                  ? const LoadingScreen()
                  : (routeConfig[route]?.page ?? const Text('Unknown sub route'));
              // Fade-through between tabs; degrades to instant under reduced motion.
              return fadeThroughRoute((_) => page, settings: setting);
            },
          ),
          bottomNavigationBar: layout.isCompact ? _buildBottomNav(context) : null,
          floatingActionButton: _buildFloatingActionButton(),
        );
        if (layout.isCompact) return page;

        // Wide layout: a rail on the left, the page (app bar, content and its
        // FAB) in a centered column so nothing stretches across the window.
        return Scaffold(
          body: Row(
            children: [
              _buildRail(context, extended: layout == LayoutSize.expanded),
              VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).appTokens.hairline),
              Expanded(
                child: ContentColumn(
                  maxWidth: _selectedIndex == routeConfig['/performance']!.index
                      ? ContentWidths.dashboard
                      : ContentWidths.reading,
                  child: page,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
