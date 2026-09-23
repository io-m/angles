/** Stable public path. `v` changes when the object key does, so a replaced photo is not a day-old cache hit. */
export function avatarUrlFor(userId: string, avatarKey: string | null): string | undefined {
  if (!avatarKey) {
    return undefined;
  }
  const version = /-(\d+)\.jpg$/.exec(avatarKey)?.[1];
  return version ? `/avatars/${userId}?v=${version}` : `/avatars/${userId}`;
}

export function avatarObjectKey(userId: string, version = Date.now()): string {
  return `avatars/${userId}-${version}.jpg`;
}

/** Two letters from the first two words, otherwise the first letter. Empty name returns null. */
export function initialsFromDisplayName(name: string): string | null {
  const parts = name
    .split(/[\s\n]+/)
    .map((part) => part.replace(/^\p{P}+|\p{P}+$/gu, ""))
    .filter((part) => part.length > 0);

  const first = parts[0]?.[0];
  const second = parts[1]?.[0];
  if (first && second) {
    return `${first}${second}`.toLocaleUpperCase("en-US");
  }
  return first ? first.toLocaleUpperCase("en-US") : null;
}
