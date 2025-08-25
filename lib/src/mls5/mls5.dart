import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:lib5/src/util/big_endian.dart';
import 'package:lib5/util.dart';
import 'package:ntp/ntp.dart';
import 'package:s5/s5.dart';
import 'package:s5/src/hive_key_value_db.dart';
import 'package:s5_messenger/src/mls5/state/messenger.dart';
import 'package:s5_messenger/src/rust/api/simple.dart';
import 'package:s5_messenger/src/rust/frb_generated.dart';
import 'package:hive_ce/hive.dart';

import '../mls5/util/state.dart';
import '../mls5/model/message.dart';

// TODO There are too many saveKeyStore() calls in here, some of them are redundant and can be removed

/// Main class for MLS (Messaging Layer Security) functionality in the S5 messenger.
/// Handles group creation, message encryption/decryption, and member management.
class S5Messenger {
  final messengerState = MessengerState();

  late final Box dataBox;
  late final Box groupsBox;
  late final Box groupCursorBox;

  late final Box messageStoreBox;

  late final Box keystoreBox;
  // late final KeyValueDB groupStateDB;

  late final OpenMlsConfig config;
  late final S5 s5;
  late Logger logger;

  CryptoImplementation get crypto => s5.crypto;

  final RustLibApi rust = RustLib.instance.api;

  Future<void> init(S5 inputS5, [String prefix = 'default']) async {
    logger = SimpleLogger(prefix: "[s5_messenger]");
    s5 = inputS5;
    dataBox = await Hive.openBox('s5-messenger-data');
    groupsBox = await Hive.openBox('s5-messenger-groups');
    final databaseEncryptionKey = Uint8List(32);

    messageStoreBox = await Hive.openBox(
      's5-messenger-messages',
      encryptionCipher: HiveAesCipher(databaseEncryptionKey),
    );

    // ! if it breaks
    // groupsBox.clear();

    groupCursorBox = await Hive.openBox('s5-messenger-groups-cursor');

    keystoreBox = /*  HiveKeyValueDB( */ await Hive.openBox('$prefix-keystore');
    // groupStateDB = HiveKeyValueDB(await Hive.openBox('group_state'));

    config = await rust.crateApiSimpleOpenmlsInitConfig(
      keystoreDump:
          (keystoreBox.get('dump')?.cast<int>() ?? <int>[]) as List<int>,
    );
    logger.info('Initialized Rust!');

    await setupIdentity();

    Future.delayed(Duration(seconds: 1)).then((value) async {
      await recoverGroups();
      messengerState.update();
    });

    _setupTimeSync();
  }

  Duration timeOffset = Duration.zero;

  void _setupTimeSync() async {
    try {
      int offsetMillis = await NTP.getNtpOffset(localTime: DateTime.now());
      timeOffset = Duration(milliseconds: offsetMillis);
      logger.info('timeOffset $timeOffset');
    } catch (e, st) {
      logger.error(e.toString());
      logger.error(st.toString());
    }
  }

  Future<HiveKeyValueDB> openDB(String key) async {
    return HiveKeyValueDB(await Hive.openBox<Uint8List>('s5-node-$key'));
  }

  Future<void> saveKeyStore() async {
    logger.info('saveKeyStore');
    keystoreBox.put(
      'dump',
      await rust.crateApiSimpleOpenmlsKeystoreDump(config: config),
    );
  }

  late final MlsCredential identity;

  Future<void> setupIdentity() async {
    const key = 'identity_default';
    if (dataBox.containsKey(key)) {
      final data = dataBox.get(key) as Map;
      identity = await openmlsRecoverCredentialWithKey(
        identity: utf8.encode(data['identity']),
        publicKey: base64UrlNoPaddingDecode(data['publicKey']),
        config: config,
      );
      logger.info('$key recovered');
    } else {
      final username = 'User #${Random().nextInt(1000)}';
      identity = await openmlsGenerateCredentialWithKey(
        identity: utf8.encode(username),
        config: config,
      );
      final publicKey = await openmlsSignerGetPublicKey(
        signer: identity.signer,
      );

      dataBox.put(key, {
        'identity': username,
        'publicKey': base64UrlNoPaddingEncode(publicKey),
      });
      print('$key created');
    }
    await saveKeyStore();
  }

  final groups = <String, GroupState>{};

  GroupState group(String id) => groups[id]!;

  Future<GroupState> createNewGroup(String? name) async {
    final group = await openmlsGroupCreate(
      signer: identity.signer,
      credentialWithKey: identity.credentialWithKey,
      config: config,
    );
    final groupId = base64UrlNoPaddingEncode(
      await openmlsGroupSave(group: group, config: config),
    );
    await saveKeyStore();

    GroupState newGroup = GroupState(
      groupId,
      group: group,
      channel: await deriveCommunicationChannelKeyPair(groupId),
      mls: this,
    );
    newGroup.init();
    groups[groupId] = newGroup;

    groupsBox.put(groupId, {
      'id': groupId,
      'name': (name != null) ? name : 'Group #${groupsBox.length + 1}',
    });

    messengerState.update();

    return newGroup;
  }

  Future<void> leaveGroup(GroupState groupState) async {
    await openmlsGroupLeave(
        group: groupState.group, signer: identity.signer, config: config);
    groups.remove(groupState.groupId);
    groupsBox.delete(groupState.groupId);
    messengerState.update();
  }

  Future<KeyPairEd25519> deriveCommunicationChannelKeyPair(String groupId) {
    // TODO Better impl
    return crypto.newKeyPairEd25519(
      seed: crypto.hashBlake3Sync(
        base64UrlNoPaddingDecode(groupId),
        /*    5,
        crypto: node.crypto, */
      ),
    );
  }

  Future<void> recoverGroups() async {
    for (final id in groupsBox.keys) {
      final group = await openmlsGroupLoad(
        id: base64UrlNoPaddingDecode(id),
        config: config,
      );
      groups[id] = GroupState(
        id,
        group: group,
        channel: await deriveCommunicationChannelKeyPair(id),
        mls: this,
      );
      groups[id]!.init();
    }
    await saveKeyStore();
  }

  Future<Uint8List> createKeyPackage() async {
    final keyPackage = await openmlsGenerateKeyPackage(
      signer: identity.signer,
      credentialWithKey: identity.credentialWithKey,
      config: config,
    );
    await saveKeyStore();
    return keyPackage;
  }

  Future<String> acceptInviteAndJoinGroup(Uint8List welcomeIn, String senderID,
      String messageID, Uint8List? embed) async {
    final group = await openmlsGroupJoin(welcomeIn: welcomeIn, config: config);
    // TODO Prevent duplicate ID overwrite attacks!
    final groupId = base64UrlNoPaddingEncode(
      await openmlsGroupSave(group: group, config: config),
    );
    await saveKeyStore();

    groups[groupId] = GroupState(
      groupId,
      group: group,
      channel: await deriveCommunicationChannelKeyPair(groupId),
      mls: this,
    );
    groups[groupId]!.init();

    groupsBox.put(groupId, {
      'id': groupId,
      'name': 'Group #${groupsBox.length + 1}',
    });
    groups[groupId]!
        .sendMessage('joined the group', embed, senderID, messageID);
    return groupId;
  }

  Future<String> acceptInviteAndJoinGroupExternalCommit(
      Uint8List verifiableGroupInfoIn,
      String senderID,
      String messageID,
      Uint8List? embed) async {
    final (MlsGroup group, Uint8List commitToPropagate) =
        await openmlsGroupJoinByExternalCommit(
            verifiableGroupInfoIn: verifiableGroupInfoIn,
            signer: identity.signer,
            credentialWithKey: identity.credentialWithKey,
            config: config);
    // TODO: Prevent duplicate ID overwrite attacks!
    final String groupId = base64UrlNoPaddingEncode(
      await openmlsGroupSave(group: group, config: config),
    );
    await saveKeyStore();

    groups[groupId] = GroupState(
      groupId,
      group: group,
      channel: await deriveCommunicationChannelKeyPair(groupId),
      mls: this,
    );
    groups[groupId]!.init();

    groupsBox.put(groupId, {
      'id': groupId,
      'name': 'Group #${groupsBox.length + 1}',
    });

    groups[groupId]!.sendMessageToStreamChannel(commitToPropagate);
    // TODO: This is a supid wait, should wait for new incoming messages before sending join message
    groups[groupId]!
        .sendMessage('joined the group', embed, senderID, messageID);
    return groupId;
  }
}

class GroupState {
  final String groupId;
  GroupState(
    this.groupId, {
    required this.group,
    required this.channel,
    required this.mls,
  });

  final S5Messenger mls;

  final ignoreMessageIds = <int>{};
  final MlsGroup group;
  final KeyPairEd25519 channel;

  bool isInitialized = false;

  final messageListStateNotifier = StateNotifier();

  final membersStateNotifier = StateNotifier();
  List<GroupMember> members = [];
  // GroupMember? self;

  void init() {
    if (isInitialized) return;
    isInitialized = true;
    listenForIncomingMessages();
    initGroupMemberListSync();
  }

  void listenForIncomingMessages() async {
    // messagesTemp[groupId] = [];

    await for (final event in mls.s5.api.streamSubscribe(
      channel.publicKey,
      afterTimestamp: mls.groupCursorBox.get(groupId),
    )) {
      Logger logger = SimpleLogger(prefix: "[s5_messenger]");
      logger.info('debug1 incoming $groupId ${event.ts}');
      try {
        if (ignoreMessageIds.contains(event.ts)) {
          logger.info('debug1 ignore incoming message $groupId ${event.ts}');
          await mls.groupCursorBox.put(groupId, event.ts);
          return;
        }
        if ((mls.groupCursorBox.get(groupId) ?? -1) >= event.ts) {
          logger.info('skipping message, unexpected ts');
          return;
        }
        try {
          final res = await openmlsGroupProcessIncomingMessage(
            group: group,
            mlsMessageIn: event.data,
            config: mls.config,
          );
          await mls.saveKeyStore();
          if (res.isApplicationMessage) {
            logger.info('processed incoming message, epoch is ${res.epoch}');

            final msg =
                MLSApplicationMessage.fromProcessIncomingMessageResponse(
              res,
              event.ts,
            );
            _processNewMessage(msg);
          } else {
            refreshGroupMemberList();
          }
        } catch (e) {
          logger.error("Failed to decrypt message");
          logger.error(e.toString());
        }

        await mls.groupCursorBox.put(groupId, event.ts);
      } catch (e, st) {
        logger.error(e.toString());
        logger.error(st.toString());
      }
    }
  }

  void _processNewMessage(MLSApplicationMessage msg) {
    messagesMemory.insert(0, msg);
    mls.messageStoreBox.put(makeKey(msg), msg.serialize());
    messageListStateNotifier.update();
  }

  bool canLoadMore = true;
  final messagesMemory = <MLSApplicationMessage>[];

  void loadMoreMessages() {
    final anchorLow = String.fromCharCodes(base64UrlNoPaddingDecode(groupId));
    final anchorHigh = messagesMemory.isEmpty
        ? String.fromCharCodes(base64UrlNoPaddingDecode(groupId) + [255])
        : makeKey(messagesMemory.last);
    final keys = mls.messageStoreBox.keys
        .where((k) => k.compareTo(anchorLow) > 0 && k.compareTo(anchorHigh) < 0)
        .toList();
    keys.sort((a, b) => b.compareTo(a));
    // print(keys);

    if (keys.length < 50) {
      canLoadMore = false;
    } else {
      keys.removeRange(50, keys.length);
    }
    for (final String k in keys) {
      messagesMemory.add(
        MLSApplicationMessage.deserialize(
          mls.messageStoreBox.get(k)!,
          decodeEndian(
            Uint8List.fromList(k.codeUnits.reversed.take(8).toList()),
          ),
        ),
      );
    }
    /*  if (keys.isEmpty) {
    } */

    messageListStateNotifier.update();
  }

  /*   void _loadMoreMessages() {
  } */

  String makeKey(MLSApplicationMessage msg) {
    // final seq = encodeEndian(msg.ts, 8);
    /*     
    return '$groupId/${msg.ts}'; */
    return String.fromCharCodes(
      Uint8List.fromList(
        base64UrlNoPaddingDecode(groupId) + encodeBigEndian(msg.ts, 8),
      ),
    );
  }

  void initGroupMemberListSync() {
    refreshGroupMemberList();
    // TODO Properly implement this
  }

  Future<void> refreshGroupMemberList() async {
    members = await openmlsGroupListMembers(group: group);

    // TODO This one is likely not needed
    await mls.saveKeyStore();
    /* try {
      final selfHash= Multihash(mls.identity)
      self = members.firstWhere((m) => Multihash(m.signatureKey)==);
    } catch (e, st) {
      // TODO Error handling
      print(e);
      print(st);
    } */
    membersStateNotifier.update();
  }

  Future<String> addMemberToGroup(Uint8List keyPackage) async {
    final MLSGroupAddMembersResponse res = await openmlsGroupAddMember(
      group: group,
      signer: mls.identity.signer,
      keyPackage: keyPackage,
      config: mls.config,
    );
    await mls.saveKeyStore();

    final ts = await sendMessageToStreamChannel(res.mlsMessageOut);
    await openmlsGroupSave(group: group, config: mls.config);

    refreshGroupMemberList();

    await mls.saveKeyStore();

    /*     return 's5messenger-group-invite:${base64UrlNoPaddingEncode(groupChannels[groupId]!.publicKey)}/$ts/${base64UrlNoPaddingEncode(res.welcomeOut)}'; */
    return 's5messenger-group-invite:${base64UrlNoPaddingEncode(res.welcomeOut)}';
  }

  Future<String> generateExternalCommitInvite() async {
    final Uint8List res = await openmlsGroupExportGroupInfo(
        group: group, signer: mls.identity.signer, config: mls.config);
    return base64UrlNoPaddingEncode(res);
  }

  Future<void> sendMessage(
      String text, Uint8List? embed, String senderID, String messageID) async {
    final msg = TextMessage(
        text: text,
        ts: DateTime.now().millisecondsSinceEpoch,
        embed: embed,
        senderId: senderID,
        messageId: messageID);
    final message = Uint8List.fromList(msg.prefix + msg.serialize());

    final payload = await openmlsGroupCreateMessage(
      group: group,
      signer: mls.identity.signer,
      message: message,
      config: mls.config,
    );
    final ts = await sendMessageToStreamChannel(payload);
    await mls.saveKeyStore();

    _processNewMessage(
      MLSApplicationMessage(
        msg: msg,
        identity: Uint8List(0),
        sender: Uint8List(0),
        ts: ts,
      ),
    );
  }

  Future<int> sendMessageToStreamChannel(Uint8List message) async {
    final msg = await SignedStreamMessage.create(
      kp: channel,
      data: message,
      ts: DateTime.now()
          .add(mls.timeOffset)
          .millisecondsSinceEpoch, // TODO Maybe use microseconds or seq numbers  to further avoid collisions on the s5 streams transport layer
      crypto: mls.crypto,
    );

    ignoreMessageIds.add(msg.ts);
    await mls.s5.api.streamPublish(msg);
    return msg.ts;
  }

  void rename(String newName) {
    final Map map = mls.groupsBox.get(groupId);
    map['name'] = newName;
    mls.groupsBox.put(groupId, map);
    mls.messengerState.update();
  }

  /*   final ignoreMessageIds = <String, Set<int>>{};
  final groups = <String, MlsGroup>{};
  final groupChannels = <String, KeyPairEd25519>{};
  final newMessageStreams = <String, StreamController<Message>>{};
  final messagesTemp = <String, List<Message>>{}; */
}
