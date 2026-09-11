import 'package:flutter/material.dart';

/// Runs app startup and, if it fails, puts the reason on the screen.
///
/// Everything an app does before `runApp` — validating configuration, bringing
/// up Supabase, initialising crash reporting — happens with nothing rendered
/// yet. An exception in any of it leaves the Flutter view exactly as the engine
/// created it: a blank white rectangle, on a device where the only way to read
/// the actual error is a USB cable and `adb logcat`.
///
/// That is a bad trade for the sake of a few lines. This catches whatever went
/// wrong and renders it, so a misconfigured build explains itself on the phone
/// it was installed on.
///
/// It deliberately does not try to recover. If startup failed the app is not
/// usable, and pretending otherwise produces a second, more confusing failure
/// further in.
Future<void> bootstrap(Future<void> Function() start) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await start();
  } on Object catch (error, stack) {
    debugPrint('Paasel startup failed: $error\n$stack');
    runApp(StartupFailureApp(error: error, stack: stack));
  }
}

/// The screen shown when startup threw. Plain, self-contained, and dependent on
/// nothing that might itself have failed to initialise.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({required this.error, this.stack, super.key});

  final Object error;
  final StackTrace? stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF14110F),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFE5484D),
                  size: 36,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Paasel couldn't start",
                  style: TextStyle(
                    color: Color(0xFFF5F2EF),
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This is a configuration problem in this build, not '
                  'something you can fix on the phone.',
                  style: TextStyle(color: Color(0xFF9A938C), fontSize: 14),
                ),
                const SizedBox(height: 20),
                // Selectable so the message can be copied off the device
                // without a cable.
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      '$error',
                      style: const TextStyle(
                        color: Color(0xFFF5F2EF),
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
