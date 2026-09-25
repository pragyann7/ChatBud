import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:chatbud/models/message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.textListenable,
  });

  final Message message;
  final ValueListenable<String>? textListenable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = textListenable == null
        ? Text(message.text)
        : ValueListenableBuilder<String>(
            valueListenable: textListenable!,
            builder: (context, value, _) => Text(value),
          );

    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: message.isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: message.isUser
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
          child: text,
        ),
      ),
    );
  }
}
