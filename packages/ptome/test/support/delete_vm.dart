import 'dart:io';

/// Deletes the file at [path], if there is one.
void deleteFile(String path) {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
}
