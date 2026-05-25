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

  test('Reconnection Test - Stream Drop', () async {
    final group = await t.messenger.createNewGroup('Recon Group');
    await t.mockS5.mockApi.nextSubscription; // Wait for initial sub
    expect(t.mockS5.mockApi.subscriptionCount, 1);

    t.mockS5.mockApi.close();

    // Wait for the next subscription to happen (after 1s retry delay)
    await t.mockS5.mockApi.nextSubscription.timeout(const Duration(seconds: 2));

    await group.sendMessage('Message after drop', null, 'sender', 'msg-drop');
    await Future.delayed(const Duration(milliseconds: 100));

    expect(t.mockS5.mockApi.subscriptionCount, greaterThan(1), reason: 'Should have re-subscribed after closure');
  });

  test('Reconnection Test - Stream Error', () async {
    final group = await t.messenger.createNewGroup('Error Recon Group');
    await t.mockS5.mockApi.nextSubscription; // Wait for initial sub
    expect(t.mockS5.mockApi.subscriptionCount, 1);

    t.mockS5.mockApi.addError(Exception('Network Error'));

    // Wait for reconnection
    await t.mockS5.mockApi.nextSubscription.timeout(const Duration(seconds: 2));

    await group.sendMessage('Message after error', null, 'sender', 'msg-err');
    await Future.delayed(const Duration(milliseconds: 100));

    expect(t.mockS5.mockApi.subscriptionCount, greaterThan(1), reason: 'Should have re-subscribed after error');
  });

  test('Reconnection Test - Intermittent Drops', () async {
    final group = await t.messenger.createNewGroup('Choppy Group');
    await t.mockS5.mockApi.nextSubscription;

    for (int i = 0; i < 3; i++) {
        t.mockS5.mockApi.close();
        await t.mockS5.mockApi.nextSubscription.timeout(const Duration(seconds: 2));
        await group.sendMessage('Choppy $i', null, 'sender', 'c$i');
        await Future.delayed(const Duration(milliseconds: 50));
    }

    expect(t.mockS5.mockApi.subscriptionCount, greaterThan(3));
  });


  test('Node Sleep/Wake Simulation', () async {
    final group = await t.messenger.createNewGroup('Sleep Group');
    final startTs = DateTime.now().millisecondsSinceEpoch;
    
    t.mockS5.mockApi.close();
    await Future.delayed(Duration(milliseconds: 100));
    
    final payloadWhileAsleep = await t.messenger.rust.crateApiSimpleOpenmlsGroupCreateMessage(
            group: group.group,
            signer: t.messenger.identity.signer,
            message: Uint8List.fromList(TextMessage(text: 'Missed you', ts: startTs + 1000, senderId: 'other', messageId: 'm1').prefix + TextMessage(text: 'Missed you', ts: startTs + 1000, senderId: 'other', messageId: 'm1').serialize()),
            config: t.messenger.config,
        );
    final msgWhileAsleep = await SignedStreamMessage.create(
        kp: group.channel,
        data: payloadWhileAsleep,
        ts: startTs + 1000,
        crypto: t.mockS5.crypto,
    );
    t.mockS5.mockApi.emit(msgWhileAsleep);

    await group.sendMessage('Waking up', null, 'sender', 'wake-id');
    await Future.delayed(Duration(milliseconds: 500));

    expect(group.messagesMemory.any((m) => (m.msg as TextMessage).text == 'Missed you'), true, reason: 'History sync failed');
  });
}
