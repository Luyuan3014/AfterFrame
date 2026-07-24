import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_asset.dart';
import '../services/media_engine.dart';
import '../theme.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({
    super.key,
    required this.assets,
    required this.engine,
    this.initialMode = 0,
  }) : assert(assets.length > 0);
  final List<MediaAsset> assets;
  final MediaEngine engine;
  final int initialMode;

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  List<FrameSample> _frames = [];
  bool _loading = true;
  bool _exporting = false;
  int _coverMs = 0;
  int _startMs = 0;
  late int _endMs;
  bool _keepAudio = true;
  bool _loop = false;
  late int _mode;
  int _activeIndex = 0;
  int _loadGeneration = 0;

  MediaAsset get _asset => widget.assets[_activeIndex];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _endMs = _asset.durationMs.clamp(1, 6000).toInt();
    _coverMs = _endMs ~/ 2;
    _loadFrames();
  }

  Future<void> _loadFrames() async {
    final generation = ++_loadGeneration;
    final asset = _asset;
    try {
      final frames = await widget.engine.extractTimeline(
        asset.uri,
        asset.durationMs,
        count: 9,
      );
      if (mounted && generation == _loadGeneration) {
        setState(() => _frames = frames);
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) _message(error.toString());
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectSource(int index) {
    if (index == _activeIndex || _exporting) return;
    setState(() {
      _activeIndex = index;
      _frames = [];
      _loading = true;
      _startMs = 0;
      _endMs = _asset.durationMs.clamp(1, 6000).toInt();
      _coverMs = _endMs ~/ 2;
    });
    _loadFrames();
  }

  FrameSample? get _cover {
    if (_frames.isEmpty) return null;
    return _frames.reduce(
      (a, b) =>
          (a.timeMs - _coverMs).abs() < (b.timeMs - _coverMs).abs() ? a : b,
    );
  }

  Future<void> _export() async {
    final cover = _cover;
    if (cover == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final preciseCover = await widget.engine.extractFrame(
        _asset.uri,
        _coverMs,
      );
      final path = await widget.engine.exportLive(
        asset: _asset,
        startMs: _startMs,
        endMs: _endMs,
        coverMs: _coverMs,
        coverPath: preciseCover,
        keepAudio: _keepAudio,
        loop: _loop,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AfterFrameColors.panel,
        showDragHandle: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: AfterFrameColors.lime,
                child: Icon(Icons.check_rounded, color: Colors.black, size: 32),
              ),
              const SizedBox(height: 16),
              const Text(
                '这一刻，留下了',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 7),
              Text(
                path,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AfterFrameColors.muted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      );
      if (mounted) {
        Navigator.pop(
          context,
          LiveExport(
            path: path,
            createdAt: DateTime.now(),
            coverPath: preciseCover,
          ),
        );
      }
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(value), behavior: SnackBarBehavior.floating),
  );

  String _time(int ms) {
    final total = ms ~/ 1000;
    final tenth = (ms % 1000) ~/ 100;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}.$tenth';
  }

  @override
  Widget build(BuildContext context) {
    final cover = _cover;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          children: [
            const Text(
              '动态工作台',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              widget.assets.length > 1
                  ? '${_activeIndex + 1} / ${widget.assets.length} · 按选择顺序'
                  : '选择最值得留下的一帧',
              style: const TextStyle(
                fontSize: 10,
                color: AfterFrameColors.muted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _exporting || cover == null ? null : _export,
            child: const Text(
              '导出',
              style: TextStyle(
                color: AfterFrameColors.lime,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AfterFrameColors.lime),
                  SizedBox(height: 16),
                  Text(
                    '正在读懂这段视频…',
                    style: TextStyle(color: AfterFrameColors.muted),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: cover == null
                            ? const Icon(Icons.broken_image_outlined, size: 80)
                            : ClipRRect(
                                key: ValueKey(cover.path),
                                borderRadius: BorderRadius.circular(24),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    AspectRatio(
                                      aspectRatio: _asset.aspectRatio
                                          .clamp(.58, 1.2)
                                          .toDouble(),
                                      child: Image.file(
                                        File(cover.path),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      left: 13,
                                      top: 13,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(
                                              Icons.motion_photos_on,
                                              size: 15,
                                              color: AfterFrameColors.lime,
                                            ),
                                            SizedBox(width: 5),
                                            Text(
                                              'LIVE',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 58,
                                      height: 58,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: .48,
                                        ),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white24,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        size: 32,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: AfterFrameColors.panel,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 17, 18, 22),
                  child: Column(
                    children: [
                      if (widget.assets.length > 1) ...[
                        _SourceStrip(
                          assets: widget.assets,
                          engine: widget.engine,
                          selectedIndex: _activeIndex,
                          onSelected: _selectSource,
                        ),
                        const SizedBox(height: 14),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _Segment(
                              label: 'Live 单帧',
                              selected: _mode == 0,
                              onTap: () => setState(() => _mode = 0),
                            ),
                          ),
                          Expanded(
                            child: _Segment(
                              label: 'Live 拼图',
                              selected: _mode == 1,
                              onTap: () => setState(() => _mode = 1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_mode == 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '选择封面帧',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              _time(_coverMs),
                              style: const TextStyle(
                                color: AfterFrameColors.lime,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 58,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              children: [
                                Row(
                                  children: [
                                    for (final frame in _frames)
                                      Expanded(
                                        child: Image.file(
                                          File(frame.path),
                                          height: 58,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                  ],
                                ),
                                Positioned.fill(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 0,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 8,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 16,
                                          ),
                                      thumbColor: AfterFrameColors.lime,
                                    ),
                                    child: Slider(
                                      min: 0,
                                      max: _asset.durationMs
                                          .toDouble()
                                          .clamp(1, double.infinity)
                                          .toDouble(),
                                      value: _coverMs.toDouble(),
                                      onChanged: (v) =>
                                          setState(() => _coverMs = v.round()),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: _Option(
                                icon: _keepAudio
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_off_rounded,
                                label: '保留声音',
                                active: _keepAudio,
                                onTap: () =>
                                    setState(() => _keepAudio = !_keepAudio),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _Option(
                                icon: Icons.loop_rounded,
                                label: '循环播放',
                                active: _loop,
                                onTap: () => setState(() => _loop = !_loop),
                              ),
                            ),
                          ],
                        ),
                      ] else
                        _CollageChooser(frames: _frames),
                      const SizedBox(height: 17),
                      Row(
                        children: [
                          Text(
                            _time(_startMs),
                            style: const TextStyle(
                              color: AfterFrameColors.muted,
                              fontSize: 11,
                            ),
                          ),
                          Expanded(
                            child: RangeSlider(
                              min: 0,
                              max: _asset.durationMs
                                  .toDouble()
                                  .clamp(1, double.infinity)
                                  .toDouble(),
                              values: RangeValues(
                                _startMs.toDouble(),
                                _endMs.toDouble(),
                              ),
                              onChanged: (value) {
                                if (value.end - value.start < 500) return;
                                setState(() {
                                  _startMs = value.start.round();
                                  _endMs = value.end.round();
                                  _coverMs = _coverMs
                                      .clamp(_startMs, _endMs)
                                      .toInt();
                                });
                              },
                            ),
                          ),
                          Text(
                            _time(_endMs),
                            style: const TextStyle(
                              color: AfterFrameColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _exporting || cover == null
                              ? null
                              : _export,
                          icon: _exporting
                              ? const SizedBox.square(
                                  dimension: 19,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.ios_share_rounded),
                          label: Text(
                            _exporting ? '正在封装动态记忆…' : '生成 AfterFrame Live',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SourceStrip extends StatelessWidget {
  const _SourceStrip({
    required this.assets,
    required this.engine,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<MediaAsset> assets;
  final MediaEngine engine;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: assets.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, index) {
        final selected = index == selectedIndex;
        return InkWell(
          onTap: () => onSelected(index),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 76,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AfterFrameColors.panelSoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AfterFrameColors.lime : Colors.transparent,
                width: 2,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: FutureBuilder<String>(
                    future: engine.videoThumbnail(assets[index].uri),
                    builder: (_, snapshot) =>
                        snapshot.hasData && snapshot.data!.isNotEmpty
                        ? Image.file(File(snapshot.data!), fit: BoxFit.cover)
                        : const ColoredBox(color: Colors.white10),
                  ),
                ),
                Positioned(
                  left: 4,
                  top: 4,
                  child: CircleAvatar(
                    radius: 9,
                    backgroundColor: selected
                        ? AfterFrameColors.lime
                        : Colors.black54,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: selected ? Colors.black : Colors.white,
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
  );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? AfterFrameColors.panelSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : AfterFrameColors.muted,
        ),
      ),
    ),
  );
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: active
            ? AfterFrameColors.lime.withValues(alpha: .12)
            : AfterFrameColors.panelSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? AfterFrameColors.lime.withValues(alpha: .45)
              : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: active ? AfterFrameColors.lime : AfterFrameColors.muted,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : AfterFrameColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CollageChooser extends StatefulWidget {
  const _CollageChooser({required this.frames});
  final List<FrameSample> frames;
  @override
  State<_CollageChooser> createState() => _CollageChooserState();
}

class _CollageChooserState extends State<_CollageChooser> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('选择拼图布局', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Row(
        children: [
          for (int i = 0; i < 3; i++) ...[
            Expanded(
              child: InkWell(
                onTap: () => setState(() => selected = i),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 68,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AfterFrameColors.panelSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected == i
                          ? AfterFrameColors.lime
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: _layout(i),
                ),
              ),
            ),
            if (i < 2) const SizedBox(width: 9),
          ],
        ],
      ),
      const SizedBox(height: 9),
      const Text(
        '当前 MVP 使用同一视频的不同时间切片；多视频同步将在下一阶段开放。',
        style: TextStyle(fontSize: 10, color: AfterFrameColors.muted),
      ),
    ],
  );

  Widget _layout(int index) {
    if (index == 0) {
      return Row(children: [tile(0), const SizedBox(width: 3), tile(1)]);
    }
    if (index == 1) {
      return Column(children: [tile(1), const SizedBox(height: 3), tile(2)]);
    }
    return Row(
      children: [
        tile(0, flex: 2),
        const SizedBox(width: 3),
        Expanded(
          child: Column(
            children: [tile(1), const SizedBox(height: 3), tile(2)],
          ),
        ),
      ],
    );
  }

  Widget tile(int index, {int flex = 1}) {
    final child = widget.frames.isEmpty
        ? Container(color: Colors.white10)
        : ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(
                widget
                    .frames[index.clamp(0, widget.frames.length - 1).toInt()]
                    .path,
              ),
              fit: BoxFit.cover,
            ),
          );
    return Expanded(flex: flex, child: child);
  }
}
