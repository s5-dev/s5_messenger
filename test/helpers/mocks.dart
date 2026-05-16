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
  @override
  Future<OpenMlsConfig> crateApiSimpleOpenmlsInitConfig({required String dbPath}) async {
    return FakeOpenMlsConfig();
  }

  @override
  Future<MlsCredential> crateApiSimpleOpenmlsGenerateCredentialWithKey({required List<int> identity, required OpenMlsConfig config}) async {
    return FakeMlsCredential();
  }

  @override
  Future<Uint8List> crateApiSimpleOpenmlsSignerGetPublicKey({required SignatureKeyPair signer}) async {
    return Uint8List(32);
  }

  @override
  Future<MlsGroup> crateApiSimpleOpenmlsGroupCreate({required SignatureKeyPair signer, required CredentialWithKey credentialWithKey, required OpenMlsConfig config}) async {
    return FakeMlsGroup();
  }

  @override
  Future<Uint8List> crateApiSimpleOpenmlsGroupSave({required MlsGroup group, required OpenMlsConfig config}) async {
    return Uint8List(16);
  }

  @override
  Future<Uint8List> crateApiSimpleOpenmlsGroupCreateMessage({required MlsGroup group, required SignatureKeyPair signer, required List<int> message, required OpenMlsConfig config}) async {
    return Uint8List.fromList(message);
  }

  @override
  Future<ProcessIncomingMessageResponse> crateApiSimpleOpenmlsGroupProcessIncomingMessage({required MlsGroup group, required List<int> mlsMessageIn, required OpenMlsConfig config}) async {
    return ProcessIncomingMessageResponse(
        isApplicationMessage: true,
        applicationMessage: Uint8List.fromList(mlsMessageIn),
        epoch: BigInt.zero,
        sender: Uint8List(0),
        identity: Uint8List(0)
    );
  }

  @override
  Future<List<GroupMember>> crateApiSimpleOpenmlsGroupListMembers({required MlsGroup group}) async {
    return [];
  }
}

class FakeOpenMlsConfig extends Fake implements OpenMlsConfig {}
class FakeMlsCredential extends Fake implements MlsCredential {
    @override
    SignatureKeyPair get signer => FakeSignatureKeyPair();
    @override
    CredentialWithKey get credentialWithKey => FakeCredentialWithKey();
}
class FakeSignatureKeyPair extends Fake implements SignatureKeyPair {}
class FakeCredentialWithKey extends Fake implements CredentialWithKey {}
class FakeMlsGroup extends Fake implements MlsGroup {}

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
    if (_controller.isClosed) {
        _controller = StreamController<SignedStreamMessage>.broadcast();
    }
    
    if (afterTimestamp != null) {
        for (final msg in _history) {
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
