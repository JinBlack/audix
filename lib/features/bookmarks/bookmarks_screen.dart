import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_providers.dart';
import '../../core/database/database.dart';
import '../../core/providers.dart';
import '../../core/util/format.dart';
import '../library/book_cover.dart';
import '../player/player_screen.dart';
import 'bookmarks_sheet.dart';

class BookmarksScreen extends ConsumerStatefulWidget {
  const BookmarksScreen({super.key});

  @override
  ConsumerState<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends ConsumerState<BookmarksScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookmarksAsync = ref.watch(allBookmarksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: bookmarksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No bookmarks yet.\nTap "Bookmark" on the player to save your spot.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final filtered = [
            for (final e in entries)
              if (bookmarkMatches(e.bookmark.note, e.bookmark.chapterIndex,
                  _query, bookTitle: e.book.title))
                e,
          ];

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: BookmarkSearchField(
                  controller: _controller,
                  onChanged: (v) => setState(() => _query = v),
                  hintText: 'Search ${entries.length} bookmarks…',
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('No matching bookmarks'),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final entry = filtered[i];
                          final b = entry.bookmark;
                          final hasNote = b.note?.isNotEmpty == true;
                          final time = formatDuration(
                              Duration(milliseconds: b.positionMs));
                          final where = 'Chapter ${b.chapterIndex + 1} • $time';

                          return ListTile(
                            leading: BookCover(
                                coverPath: entry.book.coverPath, size: 48),
                            title: Text(
                              hasNote ? b.note! : entry.book.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              hasNote ? '${entry.book.title} • $where' : where,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'note') {
                                  showBookmarkNoteDialog(
                                      context, ref, b.id, b.note);
                                } else if (v == 'delete') {
                                  ref
                                      .read(databaseProvider)
                                      .deleteBookmark(b.id);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'note', child: Text('Edit note')),
                                PopupMenuItem(
                                    value: 'delete', child: Text('Delete')),
                              ],
                            ),
                            onTap: () => _open(entry),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(BookmarkEntry entry) async {
    await ref
        .read(playerControllerProvider)
        .openBookmark(entry.book, entry.bookmark.positionMs);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }
}
