/// Applies a `ReorderableListView` drag to a list of ids.
///
/// The off-by-one is Flutter's, not ours: when an item moves **down**, the
/// callback reports the index the item would land at *before* it is removed
/// from its old position, so the target must be decremented. Getting this
/// wrong silently shifts every drag by one, which is why it lives in a named
/// function with a unit test rather than inline in a widget.
List<String> reorderedIds(List<String> ids, int oldIndex, int newIndex) {
  if (oldIndex < 0 || oldIndex >= ids.length) return ids;

  final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
  final reordered = [...ids];
  final moved = reordered.removeAt(oldIndex);
  reordered.insert(target.clamp(0, reordered.length), moved);
  return reordered;
}
