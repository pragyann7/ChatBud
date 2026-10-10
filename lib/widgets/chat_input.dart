import 'package:flutter/material.dart';

class ChatInput extends StatelessWidget {
  const ChatInput({
    super.key,
    required this.controller,
    required this.isGenerating,
    required this.onSend,
    this.focusNode,
    this.onStop,
    this.onAddAttachment,
    this.enabled = true,
    this.hintText,
  });

  final TextEditingController controller;
  final bool isGenerating;
  final VoidCallback onSend;
  final FocusNode? focusNode;
  final VoidCallback? onStop;
  final VoidCallback? onAddAttachment;
  final bool enabled;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canType = enabled && !isGenerating;
    final canSend = enabled && !isGenerating;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, top: 6, bottom: 14),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(
              enabled ? 0.7 : 0.4,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(
                enabled ? 0.5 : 0.25,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: false,
                enabled: enabled,
                minLines: 1,
                maxLines: 11,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: enabled
                      ? null
                      : theme.colorScheme.onSurface.withOpacity(0.38),
                ),
                decoration: InputDecoration(
                  hintText: hintText ?? "Type a message…",
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: enabled
                        ? theme.colorScheme.onSurfaceVariant.withOpacity(0.7)
                        : theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                    fontStyle: enabled ? FontStyle.normal : FontStyle.italic,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(
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
                      tooltip: enabled ? "Add attachment" : "Model not loaded",
                      onPressed: canType ? onAddAttachment : null,
                      icon: Icon(
                        Icons.add_rounded,
                        size: 22,
                        color: enabled
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
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
                        tooltip: enabled ? "Send message" : (hintText ?? "Model not loaded"),
                        onPressed: canSend ? onSend : null,
                        icon: CircleAvatar(
                          radius: 15,
                          backgroundColor: canSend
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withOpacity(0.12),
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 18,
                            color: canSend
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface.withOpacity(0.38),
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
