import 'package:flutter/material.dart';
import 'package:taskr/routing.dart';

class BottomNavBar extends StatefulWidget {
  const BottomNavBar({super.key});

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: selectedIndex,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.grey,
      showUnselectedLabels: true,
      selectedLabelStyle: TextStyle(shadows: [
        Shadow(blurRadius: 4.0, offset: const Offset(3.0, 3.0), color: Colors.grey.withAlpha(128)),
      ]),
      items: routeConfig.values.map((route) {
        return BottomNavigationBarItem(
          icon: Icon(route.icon, size: 20),
          label: route.label,
          tooltip: route.label,
        );
      }).toList(),
      backgroundColor: Colors.black,
      onTap: (int idx) {
        if (idx == selectedIndex) {
          return;
        }
        String route = routeConfig.entries.firstWhere((entry) => entry.value.index == idx).key;
        innerNavigatorKey.currentState?.pushReplacementNamed(route);
        setState(() => selectedIndex = idx);
        // switch (idx) {
        //   case 0:
        //     Navigator.pushAndRemoveUntil(
        //         context,
        //         PageRouteBuilder(
        //           pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        //           transitionsBuilder: (context, animation, secondaryAnimation, child) {
        //             return FadeTransition(
        //                 opacity: animation,
        //                 child: SlideTransition(
        //                   position: Tween<Offset>(
        //                     begin: const Offset(-1.0, 0.0),
        //                     end: Offset.zero,
        //                   ).animate(animation),
        //                   child: child,
        //                 ));
        //           },
        //         ),
        //         (route) => false);
        //     break;
        //   case 1:
        //     Navigator.pushNamedAndRemoveUntil(context, '/performance', (route) => false);
        //     break;
        // }
      },
    );
  }
}
