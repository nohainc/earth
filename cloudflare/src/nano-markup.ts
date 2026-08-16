import { parse, stringify } from 'nanomarkup';

function toNanoTree(val: unknown): unknown {
  if (val === null || val === undefined) {
    return 'null';
  }
  if (typeof val === 'number' || typeof val === 'boolean' || typeof val === 'bigint') {
    return String(val);
  }
  if (typeof val === 'string') {
    return val;
  }
  if (Array.isArray(val)) {
    return val.map((item) => toNanoTree(item));
  }
  if (typeof val === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, v] of Object.entries(val as Record<string, unknown>)) {
      result[key] = toNanoTree(v);
    }
    return result;
  }
  return String(val);
}

/**
 * Encodes an object, map, sequence, or primitive to a canonical Nano Markup string.
 */
export function toNanoMarkup(value: unknown): string {
  if (value === null || value === undefined) {
    return 'null';
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed.startsWith('..') || trimmed.startsWith(':')) {
      return value; // Already formatted as Nano Markup
    }
  }
  try {
    const tree = toNanoTree(value);
    if (typeof tree === 'string') {
      return tree;
    }
    return stringify(tree as Record<string, unknown> | unknown[]);
  } catch {
    return JSON.stringify(value);
  }
}

/**
 * Decodes a Nano Markup string (or fallback JSON string) into a structured object/value.
 */
export function fromNanoMarkup<T = unknown>(value: unknown): T {
  if (typeof value !== 'string') {
    return value as T;
  }
  const text = value.trim();
  if (!text) {
    return {} as T;
  }
  // Check if it's legacy JSON object or array
  if ((text.startsWith('{') && text.endsWith('}')) || (text.startsWith('[') && text.endsWith(']'))) {
    try {
      return JSON.parse(text) as T;
    } catch {
      // Fall through to Nano Markup parsing
    }
  }
  // Try parsing as Nano Markup
  try {
    const result = parse(text);
    if (result !== undefined && result !== null && typeof result !== 'string') {
      return result as T;
    }
    if (typeof result === 'string') {
      // Check if the string itself was a JSON representation
      if ((result.startsWith('{') && result.endsWith('}')) || (result.startsWith('[') && result.endsWith(']'))) {
        try {
          return JSON.parse(result) as T;
        } catch {
          return result as unknown as T;
        }
      }
      return result as unknown as T;
    }
    return result as T;
  } catch {
    // Fallback if legacy JSON format or plain string
    try {
      return JSON.parse(text) as T;
    } catch {
      return text as unknown as T;
    }
  }
}
