import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/shared.dart';

import '../services/services.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var report = Provider.of<Report>(context);
    var user = AuthService().user;

    if (user != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(user.displayName ?? 'Profile'),
          actions: [
            ElevatedButton(
                child: Text('signout'),
                onPressed: () async {
                  await AuthService().signOut();
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (route) => false);
                }),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(
                        image: NetworkImage(user.photoURL ??
                            'https://www.gravatar.com/avatar/placeholer'))),
              ),
              Text(user.email ?? ''),
              const Spacer(),
              Text('${report.total}'),
              const Spacer(),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavBar(),
      );
    } else {
      return Scaffold(
        appBar: AppBar(
          title: Text('Profile'),
        ),
        bottomNavigationBar: BottomNavBar(),
      );
    }
  }
}
