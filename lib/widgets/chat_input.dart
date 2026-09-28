import 'package:flutter/material.dart';

class ChatInput extends StatelessWidget {
  const ChatInput({
    super.key,
    required this.controller,
    required this.isGenerating,
    required this.onSend,
    this.onStop,
    this.onAddAttachment,
  });

  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final VoidCallback? onAddAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 26),
        child: Row(
          children: [
            IconButton(
              onPressed: isGenerating ? null : onAddAttachment,
              icon: const Icon(Icons.add),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: true, // Allow user to type next message while generating
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (!isGenerating) {
                    onSend();
                  }
                },
                decoration: InputDecoration(
                  hintText: "Type a message…",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (isGenerating)
              IconButton(
                tooltip: "Stop generation",
                onPressed: onStop,
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primary,
                  child: Icon(
                    Icons.stop_rounded,
                    size: 18,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              )
            else
              IconButton(
                tooltip: "Send message",
                onPressed: onSend,
                icon: const Icon(Icons.send_rounded),
              ),
          ],
        ),
      ),
    );
  }
}
