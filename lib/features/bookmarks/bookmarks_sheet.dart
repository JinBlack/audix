import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_providers.dart';
import '../../core/database/database.dart';
import '../../core/providers.dart';
import '../../core/util/format.dart';

/// True if a bookmark's note / book title / "Chapter N" label contains [query].
bool bookmarkMatches(
  String? note,
  int chapterIndex,
  String query, {
  String? bookTitle,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final haystack =
      '${note ?? ''} ${bookTitle ?? ''} chapter ${chapterIndex + 1}'
          .toLowerCase();
  return haystack.contains(q);
}

/// A reusable rounded filter field for the bookmark views.
class BookmarkSearchField extends StatelessWidget {
  const BookmarkSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Filter bookmarks…',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Clear',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Opens the per-book bookmarks bottom sheet for the current book.
void showBookmarksSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _BookmarksSheet(),
  );
}

class _BookmarksSheet extends ConsumerStatefulWidget {
  const _BookmarksSheet();

  @override
  ConsumerState<_BookmarksSheet> createState() => _BookmarksSheetState();
}

class _BookmarksSheetState extends ConsumerState<_BookmarksSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks =
        ref.watch(currentBookmarksProvider).value ?? const <Bookmark>[];
    final controller = ref.read(playerControllerProvider);

    if (bookmarks.isEmpty) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('No bookmarks yet')),
        ),
      );
    }

    final filtered = [
      for (final b in bookmarks)
        if (bookmarkMatches(b.note, b.chapterIndex, _query)) b,
    ];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: BookmarkSearchField(
              controller: _controller,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Flexible(
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No matching bookmarks'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final b = filtered[i];
                      final chapterNo = b.chapterIndex + 1;
                      final time =
                          formatDuration(Duration(milliseconds: b.positionMs));
                      return ListTile(
                        leading: const Icon(Icons.bookmark),
                        title: Text(
                          b.note?.isNotEmpty == true
                              ? b.note!
                              : 'Chapter $chapterNo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('Chapter $chapterNo • $time'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'note') {
                              showBookmarkNoteDialog(context, ref, b.id, b.note);
                            } else if (v == 'delete') {
                              ref.read(databaseProvider).deleteBookmark(b.id);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'note', child: Text('Edit note')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                          ],
                        ),
                        onTap: () {
                          controller.seek(Duration(milliseconds: b.positionMs));
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shows a dialog to add/edit a bookmark's note.
Future<void> showBookmarkNoteDialog(
  BuildContext context,
  WidgetRef ref,
  int bookmarkId,
  String? currentNote,
) async {
  final db = ref.read(databaseProvider);
  final textController = TextEditingController(text: currentNote ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Bookmark note'),
      content: TextField(
        controller: textController,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Note'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, textController.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (result == null) return;
  await db.updateBookmarkNote(bookmarkId, result.isEmpty ? null : result);
}
