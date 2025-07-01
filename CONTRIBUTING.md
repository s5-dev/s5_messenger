# Contribution Areas

We welcome contributions to these three core components:

### 1. Rust Core

**The cryptographic backbone** - handles all heavy lifting through:

- MLS protocol implementation
- S5 network integration
- Performance-critical operations

**Getting Started:**

1. Follow the [Flutter+Rust Bridge tutorial](https://cjycode.com/flutter_rust_bridge/)
2. Ensure `rustup` is installed (`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`)
3. After modifications, regenerate bindings:

   ```bash
   flutter_rust_bridge_codegen generate
   ```

**Common Pitfalls:**

- Missing Rust toolchain (install via `rustup`)
- Incompatible toolchain versions
- Forgetting to regenerate bindings after Rust changes

### 2. Dart Library

**The Flutter interface layer** needs help with:

- API ergonomics improvements
- Documentation examples
- Platform-specific optimizations
- Unit/integration tests

**Getting Started:**

- Start in `lib/`

### 3. Example App

**Reference implementation** that demonstrates:

- Complete integration workflow
- Best practice usage patterns
- UI/UX improvements welcome!

**Getting Started**

- Start in [example/](./example)

**Improvement Ideas:**

- Better state management examples
- Additional demo scenarios
- Enhanced error handling displays
