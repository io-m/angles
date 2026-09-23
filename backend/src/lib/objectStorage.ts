import {
  DeleteObjectCommand,
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";

export class StorageUnavailableError extends Error {
  constructor() {
    super("Object storage is not configured");
    this.name = "StorageUnavailableError";
  }
}

const JPEG = "image/jpeg";

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new StorageUnavailableError();
  }
  return value;
}

let client: S3Client | undefined;

function s3(): S3Client {
  if (!client) {
    client = new S3Client({
      region: requiredEnv("REGION"),
      endpoint: requiredEnv("ENDPOINT"),
      credentials: {
        accessKeyId: requiredEnv("ACCESS_KEY_ID"),
        secretAccessKey: requiredEnv("SECRET_ACCESS_KEY"),
      },
      forcePathStyle: process.env.S3_URL_STYLE === "path",
    });
  }
  return client;
}

function bucket(): string {
  return requiredEnv("BUCKET");
}

export async function putAvatar(key: string, body: Uint8Array): Promise<void> {
  await s3().send(
    new PutObjectCommand({
      Bucket: bucket(),
      Key: key,
      Body: body,
      ContentType: JPEG,
    }),
  );
}

export async function deleteAvatar(key: string): Promise<void> {
  await s3().send(
    new DeleteObjectCommand({
      Bucket: bucket(),
      Key: key,
    }),
  );
}

export async function getAvatar(key: string): Promise<Uint8Array | null> {
  try {
    const result = await s3().send(
      new GetObjectCommand({
        Bucket: bucket(),
        Key: key,
      }),
    );
    if (!result.Body) {
      return null;
    }
    return await result.Body.transformToByteArray();
  } catch (error) {
    if (isMissingObject(error)) {
      return null;
    }
    throw error;
  }
}

function isMissingObject(error: unknown): boolean {
  if (typeof error !== "object" || error === null || !("name" in error)) {
    return false;
  }
  const name = String(error.name);
  return name === "NoSuchKey" || name === "NotFound";
}
