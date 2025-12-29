import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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

        return Scaffold(
          appBar: AppBar(
            title: const Text('Taskr'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'settings') {
                    Navigator.pushNamed(context, '/settings');
                  } else if (value == 'logout') {
                    AuthService().signOut();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'settings',
                    child: Text('Settings'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Text('Logout'),
                  ),
                ],
                icon: const Icon(FontAwesomeIcons.bars),
              ),
            ],
          ),
          body: Navigator(
            key: innerNavigatorKey,
            initialRoute: '/',
            onGenerateRoute: (setting) {
              Widget page;
              if (setting.name == null) {
                page = const LoadingScreen();
              }
              final route = setting.name!;
              page = routeConfig[route]?.page ?? const Text('Unknown sub route');
              return MaterialPageRoute(builder: (_) => page);
            },
          ),
          bottomNavigationBar: const BottomNavBar(),
          floatingActionButton: FloatingActionButton(
            child: const Icon(FontAwesomeIcons.plus, size: 20),
            onPressed: () => showModalBottomSheet(
              isScrollControlled: true,
              useSafeArea: true,
              context: context,
              builder: (BuildContext context) => const AddTaskScreen(isBacklog: false),
            ),
          ),
        );
      },
    );
  }
}
