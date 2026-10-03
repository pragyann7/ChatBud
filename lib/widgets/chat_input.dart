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
        padding: const EdgeInsets.only(left: 12, right: 12, top: 6, bottom: 14),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                enabled: true, // Allow user to type next message while generating
                minLines: 1,
                maxLines: 11, // Expands up to 7 lines then becomes scrollable
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: theme.textTheme.bodyMedium,
                decoration: const InputDecoration(
                  hintText: "Type a message…",
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: 4,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: 6,
                  right: 8,
                  bottom: 6,
                  top: 2,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: "Add attachment",
                      onPressed: isGenerating ? null : onAddAttachment,
                      icon: Icon(
                        Icons.add_rounded,
                        size: 22,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (isGenerating)
                      IconButton(
                        tooltip: "Stop generation",
                        onPressed: onStop,
                        icon: CircleAvatar(
                          radius: 15,
                          backgroundColor: theme.colorScheme.primary,
                          child: Icon(
                            Icons.stop_rounded,
                            size: 16,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      )
                    else
                      IconButton(
                        tooltip: "Send message",
                        onPressed: onSend,
                        icon: CircleAvatar(
                          radius: 15,
                          backgroundColor: theme.colorScheme.primary,
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 18,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
