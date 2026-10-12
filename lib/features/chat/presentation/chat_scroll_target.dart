double estimateMessageScrollOffset({
  required int targetIndex,
  required int itemCount,
  required double maxScrollExtent,
}) {
  if (targetIndex <= 0 || itemCount <= 1 || maxScrollExtent <= 0) return 0;
  if (targetIndex >= itemCount - 1) return maxScrollExtent;
  return maxScrollExtent * targetIndex / (itemCount - 1);
}

int directionToMessage({
  required int targetIndex,
  required Iterable<int> visibleIndices,
}) {
  if (visibleIndices.isEmpty) return 0;
  var first = visibleIndices.first;
  var last = first;
  for (final index in visibleIndices.skip(1)) {
    if (index < first) first = index;
    if (index > last) last = index;
  }
  if (targetIndex < first) return -1;
  if (targetIndex > last) return 1;
  return 0;
}

double preserveScrollOffsetAfterPrepend({
  required double previousPixels,
  required double previousMaxScrollExtent,
  required double nextMaxScrollExtent,
  required double minScrollExtent,
}) {
  final addedExtent = nextMaxScrollExtent - previousMaxScrollExtent;
  if (addedExtent <= 0) return previousPixels;
  return (previousPixels + addedExtent).clamp(
    minScrollExtent,
    nextMaxScrollExtent,
  );
}

bool shouldFollowLatestMessage({
  required bool isMine,
  required bool hasScrollClients,
  required double distanceFromBottom,
}) => isMine || !hasScrollClients || distanceFromBottom <= 120;
