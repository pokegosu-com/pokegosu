// same-json <expected file> — exits 0 when stdin is the same JSON as the file.
//
// Compared as values rather than as bytes: what the fixtures fix is the
// rollups and the field names. How an implementation's encoder orders keys
// inside an object, or indents, is its own business. On a mismatch both are
// printed with sorted keys, one per line, so a diff says what differs.
import { readFileSync } from 'node:fs'

const sorted = (value) =>
  Array.isArray(value)
    ? value.map(sorted)
    : value !== null && typeof value === 'object'
      ? Object.fromEntries(
          Object.keys(value)
            .sort()
            .map((key) => [key, sorted(value[key])]),
        )
      : value

const render = (text, what) => {
  try {
    return JSON.stringify(sorted(JSON.parse(text)), null, 2)
  } catch {
    console.error(`${what} is not JSON: ${text}`)
    process.exit(2)
  }
}

const expected = render(readFileSync(process.argv[2], 'utf8'), 'the expectation')
const actual = render(readFileSync(0, 'utf8'), "the driver's output")

if (expected !== actual) {
  console.error(`--- expected\n${expected}\n--- actual\n${actual}`)
  process.exit(1)
}
