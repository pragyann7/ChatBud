import 'package:flutter_test/flutter_test.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart' hide Message;

void main() {
  test('Inspect LlamaParent exports', () {
    expect(LlamaParent, isNotNull);
  });
}
