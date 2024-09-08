import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/home/home.dart';

class BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  const BottomNavBar({super.key, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: selectedIndex,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.grey,
      showUnselectedLabels: true,
      selectedLabelStyle: TextStyle(shadows: [
        Shadow(
            blurRadius: 4.0, offset: const Offset(3.0, 3.0), color: Colors.grey.withOpacity(0.5)),
      ]),
      items: const [
        BottomNavigationBarItem(
            icon: Icon(
              FontAwesomeIcons.listCheck,
              size: 20,
            ),
            label: 'List',
            tooltip: 'List'),
        BottomNavigationBarItem(
            icon: Icon(
              FontAwesomeIcons.gaugeHigh,
              size: 20,
            ),
            label: 'Performance',
            tooltip: 'Performance'),
        BottomNavigationBarItem(
            icon: Icon(
              FontAwesomeIcons.tableColumns,
              size: 20,
            ),
            label: 'Backlog',
            tooltip: 'Backlog'),
        BottomNavigationBarItem(
            icon: Icon(
              FontAwesomeIcons.gear,
              size: 20,
            ),
            label: 'Settings',
            tooltip: 'Settings'),
      ],
      backgroundColor: Colors.black,
      onTap: (int idx) {
        if (idx == selectedIndex) {
          return;
        }
        switch (idx) {
          case 0:
            Navigator.pushAndRemoveUntil(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const HomeScreen(isBacklog: false),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(-1.0, 0.0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ));
                  },
                ),
                (route) => false);
            break;
          case 1:
            Navigator.pushNamedAndRemoveUntil(context, '/performance', (route) => false);
            break;
          case 2:
            Navigator.pushAndRemoveUntil(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const HomeScreen(isBacklog: true),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(1.0, 0.0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ));
                  },
                ),
                (route) => false);
            break;
          case 3:
            Navigator.pushNamedAndRemoveUntil(context, '/settings', (route) => false);
            break;
        }
      },
    );
  }
}
