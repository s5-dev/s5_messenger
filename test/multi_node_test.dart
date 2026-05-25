import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:s5_messenger/s5_messenger.dart';
import 'package:s5_messenger/src/rust/frb_generated.dart';
import 'package:lib5/util.dart';
import 'helpers/mocks.dart';

void main() {
  late MockS5 sharedS5;
  late MockRustLibApi mockRust;

  setUpAll(() async {
    mockRust = MockRustLibApi();
    RustLib.initMock(api: mockRust);
  });

  setUp(() async {
    sharedS5 = MockS5();
  });

  Future<S5Messenger> createNode(String name) async {
    final tempDir = await Directory.systemTemp.createTemp('s5_node_$name');
    Hive.init(tempDir.path);
    final messenger = S5Messenger();
    await messenger.init(sharedS5, tempDir.path, name);
    return messenger;
  }

  test('Multi-Node Membership Propagation Test (A -> B -> C)', () async {
    // 1. Initialize three nodes
    final nodeA = await createNode('nodeA');
    final nodeB = await createNode('nodeB');
    final nodeC = await createNode('nodeC');

    // 2. Node A creates a group
    final groupA = await nodeA.createNewGroup('Multi Group');
    await sharedS5.mockApi.nextSubscription; 
    expect(groupA.members.length, 1);

    // 3. Node A adds Node B
    final keyPackageB = await nodeB.createKeyPackage();
    final welcomeB = await groupA.addMemberToGroup(keyPackageB);
    
    // Node B joins
    final groupId = await nodeB.acceptInviteAndJoinGroup(
        base64UrlNoPaddingDecode(welcomeB.split(':').last), 
        'nodeA', 'msg1', null
    );
    final groupB = nodeB.group(groupId);
    await sharedS5.mockApi.nextSubscription;

    // Verify both see 2 members
    await Future.delayed(Duration(milliseconds: 200)); // Allow background processing
    expect(groupA.members.length, 2, reason: 'Node A should see itself and Node B');
    expect(groupB.members.length, 2, reason: 'Node B should see itself and Node A');

    // 4. Node A adds Node C
    final keyPackageC = await nodeC.createKeyPackage();
    final welcomeC = await groupA.addMemberToGroup(keyPackageC);
    
    // Node C joins
    await nodeC.acceptInviteAndJoinGroup(
        base64UrlNoPaddingDecode(welcomeC.split(':').last), 
        'nodeA', 'msg2', null
    );
    final groupC = nodeC.group(groupId);
    await sharedS5.mockApi.nextSubscription;

    // 5. FINAL VERIFICATION: All nodes should see 3 members
    await Future.delayed(Duration(milliseconds: 500)); 
    
    expect(groupA.members.length, 3, reason: 'Node A should see 3 members');
    expect(groupC.members.length, 3, reason: 'Node C should see 3 members');
    expect(groupB.members.length, 3, reason: 'Node B should see 3 members');
  });

  test('Membership Sync Test (Node B offline when C joins)', () async {
    // 1. Setup A and B
    final nodeA = await createNode('syncA');
    final nodeB = await createNode('syncB');
    final groupA = await nodeA.createNewGroup('Sync Group');
    await sharedS5.mockApi.nextSubscription;

    final keyPackageB = await nodeB.createKeyPackage();
    final welcomeB = await groupA.addMemberToGroup(keyPackageB);
    final groupId = await nodeB.acceptInviteAndJoinGroup(
        base64UrlNoPaddingDecode(welcomeB.split(':').last), 
        'nodeA', 'm1', null
    );
    final groupB = nodeB.group(groupId);
    await sharedS5.mockApi.nextSubscription;
    
    await Future.delayed(Duration(milliseconds: 100));
    expect(groupB.members.length, 2);

    // 2. Node B goes OFFLINE
    nodeB.groups.clear(); // Simulate app close/loss of state or just stop listener
    // In our mock, we'll just close Node B's potential stream if it had one
    // But since they share MockS5Api, we'll just rely on the fact that B won't be "listening"
    
    // 3. Node A adds Node C while B is gone
    final nodeC = await createNode('syncC');
    final keyPackageC = await nodeC.createKeyPackage();
    await groupA.addMemberToGroup(keyPackageC);
    
    // 4. Node B "wakes up" (In reality, it should reconnect and sync)
    // We'll simulate this by calling recoverGroups which starts the listener again
    await nodeB.recoverGroups();
    
    // Give it time to process history
    await Future.delayed(Duration(milliseconds: 1000));
    
    // 5. VERIFICATION
    expect(groupB.members.length, 3, reason: 'Node B should have learned about Node C from history sync');
  });
}
