import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:lib5/util.dart';
import 'package:flutter/services.dart';
import 'package:s5_messenger_example/main.dart';
import 'package:uuid/uuid.dart';

class GroupListView extends StatefulWidget {
  const GroupListView({super.key});

  @override
  State<GroupListView> createState() => _GroupListViewState();
}

class _GroupListViewState extends State<GroupListView> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: s5messenger.messengerState.stream,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          return ListView(
            children: [
              for (final group in s5messenger.groupsBox.values)
                ListTile(
                  onTap: () {
                    s5messenger.messengerState.groupId = group['id'];
                    s5messenger.messengerState.update();
                  },
                  title: Text(group['name']),
                  subtitle: Text(group['id']),
                  enabled: s5messenger.groups.isNotEmpty,
                  selected: s5messenger.messengerState.groupId == group['id'],
                  selectedTileColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  trailing: PopupMenuButton<String>(
                    onSelected: (String value) async {
                      // Handle menu item selection
                      switch (value) {
                        case 'leave':
                          final currentGroupId = group['id'];
                          // Clear the current group selection if it's the one being deleted
                          if (s5messenger.messengerState.groupId ==
                              currentGroupId) {
                            s5messenger.messengerState.groupId = null;
                            s5messenger.messengerState.update();
                          }
                          // Leave the group
                          await s5messenger
                              .leaveGroup(s5messenger.group(currentGroupId));
                          break;
                        case 'rename':
                          final res = await showTextInputDialog(
                            context: context,
                            textFields: [
                              DialogTextField(
                                  hintText: 'Edit Group Name (local)'),
                            ],
                          );
                          if (res == null) return;
                          s5messenger.group(group['id']).rename(res.first);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit),
                            Center(
                              child: Text('Rename'),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'leave',
                        child: Row(
                          children: [
                            Icon(Icons.delete),
                            Center(
                              child: Text('Leave'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    icon: Icon(Icons.more_vert), // Icon to trigger the menu
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final res = await showTextInputDialog(
                          context: context,
                          textFields: [
                            DialogTextField(hintText: 'external commit group:')
                          ],
                        );
                        if (res == null) return;
                        final String welcome = res.first;

                        final groupId = await s5messenger
                            .acceptInviteAndJoinGroupExternalCommit(
                          base64UrlNoPaddingDecode(welcome),
                          userID,
                          Uuid().v4(),
                          null,
                        );
                        s5messenger.messengerState.groupId = groupId;
                        s5messenger.messengerState.update();
                      },
                      child: Text(
                        'Join Group',
                      ),
                    ),
                    SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () async {
                        await s5messenger.createNewGroup(null);
                        setState(() {});
                      },
                      child: Text(
                        'Create Group',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        });
  }
}
