import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:s5/s5.dart';
import 'package:s5_messenger/s5_messenger.dart';

late S5 s5;
late S5Messenger s5messenger;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const InitializationScreen(),
    );
  }
}

class InitializationScreen extends StatefulWidget {
  const InitializationScreen({super.key});

  @override
  State<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends State<InitializationScreen> {
  bool hiveInitialized = false;
  bool s5Initialized = false;
  bool messengerInitialized = false;
  bool initializationComplete = false;

  @override
  void initState() {
    super.initState();
    _initializeDependencies();
  }

  Future<void> _initializeDependencies() async {
    try {
      // Initialize Hive
      Hive.init('data');
      setState(() => hiveInitialized = true);
      // Initialize Rust

      // Initialize S5
      s5 = await S5.create(
        initialPeers: [
          'wss://z2DeVYsXdq3Rgt8252LRwNnreAtsGr3BN6FPc6Hvg6dTtRk@s5.jptr.tech/s5/p2p', // add my S5 node first
          'wss://z2Das8aEF7oNoxkcrfvzerZ1iBPWfm6D7gy3hVE4ALGSpVB@node.sfive.net/s5/p2p',
          'wss://z2DdbxV4xyoqWck5pXXJdVzRnwQC6Gbv6o7xDvyZvzKUfuj@s5.vup.dev/s5/p2p',
          'wss://z2DWuWNZcdSyZLpXFK2uCU3haaWMXrDAgxzv17sDEMHstZb@s5.garden/s5/p2p',
        ],
      );
      setState(() => s5Initialized = true);

      // Initialize S5Messenger
      s5messenger = S5Messenger();
      await s5messenger.init(s5);
      setState(() => messengerInitialized = true);

      // All done
      setState(() => initializationComplete = true);

      // Navigate to home page
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MyHomePage()),
        );
      }
    } catch (e) {
      // Handle initialization errors
      debugPrint('Initialization error: $e');
      // You might want to show an error message to the user
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Initializing App...',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            _buildInitializationStep('Hive Initialization', hiveInitialized),
            _buildInitializationStep('S5 Initialization', s5Initialized),
            _buildInitializationStep(
              'Messenger Initialization',
              messengerInitialized,
            ),
            if (initializationComplete) ...[
              const SizedBox(height: 32),
              const Text('Ready!', style: TextStyle(fontSize: 20)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInitializationStep(String label, bool isComplete) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          isComplete
              ? const Icon(Icons.check_circle, color: Colors.green)
              : const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Awesome aws = Awesome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text("${aws.isAwesome}")));
  }
}
