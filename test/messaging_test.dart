import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:s5_messenger/s5_messenger.dart';
import 'package:s5_messenger/src/rust/frb_generated.dart';
import 'helpers/mocks.dart';
import 'helpers/test_setup.dart';

void main() {
  final t = TestSetup();

  setUpAll(() async {
    RustLib.initMock(api: MockRustLibApi());
  });

  setUp(() async => await t.setup());
  tearDown(() async => await t.tearDown());

  test('Basic Messaging Test', () async {
    final group = await t.messenger.createNewGroup('Test Group');
    
    final completer = Completer<String>();
    final subscription = group.messageListStateNotifier.stream.listen((_) {
        if (group.messagesMemory.isNotEmpty) {
            final msg = group.messagesMemory.first.msg;
            if (msg is TextMessage) {
                if (!completer.isCompleted) {
                  completer.complete(msg.text);
                }
            }
        }
    });

    await group.sendMessage('Hello World', null, 'sender', 'msgid');
    
    final receivedText = await completer.future.timeout(Duration(seconds: 5));
    expect(receivedText, 'Hello World');
    subscription.cancel();
  });

  test('Rapid Sends Test', () async {
    final group = await t.messenger.createNewGroup('Rapid Group');
    
    const count = 50;
    for (int i = 0; i < count; i++) {
        await group.sendMessage('Msg $i', null, 'sender', 'id$i');
        await Future.delayed(Duration(milliseconds: 10));
    }
    
    await Future.delayed(Duration(milliseconds: 500));
    expect(group.messagesMemory.length, count, reason: 'Double-processing bug detected if this is ${count * 2}');
  });

  test('Large Payload Test', () async {
    final group = await t.messenger.createNewGroup('Large Group');
    final largeText = 'A' * 1024 * 512;
    
    await group.sendMessage(largeText, null, 'sender', 'large-id');
    await Future.delayed(Duration(milliseconds: 200));
    
    expect(group.messagesMemory.any((m) => (m.msg as TextMessage).text == largeText), true);
  });

  test('Publish Failure Test', () async {
    final group = await t.messenger.createNewGroup('Fail Group');
    t.mockS5.mockApi.failNextPublish = true;
    
    expect(
        () => group.sendMessage('Should fail', null, 'sender', 'fail-id'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Mock Publish Failure')))
    );
  });
}
