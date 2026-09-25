import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:chatbud/models/app_settings.dart';
import 'package:chatbud/models/bud.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/models/message.dart';

class AppDatabase {
  late final Isar isar;

  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();

    isar = await Isar.open(
      [
        ConversationSchema,
        MessageSchema,
        BudSchema,
        AppSettingsSchema,
      ],
      directory: dir.path,
    );
  }
}
