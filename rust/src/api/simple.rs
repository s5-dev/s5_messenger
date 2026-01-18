use flutter_rust_bridge::frb;
use openmls::prelude::tls_codec::{Deserialize, Serialize};
pub use openmls::prelude::*;
pub use openmls_basic_credential::SignatureKeyPair;
use openmls_memory_storage::MemoryStorage;
use openmls_rust_crypto::RustCrypto;
pub use std::borrow::Borrow;
use std::io::Cursor;
use std::sync::Arc;
pub use std::sync::RwLock;

// TODO: Move away from sync bridge
#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[frb(opaque)]
pub struct MLSCredential {
    pub credential_with_key: CredentialWithKey,
    pub signer: SignatureKeyPair,
}

#[frb(opaque)]
pub struct OpenMLSConfig {
    pub ciphersuite: Ciphersuite,
    pub backend: MyOpenMlsRustCrypto,
    pub credential_type: CredentialType,
    pub signature_algorithm: SignatureScheme,
    pub mls_group_create_config: MlsGroupCreateConfig,
}

pub fn openmls_init_config(keystore_dump: Vec<u8>) -> OpenMLSConfig {
    let ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

    let mls_group_create_config = MlsGroupCreateConfig::builder()
        .sender_ratchet_configuration(SenderRatchetConfiguration::new(
            50,   // out_of_order_tolerance
            1000, // maximum_forward_distance
        ))
        .use_ratchet_tree_extension(true)
        .max_past_epochs(5)
        // TODO wire_format_policy
        .build();

    let backend = if !keystore_dump.is_empty() {
        println!("[keystore] load existing");
        let mut cursor = Cursor::new(keystore_dump);
        MyOpenMlsRustCrypto {
            crypto: RustCrypto::default().into(),
            key_store: MemoryStorage::deserialize(&mut cursor).unwrap(),
        }
    } else {
        println!("[keystore] init empty");
        MyOpenMlsRustCrypto::default()
    };

    OpenMLSConfig {
        ciphersuite,
        backend,
        credential_type: CredentialType::Basic,
        signature_algorithm: ciphersuite.signature_algorithm(),
        mls_group_create_config,
    }
}

#[derive(Default, Clone)]
#[frb(opaque)]
pub struct MyOpenMlsRustCrypto {
    crypto: Arc<RustCrypto>,
    key_store: MemoryStorage,
}

#[frb(opaque)]
impl OpenMlsProvider for MyOpenMlsRustCrypto {
    type CryptoProvider = RustCrypto;
    type RandProvider = RustCrypto;
    type StorageProvider = MemoryStorage;

    fn storage(&self) -> &Self::StorageProvider {
        &self.key_store
    }

    fn crypto(&self) -> &Self::CryptoProvider {
        &self.crypto
    }

    fn rand(&self) -> &Self::RandProvider {
        &self.crypto
    }
}

pub fn openmls_keystore_dump(config: &OpenMLSConfig) -> Vec<u8> {
    let mut bytes = vec![];
    let _ = config.backend.storage().serialize(&mut bytes);
    bytes
}

pub fn openmls_generate_credential_with_key(
    identity: Vec<u8>,
    config: &OpenMLSConfig,
) -> MLSCredential {
    let credential = Credential::new(config.credential_type, identity);
    let signature_keys = SignatureKeyPair::new(config.signature_algorithm)
        .expect("Error generating a signature key pair.");

    // Store the signature key into the key store so OpenMLS has access
    // to it.
    signature_keys
        .store(config.backend.storage())
        .expect("Error storing signature keys in key store.");

    MLSCredential {
        credential_with_key: CredentialWithKey {
            credential,
            signature_key: signature_keys.public().into(),
        },
        signer: signature_keys,
    }
}

pub fn openmls_signer_get_public_key(signer: &SignatureKeyPair) -> Vec<u8> {
    signer.to_public_vec()
}

pub fn openmls_recover_credential_with_key(
    identity: Vec<u8>,
    public_key: Vec<u8>,
    config: &OpenMLSConfig,
) -> MLSCredential {
    let credential = Credential::new(config.credential_type, identity);

    let signature_keys = SignatureKeyPair::read(
        config.backend.storage(),
        &public_key,
        config.signature_algorithm,
    )
    .expect("Error generating a signature key pair.");

    MLSCredential {
        credential_with_key: CredentialWithKey {
            credential,
            signature_key: signature_keys.public().into(),
        },
        signer: signature_keys,
    }
}

// A helper to create key package bundles.
pub fn openmls_generate_key_package(
    signer: &SignatureKeyPair,
    credential_with_key: &CredentialWithKey,
    config: &OpenMLSConfig,
) -> Vec<u8> {
    // Create the key package
    let key_package = KeyPackage::builder()
        .build(
            config.ciphersuite,
            &config.backend,
            signer,
            (*credential_with_key).clone(),
        )
        .unwrap();

    key_package
        .key_package()
        .tls_serialize_detached()
        .expect("Error serializing key_package")
}

pub fn openmls_group_create(
    signer: &SignatureKeyPair,
    credential_with_key: &CredentialWithKey,
    config: &OpenMLSConfig,
) -> RwLock<MlsGroup> {
    let group = MlsGroup::new(
        &config.backend,
        signer,
        &config.mls_group_create_config,
        (*credential_with_key).clone(),
    )
    .expect("An unexpected error occurred.");
    RwLock::new(group)
}

pub struct MLSGroupAddMembersResponse {
    pub mls_message_out: Vec<u8>,
    pub welcome_out: Vec<u8>,
}

// Add member from welcome
pub fn openmls_group_add_member(
    group: &RwLock<MlsGroup>,
    signer: &SignatureKeyPair,
    key_package: Vec<u8>,
    config: &OpenMLSConfig,
) -> MLSGroupAddMembersResponse {
    let mut group_rw = match group.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    let kp = KeyPackageIn::tls_deserialize_exact(key_package.as_slice())
        .expect("Could not deserialize KeyPackage")
        .validate(config.backend.crypto(), ProtocolVersion::Mls10)
        .expect("Invalid KeyPackage");

    let (mls_message_out, welcome_out, _) = group_rw
        .add_members(&config.backend, signer, &[kp])
        .expect("Could not add members.");

    group_rw
        .merge_pending_commit(&config.backend)
        .expect("error merging pending commit");

    let serialized_mls_message = mls_message_out
        .tls_serialize_detached()
        .expect("Error serializing mls_message");

    let serialized_welcome = welcome_out
        .tls_serialize_detached()
        .expect("Error serializing welcome");

    MLSGroupAddMembersResponse {
        mls_message_out: serialized_mls_message,
        welcome_out: serialized_welcome,
        /*  ratchet_tree: group_rw
        .export_ratchet_tree()
        .tls_serialize_detached()
        .expect("Error serializing ratchet_tree"), */
    }
}

pub fn openmls_group_create_message(
    group: &RwLock<MlsGroup>,
    signer: &SignatureKeyPair,
    message: Vec<u8>,
    config: &OpenMLSConfig,
) -> Vec<u8> {
    let mut group_rw = match group.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    let mls_message_out = group_rw
        .create_message(&config.backend, signer, &message)
        .expect("Error creating application message.");

    mls_message_out
        .tls_serialize_detached()
        .expect("Error serializing welcome")
}

// This is for joining with a welcome message
pub fn openmls_group_join(
    welcome_in: Vec<u8>,
    // ratchet_tree: Vec<u8>,
    config: &OpenMLSConfig,
) -> RwLock<MlsGroup> {
    // de-serialize the message as an [`MlsMessageIn`] ...
    let mls_message_in = MlsMessageIn::tls_deserialize_exact(welcome_in.as_slice())
        .expect("An unexpected error occurred.");

    // inspect the message.
    let welcome = match mls_message_in.extract() {
        MlsMessageBodyIn::Welcome(welcome) => welcome,
        // We know it's a welcome message, so we ignore all other cases.
        _ => unreachable!("Unexpected message type."),
    };

    // join the group
    let group = StagedWelcome::new_from_welcome(
        &config.backend,
        config.mls_group_create_config.join_config(),
        welcome,
        None,
    )
    .expect("Failed to create staged join")
    .into_group(&config.backend)
    .expect("Failed to create MlsGroup");

    RwLock::new(group)
}

// For doing external commit invite
// This function will be called by an existing group member to create an invite
pub fn openmls_group_export_group_info(
    group: &RwLock<MlsGroup>,
    signer: &SignatureKeyPair,
    config: &OpenMLSConfig,
) -> Vec<u8> {
    let group_ro = match group.read() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    let mls_message_out: MlsMessageOut = group_ro
        .export_group_info(&config.backend, signer, true) // `true` includes the ratchet tree extension
        .expect("Cannot export group info");

    let message_serialized: Vec<u8> = mls_message_out
        .to_bytes()
        .expect("Cannot marshal mls message to bytes");

    message_serialized
}

// This is for joining with an external commit, so single step pairng baby!
// Return is a typle because frb gets mad and trys to clone the MlsGroup if put
// in a struct which isn't possible
pub fn openmls_group_join_by_external_commit(
    verifiable_group_info_in: Vec<u8>,
    signer: &SignatureKeyPair,
    credential_with_key: &CredentialWithKey,
    config: &OpenMLSConfig,
) -> (RwLock<MlsGroup>, Vec<u8>) {
    // Deserialize the VerifiableGroupInfo received from the existing member
    let mls_message_in: MlsMessageIn =
        MlsMessageIn::tls_deserialize_exact(&verifiable_group_info_in)
            .expect("Failed to deserialize mls message in");

    let verifiable_group_info = {
        match mls_message_in.extract() {
            MlsMessageBodyIn::GroupInfo(verifiable_group_info) => verifiable_group_info,
            other => panic!("Expected `MlsMessageBodyIn::GroupInfo`, got {other:?}."),
        }
    };

    let join_config = config.mls_group_create_config.join_config();

    let (mut group, commit_message_out, _group_info) = MlsGroup::join_by_external_commit(
        &config.backend,
        signer,
        None,
        verifiable_group_info,
        join_config,
        None,
        None,
        &[],
        credential_with_key.clone(),
    )
    .expect("Error joining group by external commit");

    group
        .merge_pending_commit(&config.backend)
        .expect("Error merging pending commit for new member");

    let commit_message_bytes = commit_message_out
        .tls_serialize_detached()
        .expect("Could not serialize commit message");

    (RwLock::new(group), commit_message_bytes)
}

pub struct ProcessIncomingMessageResponse {
    pub is_application_message: bool,
    pub application_message: Vec<u8>,
    pub identity: Vec<u8>,
    pub sender: Vec<u8>,
    pub epoch: u64,
}

pub fn openmls_group_process_incoming_message(
    group: &RwLock<MlsGroup>,
    mls_message_in: Vec<u8>,
    config: &OpenMLSConfig,
) -> ProcessIncomingMessageResponse {
    let message_in = MlsMessageIn::tls_deserialize_exact(&mut mls_message_in.as_slice())
        .expect("Could not deserialize message.");

    let mut group_rw = match group.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    let protocol_message: ProtocolMessage = match message_in.extract() {
        MlsMessageBodyIn::PrivateMessage(m) => m.into(),
        MlsMessageBodyIn::PublicMessage(m) => m.into(),
        _ => panic!("This is not an MLS message."),
    };
    let processed_message = group_rw
        .process_message(&config.backend, protocol_message)
        .expect("Could not process unverified message.");
    let processed_message_credential: Credential = processed_message.credential().clone();
    let processed_message_sender = processed_message
        .sender()
        .tls_serialize_detached()
        .expect("failed to serialize sender");
    let processed_message_epoch: u64 = processed_message.epoch().as_u64();

    match processed_message.into_content() {
        ProcessedMessageContent::ApplicationMessage(application_message) => {
            return ProcessIncomingMessageResponse {
                is_application_message: true,
                application_message: application_message.into_bytes(),
                identity: processed_message_credential.serialized_content().to_vec(),
                sender: processed_message_sender,
                epoch: processed_message_epoch,
            };
        }
        ProcessedMessageContent::ProposalMessage(_proposal_ptr) => {
            // intentionally left blank.
        }
        ProcessedMessageContent::ExternalJoinProposalMessage(_external_proposal_ptr) => {
            // intentionally left blank.
        }
        ProcessedMessageContent::StagedCommitMessage(staged_commit) => {
            // This makes sure to load up the new commit if it comes in
            group_rw
                .merge_staged_commit(&config.backend, *staged_commit)
                .expect("failed to merge staged commit");

            return ProcessIncomingMessageResponse {
                is_application_message: false,
                application_message: vec![],
                identity: processed_message_credential.serialized_content().to_vec(),
                sender: processed_message_sender,
                epoch: processed_message_epoch, // now equals the new epoch
            };
        }
    }
    ProcessIncomingMessageResponse {
        is_application_message: false,
        application_message: vec![],
        identity: vec![],
        epoch: 0,
        sender: processed_message_sender,
    }
}

pub fn openmls_group_save(group: &RwLock<MlsGroup>, _config: &OpenMLSConfig) -> Vec<u8> {
    let group_rw = match group.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    group_rw.group_id().as_slice().to_vec()
}

pub fn openmls_group_load(id: Vec<u8>, config: &OpenMLSConfig) -> RwLock<MlsGroup> {
    let group = MlsGroup::load(config.backend.storage(), &GroupId::from_slice(&id))
        .unwrap()
        .unwrap();

    RwLock::new(group)
}

pub fn openmls_group_leave(
    group: &RwLock<MlsGroup>,
    signer: &SignatureKeyPair,
    config: &OpenMLSConfig,
) -> Vec<u8> {
    // Get a mutable reference to the group. We need this because `leave_group`
    // creates a proposal and thus modifies the internal group state.
    let mut group_rw = match group.write() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    // Call the `leave_group` method. It takes the backend and a signer to
    // create and sign the leave proposal as a Commit message.
    let mls_message_out = group_rw
        .leave_group(&config.backend, signer)
        .expect("Error creating leave group message");

    // Serialize the resulting MlsMessageOut to bytes so it can be sent
    // over the FFI boundary to your app and then to other group members.
    mls_message_out
        .tls_serialize_detached()
        .expect("Error serializing leave message")
}

pub struct GroupMember {
    pub identity: Vec<u8>,
    pub index: u32,
    pub signature_key: Vec<u8>,
}

pub fn openmls_group_list_members(group: &RwLock<MlsGroup>) -> Vec<GroupMember> {
    let group_ro = match group.read() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    let mut members = vec![];
    for member in group_ro.members() {
        members.push(GroupMember {
            identity: member.credential.serialized_content().to_vec(),
            index: member.index.u32(),
            signature_key: member.signature_key,
        });
    }
    members
}
