// Request validation shared by the functions.
//
// Everything here duplicates a constraint the database already enforces. That
// is on purpose: the constraints are the last line of defence and report
// themselves as 500s, while these report which field of which rollup is wrong.

import { invalid } from './http.ts'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function uuid(value: unknown, field: string): string {
  if (typeof value !== 'string' || !UUID.test(value)) {
    return invalidField(field, 'must be a UUID')
  }
  return value.toLowerCase()
}

export function nonEmptyString(value: unknown, field: string, maxLength: number): string {
  if (typeof value !== 'string') {
    return invalidField(field, 'must be a string')
  }
  const trimmed = value.trim()
  if (trimmed === '') {
    return invalidField(field, 'must not be blank')
  }
  if (trimmed.length > maxLength) {
    return invalidField(field, `must be at most ${maxLength} characters`)
  }
  return trimmed
}

/**
 * hourBucket accepts a timestamp that is exactly on the hour in UTC and
 * returns it in one canonical spelling.
 *
 * The schema has the same check, because each client implements its own
 * truncation and a bug there would otherwise write several rows for one hour
 * without violating the primary key.
 */
export function hourBucket(value: unknown, field: string): string {
  if (typeof value !== 'string') {
    return invalidField(field, 'must be an RFC3339 timestamp')
  }
  const at = new Date(value)
  if (Number.isNaN(at.getTime())) {
    return invalidField(field, `is not a valid timestamp: ${value}`)
  }
  if (at.getUTCMinutes() !== 0 || at.getUTCSeconds() !== 0 || at.getUTCMilliseconds() !== 0) {
    return invalidField(field, `must be on the hour in UTC, got ${value}`)
  }
  return onTheHour(at)
}

/**
 * onTheHour spells an instant the way every part of this system does:
 * RFC3339 in UTC with no fractional seconds. toISOString always writes
 * milliseconds, and a bucket that reads ".000Z" here and "Z" from the client
 * is the kind of difference that turns into a bug in whoever compares them.
 */
export function onTheHour(at: Date): string {
  return at.toISOString().replace(/\.\d{3}Z$/, 'Z')
}

/**
 * tokenCount accepts a non-negative whole number that survives a round trip
 * through JSON. The column is bigint, but a client sending more than
 * Number.MAX_SAFE_INTEGER has already lost precision before we see it.
 */
export function tokenCount(value: unknown, field: string): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value)) {
    return invalidField(field, 'must be a whole number')
  }
  if (value < 0) {
    return invalidField(field, 'must not be negative')
  }
  return value
}

export function array(value: unknown, field: string, max: number): unknown[] {
  if (!Array.isArray(value)) {
    return invalidField(field, 'must be an array')
  }
  if (value.length === 0) {
    return invalidField(field, 'must not be empty')
  }
  if (value.length > max) {
    return invalidField(field, `must hold at most ${max} entries; send them in batches`)
  }
  return value
}

function invalidField(field: string, problem: string): never {
  throw invalid(`${field} ${problem}`)
}
