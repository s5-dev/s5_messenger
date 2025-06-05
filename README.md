
# s5_messenger

A **Flutter package** for secure messaging using [s5](https://s5.pro/) and [MLS](https://www.ietf.org/blog/mls-secure-and-usable-end-to-end-encryption/) (Messaging Layer Security) protocols. Enables easy-to-set-up, end-to-end encrypted messaging between clients.

## Features ✨

- **End-to-end encryption** via MLS protocol
- **Decentralized storage** using S5 for message transportation
- **Cross-platform** support (Android, iOS, Linux, macOS, Windows)
- **Rust-powered** core via ```flutter_rust_bridge``` for performance
- **Minimal-config** messaging between authenticated clients

## Installation 📦

Add to your ```pubspec.yaml```:

```yaml
dependencies:
  s5_messenger: ^0.1.0
```

## Basic Usage 🚀

See [example](./example/)

## Architecture 🏗

1. **MLS Protocol**: Handles key management and message encryption
2. **S5 Integration**: Stores encrypted messages in a decentralized network
3. **Flutter Interface**: Platform-agnostic UI components
4. **Rust Core**: High-performance cryptographic operations

## Platform Support ✔

| Platform | Status |
|----------|--------|
| Android  | ✅     |
| iOS      | ✅     |
| Linux    | ✅     |
| macOS    | ✅     |
| Windows  | ✅     |

## Contributing 🤝

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup using:

- ```flutter_rust_bridge``` for FFI
- ```cargokit``` for Rust-Flutter integration

## License 📄

MIT (See [LICENSE](LICENSE))
