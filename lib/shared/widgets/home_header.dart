import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:music_app/features/auth/data/profile_service.dart';
import 'package:music_app/shared/widgets/cache_sheet.dart';

/// Top Brand Bar + Warm Personalized Greeting ala Stitch MelodyFlow.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  String _getGreeting(String name) {
    final hour = DateTime.now().hour;
    final displayName = name.isNotEmpty ? name : 'Pengguna';
    if (hour < 12) return 'Selamat pagi, $displayName';
    if (hour < 17) return 'Selamat siang, $displayName';
    if (hour < 19) return 'Selamat sore, $displayName';
    return 'Selamat malam, $displayName';
  }

  void _showProfileMenu(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = context.read<ProfileCubit>().state.profile;

    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant.withAlpha(120),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Profile avatar
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer,
                ),
                child: Center(
                  child: Text(
                    profile.initial,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                profile.displayName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.person_rounded, color: scheme.primary),
                title: Text(profile.hasProfile ? 'Ubah Profil' : 'Buat Profil'),
                subtitle: Text(profile.hasProfile
                    ? 'Ganti nama profil'
                    : 'Atur nama profil'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditProfileDialog(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.tune_rounded, color: scheme.secondary),
                title: const Text('Pengaturan'),
                subtitle: const Text('Cache, equalizer, dan lainnya'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSettingsSheet(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showEditProfileDialog(BuildContext context) {
    final profile = context.read<ProfileCubit>().state.profile;
    final nameCtrl = TextEditingController(text: profile.name);
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(profile.hasProfile ? 'Ubah Profil' : 'Buat Profil'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Nama Pengguna',
            hintText: 'Masukkan nama Anda...',
            prefixIcon: const Icon(Icons.person_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                context.read<ProfileCubit>().saveProfile(name, '');
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Profil disimpan sebagai "$name"')),
                );
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollCtrl) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant.withAlpha(120),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Icon(Icons.settings_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Pengaturan',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    children: [
                      _SettingsTile(
                        icon: Icons.cached_rounded,
                        iconColor: scheme.primary,
                        title: 'Hapus Cache',
                        subtitle: 'Bersihkan cache audio streaming, data & lirik',
                        onTap: () {
                          Navigator.pop(ctx);
                          showCacheSheet(context);
                        },
                      ),
                      _SettingsTile(
                        icon: Icons.info_rounded,
                        iconColor: scheme.outline,
                        title: 'Tentang MelodyFlow',
                        subtitle: 'Versi 1.0.0 • Streaming musik modern',
                        onTap: () {
                          Navigator.pop(ctx);
                          showAboutDialog(
                            context: context,
                            applicationName: 'MelodyFlow',
                            applicationVersion: '1.0.0',
                            applicationIcon: Icon(Icons.music_note_rounded, size: 40, color: scheme.primary),
                            applicationLegalese: '© 2026 MelodyFlow. Streaming musik cepat & hemat kuota.',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, profileState) {
        final profile = profileState.profile;

        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Bar: MelodyFlow Logo/Brand + Profile Avatar (No redundant search button)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(40),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: scheme.primary,
                                child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'MelodyFlow',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    // Profile avatar button → opens profile/settings menu
                    GestureDetector(
                      onTap: () => _showProfileMenu(context),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primaryContainer,
                        ),
                        child: Center(
                          child: profile.hasProfile
                              ? Text(
                                  profile.initial,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                )
                              : Icon(
                                  Icons.person_rounded,
                                  size: 20,
                                  color: scheme.onPrimaryContainer,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Compact Greeting (Perkecil ukuran & tanpa teks rileks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    _getGreeting(profile.name),
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: scheme.onSurface,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Settings tile widget
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withAlpha(30),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.outline, size: 20),
      onTap: onTap,
    );
  }
}

