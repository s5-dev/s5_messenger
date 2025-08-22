import 'dart:convert';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lib5/util.dart';
import 'package:s5_messenger_example/main.dart';
import 'package:s5_messenger/s5_messenger.dart';
import 'package:uuid/uuid.dart';

/// This is a demo of how to handle group chats & subscriptions
class GroupChatView extends StatefulWidget {
  final String id;
  GroupChatView(this.id) : super(key: ValueKey('group-chat-$id'));

  @override
  State<GroupChatView> createState() => _GroupChatViewState();
}

class _GroupChatViewState extends State<GroupChatView> {
  final textCtrl = TextEditingController();
  final textCtrlFocusNode = FocusNode();

  GroupState get group => s5messenger.group(widget.id);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: Column(
          children: [
            Expanded(
              child: StreamBuilder<void>(
                stream: group.messageListStateNotifier.stream,
                builder: (context, snapshot) {
                  // On each rebuild print the embed (which should be 7, to demonstrate embedding)
                  if (group.messagesMemory.isNotEmpty) {
                    final TextMessage message =
                        (group.messagesMemory.first.msg as TextMessage);
                    logger.info("The embed is: ${message.embed}");
                  }
                  return ListView.builder(
                    reverse: true,
                    itemCount: group.messagesMemory.length +
                        (group.canLoadMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == group.messagesMemory.length) {
                        group.loadMoreMessages();
                        return Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      final msg = group.messagesMemory[index];
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Text(
                              DateTime.fromMillisecondsSinceEpoch(msg.ts)
                                  .toIso8601String()
                                  .substring(11, 19),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              msg.identity.isEmpty
                                  ? 'You'
                                  : utf8.decode(msg.identity),
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child:
                                  SelectableText((msg.msg as TextMessage).text),
                            ),
                            /* SelectableText(msg.ts.toString()), */
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                focusNode: textCtrlFocusNode,
                controller: textCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Your message',
                ),
                onSubmitted: (text) async {
                  // Also send along an embed of 7 to test decoding on the other end
                  await group.sendMessage(
                      text, Uint8List.fromList([7]), userID, Uuid().v4());
                  textCtrl.clear();
                  textCtrlFocusNode.requestFocus();
                },
              ),
            ),
          ],
        )),
        SizedBox(
          width: 256,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final res = await showTextInputDialog(
                          context: context,
                          textFields: [
                            DialogTextField(
                                hintText: 's5-messenger-key-package:')
                          ],
                        );
                        if (res == null) return;
                        final String kp = res.first;
                        logger.info(kp);
                        if (!kp.startsWith('s5-messenger-key-package:'))
                          throw 'TODO1';
                        final bytes = base64UrlNoPaddingDecode(
                          kp.substring(25),
                        );
                        print(bytes);

                        final welcomeMessage =
                            await group.addMemberToGroup(bytes);

                        print(welcomeMessage);

                        Clipboard.setData(
                          ClipboardData(
                            text: welcomeMessage,
                          ),
                        );

                        /* final kp = await mls.createKeyPackage();

                        */
                      },
                      child: Text(
                        'Invite User',
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final String inviteToken =
                            await group.generateExternalCommitInvite();
                        logger.info("Invite token: $inviteToken");
                        Clipboard.setData(
                          ClipboardData(
                            text: inviteToken,
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied invite token to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: Text(
                        'Generate Group Info',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<void>(
                  stream: group.membersStateNotifier.stream,
                  builder: (context, snapshot) {
                    return ListView(
                      children: [
                        for (final member in group.members)
                          ListTile(
                            title: Text(utf8.decode(member.identity)),
                          )
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}
