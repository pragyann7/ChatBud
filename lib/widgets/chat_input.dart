import 'package:flutter/material.dart';

class ChatInput extends StatelessWidget {
  const ChatInput({
    super.key,
    required this.controller,
    required this.isGenerating,
    required this.onSend,
    this.onAddAttachment,
  });

  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback onSend;
  final VoidCallback? onAddAttachment;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            IconButton(
              onPressed: isGenerating ? null : onAddAttachment,
              icon: const Icon(Icons.add),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !isGenerating,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: isGenerating ? "Generating…" : "Type a message…",
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
            IconButton(
              tooltip: "Send message",
              onPressed: isGenerating ? null : onSend,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
