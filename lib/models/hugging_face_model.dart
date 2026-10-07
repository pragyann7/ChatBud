class HuggingFaceRepo {
  final String id;
  final String author;
  final String modelName;
  final int downloads;
  final int likes;
  final List<String> tags;
  final String pipelineTag;
  final String license;

  HuggingFaceRepo({
    required this.id,
    required this.author,
    required this.modelName,
    required this.downloads,
    required this.likes,
    required this.tags,
    required this.pipelineTag,
    required this.license,
  });

  factory HuggingFaceRepo.fromJson(Map<String, dynamic> json) {
    final String idStr = json['id'] as String? ?? '';
    final parts = idStr.split('/');
    final author = parts.length > 1 ? parts[0] : 'huggingface';
    final modelName = parts.length > 1 ? parts.sublist(1).join('/') : idStr;

    final tagsList = (json['tags'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    String foundLicense = 'LICENSE N/A';
    for (final tag in tagsList) {
      if (tag.startsWith('license:')) {
        foundLicense = tag.substring(8).toUpperCase();
        break;
      }
    }

    return HuggingFaceRepo(
      id: idStr,
      author: author,
      modelName: modelName,
      downloads: json['downloads'] as int? ?? 0,
      likes: json['likes'] as int? ?? 0,
      tags: tagsList,
      pipelineTag: json['pipeline_tag'] as String? ?? 'text-generation',
      license: foundLicense,
    );
  }
}

class GgufFile {
  final String fileName;
  final String downloadUrl;
  final int sizeBytes;

  GgufFile({
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  String get formattedSize {
    if (sizeBytes <= 0) return 'Size unknown';
    final mb = sizeBytes / (1024 * 1024);
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}

class PresetModel {
  final String title;
  final String description;
  final String repoId;
  final String fileName;
  final String downloadUrl;
  final String sizeText;

  const PresetModel({
    required this.title,
    required this.description,
    required this.repoId,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeText,
  });
}
