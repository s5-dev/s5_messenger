
# s5_messenger

A **Flutter package** for secure messaging using [s5](https://s5.pro/) and [MLS](https://www.ietf.org/blog/mls-secure-and-usable-end-to-end-encryption/) (Messaging Layer Security) protocols. Enables easy-to-set-up, end-to-end encrypted messaging between clients.

## Features

- **End-to-end encryption** via MLS
- **Decentralized routing** using S5 for message transportation
- **Cross-platform** support (Android, iOS, Linux, macOS, Windows)
- **Rust-powered** core via ```flutter_rust_bridge``` for performance
- **Minimal-config** messaging between authenticated clients

## Installation

Add to your ```pubspec.yaml```:

```yaml
dependencies:
  s5_messenger: ^0.1.2
  hive_ce: ^2.11.3
  s5:
    git: 
      url: https://github.com/lukehmcc/s5-dart.git
      ref: 0.2.0-patched

```

## Basic Usage

See [example](./example/)

> ⚠ `cargo` is required to build this project. Make sure to install first [here](https://www.rust-lang.org/tools/install)

To test the library:

```bash
git clone --recursive https://github.com/s5-dev/s5_messenger.git # make sure to recuse submodules
# If you forgot to recurse and already cloned you can do this
# git submodule init && git submodule update
cd s5_messenger/
./flutterw run # Make sure to run with the flutter wrapper so everyone is on the same flutter version
```

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup using:

- ```flutter_rust_bridge``` for FFI
- ```cargokit``` for Rust-Flutter integration

## License

MIT (See [LICENSE](LICENSE))

## Acknowledgement

This work is supported by a [Sia Foundation](https://sia.tech/) grant
