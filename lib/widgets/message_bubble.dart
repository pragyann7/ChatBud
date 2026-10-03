import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:chatbud/models/message.dart';

class ParsedMessage {
  final String? thinkingText;
  final String answerText;
  final bool isStillThinking;

  ParsedMessage({
    this.thinkingText,
    required this.answerText,
    required this.isStillThinking,
  });

  static ParsedMessage parse(String rawText) {
    if (!rawText.contains('<think>')) {
      return ParsedMessage(
        answerText: rawText,
        isStillThinking: false,
      );
    }

    final thinkStartIndex = rawText.indexOf('<think>') + 7;
    if (!rawText.contains('</think>')) {
      final thinking = rawText.substring(thinkStartIndex).trim();
      return ParsedMessage(
        thinkingText: thinking,
        answerText: '',
        isStillThinking: true,
      );
    }

    final thinkEndIndex = rawText.indexOf('</think>');
    final thinking = rawText.substring(thinkStartIndex, thinkEndIndex).trim();
    final answer = rawText.substring(thinkEndIndex + 8).trim();

    return ParsedMessage(
      thinkingText: thinking,
      answerText: answer,
      isStillThinking: false,
    );
  }
}

class ThinkingAccordion extends StatefulWidget {
  final String thinkingText;
  final bool isStillThinking;

  const ThinkingAccordion({
    super.key,
    required this.thinkingText,
    required this.isStillThinking,
  });

  @override
  State<ThinkingAccordion> createState() => _ThinkingAccordionState();
}

class _ThinkingAccordionState extends State<ThinkingAccordion> {
  bool? _userExpanded;

  bool get _isExpanded => _userExpanded ?? widget.isStillThinking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _userExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.isStillThinking
                          ? "Thinking…"
                          : "Thought Process",
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded && widget.thinkingText.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.thinkingText,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.textListenable,
    this.onRetry,
    this.isLatest = true,
  });

  final Message message;
  final ValueListenable<String>? textListenable;
  final VoidCallback? onRetry;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGenerating = textListenable != null;
    final isFailed = message.status == MessageStatus.failed;
    final showFailedBadge = isFailed && !message.isUser && isLatest && !isGenerating;

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
          border: showFailedBadge
              ? Border.all(
                  color: theme.colorScheme.error.withOpacity(0.5),
                  width: 1,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.isUser)
              DefaultTextStyle.merge(
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                child: Text(message.text),
              )
            else ...[
              textListenable == null
                  ? _buildParsedAssistantMessage(context, message.text)
                  : ValueListenableBuilder<String>(
                      valueListenable: textListenable!,
                      builder: (context, value, _) {
                        final raw = value.isNotEmpty ? value : message.text;
                        return _buildParsedAssistantMessage(context, raw);
                      },
                    ),
            ],
            if (showFailedBadge) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "Generation failed",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onRetry,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 12,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "Retry",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParsedAssistantMessage(BuildContext context, String rawText) {
    final theme = Theme.of(context);
    final parsed = ParsedMessage.parse(rawText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (parsed.thinkingText != null && parsed.thinkingText!.isNotEmpty)
          ThinkingAccordion(
            thinkingText: parsed.thinkingText!,
            isStillThinking: parsed.isStillThinking,
          ),
        if (parsed.answerText.isNotEmpty)
          DefaultTextStyle.merge(
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            child: Text(parsed.answerText),
          ),
      ],
    );
  }
}
