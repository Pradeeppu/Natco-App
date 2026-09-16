/**
 * Backs up a captured OMR image to a folder on the service account's shared
 * Google Drive location, on behalf of every device — nobody signs into
 * Google on the phone (see docs/13-google-drive-backup-setup.md). This file
 * holds the logic; `index.ts` wraps it as the callable `backupOmrCapture`
 * function.
 */

/** The slice of Drive's Files API this backup needs. Kept as its own
 * interface, separate from the real `googleapis` client, so
 * `backupToFolder`'s folder-reuse / create-if-missing / upload logic can be
 * unit tested (`driveBackup.test.ts`) against a fake, without a real Drive
 * project or network access.
 */
export interface DriveFilesApi {
  /** Ids of existing, non-trashed folders named `folderName`, direct
   * children of `parentId`. */
  findFolderIds(folderName: string, parentId: string): Promise<string[]>;

  /** Creates a folder named `folderName` under `parentId`, returns its id. */
  createFolder(folderName: string, parentId: string): Promise<string>;

  /** Uploads `contentBase64` as `fileName` inside `folderId`. */
  uploadFile(params: {
    fileName: string;
    folderId: string;
    contentBase64: string;
  }): Promise<void>;
}

async function getOrCreateFolder(
  filesApi: DriveFilesApi,
  rootFolderId: string,
  folderName: string,
): Promise<string | null> {
  try {
    const existing = await filesApi.findFolderIds(folderName, rootFolderId);
    if (existing.length > 0) {
      return existing[0];
    }
    return await filesApi.createFolder(folderName, rootFolderId);
  } catch {
    return null;
  }
}

/**
 * The upload logic with its Drive dependency injected — what
 * `driveBackup.test.ts` calls directly against a fake `DriveFilesApi`, the
 * Node-side mirror of `GoogleDriveService.uploadToFolder` on the Dart side.
 */
export async function backupToFolder(
  filesApi: DriveFilesApi,
  rootFolderId: string,
  folderName: string,
  fileName: string,
  contentBase64: string,
): Promise<boolean> {
  try {
    const folderId = await getOrCreateFolder(filesApi, rootFolderId, folderName);
    if (folderId === null) {
      return false;
    }
    await filesApi.uploadFile({ fileName, folderId, contentBase64 });
    return true;
  } catch {
    // Best-effort backup: the capture flow already saved the sheet
    // durably and enqueued the real submission before this ever runs, so a
    // Drive failure here is reported as `false`, never thrown.
    return false;
  }
}
