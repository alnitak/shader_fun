import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> loadFileOrHttpBytes(String path) async {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    final uri = Uri.parse(path);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final builder = BytesBuilder();
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.toBytes();
    } finally {
      client.close();
    }
  } else if (path.startsWith('file://') ||
      path.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path)) {
    final cleanPath = path.startsWith('file://')
        ? Uri.parse(path).toFilePath()
        : path;
    final file = File(cleanPath);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
  }
  return null;
}

Uint8List? tryLoadFilesystemCandidates(List<String> candidates) {
  for (final cand in candidates) {
    final f = File(cand);
    if (f.existsSync()) {
      return f.readAsBytesSync();
    }
  }
  return null;
}
