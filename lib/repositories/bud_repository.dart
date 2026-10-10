import 'package:isar/isar.dart';
import 'package:chatbud/models/bud.dart';

class BudRepository {
  final Isar isar;

  BudRepository(this.isar);

  Future<void> seedDefaultBuds() async {
    final defaultBuds = [
      Bud(
        id: 1,
        name: "General Bud",
        systemPrompt:
            "You are ChatBud, a helpful, friendly, and knowledgeable AI assistant.",
        iconName: "smart_toy",
        isDefault: true,
      ),
      Bud(
        id: 2,
        name: "Coding Bud",
        systemPrompt:
            "You are an expert programming assistant and software architect. Provide clean, efficient, well-documented code examples and concise explanations.",
        iconName: "code",
        isDefault: true,
      ),
      Bud(
        id: 3,
        name: "Study Bud",
        systemPrompt:
            "You are an encouraging and patient tutor. Explain complex concepts clearly using analogies, step-by-step guidance, and engaging questions.",
        iconName: "school",
        isDefault: true,
      ),
      Bud(
        id: 4,
        name: "Creative Bud",
        systemPrompt:
            "You are an imaginative creative writer and brainstorming partner. Help express ideas vividly with rich vocabulary and narrative flair.",
        iconName: "palette",
        isDefault: true,
      ),
    ];

    await isar.writeTxn(() async {
      for (final bud in defaultBuds) {
        final existing = await isar.buds.get(bud.id);
        if (existing == null) {
          await isar.buds.put(bud);
        }
      }
    });
  }

  Future<List<Bud>> getBuds() async {
    return await isar.buds.where().findAll();
  }

  Stream<List<Bud>> watchBuds() {
    return isar.buds
        .where()
        .watch(fireImmediately: true)
        .asBroadcastStream();
  }

  Future<Bud?> getBud(int id) async {
    return await isar.buds.get(id);
  }

  Future<Bud> getDefaultBud() async {
    final buds = await getBuds();
    if (buds.isNotEmpty) {
      return buds.firstWhere((b) => b.isDefault, orElse: () => buds.first);
    }
    final fallback = Bud(
      id: 1,
      name: "General Bud",
      systemPrompt:
          "You are ChatBud, a helpful, friendly, and knowledgeable AI assistant.",
      iconName: "smart_toy",
      isDefault: true,
    );
    await saveBud(fallback);
    return fallback;
  }

  Future<int> saveBud(Bud bud) async {
    return await isar.writeTxn(() async {
      return await isar.buds.put(bud);
    });
  }

  Future<bool> deleteBud(int id) async {
    return await isar.writeTxn(() async {
      final bud = await isar.buds.get(id);
      if (bud != null && bud.isDefault) {
        // Prevent deleting built-in default buds
        return false;
      }
      return await isar.buds.delete(id);
    });
  }
}
