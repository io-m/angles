export const MAX_TAGS = 8;

export function slugify(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

export function titleCase(slug: string): string {
  return slug
    .split("_")
    .filter((part) => part.length > 0)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

export function normalizeTagSlugs(values: readonly string[] | null | undefined): string[] {
  const tags: string[] = [];
  for (const value of values ?? []) {
    const slug = slugify(value);
    if (slug.length > 0 && !tags.includes(slug)) {
      tags.push(slug);
    }
    if (tags.length === MAX_TAGS) {
      break;
    }
  }
  return tags;
}
