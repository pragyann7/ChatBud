import 'dart:io';
import 'package:flutter/material.dart';
import 'package:chatbud/models/hugging_face_model.dart';
import 'package:chatbud/repositories/settings_repository.dart';
import 'package:chatbud/services/huggingface_service.dart';
import 'package:provider/provider.dart';

class ModelHubScreen extends StatefulWidget {
  const ModelHubScreen({super.key});

  @override
  State<ModelHubScreen> createState() => _ModelHubScreenState();
}

class _ModelHubScreenState extends State<ModelHubScreen>
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
    if (query.isEmpty) return;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  void _showRepoFilesSheet(HuggingFaceRepo repo) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return FutureBuilder<List<GgufFile>>(
              future: _hfService.getRepoGgufFiles(repo.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Error: ${snapshot.error}'),
                    ),
                  );
                }

                final files = snapshot.data ?? [];
                if (files.isEmpty) {
                  return const Center(
                    child: Text('No .gguf files found in this repository.'),
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        repo.id,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _hfService,
                        builder: (context, _) {
                          return ListView.builder(
                            controller: scrollController,
                            itemCount: files.length,
                            itemBuilder: (context, index) {
                              final file = files[index];
                              final isDownloading =
                                  _hfService.isDownloading(file.fileName);

                              return ListTile(
                                leading: const Icon(Icons.insert_drive_file_outlined),
                                title: Text(
                                  file.fileName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(file.formattedSize),
                                trailing: isDownloading
                                    ? IconButton(
                                        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                                        onPressed: () => _cancelDownload(file.fileName),
                                      )
                                    : IconButton(
                                        icon: const Icon(Icons.download_rounded),
                                        onPressed: () {
                                          Navigator.pop(ctx);
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
                      ),
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
        title: const Text('Model Hub (GGUF Downloader)'),
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
          return StreamBuilder(
            stream: settingsRepo.watchSettings(),
            builder: (context, snapshot) {
              final activeModelPath = snapshot.data?.modelPath;

              return TabBarView(
                controller: _tabController,
                children: [
                  _buildRecommendedTab(activeModelPath),
                  _buildSearchTab(),
                  _buildDownloadedTab(settingsRepo, activeModelPath),
                ],
              );
            },
          );
        },
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
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
                  LinearProgressIndicator(value: progress > 0 ? progress : null),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        statusText,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _cancelDownload(preset.fileName),
                        icon: const Icon(Icons.close_rounded, size: 14),
                        label: const Text('Cancel', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isDownloaded)
                        const Chip(
                          avatar: Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                          label: Text('Downloaded', style: TextStyle(fontSize: 12)),
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
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        if (_isSearching) const Expanded(child: Center(child: CircularProgressIndicator())),
        if (_searchError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_searchError, style: const TextStyle(color: Colors.red)),
          ),
        if (!_isSearching && _searchError.isEmpty)
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(child: Text('Type a keyword to search Hugging Face GGUF models.'))
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final repo = _searchResults[index];
                      return ListTile(
                        title: Text(
                          repo.id,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text('Downloads: ${repo.downloads} • Likes: ${repo.likes}'),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                        onTap: () => _showRepoFilesSheet(repo),
                      );
                    },
                  ),
          ),
      ],
    );
  }

  Widget _buildDownloadedTab(SettingsRepository settingsRepo, String? activeModelPath) {
    if (_isLoadingDownloaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_downloadedFiles.isEmpty) {
      return const Center(
        child: Text('No downloaded .gguf models found.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _downloadedFiles.length,
      itemBuilder: (context, index) {
        final file = _downloadedFiles[index];
        final fileName = file.path.split('/').last;
        final isActive = activeModelPath == file.path;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: Icon(
              Icons.memory_rounded,
              color: isActive ? Colors.green : Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              fileName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(isActive ? 'Active Engine Model' : 'Offline GGUF File'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isActive)
                  IconButton(
                    tooltip: 'Set as Active Model',
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    onPressed: () async {
                      await settingsRepo.updateModelPath(file.path);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Set $fileName as Active Model!')),
                        );
                      }
                    },
                  )
                else
                  const Chip(
                    label: Text('ACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    backgroundColor: Colors.greenAccent,
                  ),
                IconButton(
                  tooltip: 'Delete File',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
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
      },
    );
  }
}
