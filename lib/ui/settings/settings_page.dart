import 'package:flutter/material.dart';

import '../../core/database/local_storage.dart';
import '../../core/events/app_events.dart';
import '../../core/services/opml_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_settings.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback onThemeChanged;

  const SettingsPage({super.key, required this.onThemeChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  AppSettings _settings = AppSettings();
  bool _isLoading = true;
  bool _isSyncing = false;
  late AnimationController _syncAnimController;

  // Supabase Auth inputs
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isAuthLoading = false;

  @override
  void initState() {
    super.initState();
    _syncAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _loadSettings();
  }

  @override
  void dispose() {
    _syncAnimController.dispose();
    super.dispose();
  }

  Future<void> _performPush() async {
    setState(() => _isSyncing = true);
    _syncAnimController.repeat();
    try {
      await SyncService.instance.pushToCloud();
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        _syncAnimController.stop();
        _syncAnimController.reset();
      }
    }
  }

  Future<void> _performPull() async {
    setState(() => _isSyncing = true);
    _syncAnimController.repeat();
    try {
      await SyncService.instance.pullFromCloud();
      await _loadSettings();
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        _syncAnimController.stop();
        _syncAnimController.reset();
      }
    }
  }

  Future<void> _loadSettings() async {
    final settings = await LocalStorage.instance.getSettings();
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  Future<void> _updateSettings(AppSettings updated) async {
    setState(() {
      _settings = updated;
    });
    await LocalStorage.instance.saveSettings(updated);
    widget.onThemeChanged();

    // If signed in, automatically sync to Supabase
    if (SyncService.instance.isAuthenticated) {
      await SyncService.instance.pushToCloud();
    }
  }

  static const Map<String, String> _countryNames = {
    'us': 'United States (US)',
    'br': 'Brazil (BR)',
    'gb': 'United Kingdom (UK)',
    'ca': 'Canada (CA)',
    'au': 'Australia (AU)',
    'de': 'Germany (DE)',
    'fr': 'France (FR)',
    'es': 'Spain (ES)',
    'pt': 'Portugal (PT)',
    'it': 'Italy (IT)',
    'jp': 'Japan (JP)',
    'mx': 'Mexico (MX)',
  };

  void _showRegionPickerModal(BuildContext context, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.public, size: 22),
                    const SizedBox(width: 12),
                    Text(
                      'Select Discover Region',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.55,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: _countryNames.entries.map((entry) {
                    final isSelected =
                        _settings.countryCode.toLowerCase() == entry.key;
                    return ListTile(
                      title: Text(
                        entry.value,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? theme.colorScheme.primary : null,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle,
                              color: theme.colorScheme.primary)
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        _updateRegion(entry.key);
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateRegion(String countryCode) async {
    await _updateSettings(_settings.copyWith(countryCode: countryCode));
    AppEvents.notifyDiscoverRefresh();
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      return;
    }
    setState(() => _isAuthLoading = true);
    try {
      await SyncService.instance.signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected to JoyPlay & synced!')),
        );
      }
      _loadSettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Login failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isAuthLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    await SyncService.instance.signOut();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isAuthed = SyncService.instance.isAuthenticated;
    final userEmail = SyncService.instance.userEmail;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: JoyPlay / Supabase Sync
          _buildSectionHeader('CLOUD SYNC & JOYPLAY', theme),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: isAuthed
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Connected as $userEmail',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.cloud_upload_outlined),
                              label: const Text('Push'),
                              onPressed: _isSyncing ? null : _performPush,
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.cloud_download_outlined),
                              label: const Text('Pull'),
                              onPressed: _isSyncing ? null : _performPull,
                            ),
                            if (_isSyncing) ...[
                              const SizedBox(width: 12),
                              RotationTransition(
                                turns: _syncAnimController,
                                child: Icon(
                                  Icons.sync,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                            const Spacer(),
                            TextButton(
                              onPressed: _handleLogout,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Sign Out'),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Supabase / JoyPlay Email',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                        ),
                        const SizedBox(height: 14),
                        _isAuthLoading
                            ? const CircularProgressIndicator()
                            : Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _handleLogin,
                                      child: const Text('Log In & Sync'),
                                    ),
                                  ),
                                ],
                              ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // Section 2: Appearance & Theme
          _buildSectionHeader('APPEARANCE & THEME', theme),
          Card(
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    // On narrow screens use a dropdown; on wider ones use SegmentedButton
                    if (constraints.maxWidth < 480) {
                      return ListTile(
                        title: const Text('Theme Mode'),
                        trailing: SizedBox(
                          width: 112,
                          child: DropdownButtonFormField<String>(
                            initialValue: _settings.themeMode,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'light',
                                child: Text('Light'),
                              ),
                              DropdownMenuItem(
                                value: 'dark',
                                child: Text('Dark'),
                              ),
                              DropdownMenuItem(
                                value: 'amoled',
                                child: Text('AMOLED'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                _updateSettings(
                                  _settings.copyWith(themeMode: val),
                                );
                              }
                            },
                          ),
                        ),
                      );
                    }
                    return ListTile(
                      title: const Text('Theme Mode'),
                      subtitle: Text(_settings.themeMode.toUpperCase()),
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'light', label: Text('Light')),
                          ButtonSegment(value: 'dark', label: Text('Dark')),
                          ButtonSegment(value: 'amoled', label: Text('AMOLED')),
                        ],
                        selected: {_settings.themeMode},
                        onSelectionChanged: (set) {
                          _updateSettings(
                            _settings.copyWith(themeMode: set.first),
                          );
                        },
                      ),
                    );
                  },
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Accent Color Preset',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: AppTheme.accentPresets.map((preset) {
                          final isSelected =
                              _settings.accentColorHex.toUpperCase() ==
                              preset.hex.toUpperCase();
                          return GestureDetector(
                            onTap: () {
                              _updateSettings(
                                _settings.copyWith(accentColorHex: preset.hex),
                              );
                            },
                            child: CircleAvatar(
                              backgroundColor: preset.color,
                              radius: 18,
                              child: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 20,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('Discover Country / Region'),
                  subtitle: Text(
                    '${_countryNames[_settings.countryCode.toLowerCase()] ?? _settings.countryCode.toUpperCase()} • Localizes charts & search',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _settings.countryCode.toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 20),
                    ],
                  ),
                  onTap: () => _showRegionPickerModal(context, theme),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 3: Smart Downloads & Storage
          _buildSectionHeader('DOWNLOAD RULES & STORAGE', theme),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Auto-Download New Episodes'),
                  subtitle: const Text(
                    'Check for releases in the background and auto-download',
                  ),
                  value: _settings.autoDownloadGlobal,
                  onChanged: (val) => _updateSettings(
                    _settings.copyWith(autoDownloadGlobal: val),
                  ),
                ),
                ListTile(
                  title: const Text('Default Quota per Subscription'),
                  subtitle: Text(
                    'Keep latest ${_settings.autoDownloadEpisodesPerSub} auto-downloaded episodes',
                  ),
                  trailing: DropdownButton<int>(
                    value: _settings.autoDownloadEpisodesPerSub,
                    items: [1, 2, 3, 5, 10].map((count) {
                      return DropdownMenuItem(
                        value: count,
                        child: Text('$count ep'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        _updateSettings(
                          _settings.copyWith(autoDownloadEpisodesPerSub: val),
                        );
                      }
                    },
                  ),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Auto-Delete on Completion'),
                  subtitle: const Text(
                    'Automatically remove audio files once finished playing',
                  ),
                  value: _settings.autoDeleteOnCompletion,
                  onChanged: (val) => _updateSettings(
                    _settings.copyWith(autoDeleteOnCompletion: val),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Download on Wi-Fi Only'),
                  subtitle: const Text(
                    'Prevent cellular data consumption for downloads',
                  ),
                  value: _settings.downloadOnlyOnWifi,
                  onChanged: (val) => _updateSettings(
                    _settings.copyWith(downloadOnlyOnWifi: val),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 4: OPML Backup & Restore
          _buildSectionHeader('OPML BACKUP & RESTORE', theme),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('Export OPML File'),
                  subtitle: const Text(
                    'Export subscriptions to import into any podcast app',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final success = await OpmlService.exportOpml();
                    if (success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('OPML exported successfully!'),
                        ),
                      );
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Import OPML File'),
                  subtitle: const Text(
                    'Import podcast feeds from Google Podcasts, AntennaPod, etc.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final count = await OpmlService.importOpml();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Imported $count new podcast subscriptions!',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
