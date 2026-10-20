import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Exports are written to the app's private cache so they can be shared.
/// They contain financial data, so we remove old ones whenever we can.
Future<void> cleanTempExports() async {
  try {
    final dir = await getTemporaryDirectory();
    await for (final f in dir.list()) {
      if (f is File && f.uri.pathSegments.last.startsWith('spendwise_export')) await f.delete();
    }
  } catch (_) {/* best effort */}
}
