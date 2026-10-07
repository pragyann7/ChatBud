import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:chatbud/models/app_settings.dart';
import 'package:chatbud/repositories/settings_repository.dart';
import 'package:chatbud/screens/models_screen.dart';
import 'package:chatbud/services/huggingface_service.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final HuggingFaceService _hfService = HuggingFaceService();
  late TextEditingController _serverIpController;

  List<File> _downloadedGgufFiles = [];
  bool _isLoadingFiles = true;

  @override
  void initState() {
    super.initState();
    _serverIpController = TextEditingController();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      final files = await _hfService.getDownloadedGgufFiles();
      if (mounted) {
        setState(() {
          _downloadedGgufFiles = files;
          _isLoadingFiles = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingFiles = false);
      }
    }
  }

  @override
  void dispose() {
    _serverIpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsRepo = context.read<SettingsRepository>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: StreamBuilder<AppSettings?>(
        stream: settingsRepo.watchSettings(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final settings = snapshot.data!;
          if (_serverIpController.text.isEmpty && settings.serverIp != null) {
            _serverIpController.text = settings.serverIp!;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // CATEGORY 1: APPEARANCE
              _buildSectionHeader(context, '🎨 Appearance'),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "App Theme:",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'system',
                            label: Text('System'),
                            icon: Icon(Icons.brightness_auto_rounded, size: 16),
                          ),
                          ButtonSegment<String>(
                            value: 'light',
                            label: Text('Light'),
                            icon: Icon(Icons.wb_sunny_rounded, size: 16),
                          ),
                          ButtonSegment<String>(
                            value: 'dark',
                            label: Text('Dark'),
                            icon: Icon(Icons.nightlight_round, size: 16),
                          ),
                        ],
                        selected: {settings.theme},
                        onSelectionChanged: (Set<String> selection) {
                          settingsRepo.updateTheme(selection.first);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // CATEGORY 2: INFERENCE ENGINE & HARDWARE
              _buildSectionHeader(context, '⚡ Inference Engine & Hardware'),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Inference Engine Mode:",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'ollama',
                            label: Text('Ollama (Network)'),
                            icon: Icon(Icons.wifi_rounded, size: 16),
                          ),
                          ButtonSegment<String>(
                            value: 'llama_cpp',
                            label: Text('llama.cpp (Offline)'),
                            icon: Icon(Icons.memory_rounded, size: 16),
                          ),
                        ],
                        selected: {settings.engineType},
                        onSelectionChanged: (Set<String> selection) {
                          settingsRepo.updateEngineType(selection.first);
                        },
                      ),

                      const SizedBox(height: 16),

                      if (settings.engineType == 'ollama') ...[
                        const Text(
                          "Ollama Network Server IP:",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _serverIpController,
                                decoration: const InputDecoration(
                                  labelText: "Server IP / Host",
                                  hintText: "e.g., 192.168.1.74",
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                settingsRepo.updateServerIp(_serverIpController.text.trim());
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Ollama server IP updated!")),
                                );
                              },
                              child: const Text("Save"),
                            ),
                          ],
                        ),
                      ] else ...[
                        const Text(
                          "Hardware Performance Parameters:",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),

                        // CPU Threads Slider
                        Row(
                          children: [
                            const Text("CPU Threads:", style: TextStyle(fontSize: 13)),
                            const Spacer(),
                            Text(
                              "${settings.cpuThreads} threads",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: settings.cpuThreads.toDouble(),
                          min: 1,
                          max: 16,
                          divisions: 15,
                          label: "${settings.cpuThreads} threads",
                          onChanged: (val) {
                            settingsRepo.updateInferenceParams(cpuThreads: val.toInt());
                          },
                        ),

                        const SizedBox(height: 8),

                        // Context Window Dropdown
                        Row(
                          children: [
                            const Text("Context Window:", style: TextStyle(fontSize: 13)),
                            const Spacer(),
                            DropdownButton<int>(
                              value: settings.contextSize,
                              items: const [
                                DropdownMenuItem(value: 1024, child: Text("1024 tokens")),
                                DropdownMenuItem(value: 2048, child: Text("2048 tokens")),
                                DropdownMenuItem(value: 4096, child: Text("4096 tokens")),
                                DropdownMenuItem(value: 8192, child: Text("8192 tokens")),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  settingsRepo.updateInferenceParams(contextSize: val);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // CATEGORY 3: MODEL SELECTION & MANAGEMENT
              _buildSectionHeader(context, '📦 Model Selection & Management'),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Active GGUF Model:",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        settings.modelPath != null
                            ? settings.modelPath!.split('/').last
                            : "No model selected",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: settings.modelPath != null
                              ? Colors.green
                              : theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (!_isLoadingFiles && _downloadedGgufFiles.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: _downloadedGgufFiles.any((f) => f.path == settings.modelPath)
                              ? settings.modelPath
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            labelText: "Select Downloaded Model",
                          ),
                          hint: const Text("Choose model file"),
                          items: _downloadedGgufFiles.map((file) {
                            final name = file.path.split('/').last;
                            return DropdownMenuItem<String>(
                              value: file.path,
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            settingsRepo.updateModelPath(val);
                          },
                        ),
                        const SizedBox(height: 12),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final result = await FilePicker.platform.pickFiles(
                                  type: FileType.any,
                                );
                                if (result != null &&
                                    result.files.isNotEmpty &&
                                    result.files.single.path != null) {
                                  settingsRepo.updateModelPath(result.files.single.path);
                                  _loadFiles();
                                }
                              },
                              icon: const Icon(Icons.folder_open_rounded, size: 16),
                              label: const Text("Browse"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ModelsScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.cloud_download_rounded, size: 16),
                              label: const Text("Models"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
