import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:chatbud/models/app_settings.dart';
import 'package:chatbud/models/hugging_face_model.dart';
import 'package:chatbud/repositories/settings_repository.dart';
import 'package:chatbud/services/huggingface_service.dart';
import 'package:chatbud/services/llama_cpp_service.dart';
import 'package:provider/provider.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final HuggingFaceService _hfService = HuggingFaceService();
  final TextEditingController _searchController = TextEditingController();

  List<HuggingFaceRepo> _searchResults = [];
  bool _isSearching = false;
  String _searchError = '';

  List<File> _downloadedFiles = [];
  bool _isLoadingDownloaded = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDownloadedModels();
    _fetchInitialTrendingModels();
  }

  Future<void> _fetchInitialTrendingModels() async {
    setState(() {
      _isSearching = true;
      _searchError = '';
    });

    try {
      final results = await _hfService.fetchTrendingGgufModels();
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = 'Failed to load trending models: $e';
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _loadDownloadedModels() async {
    setState(() => _isLoadingDownloaded = true);
    try {
      final files = await _hfService.getDownloadedGgufFiles();
      if (mounted) {
        setState(() {
          _downloadedFiles = files;
          _isLoadingDownloaded = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDownloaded = false);
      }
    }
  }

  Future<void> _searchModels() async {
    final query = _searchController.text.trim();

    setState(() {
      _isSearching = true;
      _searchError = '';
    });

    try {
      final results = await _hfService.searchGgufModels(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = 'Failed to search models: $e';
          _isSearching = false;
        });
      }
    }
  }

  void _cancelDownload(String fileName) {
    _hfService.cancelDownload(fileName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Download cancelled for $fileName.')),
    );
  }

  Future<void> _startDownload({
    required String downloadUrl,
    required String fileName,
  }) async {
    try {
      await _hfService.startGgufDownload(
        downloadUrl: downloadUrl,
        fileName: fileName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded $fileName successfully!')),
        );
        _loadDownloadedModels();
      }
    } catch (e) {
      if (mounted && !e.toString().contains('DOWNLOAD_CANCELLED')) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  Future<void> _pickLocalGgufFile(SettingsRepository settingsRepo) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    if (result != null &&
        result.files.isNotEmpty &&
        result.files.single.path != null) {
      final selectedPath = result.files.single.path!;
      if (LlamaCppAiService.loadedModelPath != null &&
          LlamaCppAiService.loadedModelPath != selectedPath) {
        await LlamaCppAiService.unloadModel();
      }
      await settingsRepo.updateModelPath(selectedPath);
      await _loadDownloadedModels();

      if (mounted) {
        final name = selectedPath.split('/').last;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported and set active model: $name')),
        );
      }
    }
  }

  void _showRepoFilesSheet(HuggingFaceRepo repo) async {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return FutureBuilder<List<GgufFile>>(
              future: _hfService.getRepoGgufFiles(repo.id),
              builder: (context, snapshot) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Model Details & Metadata Header Card
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                repo.author,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  repo.license,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            repo.modelName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Chip(
                                avatar: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                                label: Text(
                                  repo.pipelineTag,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "📥 ${_formatCount(repo.downloads)} downloads",
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "❤️ ${_formatCount(repo.likes)} likes",
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        "AVAILABLE GGUF QUANTIZATIONS:",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    Expanded(
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const Center(child: CircularProgressIndicator())
                          : (snapshot.hasError
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text('Error: ${snapshot.error}'),
                                  ),
                                )
                              : ((snapshot.data ?? []).isEmpty
                                  ? const Center(
                                      child: Text('No .gguf files found in this repository.'),
                                    )
                                  : AnimatedBuilder(
                                      animation: _hfService,
                                      builder: (context, _) {
                                        final files = snapshot.data!;
                                        return ListView.builder(
                                          controller: scrollController,
                                          itemCount: files.length,
                                          itemBuilder: (context, index) {
                                            final file = files[index];
                                            final isDownloading =
                                                _hfService.isDownloading(file.fileName);

                                            if (isDownloading) {
                                              final progress = _hfService.getProgress(file.fileName);
                                              final statusText = _hfService.getStatusText(file.fileName);

                                              return Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 16, vertical: 8),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            file.fileName,
                                                            style: const TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        TextButton.icon(
                                                          style: TextButton.styleFrom(
                                                            foregroundColor: Colors.red,
                                                            padding: const EdgeInsets.symmetric(
                                                                horizontal: 6, vertical: 2),
                                                            minimumSize: Size.zero,
                                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                          ),
                                                          onPressed: () => _cancelDownload(file.fileName),
                                                          icon: const Icon(Icons.close_rounded, size: 14),
                                                          label: const Text('Cancel', style: TextStyle(fontSize: 11)),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    LinearProgressIndicator(value: progress > 0 ? progress : null),
                                                    const SizedBox(height: 4),
                                                    Text(statusText, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                                  ],
                                                ),
                                              );
                                            }

                                            return ListTile(
                                              leading: const Icon(
                                                Icons.memory_rounded,
                                              ),
                                              title: Text(
                                                file.fileName,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              subtitle: Text(file.formattedSize),
                                              trailing: IconButton(
                                                icon: const Icon(
                                                  Icons.download_rounded,
                                                ),
                                                onPressed: () {
                                                  _startDownload(
                                                    downloadUrl: file.downloadUrl,
                                                    fileName: file.fileName,
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ))),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsRepo = context.read<SettingsRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Model Hub & Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Recommended'),
            Tab(text: 'Search HF'),
            Tab(text: 'Downloaded'),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: _hfService,
        builder: (context, _) {
          return StreamBuilder<AppSettings?>(
            stream: settingsRepo.watchSettings(),
            builder: (context, snapshot) {
              final settings = snapshot.data;
              final activeModelPath = settings?.modelPath;

              return Column(
                children: [
                  // ACTIVE MODEL TOP STATUS BANNER
                  _buildActiveModelTopBanner(context, settings),

                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildRecommendedTab(activeModelPath),
                        _buildSearchTab(),
                        _buildDownloadedTab(settingsRepo, activeModelPath),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // TOP ACTIVE MODEL BANNER
  Widget _buildActiveModelTopBanner(
    BuildContext context,
    AppSettings? settings,
  ) {
    final theme = Theme.of(context);
    final isLlama = settings?.engineType == 'llama_cpp';
    final modelPath = settings?.modelPath;
    final activeModelName = modelPath != null && modelPath.isNotEmpty
        ? modelPath.split('/').last
        : null;

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            isLlama ? Icons.memory_rounded : Icons.wifi_rounded,
            size: 18,
            color: activeModelName != null ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      "ACTIVE MODEL: ",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: Colors.grey,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isLlama
                            ? Colors.green.withOpacity(0.15)
                            : Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isLlama ? 'llama.cpp' : 'Ollama',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isLlama ? Colors.green : Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  activeModelName ?? "No model selected (Local Engine)",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: activeModelName != null
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.error,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (activeModelName != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 12, color: Colors.green),
                  SizedBox(width: 4),
                  Text(
                    "LOADED",
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecommendedTab(String? activeModelPath) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: HuggingFaceService.recommendedModels.length,
      itemBuilder: (context, index) {
        final preset = HuggingFaceService.recommendedModels[index];
        final isDownloading = _hfService.isDownloading(preset.fileName);
        final progress = _hfService.getProgress(preset.fileName);
        final statusText = _hfService.getStatusText(preset.fileName);

        final isDownloaded = _downloadedFiles.any(
          (f) => f.path.endsWith(preset.fileName),
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        preset.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer
                            .withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        preset.sizeText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  preset.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (isDownloading) ...[
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _cancelDownload(preset.fileName),
                        icon: const Icon(Icons.close_rounded, size: 14),
                        label: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isDownloaded)
                        const Chip(
                          avatar: Icon(
                            Icons.check_circle_rounded,
                            color: Colors.green,
                            size: 18,
                          ),
                          label: Text(
                            'Downloaded',
                            style: TextStyle(fontSize: 12),
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () {
                            _startDownload(
                              downloadUrl: preset.downloadUrl,
                              fileName: preset.fileName,
                            );
                          },
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Download GGUF'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchTab() {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search GGUF repo (e.g. qwen, llama, phi)...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onSubmitted: (_) => _searchModels(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _searchModels,
                icon: const Icon(Icons.search_rounded),
              ),
            ],
          ),
        ),
        if (_isSearching)
          const Expanded(child: Center(child: CircularProgressIndicator())),
        if (_searchError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _searchError,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        if (!_isSearching && _searchError.isEmpty)
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(
                    child: Text('No GGUF models found.'),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final repo = _searchResults[index];

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _showRepoFilesSheet(repo),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.person_outline_rounded,
                                      size: 14,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        repo.author,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: Text(
                                    repo.modelName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.secondaryContainer
                                            .withOpacity(0.8),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        repo.license,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.onSecondaryContainer,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.tertiaryContainer
                                            .withOpacity(0.6),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        repo.pipelineTag,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.onTertiaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 12),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.download_rounded,
                                      size: 13,
                                      color: theme.colorScheme.outline,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      _formatCount(repo.downloads),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(
                                      Icons.favorite_rounded,
                                      size: 13,
                                      color: Colors.redAccent.shade100,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      _formatCount(repo.likes),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.outline,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () => _showRepoFilesSheet(repo),
                                    child: const Text(
                                      "Browse Files",
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '$count';
  }

  Widget _buildDownloadedTab(
    SettingsRepository settingsRepo,
    String? activeModelPath,
  ) {
    final theme = Theme.of(context);
    final activeDownloadingKeys =
        _hfService.activeDownloadProgress.keys.toList();

    if (_isLoadingDownloaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // LOCAL IMPORT CALL-TO-ACTION CARD
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.folder_open_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Import Local GGUF File",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "Browse device storage for external GGUF models.",
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _pickLocalGgufFile(settingsRepo),
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text("Browse", style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Active In-Progress Downloads Section
        if (activeDownloadingKeys.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
            child: Text(
              "IN PROGRESS DOWNLOADS",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ...activeDownloadingKeys.map((fileName) {
            final progress = _hfService.getProgress(fileName);
            final statusText = _hfService.getStatusText(fileName);

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            fileName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _cancelDownload(fileName),
                          icon: const Icon(Icons.close_rounded, size: 14),
                          label: const Text(
                            'Cancel',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusText,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }),
          Divider(
            height: 20,
            thickness: 0.8,
            color: theme.colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ],

        // Downloaded Models List Section
        if (_downloadedFiles.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
            child: Text(
              "OFFLINE GGUF MODELS (${_downloadedFiles.length})",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          ..._downloadedFiles.map((file) {
            final fileName = file.path.split('/').last;
            final isActive = activeModelPath == file.path;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isActive
                      ? Colors.green.withOpacity(0.8)
                      : theme.colorScheme.outlineVariant.withOpacity(0.3),
                  width: isActive ? 2 : 1,
                ),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.memory_rounded,
                  color: isActive ? Colors.green : theme.colorScheme.primary,
                ),
                title: Text(
                  fileName,
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  isActive ? 'Active Engine Model' : 'Offline GGUF File',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isActive)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.check_circle_outline_rounded,
                            size: 14),
                        label: const Text('Use', style: TextStyle(fontSize: 11)),
                        onPressed: () async {
                          if (LlamaCppAiService.loadedModelPath != null &&
                              LlamaCppAiService.loadedModelPath != file.path) {
                            await LlamaCppAiService.unloadModel();
                          }
                          await settingsRepo.updateModelPath(file.path);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Set $fileName as Active Model!'),
                              ),
                            );
                          }
                        },
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Delete File',
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.red, size: 20),
                      onPressed: () async {
                        if (LlamaCppAiService.loadedModelPath == file.path) {
                          await LlamaCppAiService.unloadModel();
                        }
                        await _hfService.deleteDownloadedFile(file.path);
                        if (isActive) {
                          await settingsRepo.updateModelPath(null);
                        }
                        _loadDownloadedModels();
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
        ] else if (activeDownloadingKeys.isEmpty) ...[
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.extension_off_outlined,
                  size: 48,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  'No local .gguf models found',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Import a local .gguf file using the button above\nor download from Recommended / Search HF tabs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
