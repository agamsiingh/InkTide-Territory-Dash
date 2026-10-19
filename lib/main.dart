import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
  ));
  LicenseRegistry.addLicense(() async* {
    for (final f in ['Fredoka', 'LilitaOne']) {
      final text = await rootBundle.loadString('assets/fonts/LICENSE-$f-OFL.txt');
      yield LicenseEntryWithLineBreaks([f], text);
    }
  });
  runApp(const InkTideApp());
}
