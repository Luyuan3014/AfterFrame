import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_asset.dart';
import '../services/media_engine.dart';
import '../theme.dart';
import 'studio_screen.dart';
import 'video_picker_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _engine = const MediaEngine();
  final List<LiveExport> _exports = [];
  int _page = 0;
  bool _picking = false;

  Future<void> _create([int mode = 0]) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final assets = await Navigator.of(context).push<List<MediaAsset>>(
        MaterialPageRoute(
          builder: (_) => VideoPickerScreen(engine: _engine, mode: mode),
        ),
      );
      if (!mounted || assets == null || assets.isEmpty) return;
      final result = await Navigator.of(context).push<LiveExport>(
        MaterialPageRoute(
          builder: (_) =>
              StudioScreen(assets: assets, engine: _engine, initialMode: mode),
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
      content: Text(error.toString()),
      behavior: SnackBarBehavior.floating,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _page,
          children: [
            _Discover(onCreate: _create, loading: _picking),
            _Works(exports: _exports, onCreate: () => _create()),
            const _Profile(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (value) => setState(() => _page = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '创作',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: '余帧',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class _Discover extends StatelessWidget {
  const _Discover({required this.onCreate, required this.loading});
  final ValueChanged<int> onCreate;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AfterFrameColors.lime,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.motion_photos_on_rounded,
                color: AfterFrameColors.ink,
              ),
            ),
            const SizedBox(width: 11),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AFTERFRAME',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  '余帧',
                  style: TextStyle(
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
          '让过去的某一帧，\n重新发生。',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 13),
        const Text(
          '从一段视频里，拾起值得反复观看的瞬间。',
          style: TextStyle(color: AfterFrameColors.muted, fontSize: 15),
        ),
        const SizedBox(height: 28),
        _HeroCreate(onTap: () => onCreate(0), loading: loading),
        const SizedBox(height: 34),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('创作方式', style: Theme.of(context).textTheme.titleLarge),
            const Text(
              '把一刻，做成作品',
              style: TextStyle(color: AfterFrameColors.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _ModeCard(
                icon: Icons.motion_photos_on_rounded,
                color: AfterFrameColors.coral,
                title: 'Live 单帧',
                detail: '视频 · 封面 · 动态',
                onTap: () => onCreate(0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ModeCard(
                icon: Icons.grid_on_rounded,
                color: AfterFrameColors.violet,
                title: 'Live 拼图',
                detail: '多格 · 同步 · 叙事',
                onTap: () => onCreate(1),
              ),
            ),
          ],
        ),
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
                    child: const Text(
                      'NEW MEMORY',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    '从视频开始',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    '选择一段视频，捕捉你的动态记忆',
                    style: TextStyle(color: Color(0xFF555A54)),
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
                      const Text(
                        '导入视频',
                        style: TextStyle(
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.black),
            ),
            const SizedBox(height: 28),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              detail,
              style: const TextStyle(
                color: AfterFrameColors.muted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TipCard extends StatelessWidget {
  const _TipCard();
  @override
  Widget build(BuildContext context) => Card(
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('余帧提示', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 3),
                Text(
                  '2～6 秒的片段，最适合做成动态记忆。',
                  style: TextStyle(color: AfterFrameColors.muted, fontSize: 12),
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

class _Works extends StatelessWidget {
  const _Works({required this.exports, required this.onCreate});
  final List<LiveExport> exports;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('我的余帧', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 5),
        Text(
          '${exports.length} 个动态记忆',
          style: const TextStyle(color: AfterFrameColors.muted),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: exports.isEmpty
              ? _EmptyWorks(onCreate: onCreate)
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: .76,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: exports.length,
                  itemBuilder: (_, index) {
                    final item = exports[index];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(item.coverPath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Container(color: AfterFrameColors.panelSoft),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, Colors.black87],
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
                            bottom: 13,
                            child: Text(
                              item.path.split('/').last,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class _EmptyWorks extends StatelessWidget {
  const _EmptyWorks({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.filter_vintage_outlined,
          size: 74,
          color: Colors.white.withValues(alpha: .18),
        ),
        const SizedBox(height: 18),
        const Text(
          '还没有被留下的瞬间',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 7),
        const Text(
          '从相册选一段视频开始吧',
          style: TextStyle(color: AfterFrameColors.muted),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text('创建第一张余帧'),
        ),
      ],
    ),
  );
}

class _Profile extends StatelessWidget {
  const _Profile();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const SizedBox(height: 10),
      Text('我的', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 26),
      const CircleAvatar(
        radius: 38,
        backgroundColor: AfterFrameColors.lime,
        child: Icon(Icons.person_rounded, size: 38, color: Colors.black),
      ),
      const SizedBox(height: 14),
      const Center(
        child: Text(
          '记忆收藏家',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 30),
      for (final item in const [
        (Icons.high_quality_rounded, '导出画质', '原始画质'),
        (Icons.folder_zip_outlined, 'Live 容器', '.live'),
        (Icons.info_outline_rounded, '关于余帧', '0.1.0'),
      ])
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: Icon(item.$1),
            title: Text(item.$2),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.$3,
                  style: const TextStyle(color: AfterFrameColors.muted),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
    ],
  );
}
