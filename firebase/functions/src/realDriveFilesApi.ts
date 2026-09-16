import { google, drive_v3 } from 'googleapis';
import { Readable } from 'stream';
import { DriveFilesApi } from './driveBackup';

/** Wraps a real, service-account-authenticated Drive v3 client. */
export class RealDriveFilesApi implements DriveFilesApi {
  private readonly drive: drive_v3.Drive;

  constructor(drive: drive_v3.Drive) {
    this.drive = drive;
  }

  /** Builds a client authenticated as the service account described by
   * `serviceAccountKeyJson` (the full JSON key file content), scoped to
   * `drive.file` — access limited to files/folders this identity itself
   * creates or is explicitly shared, never the whole of anyone's Drive. */
  static fromServiceAccountKey(serviceAccountKeyJson: string): RealDriveFilesApi {
    const credentials = JSON.parse(serviceAccountKeyJson) as {
      client_email: string;
      private_key: string;
    };
    const auth = new google.auth.JWT({
      email: credentials.client_email,
      key: credentials.private_key,
      scopes: ['https://www.googleapis.com/auth/drive.file'],
    });
    return new RealDriveFilesApi(google.drive({ version: 'v3', auth }));
  }

  async findFolderIds(folderName: string, parentId: string): Promise<string[]> {
    const escapedName = folderName.replace(/'/g, "\\'");
    const response = await this.drive.files.list({
      q:
        `mimeType='application/vnd.google-apps.folder' and ` +
        `name='${escapedName}' and '${parentId}' in parents and trashed=false`,
      fields: 'files(id, name)',
    });
    return (response.data.files ?? [])
      .map((f) => f.id)
      .filter((id): id is string => typeof id === 'string');
  }

  async createFolder(folderName: string, parentId: string): Promise<string> {
    const response = await this.drive.files.create({
      requestBody: {
        name: folderName,
        mimeType: 'application/vnd.google-apps.folder',
        parents: [parentId],
      },
      fields: 'id',
    });
    if (!response.data.id) {
      throw new Error('Drive did not return an id for the created folder');
    }
    return response.data.id;
  }

  async uploadFile(params: {
    fileName: string;
    folderId: string;
    contentBase64: string;
  }): Promise<void> {
    await this.drive.files.create({
      requestBody: {
        name: params.fileName,
        parents: [params.folderId],
      },
      media: {
        mimeType: 'image/jpeg',
        body: Readable.from(Buffer.from(params.contentBase64, 'base64')),
      },
    });
  }
}
