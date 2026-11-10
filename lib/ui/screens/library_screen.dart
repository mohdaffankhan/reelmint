import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/scope.dart';
import '../../app/theme.dart';
import '../../services/library.dart';
import '../../services/settings.dart';
import '../../utils/format.dart';
import '../../services/recorder.dart';
import '../widgets/common.dart';
import '../widgets/tools.dart';
import 'player_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onRecord});
  final VoidCallback onRecord;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _selected = <String>{};
  String _query = '';
  bool _favoritesOnly = false;
  final _search = TextEditingController();

  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Recording> _visible(Library lib, Settings s) {
    final favs = s.favorites;
    final q = _query.toLowerCase();
    return lib.items.where((r) {
      if (_favoritesOnly && !favs.contains(r.fileName)) return false;
      if (q.isNotEmpty &&
          !r.title.toLowerCase().contains(q) &&
          !r.fileName.toLowerCase().contains(q))
        return false;
      return true;
    }).toList();
  }

  void _toggle(Recording r) {
    haptic(context, HapticKind.select);
    setState(
      () => _selected.contains(r.path)
          ? _selected.remove(r.path)
          : _selected.add(r.path),
    );
  }

  Future<void> _deleteSelected() async {
    final lib = context.library;
    final recs = lib.items.where((r) => _selected.contains(r.path)).toList();
    final ok = await confirm(
      context,
      title: 'Delete ${recs.length} recording${recs.length == 1 ? '' : 's'}?',
      message:
          'This frees ${formatBytes(recs.fold(0, (a, r) => a + r.size))} and can’t be undone.',
    );
    if (!ok) return;
    final failed = await lib.delete(recs);
    if (!mounted) return;
    setState(_selected.clear);
    toast(
      context,
      failed == 0
          ? 'Deleted'
          : 'Couldn’t delete $failed recording${failed == 1 ? '' : 's'}',
      error: failed > 0,
    );
  }

  /// Joins the selected clips in recording order into one new video.
  Future<void> _mergeSelected() async {
    final lib = context.library;
    final recs = lib.items.where((r) => _selected.contains(r.path)).toList()
      ..sort((a, b) => a.modified.compareTo(b.modified));
    final out = await runTransform(
      context,
      recs.map((r) => r.path).toList(),
      const TransformSpec(),
      title: 'Merging ${recs.length} clips',
    );
    if (out == null || !mounted) return;
    setState(_selected.clear);
    await lib.refresh();
    if (!mounted) return;
    toast(context, 'Merged into one video', icon: Icons.merge_rounded);
    final r = lib.byPath(out);
    if (r != null)
      Navigator.of(context)
          .push(PlayerScreen.route(r, heroTag: 'merged-${r.path}'));
  }

  Future<void> _shareSelected() async {
    final recs = context.library.items
        .where((r) => _selected.contains(r.path))
        .toList();
    await shareRecordings(context, recs);
  }

  Future<void> _pickSort() async {
    final s = context.settings;
    final v = await showOptionSheet<LibrarySort>(
      context,
      title: 'Sort by',
      selected: s.sort,
      options: [
        for (final o in LibrarySort.values)
          OptionItem(
            o,
            o.label,
            icon: switch (o) {
              LibrarySort.newest => Icons.south_rounded,
              LibrarySort.oldest => Icons.north_rounded,
              LibrarySort.longest => Icons.timer_outlined,
              LibrarySort.largest => Icons.sd_storage_outlined,
            },
          ),
      ],
    );
    if (v == null) return;
    s.sort = v;
    if (mounted) context.library.resort();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.library;
    final s = context.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([lib, s]),
      builder: (context, _) {
        final items = _visible(lib, s);
        _selected.removeWhere((p) => lib.byPath(p) == null);
        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(_selected.clear);
          },
          child: RefreshIndicator(
            color: L.primary,
            onRefresh: lib.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverSafeArea(
                  bottom: false,
                  sliver: SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(child: _header(context, lib)),
                  ),
                ),
                if (lib.items.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    sliver: SliverToBoxAdapter(child: _searchRow(context)),
                  ),
                if (lib.items.isNotEmpty && !_selecting)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _StorageCard(usedByReelmint: lib.totalBytes),
                    ),
                  ),
                if (lib.loading)
                  SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: L.primary),
                    ),
                  )
                else if (lib.items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Empty(onRecord: widget.onRecord),
                  )
                else if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        _favoritesOnly
                            ? 'No favorites yet — tap ♥ in the player.'
                            : 'No matches',
                        style: TextStyle(color: context.c.textDim),
                      ),
                    ),
                  )
                else
                  for (final (i, group) in _groups(items, s.sort).indexed) ...[
                    if (group.$1 != null)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          i == 0 ? 14 : 22,
                          20,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: SectionLabel(group.$1!),
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        group.$1 == null ? 12 : 0,
                        20,
                        0,
                      ),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.62,
                            ),
                        itemCount: group.$2.length,
                        itemBuilder: (context, i) {
                          final r = group.$2[i];
                          return _Card(
                            rec: r,
                            favorite: s.favorites.contains(r.fileName),
                            selecting: _selecting,
                            selected: _selected.contains(r.path),
                            onTap: () => _selecting
                                ? _toggle(r)
                                : Navigator.of(context).push(
                                    PlayerScreen.route(
                                      r,
                                      heroTag: 'lib-${r.path}',
                                    ),
                                  ),
                            onLongPress: () => _toggle(r),
                          );
                        },
                      ),
                    ),
                  ],
                const SliverToBoxAdapter(child: SizedBox(height: 140)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, Library lib) {
    if (_selecting) {
      return Row(
        children: [
          IconButton(
            onPressed: () => setState(_selected.clear),
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: Text(
              '${_selected.length} selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.titleLarge,
            ),
          ),
          IconButton(
            tooltip: 'Select all',
            onPressed: () => setState(
              () => _selected.addAll(
                _visible(lib, context.settings).map((r) => r.path),
              ),
            ),
            icon: const Icon(Icons.select_all_rounded),
          ),
          if (_selected.length >= 2)
            IconButton(
              tooltip: 'Merge',
              onPressed: _mergeSelected,
              icon: const Icon(Icons.merge_rounded),
            ),
          IconButton(
            tooltip: 'Share',
            onPressed: _shareSelected,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: _deleteSelected,
            icon: const Icon(Icons.delete_outline_rounded, color: L.rose),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Library', style: context.t.headlineLarge),
              const SizedBox(height: 2),
              Text(
                lib.items.isEmpty
                    ? 'Nothing here yet'
                    : '${lib.items.length} videos · ${formatDuration(lib.totalDuration)} · ${formatBytes(lib.totalBytes)}',
                style: TextStyle(color: context.c.textDim),
              ),
            ],
          ),
        ),
        if (lib.items.isNotEmpty)
          Pressable(
            onTap: _pickSort,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.c.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.sort_rounded),
            ),
          ),
      ],
    );
  }

  Widget _searchRow(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search recordings',
            prefixIcon: Icon(Icons.search_rounded, color: context.c.textFaint),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Pressable(
        onTap: () => setState(() => _favoritesOnly = !_favoritesOnly),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: _favoritesOnly
                ? L.rose.withValues(alpha: 0.16)
                : context.c.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            _favoritesOnly
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: _favoritesOnly ? L.rose : context.c.textDim,
          ),
        ),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.rec,
    required this.favorite,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Recording rec;
  final bool favorite, selecting, selected;
  final VoidCallback onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final i = rec.info;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      haptics: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.all(selected ? 4 : 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: selected
                    ? Border.all(color: L.primary, width: 2)
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(selected ? 16 : 20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'lib-${rec.path}',
                      child: ThumbImage(path: rec.path),
                    ),
                    // Legibility scrim only behind the labels (small, two-stop = GPU fast path).
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0x99000000)],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      bottom: 10,
                      child: Pill(child: Text(formatDuration(rec.duration))),
                    ),
                    if (i != null && i.width > 0)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Pill(
                          child: Text(resolutionLabel(i.width, i.height)),
                        ),
                      ),
                    if (favorite)
                      const Positioned(
                        top: 10,
                        right: 10,
                        child: Icon(
                          Icons.favorite_rounded,
                          color: L.rose,
                          size: 20,
                        ),
                      ),
                    if (selecting)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? L.primary : Colors.black38,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            formatRelativeDate(rec.modified),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            rec.title.startsWith('Recording ')
                ? formatBytes(rec.size)
                : '${rec.title} · ${formatBytes(rec.size)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.c.textFaint, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onRecord});
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(40, 0, 40, 120),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                L.primary.withValues(alpha: 0.35),
                L.primary.withValues(alpha: 0),
              ],
            ),
          ),
          child: const Center(
            child: GradientIcon(Icons.video_library_rounded, size: 52),
          ),
        ),
        const SizedBox(height: 18),
        Text('Your library is empty', style: context.t.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Recordings you make are stored privately on this device.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.c.textDim),
        ),
        const SizedBox(height: 24),
        GradientButton(
          label: 'Start recording',
          icon: Icons.fiber_manual_record_rounded,
          onTap: onRecord,
          expand: false,
        ),
      ],
    ),
  );
}

/// Splits [items] into date sections when sorted by date; otherwise one untitled group.
List<(String?, List<Recording>)> _groups(
  List<Recording> items,
  LibrarySort sort,
) {
  if (sort != LibrarySort.newest && sort != LibrarySort.oldest)
    return [(null, items)];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  String label(DateTime t) {
    final d = today.difference(DateTime(t.year, t.month, t.day)).inDays;
    if (d <= 0) return 'Today';
    if (d == 1) return 'Yesterday';
    if (d < 7) return 'This week';
    if (t.year == now.year && t.month == now.month) return 'This month';
    return t.year == now.year
        ? months[t.month - 1]
        : '${months[t.month - 1]} ${t.year}';
  }

  final out = <(String?, List<Recording>)>[];
  for (final r in items) {
    final l = label(r.modified);
    if (out.isEmpty || out.last.$1 != l) out.add((l, []));
    out.last.$2.add(r);
  }
  return out;
}

class _StorageCard extends StatefulWidget {
  const _StorageCard({required this.usedByReelmint});
  final int usedByReelmint;

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard> {
  StorageInfo? _info;

  @override
  void initState() {
    super.initState();
    context.recorder
        .storage()
        .then((i) {
          if (mounted) setState(() => _info = i);
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    final c = context.c;
    final used = (i?.usedFraction ?? 0).clamp(0.0, 1.0);
    final reelmint = i == null || i.total == 0
        ? 0.0
        : (widget.usedByReelmint / i.total).clamp(0.0, used);
    return Glass(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(
                Icons.sd_storage_rounded,
                color: L.amber,
                size: 30,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  i == null
                      ? 'Storage'
                      : '${formatBytes(i.free)} free of ${formatBytes(i.total)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'Reelmint ${formatBytes(widget.usedByReelmint)}',
                style: TextStyle(color: c.textDim, fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Container(color: c.surfaceHi),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      width: box.maxWidth * used,
                      color: c.textFaint,
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      width:
                          box.maxWidth *
                          (i == null ? 0 : reelmint.clamp(0.012, 1.0)),
                      decoration: BoxDecoration(gradient: L.brand),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Pressable(
            key: const ValueKey('save-location'),
            onTap: () {
              final dir = context.recorder.recordingsDir;
              if (dir == null) return;
              Clipboard.setData(ClipboardData(text: dir));
              toast(context, 'Folder path copied', icon: Icons.copy_rounded);
            },
            child: Row(
              children: [
                Icon(Icons.folder_rounded, size: 18, color: c.textDim),
                const SizedBox(width: 8),
                Text(
                  'Saved to ',
                  style: TextStyle(color: c.textDim, fontSize: 12.5),
                ),
                Expanded(
                  child: Text(
                    context.library.locationPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.copy_rounded, size: 15, color: c.textFaint),
              ],
            ),
          ),
          if (i != null && i.total > 0 && i.free < 2 * 1024 * 1024 * 1024) ...[
            const SizedBox(height: 8),
            const Text(
              'Running low on space — long recordings may stop early.',
              style: TextStyle(
                color: L.amber,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
