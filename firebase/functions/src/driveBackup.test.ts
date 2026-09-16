import { DriveFilesApi, backupToFolder } from './driveBackup';

const ROOT_FOLDER_ID = 'root_folder';

class FakeDriveFilesApi implements DriveFilesApi {
  existingFolderIds: string[];
  findFolderCalls: Array<{ folderName: string; parentId: string }> = [];
  createFolderCalls: Array<{ folderName: string; parentId: string }> = [];
  uploadCalls: Array<{ fileName: string; folderId: string; contentBase64: string }> = [];

  findFolderIdsError: unknown = null;
  createFolderError: unknown = null;
  uploadFileError: unknown = null;

  private nextCreatedFolderId = 1;

  constructor(existingFolderIds: string[] = []) {
    this.existingFolderIds = existingFolderIds;
  }

  async findFolderIds(folderName: string, parentId: string): Promise<string[]> {
    this.findFolderCalls.push({ folderName, parentId });
    if (this.findFolderIdsError) {
      throw this.findFolderIdsError;
    }
    return this.existingFolderIds;
  }

  async createFolder(folderName: string, parentId: string): Promise<string> {
    this.createFolderCalls.push({ folderName, parentId });
    if (this.createFolderError) {
      throw this.createFolderError;
    }
    return `created_folder_${this.nextCreatedFolderId++}`;
  }

  async uploadFile(params: {
    fileName: string;
    folderId: string;
    contentBase64: string;
  }): Promise<void> {
    if (this.uploadFileError) {
      throw this.uploadFileError;
    }
    this.uploadCalls.push(params);
  }
}

describe('backupToFolder', () => {
  test('creates the folder when none exists, then uploads into it', async () => {
    const filesApi = new FakeDriveFilesApi();

    const result = await backupToFolder(
      filesApi,
      ROOT_FOLDER_ID,
      'OMR_Captures_as_demo',
      '0001827_123.jpg',
      'b3Rlcw==',
    );

    expect(result).toBe(true);
    expect(filesApi.findFolderCalls).toEqual([
      { folderName: 'OMR_Captures_as_demo', parentId: ROOT_FOLDER_ID },
    ]);
    expect(filesApi.createFolderCalls).toEqual([
      { folderName: 'OMR_Captures_as_demo', parentId: ROOT_FOLDER_ID },
    ]);
    expect(filesApi.uploadCalls).toHaveLength(1);
    expect(filesApi.uploadCalls[0].fileName).toBe('0001827_123.jpg');
    expect(filesApi.uploadCalls[0].folderId).toBe('created_folder_1');
  });

  test('reuses an existing folder instead of creating a second one', async () => {
    const filesApi = new FakeDriveFilesApi(['existing_folder']);

    const result = await backupToFolder(
      filesApi,
      ROOT_FOLDER_ID,
      'OMR_Captures_as_demo',
      'sheet.jpg',
      'eA==',
    );

    expect(result).toBe(true);
    expect(filesApi.createFolderCalls).toHaveLength(0);
    expect(filesApi.uploadCalls[0].folderId).toBe('existing_folder');
  });

  test('a folder-lookup failure fails the upload without throwing', async () => {
    const filesApi = new FakeDriveFilesApi();
    filesApi.findFolderIdsError = new Error('network unreachable');

    const result = await backupToFolder(
      filesApi,
      ROOT_FOLDER_ID,
      'OMR_Captures_as_demo',
      'sheet.jpg',
      'eA==',
    );

    expect(result).toBe(false);
    expect(filesApi.uploadCalls).toHaveLength(0);
  });

  test('a folder-create failure fails the upload without throwing', async () => {
    const filesApi = new FakeDriveFilesApi();
    filesApi.createFolderError = new Error('quota exceeded');

    const result = await backupToFolder(
      filesApi,
      ROOT_FOLDER_ID,
      'OMR_Captures_as_demo',
      'sheet.jpg',
      'eA==',
    );

    expect(result).toBe(false);
    expect(filesApi.uploadCalls).toHaveLength(0);
  });

  test('an upload failure is reported as false, not a thrown exception', async () => {
    const filesApi = new FakeDriveFilesApi(['existing_folder']);
    filesApi.uploadFileError = new Error('connection reset');

    const result = await backupToFolder(
      filesApi,
      ROOT_FOLDER_ID,
      'OMR_Captures_as_demo',
      'sheet.jpg',
      'eA==',
    );

    expect(result).toBe(false);
  });
});
