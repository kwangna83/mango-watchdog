import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum MessageAction { copyAll, copyPart, reply }

Future<void> copyMessageToClipboard(String message) {
  return Clipboard.setData(ClipboardData(text: message));
}

Future<MessageAction?> showMessageActionMenu(BuildContext context) {
  return showModalBottomSheet<MessageAction>(
    context: context,
    showDragHandle: true,
    builder:
        (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy_all_rounded),
                title: const Text('전체 복사'),
                onTap: () => Navigator.pop(context, MessageAction.copyAll),
              ),
              ListTile(
                leading: const Icon(Icons.content_copy_rounded),
                title: const Text('부분 복사'),
                onTap: () => Navigator.pop(context, MessageAction.copyPart),
              ),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('답장'),
                onTap: () => Navigator.pop(context, MessageAction.reply),
              ),
            ],
          ),
        ),
  );
}

Future<void> showPartialMessageCopyDialog(
  BuildContext context, {
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: const Text('부분 복사'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(child: SelectableText(message)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        ),
  );
}
