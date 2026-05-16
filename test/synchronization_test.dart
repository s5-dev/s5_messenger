import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:s5_messenger/s5_messenger.dart';
import 'package:s5_messenger/src/rust/frb_generated.dart';
import 'package:lib5/lib5.dart';
import 'helpers/mocks.dart';
import 'helpers/test_setup.dart';

void main() {
  final t = TestSetup();

  setUpAll(() async {
    RustLib.initMock(api: MockRustLibApi());
  });

  setUp(() async => await t.setup());
  tearDown(() async => await t.tearDown());

  test('Out-of-Order Messages Test', () async {
    final group = await t.messenger.createNewGroup('OOO Group');
    
    final ts2 = DateTime.now().millisecondsSinceEpoch;
    final ts1 = ts2 - 1000;
    
    final payload1 = await t.messenger.rust.crateApiSimpleOpenmlsGroupCreateMessage(
        group: group.group,
        signer: t.messenger.identity.signer,
        message: Uint8List.fromList(TextMessage(text: 'Older Message', ts: ts1, senderId: 's', messageId: 'm1').prefix + TextMessage(text: 'Older Message', ts: ts1, senderId: 's', messageId: 'm1').serialize()),
        config: t.messenger.config,
    );

    final payload2 = await t.messenger.rust.crateApiSimpleOpenmlsGroupCreateMessage(
        group: group.group,
        signer: t.messenger.identity.signer,
        message: Uint8List.fromList(TextMessage(text: 'Newer Message', ts: ts2, senderId: 's', messageId: 'm2').prefix + TextMessage(text: 'Newer Message', ts: ts2, senderId: 's', messageId: 'm2').serialize()),
        config: t.messenger.config,
    );

    final msg1 = await SignedStreamMessage.create(
        kp: group.channel,
        data: payload1,
        ts: ts1,
        crypto: t.mockS5.crypto,
    );

    final msg2 = await SignedStreamMessage.create(
        kp: group.channel,
        data: payload2,
        ts: ts2,
        crypto: t.mockS5.crypto,
    );

    t.mockS5.mockApi.emit(msg2); // Newer first
    await Future.delayed(Duration(milliseconds: 100));
    t.mockS5.mockApi.emit(msg1); // Older second
    await Future.delayed(Duration(milliseconds: 100));

    expect(group.messagesMemory.length, greaterThanOrEqualTo(2));
    expect(group.messagesMemory.first.ts, ts2);
    expect(group.messagesMemory.last.ts, ts1);
  });

  test('Clock Skew Test', () async {
    final group = await t.messenger.createNewGroup('Skew Group');
    t.messenger.timeOffset = Duration(hours: 1);
    
    await group.sendMessage('Skews message', null, 'sender', 'skew-id');
    await Future.delayed(Duration(milliseconds: 100));
    
    final msgTs = group.messagesMemory.first.ts;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    expect(msgTs, greaterThan(now + Duration(minutes: 55).inMilliseconds));
  });

  test('Pagination Test', () async {
    final group = await t.messenger.createNewGroup('Paging Group');
    
    for (int i = 0; i < 100; i++) {
       final msg = MLSApplicationMessage(
           msg: TextMessage(text: 'Msg $i', ts: i, senderId: 's', messageId: 'i$i'),
           identity: Uint8List(0),
           sender: Uint8List(0),
           ts: i,
       );
       t.messenger.messageStoreBox.put(group.makeKey(msg), msg.serialize());
    }
    
    expect(group.messagesMemory.isEmpty, true);
    group.loadMoreMessages();
    expect(group.messagesMemory.length, 50);
    expect(group.canLoadMore, true);
    
    group.loadMoreMessages();
    expect(group.messagesMemory.length, 100);
    expect(group.canLoadMore, false);
  });
}
