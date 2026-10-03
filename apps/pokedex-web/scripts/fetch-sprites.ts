// Fills public/ with the sprites sprites.json lists, from the pinned PokeAPI
// commit, and refuses any file whose hash differs from the manifest. The files
// are not committed: the manifest is what says exactly which bytes ship.
//
// A file already on disk with the right hash is kept, so a second run costs no
// requests. A file the manifest no longer lists is deleted, so what ships is
// the manifest and nothing more, even where public/sprites was restored from
// a CI cache or left by an older manifest.
//
// The sprites repository is CC0, but that waives only its own rights: the
// images are © The Pokémon Company, as the manifest's notice says.

import { createHash } from 'node:crypto'
import { mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { dirname, relative } from 'node:path'
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

const listed = new Set(manifest.files.map((file) => file.path))
const entries = await readdir(`${root}public/sprites`, { recursive: true, withFileTypes: true })
let deleted = 0
for (const entry of entries) {
  if (!entry.isFile()) continue
  const path = `${entry.parentPath}/${entry.name}`
  if (listed.has(relative(`${root}public`, path))) continue
  await rm(path)
  deleted += 1
}

console.log(`${manifest.files.length} sprites in place, ${fetched} fetched, ${deleted} deleted`)
