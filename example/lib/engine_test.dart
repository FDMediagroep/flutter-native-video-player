import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const probe = MethodChannel('engine_test');
  const plugin = MethodChannel('native_video_player');
  StreamSubscription<dynamic>? subscription;
  final events = <dynamic>[];

  probe.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'setup':
        await plugin.invokeMethod<void>('setupControllerEventChannel', {
          'controllerId': 1,
        });
        subscription ??= const EventChannel('native_video_player_controller_1')
            .receiveBroadcastStream()
            .listen(events.add);
        // A native round trip puts the listen request ahead of the reply.
        await plugin.invokeMethod<void>('setupControllerEventChannel', {
          'controllerId': 1,
        });
        return null;
      case 'events':
        return events;
      case 'cancel':
        await subscription?.cancel();
        subscription = null;
        await plugin.invokeMethod<void>('teardownControllerEventChannel', {
          'controllerId': 1,
        });
        return null;
      case 'plugin':
        final arguments = Map<String, dynamic>.from(call.arguments as Map);
        return plugin.invokeMethod<dynamic>(
          arguments['method'] as String,
          arguments['arguments'],
        );
      default:
        throw MissingPluginException(call.method);
    }
  });
  unawaited(probe.invokeMethod<void>('ready'));
}
