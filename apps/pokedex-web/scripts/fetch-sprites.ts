// Fills public/ with the sprites sprites.json lists, from the pinned PokeAPI
// commit, and refuses any file whose hash differs from the manifest. The files
// are not committed: the manifest is what says exactly which bytes ship.
//
// A file already on disk with the right hash is kept, so a second run costs no
// requests.

import { createHash } from 'node:crypto'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

type Manifest = { files: { path: string; source: string; sha256: string }[] }

const root = fileURLToPath(new URL('../', import.meta.url))
const manifest = JSON.parse(await readFile(`${root}sprites.json`, 'utf8')) as Manifest

function sha256(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex')
}

async function onDisk(path: string): Promise<Uint8Array | null> {
  try {
    return await readFile(path)
  } catch {
    return null
  }
}

let fetched = 0
for (const file of manifest.files) {
  const target = `${root}public/${file.path}`
  const existing = await onDisk(target)
  if (existing && sha256(existing) === file.sha256) continue

  const response = await fetch(file.source)
  if (!response.ok) throw new Error(`${file.source}: ${response.status}`)
  const bytes = new Uint8Array(await response.arrayBuffer())
  if (sha256(bytes) !== file.sha256) {
    throw new Error(`${file.path}: the source no longer matches the manifest`)
  }
  await mkdir(dirname(target), { recursive: true })
  await writeFile(target, bytes)
  fetched += 1
}

console.log(`${manifest.files.length} sprites in place, ${fetched} fetched`)
