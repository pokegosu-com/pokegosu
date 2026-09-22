// The little JSON these tests need, without jq.
//
//   json get <path>                  print a field of stdin, or nothing
//   json set <file> <key> <value>    rewrite one field of a file
//   json same <expected file>        exit 0 when stdin is the same JSON
//
// A path is dotted and may index arrays: rollups.0.tokens. Strings print
// bare, everything else as JSON.
import { readFileSync, writeFileSync } from 'node:fs'

const [command, ...args] = process.argv.slice(2)
const stdin = () => readFileSync(0, 'utf8')

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

switch (command) {
  case 'get': {
    let value
    try {
      value = JSON.parse(stdin())
    } catch {
      process.exit(0)
    }
    for (const part of args[0].split('.')) {
      value = value?.[part]
    }
    if (value !== undefined && value !== null) {
      console.log(typeof value === 'string' ? value : JSON.stringify(value))
    }
    break
  }
  case 'set': {
    const [file, key, value] = args
    const doc = JSON.parse(readFileSync(file, 'utf8'))
    doc[key] = value
    writeFileSync(file, JSON.stringify(doc))
    break
  }
  case 'same': {
    const expected = JSON.stringify(sorted(JSON.parse(readFileSync(args[0], 'utf8'))), null, 2)
    const actual = JSON.stringify(sorted(JSON.parse(stdin())), null, 2)
    if (expected !== actual) {
      console.error(`--- expected\n${expected}\n--- actual\n${actual}`)
      process.exit(1)
    }
    break
  }
  default:
    console.error(`json: unknown command ${command}`)
    process.exit(2)
}
