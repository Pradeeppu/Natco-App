import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { backupToFolder } from './driveBackup';
import { RealDriveFilesApi } from './realDriveFilesApi';

const driveServiceAccountKey = defineSecret('DRIVE_SERVICE_ACCOUNT_KEY');
const driveRootFolderId = defineSecret('DRIVE_ROOT_FOLDER_ID');

interface BackupOmrCaptureRequest {
  folderName: string;
  fileName: string;
  imageBase64: string;
}

function isValidRequest(data: unknown): data is BackupOmrCaptureRequest {
  if (typeof data !== 'object' || data === null) {
    return false;
  }
  const { folderName, fileName, imageBase64 } = data as Record<string, unknown>;
  return (
    typeof folderName === 'string' &&
    folderName.length > 0 &&
    typeof fileName === 'string' &&
    fileName.length > 0 &&
    typeof imageBase64 === 'string' &&
    imageBase64.length > 0
  );
}

/**
 * Backs up one captured OMR image to the shared Drive folder configured for
 * this deployment. See docs/13-google-drive-backup-setup.md.
 *
 * Requires only a signed-in Firebase Auth session — the same one every other
 * authenticated call in this app already requires. There is no per-user
 * Google identity anywhere in this path; the Drive credential is the
 * `DRIVE_SERVICE_ACCOUNT_KEY` secret, held only here, never shipped to a
 * device.
 */
export const backupOmrCapture = onCall(
  { secrets: [driveServiceAccountKey, driveRootFolderId] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        'unauthenticated',
        'Sign in to the app before backing up a capture.',
      );
    }
    if (!isValidRequest(request.data)) {
      throw new HttpsError(
        'invalid-argument',
        'folderName, fileName and imageBase64 are all required.',
      );
    }

    const filesApi = RealDriveFilesApi.fromServiceAccountKey(
      driveServiceAccountKey.value(),
    );
    const success = await backupToFolder(
      filesApi,
      driveRootFolderId.value(),
      request.data.folderName,
      request.data.fileName,
      request.data.imageBase64,
    );
    return { success };
  },
);
