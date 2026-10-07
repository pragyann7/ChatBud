import 'package:flutter_test/flutter_test.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart' hide Message;

void main() {
  test('Inspect llama_cpp_dart package exports', () {
    expect(LlamaEngine, isNotNull);
    expect(ModelParams, isNotNull);
    expect(ContextParams, isNotNull);
  });
}
