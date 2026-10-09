import 'dart:io';

/// Deletes the directory at [path] with what is in it, if there is one.
void deleteTree(String path) {
  final dir = Directory(path);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
}
