import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:s5_messenger/src/rust/frb_generated.dart';
import 'package:s5_messenger/src/rust/api/simple.dart';
import 'package:s5/s5.dart';
import 'package:lib5/lib5.dart';
// ignore: implementation_imports
import 'package:lib5/src/api/node.dart';

class MockRustLibApi extends Fake implements RustLibApi {
  final Map<String, List<GroupMember>> _groupMembers = {};
  
  @override
  Stream<LogEntry> crateApiSimpleInitLogging() async* {
    // Return empty stream for tests
  }

  @override
  Future<OpenMlsConfig> crateApiSimpleOpenmlsInitConfig({required String dbPath}) async {
    return FakeOpenMlsConfig();
  }

  @override
  Future<MlsCredential> crateApiSimpleOpenmlsGenerateCredentialWithKey({required List<int> identity, required OpenMlsConfig config}) async {
    return FakeMlsCredential(identity: Uint8List.fromList(identity));
  }

  @override
  Future<MlsCredential> crateApiSimpleOpenmlsRecoverCredentialWithKey({required List<int> identity, required List<int> publicKey, required OpenMlsConfig config}) async {
    return FakeMlsCredential(identity: Uint8List.fromList(identity));
  }

  @override
  Future<MlsGroup> crateApiSimpleOpenmlsGroupLoad({required List<int> id, required OpenMlsConfig config}) async {
    return FakeMlsGroup(id: String.fromCharCodes(id));
  }

  @override
  Future<Uint8List> crateApiSimpleOpenmlsSignerGetPublicKey({required SignatureKeyPair signer}) async {
    return (signer as FakeSignatureKeyPair).publicKey;
  }

  @override
  Future<MlsGroup> crateApiSimpleOpenmlsGroupCreate({required SignatureKeyPair signer, required CredentialWithKey credentialWithKey, required OpenMlsConfig config}) async {
    final group = FakeMlsGroup();
    _groupMembers[group.id] = [
        GroupMember(identity: (signer as FakeSignatureKeyPair).identity, index: 0, signatureKey: signer.publicKey)
    ];
    return group;
  }

  @override
  Future<Uint8List> crateApiSimpleOpenmlsGroupSave({required MlsGroup group, required OpenMlsConfig config}) async {
    return Uint8List.fromList((group as FakeMlsGroup).id.codeUnits);
  }

  @override
  Future<Uint8List> crateApiSimpleOpenmlsGenerateKeyPackage({required SignatureKeyPair signer, required CredentialWithKey credentialWithKey, required OpenMlsConfig config}) async {
    // Mock: KeyPackage is the identity of the signer
    return (signer as FakeSignatureKeyPair).identity;
  }

  @override
  Future<Uint8List> crateApiSimpleOpenmlsGroupCreateMessage({required MlsGroup group, required SignatureKeyPair signer, required List<int> message, required OpenMlsConfig config}) async {
    return Uint8List.fromList(message);
  }

  @override
  Future<MLSGroupAddMembersResponse> crateApiSimpleOpenmlsGroupAddMember({
    required MlsGroup group,
    required SignatureKeyPair signer,
    required List<int> keyPackage,
    required OpenMlsConfig config,
  }) async {
    // KeyPackage in our mock is just the identity bytes
    final newMemberIdentity = Uint8List.fromList(keyPackage);
    final members = _groupMembers[(group as FakeMlsGroup).id]!;
    
    final newMember = GroupMember(
        identity: newMemberIdentity, 
        index: members.length, 
        signatureKey: Uint8List(32)
    );
    members.add(newMember);

    return MLSGroupAddMembersResponse(
        welcomeOut: newMemberIdentity, // Mock: welcome is just the identity
        mlsMessageOut: Uint8List.fromList([1, 2, 3]) // Mock commit
    );
  }

  @override
  Future<MlsGroup> crateApiSimpleOpenmlsGroupJoin({required List<int> welcomeIn, required OpenMlsConfig config}) async {
    // Mock: welcomeIn is the identity of the person joining.
    // In a real mock we'd need to find which group they joined.
    // For simplicity, let's assume there's only one group in the test.
    return _groupMembers.keys.map((id) => FakeMlsGroup(id: id)).first;
  }

  @override
  Future<ProcessIncomingMessageResponse> crateApiSimpleOpenmlsGroupProcessIncomingMessage({required MlsGroup group, required List<int> mlsMessageIn, required OpenMlsConfig config}) async {
    final isCommit = mlsMessageIn.length == 3 && mlsMessageIn[0] == 1;
    
    return ProcessIncomingMessageResponse(
        isApplicationMessage: !isCommit,
        applicationMessage: Uint8List.fromList(mlsMessageIn),
        epoch: BigInt.zero,
        sender: Uint8List(0),
        identity: Uint8List(0)
    );
  }

  @override
  Future<List<GroupMember>> crateApiSimpleOpenmlsGroupListMembers({required MlsGroup group}) async {
    return _groupMembers[(group as FakeMlsGroup).id] ?? [];
  }
}

class FakeOpenMlsConfig extends Fake implements OpenMlsConfig {}
class FakeMlsCredential extends Fake implements MlsCredential {
    final Uint8List identity;
    FakeMlsCredential({required this.identity});

    @override
    SignatureKeyPair get signer => FakeSignatureKeyPair(identity: identity);
    @override
    CredentialWithKey get credentialWithKey => FakeCredentialWithKey();
}
class FakeSignatureKeyPair extends Fake implements SignatureKeyPair {
    final Uint8List identity;
    final Uint8List publicKey = Uint8List(32);
    FakeSignatureKeyPair({required this.identity});
}
class FakeCredentialWithKey extends Fake implements CredentialWithKey {}
class FakeMlsGroup extends Fake implements MlsGroup {
    final String id;
    FakeMlsGroup({this.id = 'test-group'});
}

class MockS5 extends Fake implements S5 {
  final MockS5Api mockApi = MockS5Api();

  @override
  S5NodeAPI get api => mockApi;

  @override
  final MockS5Crypto crypto = MockS5Crypto();
}

class MockS5Api extends Fake implements S5NodeAPI {
  StreamController<SignedStreamMessage> _controller = StreamController<SignedStreamMessage>.broadcast();
  int subscriptionCount = 0;
  bool failNextPublish = false;
  
  Completer<void> _subscriptionCompleter = Completer<void>();
  Future<void> get nextSubscription => _subscriptionCompleter.future;

  final List<SignedStreamMessage> _history = [];

  void emit(SignedStreamMessage event) {
    _history.add(event);
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void addError(Object error) {
    if (!_controller.isClosed) {
      _controller.addError(error);
    }
  }

  void close() {
    _controller.close();
  }

  @override
  Stream<SignedStreamMessage> streamSubscribe(
    Uint8List pk, {
    int? afterTimestamp,
    int? beforeTimestamp,
    dynamic route,
  }) async* {
    subscriptionCount++;
    if (!_subscriptionCompleter.isCompleted) {
      _subscriptionCompleter.complete();
    }
    _subscriptionCompleter = Completer<void>(); // Reset for next one

    if (_controller.isClosed) {
        _controller = StreamController<SignedStreamMessage>.broadcast();
    }
    
    if (afterTimestamp != null) {
        final historySnapshot = List<SignedStreamMessage>.from(_history);
        for (final msg in historySnapshot) {
            if (msg.ts > afterTimestamp) {
                yield msg;
            }
        }
    }
    
    yield* _controller.stream;
  }

  @override
  Future<void> streamPublish(SignedStreamMessage msg, {dynamic route}) async {
    if (failNextPublish) {
        failNextPublish = false;
        throw Exception('Mock Publish Failure');
    }
    emit(msg);
  }
}

class MockS5Crypto extends Fake implements CryptoImplementation {
  @override
  Future<KeyPairEd25519> newKeyPairEd25519({Uint8List? seed}) async {
    return FakeKeyPairEd25519();
  }
  @override
  Uint8List hashBlake3Sync(Uint8List data) {
    return Uint8List(32);
  }
  @override
  Future<Uint8List> hashBlake3(Uint8List data) async {
    return Uint8List(32);
  }
  @override
  Future<Uint8List> signEd25519({required KeyPairEd25519 kp, required Uint8List message}) async {
    return Uint8List(64);
  }
}

class FakeKeyPairEd25519 extends Fake implements KeyPairEd25519 {
    @override
    Uint8List get publicKey => Uint8List(32);
}
