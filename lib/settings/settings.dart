import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/tag.provider.dart';
import 'package:taskr/shared/bottom_nav.dart';
import 'package:taskr/shared/error.dart';
import 'package:taskr/shared/loading.dart';
import 'package:taskr/task_list/add_tag.dart';

import '../services/services.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService().userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        } else if (snapshot.hasError) {
          return const Center(
            child: ErrorMessage(),
          );
        } else if (snapshot.hasData) {
          // Will be null if user is not logged in
          return SettingsForm(userId: snapshot.data!.uid);
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

class SettingsForm extends StatefulWidget {
  final String userId;
  const SettingsForm({super.key, required this.userId});

  @override
  State<StatefulWidget> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsForm> {
  bool isShowingAll = true;

  @override
  Widget build(BuildContext context) {
    var tagProvider = Provider.of<TagProvider>(context);
    var tags = tagProvider.tags;
    return Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          actions: [
            IconButton(onPressed: () => AuthService().signOut(), icon: const Icon(FontAwesomeIcons.userAstronaut))
          ],
        ),
        body: ListView(
          scrollDirection: Axis.vertical,
          children: [
            const Text("Tags", style: TextStyle(fontSize: 32)),
            Container(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: tags.map((Tag tag) {
                  return Row(children: [
                    Text(
                      tag.label,
                    ),
                    IconButton(
                        onPressed: () =>
                            showDialog(context: context, builder: (BuildContext context) => AddTagScreen(tag: tag)),
                        icon: const Icon(FontAwesomeIcons.penToSquare)),
                    IconButton(
                      onPressed: () => tagProvider.deleteTag(tag.id),
                      icon: const Icon(FontAwesomeIcons.trashCan),
                    )
                  ]);
                }).toList(),
              ),
            )
          ],
        ),
        bottomNavigationBar: const BottomNavBar(
          selectedIndex: 4,
        ),
        floatingActionButton: FloatingActionButton(
            child: const Icon(FontAwesomeIcons.plus, size: 20),
            onPressed: () => showDialog(context: context, builder: (BuildContext context) => const AddTagScreen())));
  }
}
