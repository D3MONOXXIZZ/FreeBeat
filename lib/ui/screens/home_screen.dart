import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/pixel_artwork.dart';
import '../widgets/signal_path_sheet.dart';
import 'settings/settings_screen.dart';

/// Stock Google Pixel Material 3 Expressive Home Screen.
/// Strictly implements Screen 1 ("Home 3.0 / For You") in Figma inspiration:
/// 1. Time-aware header with user profile avatar, greeting, weather badge, and Hi-Fi pill
/// 2. "Your Daily Soundtrack" Hero Carousel with procedural organic vector artwork
///    and animated stadium pagination dots
/// 3. "Pixel Playlists" 2-column squircle cards with fluid artwork thumbnails
/// 4. Stadium-pill filter chips (Focus, Chill, Hi-Fi, Offline)
/// 5. "Jump back in" track collection in unified 28dp surface container
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenNowPlaying,
    required this.onNavigateToTab,
  });

  final VoidCallback onOpenNowPlaying;
  final ValueChanged<int> onNavigateToTab;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final PageController _carouselController = PageController();
  int _activeCarouselPage = 0;

  @override
  void dispose() {
    _carouselController.dispose();
    super.dispose();
  }

  String _formatTrackDuration(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 86400);
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _pickLocalAudio() async {
    PixelHaptics.tick();
    final authService = ref.read(nativeCloudAuthServiceProvider);
    const safAccount = CloudAccount(
      id: 'local_storage',
      providerType: CloudProviderType.androidSaf,
      displayName: 'Device Storage',
      endpointOrFolder: 'Local Music Files',
    );
    final picked =
        await authService.pickFromInstalledCloudApp(account: safAccount);
    if (picked.isNotEmpty) {
      await ref.read(cloudAccountsProvider.notifier).addAccount(safAccount, {});
      await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(picked);
      await PixelHaptics.hifiConfirm();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Imported ${picked.length} tracks from device storage!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tracks = ref.watch(filteredTracksProvider);
    final allTracks = ref.watch(tracksCatalogProvider);
    final selectedFilter = ref.watch(selectedCloudFilterProvider);
    final playback = ref.watch(playbackProvider);
    final quality = ref.watch(audioQualityProvider).effectiveStreamingTier;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ─────────────────────────────────────────────────────────────────────
        // 1. Collapsing M3 Large Top App Bar with Greeting & Weather Pill
        // ─────────────────────────────────────────────────────────────────────
        SliverAppBar.large(
          expandedHeight: 130,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(
              child: SpringPressScale(
                onTap: () {
                  PixelHaptics.tick();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(
                    Icons.person_rounded,
                    color: cs.onPrimaryContainer,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_getTimeGreeting()}, Alex',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Your Mix',
                style: textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          actions: [
            // Weather / Temp Pill (Figma Screen 1: 32° ☀️)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wb_sunny_rounded,
                      size: 15,
                      color: Color(0xFFF9AB00),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '32°',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Hi-Fi Lossless Status Pill
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilledButton.tonal(
                onPressed: () {
                  PixelHaptics.sheetExpand();
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const SignalPathSheet(),
                  );
                },
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: const StadiumBorder(),
                  backgroundColor: cs.secondaryContainer,
                  foregroundColor: cs.onSecondaryContainer,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.high_quality_rounded,
                      size: 16,
                      color: cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      quality.isLossless ? 'HI-FI' : '${quality.kbps}K',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Settings Screen Button
            IconButton(
              icon: Icon(Icons.settings_outlined, color: cs.onSurface),
              tooltip: 'Settings',
              onPressed: () {
                PixelHaptics.tick();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 2. "Your Daily Soundtrack" Hero Carousel with Organic Art & Dot Indicator
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  'Your Daily Soundtrack',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              SizedBox(
                height: 180,
                child: PageView(
                  controller: _carouselController,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (page) {
                    setState(() => _activeCarouselPage = page);
                    PixelHaptics.lowTick(intensity: 0.35);
                  },
                  children: [
                    _HeroSoundtrackCard(
                      title: 'Your Daily Soundtrack',
                      subtitle: 'Lossless Flow & Synced Lyrics',
                      artStyle: PixelArtStyle.dailySoundtrack,
                      onTap: () {
                        if (allTracks.isNotEmpty) {
                          ref
                              .read(playbackProvider.notifier)
                              .playTrack(allTracks.first);
                          widget.onOpenNowPlaying();
                        }
                      },
                    ),
                    _HeroSoundtrackCard(
                      title: 'Organic Playlists',
                      subtitle: 'Warm Analogue & Lo-Fi Beats',
                      artStyle: PixelArtStyle.organicWaves,
                      onTap: () {
                        if (allTracks.length > 1) {
                          ref
                              .read(playbackProvider.notifier)
                              .playTrack(allTracks[1]);
                          widget.onOpenNowPlaying();
                        }
                      },
                    ),
                    _HeroSoundtrackCard(
                      title: 'Desert Sun Hi-Fi',
                      subtitle: '24-Bit / 96kHz Master Quality',
                      artStyle: PixelArtStyle.desertSun,
                      onTap: () {
                        if (allTracks.isNotEmpty) {
                          ref
                              .read(playbackProvider.notifier)
                              .playTrack(allTracks.first);
                          widget.onOpenNowPlaying();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Animated Pagination Pill Dots
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (idx) {
                    final isActive = idx == _activeCarouselPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isActive
                            ? cs.primary
                            : cs.outlineVariant.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 3. "Pixel Playlists" 2-Column Curated Grid
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pixel Playlists',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onNavigateToTab(1),
                  child: const Text('See all'),
                ),
              ],
            ),
          ),
        ),

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 154,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildListDelegate([
              _PixelPlaylistCard(
                title: 'Organic Playlists',
                subtitle: 'Acoustic & Ambient',
                artStyle: PixelArtStyle.organicWaves,
                onTap: () {
                  if (allTracks.isNotEmpty) {
                    ref.read(playbackProvider.notifier).playTrack(allTracks[0]);
                    widget.onOpenNowPlaying();
                  }
                },
              ),
              _PixelPlaylistCard(
                title: 'Your Daily Mix',
                subtitle: 'Adaptive Audiophile',
                artStyle: PixelArtStyle.dailySoundtrack,
                onTap: () {
                  if (allTracks.length > 1) {
                    ref.read(playbackProvider.notifier).playTrack(allTracks[1]);
                    widget.onOpenNowPlaying();
                  }
                },
              ),
              _PixelPlaylistCard(
                title: 'Desert Sun Masters',
                subtitle: 'FLAC 24-Bit Vault',
                artStyle: PixelArtStyle.desertSun,
                onTap: () {
                  ref.read(selectedCloudFilterProvider.notifier).state =
                      CloudProviderType.googleDrive.id;
                },
              ),
              _PixelPlaylistCard(
                title: 'Poweramp DSP Studio',
                subtitle: '10-Band EQ & Knobs',
                icon: Icons.graphic_eq_rounded,
                onTap: () => widget.onNavigateToTab(2),
              ),
            ]),
          ),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 4. M3 Expressive Pill Filters Row (Stadium Shapes, Zero Shadows)
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                children: [
                  _PixelPillFilter(
                    label: 'Focus',
                    isSelected: selectedFilter == 'focus',
                    icon: Icons.center_focus_strong_rounded,
                    onTap: () => ref
                        .read(selectedCloudFilterProvider.notifier)
                        .state = selectedFilter == 'focus' ? 'all' : 'focus',
                  ),
                  const SizedBox(width: 8),
                  _PixelPillFilter(
                    label: 'Chill',
                    isSelected: selectedFilter == 'chill',
                    icon: Icons.spa_rounded,
                    onTap: () => ref
                        .read(selectedCloudFilterProvider.notifier)
                        .state = selectedFilter == 'chill' ? 'all' : 'chill',
                  ),
                  const SizedBox(width: 8),
                  _PixelPillFilter(
                    label: 'Workout',
                    isSelected: selectedFilter == 'workout',
                    icon: Icons.fitness_center_rounded,
                    onTap: () => ref
                        .read(selectedCloudFilterProvider.notifier)
                        .state = selectedFilter == 'workout' ? 'all' : 'workout',
                  ),
                  const SizedBox(width: 8),
                  _PixelPillFilter(
                    label: 'Hi-Fi 24-Bit',
                    isSelected: selectedFilter == 'hifi',
                    icon: Icons.high_quality_rounded,
                    onTap: () => ref
                        .read(selectedCloudFilterProvider.notifier)
                        .state = selectedFilter == 'hifi' ? 'all' : 'hifi',
                  ),
                  const SizedBox(width: 8),
                  _PixelPillFilter(
                    label: 'Pinned Offline',
                    isSelected: selectedFilter == 'offline',
                    icon: Icons.download_done_rounded,
                    onTap: () => ref
                        .read(selectedCloudFilterProvider.notifier)
                        .state = selectedFilter == 'offline' ? 'all' : 'offline',
                  ),
                ],
              ),
            ),
          ),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 5. Hero Empty State OR "Jump Back In" Track List
        // ─────────────────────────────────────────────────────────────────────
        if (allTracks.isEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 140),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.cloud_sync_rounded,
                        size: 38,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Your Music, Everywhere',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connect your Google Drive, OneDrive, Dropbox, or home server to stream your lossless library anywhere with zero subscriptions.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        PixelHaptics.tick();
                        widget.onNavigateToTab(3);
                      },
                      icon: const Icon(Icons.add_to_drive_rounded, size: 20),
                      label: const Text('Connect Cloud Storage'),
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _pickLocalAudio,
                      icon: const Icon(Icons.folder_open_rounded, size: 20),
                      label: const Text('Import from Device Storage'),
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () {
                        PixelHaptics.tick();
                        ref
                            .read(cloudAccountsProvider.notifier)
                            .loadSampleDemoAccounts();
                        ref
                            .read(tracksCatalogProvider.notifier)
                            .loadSampleDemoTracks();
                      },
                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text('Load Demo Showcase Tracks'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ] else ...[
          // "Jump Back In" Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Jump back in',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${tracks.length} tracks',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),

          // Grouped 28dp Surface Card for Track List
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
            sliver: SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: tracks.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.filter_list_off_rounded,
                                    color: cs.onSurfaceVariant, size: 32),
                                const SizedBox(height: 8),
                                Text('No tracks match this filter',
                                    style: textTheme.titleMedium),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () => ref
                                      .read(
                                          selectedCloudFilterProvider.notifier)
                                      .state = 'all',
                                  child: const Text('Reset to All Tracks'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (int i = 0; i < tracks.length; i++) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  indent: 74,
                                  endIndent: 16,
                                  color: cs.outlineVariant
                                      .withValues(alpha: 0.25),
                                ),
                              _PixelTrackTile(
                                track: tracks[i],
                                isCurrent:
                                    playback.currentTrack.id == tracks[i].id,
                                isPlaying:
                                    playback.currentTrack.id == tracks[i].id &&
                                        playback.isPlaying,
                                durationText:
                                    _formatTrackDuration(tracks[i].durationMs),
                                onTap: () {
                                  ref
                                      .read(playbackProvider.notifier)
                                      .playTrack(tracks[i]);
                                },
                                onToggleFavorite: () {
                                  ref
                                      .read(tracksCatalogProvider.notifier)
                                      .toggleFavorite(tracks[i].id);
                                },
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subcomponents
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSoundtrackCard extends StatelessWidget {
  const _HeroSoundtrackCard({
    required this.title,
    required this.subtitle,
    required this.artStyle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final PixelArtStyle artStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SpringPressScale(
        onTap: () {
          PixelHaptics.tick();
          onTap();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PixelOrganicArtwork(
                style: artStyle,
                borderRadius: 28,
              ),
              // Gradient scrim for text legibility
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 20,
                right: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 14,
                right: 18,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PixelPlaylistCard extends StatelessWidget {
  const _PixelPlaylistCard({
    required this.title,
    required this.subtitle,
    this.artStyle,
    this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final PixelArtStyle? artStyle;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: artStyle != null
                    ? PixelOrganicArtwork(
                        style: artStyle!,
                        borderRadius: 0,
                      )
                    : Container(
                        color: cs.surfaceContainerHigh,
                        child: Center(
                          child: Icon(icon, color: cs.primary, size: 36),
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PixelPillFilter extends StatelessWidget {
  const _PixelPillFilter({
    required this.label,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.secondaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? cs.secondary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? cs.onSecondaryContainer
                  : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? cs.onSecondaryContainer
                    : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelTrackTile extends StatelessWidget {
  const _PixelTrackTile({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.durationText,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final String durationText;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: cs.surfaceContainerHighest,
              ),
              child: Center(
                child: Icon(
                  isPlaying ? Icons.equalizer_rounded : track.providerType.icon,
                  color: isCurrent ? cs.primary : cs.onSurfaceVariant,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                      color: isCurrent ? cs.primary : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          track.codec,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${track.artist} • $durationText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                track.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: track.isFavorite ? cs.error : cs.onSurfaceVariant,
                size: 20,
              ),
              onPressed: onToggleFavorite,
            ),
          ],
        ),
      ),
    );
  }
}
