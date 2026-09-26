import 'package:flutter/foundation.dart';

class LlmService {
  Stream<String> generate({
    required String prompt,
    String? systemPrompt,
  }) async* {
    debugPrint("LLM Generation with System Prompt: $systemPrompt");

    final hello = ["Hello ", "how ", "can ", "i ", "help ", "you."];
    final whatIsFlutter = [
      "Flutter ",
      "is ",
      "a ",
      "UI ",
      "framework ",
      "for ",
      "building ",
      "apps."
    ];
    final howRU = ["I ", "am ", "fine. ", "How ", "about ", "you?.😁"];
    final whoRU = [
      "I ",
      "am ",
      "a ",
      "ChatBud ",
      "created ",
      "by ",
      "Pragyanics."
    ];

    final longResponse = [
      "Flutter ", "is ", "an ", "open-source ", "UI ", "software ", "development ",
      "kit ", "created ", "by ", "Google. ", "It ", "is ", "used ", "to ", "develop ",
      "cross-platform ", "applications ", "for ", "Android, ", "iOS, ", "Linux, ",
      "macOS, ", "Windows, ", "Google ", "Fuchsia, ", "and ", "the ", "web ", "from ",
      "a ", "single ", "codebase.\n\n",
      "First ", "introduced ", "in ", "2015, ", "Flutter ", "was ", "officially ",
      "launched ", "in ", "December ", "2018. ", "Since ", "then, ", "it ", "has ",
      "grown ", "rapidly ", "in ", "popularity ", "among ", "developers ", "worldwide.\n\n",
      "Key ", "Features ", "of ", "Flutter:\n",
      "1. ", "Hot ", "Reload: ", "Allows ", "developers ", "to ", "see ", "changes ",
      "instantly ", "without ", "restarting ", "the ", "app.\n",
      "2. ", "Expressive ", "and ", "Flexible ", "UI: ", "A ", "rich ", "set ", "of ",
      "customizable ", "widgets ", "for ", "building ", "native ", "interfaces.\n",
      "3. ", "Native ", "Performance: ", "Compiles ", "to ", "native ", "ARM ",
      "or ", "Intel ", "machine ", "code ", "as ", "well ", "as ", "JavaScript.\n\n",
      "Flutter ", "uses ", "the ", "Dart ", "programming ", "language, ", "which ",
      "provides ", "strong ", "typing, ", "garbage ", "collection, ", "and ",
      "rich ", "standard ", "libraries."
    ];

    List<String> responseTokens;

    switch (prompt.toLowerCase().trim()) {
      case "hello":
      case "hi":
        responseTokens = hello;
        break;
      case "what is flutter":
      case "what is flutter?":
        responseTokens = whatIsFlutter;
        break;
      case "how are you":
      case "how are you?":
        responseTokens = howRU;
        break;
      case "who are you":
      case "who are you?":
        responseTokens = whoRU;
        break;
      case "long":
      case "test":
      case "tell me a long story":
        responseTokens = longResponse;
        break;
      default:
        // Tailor response slightly based on system prompt for demonstration
        if (systemPrompt != null && systemPrompt.contains("programming")) {
          responseTokens = [
            "As ", "a ", "coding ", "assistant: ", "Here ", "is ", "how ", "you ",
            "can ", "implement ", "that: ", "```dart\nvoid main() {\n  print('$prompt');\n}\n```"
          ];
        } else if (systemPrompt != null && systemPrompt.contains("tutor")) {
          responseTokens = [
            "Let ", "me ", "explain ", "this ", "step-by-step ", "like ", "a ",
            "tutor: ", "Think ", "of ", prompt, " as ", "a ", "building ", "block!"
          ];
        } else {
          responseTokens = ["I'm ", "here ", "to ", "help ", "you ", "with: ", prompt];
        }
        break;
    }

    for (final token in responseTokens) {
      await Future.delayed(const Duration(milliseconds: 100));
      yield token;
    }
  }
}
