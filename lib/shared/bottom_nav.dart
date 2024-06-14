import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
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
        switch (idx) {
          case 0:
            // do nothing
            break;
          case 1:
            Navigator.pushNamed(context, '/performance');
            break;
          case 2:
            Navigator.pushNamed(context, '/backlog');
            break;
          case 3:
            Navigator.pushNamed(context, '/settings');
            break;
        }
      },
    );
  }
}
