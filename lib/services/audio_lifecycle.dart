import 'dart:io';

/// Deletes a temporary WAV recording after transcription.
///
/// Returns `true` if the file existed and was deleted.
Future<bool> deleteWavFile(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      return true;
    }
  } catch (_) {
    // Missing file or delete failure — safe to ignore.
  }
  return false;
}
