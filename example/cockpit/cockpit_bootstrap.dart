import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:seeko_example/app.dart';

Widget buildCockpitDevelopmentApp() {
  const bool diagnostics = bool.fromEnvironment(
    'FLUTTER_COCKPIT_ENABLE_DEBUG_DIAGNOSTICS',
  );
  return FlutterCockpitApp(
    config: FlutterCockpitConfig.production(
      initialRouteName: SeekoRoutes.targetNavigation,
      remoteSession: CockpitRemoteSessionConfiguration.resolveFromEnvironment(
        fallback: const CockpitRemoteSessionConfiguration(
          enabled: true,
          host: '127.0.0.1',
          port: 47331,
        ),
      ),
      diagnostics: CockpitDiagnosticsConfig(enableRebuildTracking: diagnostics),
    ),
    child: SeekoExampleApp(
      navigatorObservers: <NavigatorObserver>[
        FlutterCockpit.createNavigatorObserver(),
      ],
    ),
  );
}
