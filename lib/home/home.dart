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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

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
    showModalBottomSheet(
      context: context,
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
                showModalBottomSheet(
                  isScrollControlled: true,
                  useSafeArea: true,
                  context: context,
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
            onPressed: () => showModalBottomSheet(
              isScrollControlled: true,
              useSafeArea: true,
              context: context,
              builder: (BuildContext context) => const AddTaskScreen(isBacklog: false),
            ),
          ),
        );
      case 1:
        return FloatingActionButton(
          child: const Icon(FontAwesomeIcons.plus, size: 20),
          onPressed: () => showModalBottomSheet(
            isScrollControlled: true,
            useSafeArea: true,
            context: context,
            builder: (BuildContext context) => const AccomplishmentForm(),
          ),
        );
      case 2:
        return FloatingActionButton(
          onPressed: _showGoalsCreateChooser,
          child: const Icon(FontAwesomeIcons.plus, size: 20),
        );
      case 3:
        return GestureDetector(
          onLongPress: () => _showDividerDialog(true),
          child: FloatingActionButton(
            child: const Icon(FontAwesomeIcons.plus, size: 20),
            onPressed: () => showModalBottomSheet(
              isScrollControlled: true,
              useSafeArea: true,
              context: context,
              builder: (BuildContext context) => const AddTaskScreen(isBacklog: true),
            ),
          ),
        );
      // Index 4 (People) supplies its own FloatingActionButton from within
      // PeopleListPage, so the home shell must not add a second one.
      default:
        return null;
    }
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

        final currentLabel = routeConfig.values
            .firstWhere((r) => r.index == _selectedIndex, orElse: () => routeConfig['/']!)
            .label;
        return Scaffold(
          appBar: AppBar(
            title: Text(currentLabel),
            actions: [
              PopupMenuButton<String>(
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
                  const PopupMenuItem<String>(
                    value: 'notifications',
                    child: Text('Notifications'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'settings',
                    child: Text('Settings'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'about',
                    child: Text('About'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Text('Logout'),
                  ),
                ],
                icon: StreamBuilder<int>(
                  stream: NotificationService().unreadCount(),
                  builder: (context, snap) {
                    final count = snap.data ?? 0;
                    return Badge(
                      isLabelVisible: count > 0,
                      label: Text('$count'),
                      child: const Icon(FontAwesomeIcons.bars),
                    );
                  },
                ),
              ),
            ],
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
          bottomNavigationBar: DecoratedBox(
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
          ),
          floatingActionButton: _buildFloatingActionButton(),
        );
      },
    );
  }
}
