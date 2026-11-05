import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'widgets/common.dart';

/// Writes [content] to a temp file and opens the system share sheet.
/// Falls back to the clipboard if sharing is not possible on this platform.
Future<void> shareCsv(BuildContext context, String filename, String content) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')], subject: filename);
  } catch (e) {
    await Clipboard.setData(ClipboardData(text: content));
    if (context.mounted) {
      showSnack(context, 'Could not open the share sheet ($e). The CSV was copied to the clipboard instead.', error: true);
    }
  }
}
