import 'dart:io';
import 'package:hive_ce/hive.dart';
import 'package:s5_messenger/s5_messenger.dart';
import 'mocks.dart';

class TestSetup {
  late Directory tempDir;
  late MockS5 mockS5;
  late S5Messenger messenger;

  Future<void> setup() async {
    tempDir = await Directory.systemTemp.createTemp('s5_messenger_test');
    Hive.init(tempDir.path);
    mockS5 = MockS5();
    messenger = S5Messenger();
    await messenger.init(mockS5, tempDir.path);
    // Reset subscription count after init
    mockS5.mockApi.subscriptionCount = 0;
  }

  Future<void> tearDown() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}
