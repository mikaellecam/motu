// Debug entry point: `flutter run -t lib/main_gallery.dart`. Never part of a
// release build, which only compiles lib/main.dart.
import 'package:flutter/material.dart';

import 'main.dart';
import 'presentation/debug/gallery_screen.dart';

void main() {
  runApp(const MainApp(home: GalleryScreen()));
}
