import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'root_navigator.dart';

/// Holds a course join code/PIN captured from a `/course/:code` or `/pin/:code`
/// deep link until the app reaches the main screen, which enrolls and opens it.
/// Both URL shapes resolve the same way (by course code/PIN).
final pendingDeepLinkCodeProvider = StateProvider<String?>((ref) => null);

/// Landing widget for the deep-link routes. It records the code, then hands off
/// to the normal [AuthWrapper] boot flow (auth/guest → main). Once the app is at
/// the main screen, MainScreen consumes the pending code and opens the course.
class DeepLinkEntry extends ConsumerStatefulWidget {
  final String code;

  const DeepLinkEntry({super.key, required this.code});

  @override
  ConsumerState<DeepLinkEntry> createState() => _DeepLinkEntryState();
}

class _DeepLinkEntryState extends ConsumerState<DeepLinkEntry> {
  @override
  void initState() {
    super.initState();
    // Record the code after this frame — modifying a provider during a widget
    // life-cycle (initState/build) is disallowed by Riverpod. This still runs
    // before MainScreen builds: AuthWrapper always shows a loading frame first
    // while it checks auth asynchronously, so the code is present in time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.code.isNotEmpty) {
        ref.read(pendingDeepLinkCodeProvider.notifier).state = widget.code;
      }
    });
  }

  @override
  Widget build(BuildContext context) => const AuthWrapper();
}
