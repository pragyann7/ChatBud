import 'package:flutter/material.dart';
import 'package:chatbud/models/app_settings.dart';
import 'package:chatbud/repositories/settings_repository.dart';
import 'package:chatbud/screens/models_screen.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _serverIpController;

  @override
  void initState() {
    super.initState();
    _serverIpController = TextEditingController();
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
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // HERO ENGINE OVERVIEW BANNER
              _buildEngineSummaryBanner(context, settings),

              const SizedBox(height: 20),

              // CATEGORY 1: APPEARANCE & THEME
              _buildSectionHeader(
                context,
                title: 'APPEARANCE & THEME',
                icon: Icons.palette_outlined,
              ),
              const SizedBox(height: 10),
              _buildThemeSelector(context, settingsRepo, settings),

              const SizedBox(height: 24),

              // CATEGORY 2: INFERENCE ENGINE & ARCHITECTURE
              _buildSectionHeader(
                context,
                title: 'INFERENCE ENGINE MODE',
                icon: Icons.bolt_rounded,
              ),
              const SizedBox(height: 10),
              _buildEngineSelector(context, settingsRepo, settings),

              if (settings.engineType == 'ollama') ...[
                const SizedBox(height: 14),
                _buildOllamaServerCard(context, settingsRepo, settings),
              ],

              const SizedBox(height: 24),

              // CATEGORY 3: HARDWARE & PERFORMANCE TUNING
              _buildSectionHeader(
                context,
                title: 'HARDWARE & PERFORMANCE TUNING',
                icon: Icons.tune_rounded,
              ),
              const SizedBox(height: 10),
              _buildHardwareTuningCard(context, settingsRepo, settings),

              const SizedBox(height: 24),

              // CATEGORY 4: MODELS & DOWNLOADS SHORTCUT
              _buildSectionHeader(
                context,
                title: 'MODELS & STORAGE',
                icon: Icons.folder_special_outlined,
              ),
              const SizedBox(height: 10),
              _buildModelsHubCard(context, settings),

              const SizedBox(height: 24),

              // CATEGORY 5: ABOUT & FOOTER
              _buildAboutCard(context),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  // HEADER BANNER: Visual status summary
  Widget _buildEngineSummaryBanner(
    BuildContext context,
    AppSettings settings,
  ) {
    final theme = Theme.of(context);
    final isLlama = settings.engineType == 'llama_cpp';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLlama
              ? [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.surfaceContainerHigh,
                ]
              : [
                  theme.colorScheme.tertiaryContainer,
                  theme.colorScheme.surfaceContainerHigh,
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  isLlama ? Icons.memory_rounded : Icons.wifi_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLlama
                          ? 'llama.cpp On-Device Engine'
                          : 'Ollama Remote Server Engine',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLlama
                          ? 'Local GGUF execution • Privacy First'
                          : 'HTTP/REST API Connection',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLlama
                      ? Colors.green.withOpacity(0.15)
                      : Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isLlama ? Colors.green : Colors.blue,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isLlama ? Colors.green : Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLlama ? 'LOCAL' : 'REMOTE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isLlama ? Colors.green : Colors.blue,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBannerStatItem(
                context,
                label: 'CPU Threads',
                value: '${settings.cpuThreads}',
                icon: Icons.developer_board_rounded,
              ),
              _buildBannerStatDivider(context),
              _buildBannerStatItem(
                context,
                label: 'Context Window',
                value: '${settings.contextSize} tks',
                icon: Icons.data_array_rounded,
              ),
              _buildBannerStatDivider(context),
              _buildBannerStatItem(
                context,
                label: 'Batch Size',
                value: '${settings.batchSize}',
                icon: Icons.layers_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBannerStatItem(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildBannerStatDivider(BuildContext context) {
    return Container(
      height: 24,
      width: 1,
      color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
    );
  }

  // SECTION HEADER
  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  // THEME SELECTOR: Unique Card options
  Widget _buildThemeSelector(
    BuildContext context,
    SettingsRepository settingsRepo,
    AppSettings settings,
  ) {
    final themeOptions = [
      {'key': 'system', 'label': 'System', 'icon': Icons.brightness_auto_rounded},
      {'key': 'light', 'label': 'Light', 'icon': Icons.wb_sunny_rounded},
      {'key': 'dark', 'label': 'Dark', 'icon': Icons.nightlight_round},
    ];

    return Row(
      children: themeOptions.map((opt) {
        final isSelected = settings.theme == opt['key'];
        final theme = Theme.of(context);

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => settingsRepo.updateTheme(opt['key'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant.withOpacity(0.5),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      opt['icon'] as IconData,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      opt['label'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ENGINE SELECTOR: Cards for Ollama vs llama.cpp
  Widget _buildEngineSelector(
    BuildContext context,
    SettingsRepository settingsRepo,
    AppSettings settings,
  ) {
    final theme = Theme.of(context);

    return Column(
      children: [
        _buildEngineOptionTile(
          context,
          title: 'llama.cpp (On-Device Local)',
          subtitle:
              'Runs GGUF model files directly on your hardware without internet or network.',
          icon: Icons.memory_rounded,
          isSelected: settings.engineType == 'llama_cpp',
          badgeText: 'RECOMMENDED',
          onTap: () => settingsRepo.updateEngineType('llama_cpp'),
        ),
        const SizedBox(height: 10),
        _buildEngineOptionTile(
          context,
          title: 'Ollama (Remote Network Server)',
          subtitle:
              'Connects over local Wi-Fi or LAN to an external Ollama instance.',
          icon: Icons.wifi_rounded,
          isSelected: settings.engineType == 'ollama',
          badgeText: 'NETWORK API',
          onTap: () => settingsRepo.updateEngineType('ollama'),
        ),
      ],
    );
  }

  Widget _buildEngineOptionTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required String badgeText,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: isSelected ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withOpacity(0.5),
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withOpacity(0.3)
          : theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.primary.withOpacity(0.15)
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Radio<bool>(
                value: true,
                groupValue: isSelected,
                onChanged: (_) => onTap(),
                activeColor: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // OLLAMA SERVER SETTINGS CARD
  Widget _buildOllamaServerCard(
    BuildContext context,
    SettingsRepository settingsRepo,
    AppSettings settings,
  ) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dns_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  "Ollama Server Configuration",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serverIpController,
              decoration: InputDecoration(
                labelText: "Server IP / Hostname",
                hintText: "e.g., 192.168.1.74 or localhost",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check_circle_rounded),
                  tooltip: "Save IP",
                  onPressed: () {
                    settingsRepo.updateServerIp(_serverIpController.text.trim());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Ollama server IP updated!"),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text("localhost"),
                  avatar: const Icon(Icons.computer_rounded, size: 14),
                  onPressed: () {
                    _serverIpController.text = "127.0.0.1";
                    settingsRepo.updateServerIp("127.0.0.1");
                  },
                ),
                ActionChip(
                  label: const Text("Default IP (192.168.1.74)"),
                  avatar: const Icon(Icons.wifi_outlined, size: 14),
                  onPressed: () {
                    _serverIpController.text = "192.168.1.74";
                    settingsRepo.updateServerIp("192.168.1.74");
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // HARDWARE PERFORMANCE CARD
  Widget _buildHardwareTuningCard(
    BuildContext context,
    SettingsRepository settingsRepo,
    AppSettings settings,
  ) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CPU THREADS SLIDER
            Row(
              children: [
                Icon(
                  Icons.developer_board_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  "CPU Cores Allocation",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "${settings.cpuThreads} Threads",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: settings.cpuThreads.toDouble(),
              min: 1,
              max: 16,
              divisions: 15,
              label: "${settings.cpuThreads} Threads",
              onChanged: (val) {
                settingsRepo.updateInferenceParams(cpuThreads: val.toInt());
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("1 Core",
                      style: TextStyle(
                          fontSize: 10, color: theme.colorScheme.outline)),
                  Text("4 Cores (Optimal)",
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary)),
                  Text("16 Cores",
                      style: TextStyle(
                          fontSize: 10, color: theme.colorScheme.outline)),
                ],
              ),
            ),

            const Divider(height: 24),

            // CONTEXT WINDOW SELECTOR CHIPS
            Row(
              children: [
                Icon(
                  Icons.data_array_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  "Context Window (Tokens)",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [1024, 2048, 4096, 8192, 16384].map((size) {
                final isSelected = settings.contextSize == size;
                return ChoiceChip(
                  label: Text("${size ~/ 1024}K tokens"),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      settingsRepo.updateInferenceParams(contextSize: size);
                    }
                  },
                );
              }).toList(),
            ),

            const Divider(height: 24),

            // BATCH SIZE SELECTOR
            Row(
              children: [
                Icon(
                  Icons.layers_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  "Evaluation Batch Size",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [128, 256, 512, 1024].map((batch) {
                final isSelected = settings.batchSize == batch;
                return ChoiceChip(
                  label: Text("$batch tokens"),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      settingsRepo.updateInferenceParams(batchSize: batch);
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // MODELS & DOWNLOADS SHORTCUT CARD
  Widget _buildModelsHubCard(BuildContext context, AppSettings settings) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ModelsScreen(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.file_download_outlined,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Model Hub & Downloads",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Browse HuggingFace GGUF models, manage offline model files & active model selection.",
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ABOUT & FOOTER
  Widget _buildAboutCard(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.smart_toy_rounded,
              color: theme.colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "ChatBud • On-Device AI",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Version 1.0.0 • Isar DB • llama.cpp 0.9.0",
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
