import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_asset.dart';
import '../services/media_engine.dart';
import '../services/app_update_service.dart';
import '../theme.dart';
import '../live_editor/live_editor_page.dart';
import '../localization/app_localizations.dart';
import '../widgets/media_preview_sheet.dart';
import '../widgets/app_update_card.dart';
import 'video_picker_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _engine = const MediaEngine();
  final List<LiveExport> _exports = [];
  final Set<String> _deletingExports = {};
  int _page = 0;
  bool _picking = false;
  bool _loadingExports = true;

  @override
  void initState() {
    super.initState();
    _restoreExports();
  }

  Future<void> _restoreExports() async {
    try {
      final exports = await _engine.listExports();
      if (mounted) {
        setState(() {
          _exports
            ..clear()
            ..addAll(exports);
          _loadingExports = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingExports = false);
    }
  }

  Future<void> _create() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final assets = await Navigator.of(context).push<List<MediaAsset>>(
        MaterialPageRoute(builder: (_) => VideoPickerScreen(engine: _engine)),
      );
      if (!mounted || assets == null || assets.isEmpty) return;
      final result = await Navigator.of(context).push<LiveExport>(
        MaterialPageRoute(
          builder: (_) => LiveEditorPage(assets: assets, engine: _engine),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          _exports.insert(0, result);
          _page = 1;
        });
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _showError(Object error) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.l10n.text('errorGeneric')),
      behavior: SnackBarBehavior.floating,
    ),
  );

  Future<void> _shareExport(LiveExport export) async {
    try {
      await _engine.shareExport(
        export.galleryUri,
        mimeType: export.shareMimeType,
      );
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _previewExport(LiveExport export) async {
    if (export.galleryUri.isEmpty || export.shareMimeType != 'video/mp4') {
      _message('previewUnavailable');
      return;
    }
    await showMediaPreview(
      context,
      uri: export.galleryUri,
      title: export.displayName,
      coverPath: export.coverPath,
    );
  }

  Future<void> _deleteExport(LiveExport export) async {
    if (_deletingExports.contains(export.path)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.text('deleteWorkTitle')),
        content: Text(dialogContext.l10n.text('deleteWorkDetail')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.text('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.text('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingExports.add(export.path));
    try {
      await _engine.deleteExport(export);
      if (!mounted) return;
      // Same Motion Photo may have been indexed under URI aliases; drop every
      // card that shares the work identity, then reconcile to stay authoritative.
      setState(() {
        _exports.removeWhere(
          (item) =>
              item.path == export.path ||
              (export.displayName.isNotEmpty &&
                  item.displayName == export.displayName),
        );
      });
      await _restoreExports();
      if (!mounted) return;
      _message('workDeleted');
    } catch (error) {
      // Reconcile after any partial native failure. If MediaStore was already
      // deleted, this also removes a stale card instead of leaving a ghost.
      await _restoreExports();
      if (mounted) {
        final stillExists = _exports.any((item) => item.path == export.path);
        _message(stillExists ? 'errorDelete' : 'workDeleted');
      }
    } finally {
      if (mounted) setState(() => _deletingExports.remove(export.path));
    }
  }

  void _message(String key) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.l10n.text(key)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _page,
          children: [
            _Discover(onCreate: _create, loading: _picking),
            _Works(
              exports: _exports,
              loading: _loadingExports,
              onCreate: () => _create(),
              onShare: _shareExport,
              onPreview: _previewExport,
              onDelete: _deleteExport,
              deletingExports: _deletingExports,
            ),
            _Profile(
              active: _page == 2,
              onOpenWorks: () => setState(() => _page = 1),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (value) => setState(() => _page = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome),
            label: l10n.text('navCreate'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view_rounded),
            label: l10n.text('navWorks'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: l10n.text('navProfile'),
          ),
        ],
      ),
    );
  }
}

class _Discover extends StatelessWidget {
  const _Discover({required this.onCreate, required this.loading});
  final VoidCallback onCreate;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/branding/logo.png',
                width: 38,
                height: 38,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AFTERFRAME',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  l10n.text('brandCn'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AfterFrameColors.muted,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
            const Spacer(),
            IconButton.filledTonal(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ],
        ),
        const SizedBox(height: 38),
        Text(
          l10n.text('heroTitle'),
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 13),
        Text(
          l10n.text('heroSubtitle'),
          style: const TextStyle(color: AfterFrameColors.muted, fontSize: 15),
        ),
        const SizedBox(height: 28),
        _HeroCreate(onTap: onCreate, loading: loading),
        const SizedBox(height: 34),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.text('createWays'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              l10n.text('createWaysHint'),
              style: const TextStyle(
                color: AfterFrameColors.muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _StudioEntry(onTap: onCreate),
        const SizedBox(height: 12),
        const _TipCard(),
      ],
    );
  }
}

class _HeroCreate extends StatelessWidget {
  const _HeroCreate({required this.onTap, required this.loading});
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AfterFrameColors.paper,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          height: 210,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [Color(0xFFF4F2EA), Color(0xFFDCE5D5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -22,
                bottom: -42,
                child: Icon(
                  Icons.motion_photos_on,
                  size: 190,
                  color: Colors.black.withValues(alpha: .07),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      l10n.text('newMemory'),
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    l10n.text('startFromVideo'),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    l10n.text('startFromVideoDetail'),
                    style: const TextStyle(color: Color(0xFF555A54)),
                  ),
                  const SizedBox(height: 17),
                  Row(
                    children: [
                      Container(
                        width: 43,
                        height: 43,
                        decoration: const BoxDecoration(
                          color: AfterFrameColors.lime,
                          shape: BoxShape.circle,
                        ),
                        child: loading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.black,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l10n.text('importVideo'),
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudioEntry extends StatelessWidget {
  const _StudioEntry({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AfterFrameColors.lime,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.video_collection_rounded,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.text('studioEntryTitle'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      l10n.text('studioEntryDetail'),
                      style: const TextStyle(
                        color: AfterFrameColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard();
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      color: const Color(0xFF20231C),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(
              Icons.lightbulb_outline_rounded,
              color: AfterFrameColors.lime,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.text('tipTitle'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.text('tipBody'),
                    style: const TextStyle(
                      color: AfterFrameColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: .5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Works extends StatelessWidget {
  const _Works({
    required this.exports,
    required this.onCreate,
    required this.onShare,
    required this.onPreview,
    required this.onDelete,
    required this.deletingExports,
    required this.loading,
  });
  final List<LiveExport> exports;
  final VoidCallback onCreate;
  final ValueChanged<LiveExport> onShare;
  final ValueChanged<LiveExport> onPreview;
  final ValueChanged<LiveExport> onDelete;
  final Set<String> deletingExports;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.text('myWorks'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 5),
          Text(
            l10n.text('workCount', {'count': exports.length}),
            style: const TextStyle(color: AfterFrameColors.muted),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AfterFrameColors.lime,
                    ),
                  )
                : exports.isEmpty
                ? _EmptyWorks(onCreate: onCreate)
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: .76,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: exports.length,
                    itemBuilder: (_, index) {
                      final item = exports[index];
                      final deleting = deletingExports.contains(item.path);
                      return Material(
                        color: AfterFrameColors.panelSoft,
                        borderRadius: BorderRadius.circular(22),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: deleting ? null : () => onPreview(item),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(item.coverPath),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: AfterFrameColors.panelSoft,
                                ),
                              ),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.black87,
                                    ],
                                    begin: Alignment.center,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ),
                              const Positioned(
                                right: 12,
                                top: 12,
                                child: Icon(
                                  Icons.motion_photos_on_rounded,
                                  color: AfterFrameColors.lime,
                                ),
                              ),
                              Positioned(
                                left: 14,
                                right: 14,
                                bottom: 51,
                                child: Text(
                                  item.displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 6,
                                right: 6,
                                bottom: 5,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _WorkAction(
                                      tooltip: l10n.text('previewWork'),
                                      icon: Icons.play_arrow_rounded,
                                      onPressed: deleting
                                          ? null
                                          : () => onPreview(item),
                                    ),
                                    _WorkAction(
                                      tooltip: l10n.text('shareToChat'),
                                      icon: Icons.send_rounded,
                                      onPressed: deleting
                                          ? null
                                          : () => onShare(item),
                                    ),
                                    _WorkAction(
                                      tooltip: l10n.text('delete'),
                                      icon: Icons.delete_outline_rounded,
                                      onPressed: deleting
                                          ? null
                                          : () => onDelete(item),
                                    ),
                                  ],
                                ),
                              ),
                              if (deleting)
                                Positioned.fill(
                                  child: Semantics(
                                    label: l10n.text('deletingWork'),
                                    child: const ColoredBox(
                                      color: Color(0x99000000),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: AfterFrameColors.lime,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WorkAction extends StatelessWidget {
  const _WorkAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 38, height: 38),
    padding: EdgeInsets.zero,
    onPressed: onPressed,
    icon: Icon(icon, size: 19),
  );
}

class _EmptyWorks extends StatelessWidget {
  const _EmptyWorks({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.filter_vintage_outlined,
            size: 74,
            color: Colors.white.withValues(alpha: .18),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.text('emptyWorks'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            l10n.text('emptyWorksHint'),
            style: const TextStyle(color: AfterFrameColors.muted),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.text('createFirst')),
          ),
        ],
      ),
    );
  }
}

class _Profile extends StatefulWidget {
  const _Profile({required this.active, required this.onOpenWorks});

  final bool active;
  final VoidCallback onOpenWorks;

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  final _engine = const MediaEngine();
  int? _cacheBytes;
  int? _cacheFiles;
  bool _cacheBusy = false;
  int _cacheLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) _loadCache();
  }

  @override
  void didUpdateWidget(covariant _Profile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _loadCache();
  }

  Future<void> _loadCache() async {
    final generation = ++_cacheLoadGeneration;
    if (mounted && !_cacheBusy) setState(() => _cacheBusy = true);
    try {
      final usage = await _engine.temporaryCacheUsage();
      if (mounted && generation == _cacheLoadGeneration) {
        setState(() {
          _cacheBytes = usage.bytes;
          _cacheFiles = usage.files;
          _cacheBusy = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _cacheLoadGeneration) {
        setState(() => _cacheBusy = false);
      }
    }
  }

  Future<void> _clearCache() async {
    if (_cacheBusy || (_cacheBytes ?? 0) == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.text('clearCacheTitle')),
        content: Text(dialogContext.l10n.text('clearCacheDetail')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.text('clear')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _cacheLoadGeneration++;
    setState(() => _cacheBusy = true);
    try {
      await _engine.clearTemporaryCache();
      if (!mounted) return;
      setState(() {
        _cacheBytes = 0;
        _cacheFiles = 0;
        _cacheBusy = false;
      });
      _message('cacheCleared');
    } catch (_) {
      if (!mounted) return;
      setState(() => _cacheBusy = false);
      _message('cacheClearFailed');
    }
  }

  void _onCacheTap() {
    if (_cacheBytes == null) {
      _loadCache();
    } else if (_cacheBytes == 0) {
      _message('cacheAlreadyEmpty');
    } else {
      _clearCache();
    }
  }

  Future<void> _showLanguagePicker(AppLanguageController controller) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Text(
                    sheetContext.l10n.text('appLanguage'),
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                for (final value in AppLanguage.values)
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Icon(
                      value == AppLanguage.chinese
                          ? Icons.translate_rounded
                          : Icons.language_rounded,
                    ),
                    title: Text(
                      sheetContext.l10n.text(
                        value == AppLanguage.chinese ? 'chinese' : 'english',
                      ),
                    ),
                    trailing: controller.language == value
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AfterFrameColors.lime,
                          )
                        : null,
                    selected: controller.language == value,
                    onTap: () async {
                      await controller.setLanguage(value);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                  ),
              ],
            ),
          ),
        ),
      );

  void _message(String key) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(context.l10n.text(key)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  Future<void> _showInfo({
    required String titleKey,
    required String bodyKey,
    IconData icon = Icons.info_outline_rounded,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30, color: AfterFrameColors.lime),
            const SizedBox(height: 14),
            Text(
              sheetContext.l10n.text(titleKey),
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              sheetContext.l10n.text(bodyKey),
              style: const TextStyle(
                color: AfterFrameColors.muted,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _showAbout() async {
    String version = '';
    String abi = '';
    try {
      final state = await const AppUpdateService().state();
      version = state.currentVersionName;
      abi = state.abi;
    } catch (_) {
      // The about page remains useful if native package metadata is unavailable.
    }
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'AfterFrame · ${context.l10n.text('brandCn')}',
      applicationVersion: version.isEmpty
          ? context.l10n.text('versionUnavailable')
          : '$version${abi.isEmpty ? '' : ' · $abi'}',
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset('assets/branding/logo.png', width: 56, height: 56),
      ),
      applicationLegalese: context.l10n.text('aboutLegalese'),
      children: [
        const SizedBox(height: 12),
        Text(context.l10n.text('privacySummary')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = AppLanguageScope.controllerOf(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 10),
        Text(
          l10n.text('profileTitle'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 18),
        const _LocalWorkspaceCard(),
        const SizedBox(height: 28),
        _ProfileSectionLabel(l10n.text('preferences')),
        const SizedBox(height: 10),
        _ProfileTile(
          icon: Icons.language_rounded,
          title: l10n.text('appLanguage'),
          value: l10n.text(
            language.language == AppLanguage.chinese ? 'chinese' : 'english',
          ),
          onTap: () => _showLanguagePicker(language),
        ),
        const SizedBox(height: 18),
        _ProfileSectionLabel(l10n.text('worksAndExport')),
        const SizedBox(height: 10),
        _ProfileTile(
          icon: Icons.photo_library_outlined,
          title: l10n.text('album'),
          value: l10n.text('albumValue'),
          onTap: widget.onOpenWorks,
        ),
        _ProfileTile(
          icon: Icons.high_quality_rounded,
          title: l10n.text('exportQuality'),
          value: l10n.text('adaptiveQuality'),
          onTap: () => _showInfo(
            titleKey: 'exportQuality',
            bodyKey: 'exportQualityDetail',
            icon: Icons.high_quality_rounded,
          ),
        ),
        _ProfileTile(
          icon: Icons.motion_photos_on_outlined,
          title: l10n.text('liveContainer'),
          value: l10n.text('motionPhotoAndMp4'),
          onTap: () => _showInfo(
            titleKey: 'liveContainer',
            bodyKey: 'liveContainerDetail',
            icon: Icons.motion_photos_on_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _ProfileSectionLabel(l10n.text('storageAndPrivacy')),
        const SizedBox(height: 10),
        _ProfileTile(
          icon: Icons.cleaning_services_outlined,
          title: l10n.text('temporaryCache'),
          value: _cacheBusy
              ? l10n.text('calculating')
              : _cacheBytes == null
              ? l10n.text('unavailable')
              : _formatBytes(_cacheBytes!),
          subtitle: _cacheFiles == null
              ? null
              : l10n.text('cacheFileCount', {'count': _cacheFiles!}),
          busy: _cacheBusy,
          onTap: _onCacheTap,
        ),
        _ProfileTile(
          icon: Icons.privacy_tip_outlined,
          title: l10n.text('privacyAndData'),
          value: l10n.text('localProcessing'),
          onTap: () => _showInfo(
            titleKey: 'privacyAndData',
            bodyKey: 'privacyAndDataDetail',
            icon: Icons.privacy_tip_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _ProfileSectionLabel(l10n.text('supportAndAbout')),
        const SizedBox(height: 10),
        const AppUpdateCard(),
        _ProfileTile(
          icon: Icons.info_outline_rounded,
          title: l10n.text('about'),
          value: 'AfterFrame',
          onTap: _showAbout,
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    final l10n = context.l10n;
    if (bytes < 1024) return l10n.text('bytesValue', {'value': bytes});
    if (bytes < 1024 * 1024) {
      return l10n.text('kbValue', {'value': (bytes / 1024).toStringAsFixed(1)});
    }
    return l10n.text('mbValue', {
      'value': (bytes / (1024 * 1024)).toStringAsFixed(1),
    });
  }
}

class _LocalWorkspaceCard extends StatelessWidget {
  const _LocalWorkspaceCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label:
          '${l10n.text('localWorkspaceTitle')}，${l10n.text('localWorkspaceDetail')}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  'assets/branding/logo.png',
                  width: 62,
                  height: 62,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.text('localWorkspaceTitle'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      l10n.text('localWorkspaceDetail'),
                      style: const TextStyle(
                        color: AfterFrameColors.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.phonelink_lock_rounded,
                color: AfterFrameColors.lime,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSectionLabel extends StatelessWidget {
  const _ProfileSectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(context).textTheme.labelLarge?.copyWith(
      color: AfterFrameColors.muted,
      letterSpacing: .2,
    ),
  );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.subtitle,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      onTap: busy ? null : onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .4,
              ),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AfterFrameColors.muted),
              ),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}
