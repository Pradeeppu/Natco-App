/// The state of an entry in the sync queue.
library;

enum SyncStatus {
  pending('PENDING'),
  uploading('UPLOADING'),
  synced('SYNCED'),
  failed('FAILED'),
  conflict('CONFLICT');

  const SyncStatus(this.wireName);

  final String wireName;

  static SyncStatus? tryFromWireName(String? name) {
    if (name == null) {
      return null;
    }
    for (final SyncStatus status in values) {
      if (status.wireName == name) {
        return status;
      }
    }
    return null;
  }
}
