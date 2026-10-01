// Draws the bag sprites PokeAPI/sprites has none for into public/drawn: the
// Linking Cord and Meltan Candy, which the Coder game sells, and the Shelmet
// Shell, which is the game's own. The files are not committed: this script is
// what they are, and the same run draws the same bytes.
//
// Each is drawn as the bag sprites are, 30px with a #313131 outline and four
// tones lit from the top left, so it sits among them. A shape is a function
// from a pixel's centre to a colour, or to nothing; later shapes paint over
// earlier ones, and the outline goes round whatever is painted.
//
//   node scripts/draw-items.ts

import { mkdir, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { crc32, deflateSync } from 'node:zlib'

const SIZE = 30
const OUTLINE = '#313131'
const DIR = fileURLToPath(new URL('../public/drawn/items/', import.meta.url))

type Colour = string
/** Highlight, light, mid and dark. */
type Palette = readonly [Colour, Colour, Colour, Colour]
type Shape = (x: number, y: number) => Colour | null
type Vector = [number, number, number]

const LIGHT: Vector = (() => {
  const v: Vector = [-0.55, -0.65, 0.55]
  const m = Math.hypot(...v)
  return v.map((x) => x / m) as Vector
})()

/** How lit a surface facing a way is, 0 to 1. */
function lit(normal: Vector): number {
  return Math.max(0, normal[0] * LIGHT[0] + normal[1] * LIGHT[1] + normal[2] * LIGHT[2])
}

function tone(palette: Palette, light: number): Colour {
  return light > 0.93
    ? palette[0]
    : light > 0.62
      ? palette[1]
      : light > 0.32
        ? palette[2]
        : palette[3]
}

/** How far a point is from a segment, and the way back to it. */
function toSegment(x: number, y: number, ax: number, ay: number, bx: number, by: number) {
  const vx = bx - ax
  const vy = by - ay
  const t = Math.max(0, Math.min(1, ((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy)))
  const px = ax + t * vx - x
  const py = ay + t * vy - y
  return { d: Math.hypot(px, py), nx: -px, ny: -py }
}

/** A round tube along a segment, as wide as twice its radius. */
function tube(
  palette: Palette,
  ax: number,
  ay: number,
  bx: number,
  by: number,
  radius: number,
): Shape {
  return (x, y) => {
    const s = toSegment(x, y, ax, ay, bx, by)
    if (s.d >= radius) return null
    const nr = s.d / radius
    const m = s.d || 1
    return tone(palette, lit([(s.nx / m) * nr, (s.ny / m) * nr, Math.sqrt(1 - nr * nr)]))
  }
}

/** The pixels, painted, then outlined: every empty pixel beside a painted one. */
function draw(shapes: Shape[]): (Colour | null)[][] {
  const painted = Array.from({ length: SIZE }, (_, y) =>
    Array.from({ length: SIZE }, (_, x) => {
      let colour: Colour | null = null
      for (const shape of shapes) colour = shape(x + 0.5, y + 0.5) ?? colour
      return colour
    }),
  )
  return painted.map((row, y) =>
    row.map(
      (colour, x) =>
        colour ??
        ([
          [1, 0],
          [-1, 0],
          [0, 1],
          [0, -1],
        ].some(([dx, dy]) => painted[y + dy]?.[x + dx])
          ? OUTLINE
          : null),
    ),
  )
}

/** An RGBA PNG, unfiltered: small enough that nothing else is worth it. */
function png(pixels: (Colour | null)[][]): Buffer {
  const rows = Buffer.alloc(SIZE * (1 + SIZE * 4))
  pixels.forEach((row, y) => {
    const start = y * (1 + SIZE * 4)
    row.forEach((colour, x) => {
      if (!colour) return
      const at = start + 1 + x * 4
      for (let i = 0; i < 3; i += 1) rows[at + i] = parseInt(colour.slice(1 + i * 2, 3 + i * 2), 16)
      rows[at + 3] = 255
    })
  })
  const chunk = (type: string, data: Buffer) => {
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data])
    const length = Buffer.alloc(4)
    length.writeUInt32BE(data.length)
    const crc = Buffer.alloc(4)
    crc.writeUInt32BE(crc32(body))
    return Buffer.concat([length, body, crc])
  }
  const header = Buffer.alloc(13)
  header.writeUInt32BE(SIZE, 0)
  header.writeUInt32BE(SIZE, 4)
  header.set([8, 6, 0, 0, 0], 8)
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(rows, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

const metal: Palette = ['#ffffff', '#d8dde6', '#a7afbd', '#727b8c']
const gold: Palette = ['#fff3a8', '#f2cf4a', '#c9a024', '#8f6f12']
const silver: Palette = ['#ffffff', '#dfe3ea', '#aeb5c2', '#7a8292']

/**
 * The Linking Cord: a coil of cable, seen from above at a slant, with a plug
 * out to either side. Each loop's edge is dark, so the loops read apart.
 */
function linkingCord(): Shape[] {
  const cord: Palette = ['#9fb6e6', '#5f7fc4', '#3e5a9c', '#2a3d6e']
  const loop =
    (cx: number, cy: number, rx: number, ry: number, width: number): Shape =>
    (x, y) => {
      const dx = (x - cx) / rx
      const dy = (y - cy) / ry
      const r = Math.hypot(dx, dy)
      const off = (r - 1) * Math.min(rx, ry)
      if (Math.abs(off) > width) return null
      const nr = off / width
      if (Math.abs(nr) > 0.72) return cord[3]
      return tone(cord, lit([(dx / (r || 1)) * nr, (dy / (r || 1)) * nr, Math.sqrt(1 - nr * nr)]))
    }
  const plug = (ax: number, ay: number, bx: number, by: number): Shape[] => {
    const length = Math.hypot(bx - ax, by - ay)
    const tx = bx + ((bx - ax) / length) * 2
    const ty = by + ((by - ay) / length) * 2
    return [tube(gold, bx, by, tx, ty, 1.1), tube(metal, ax, ay, bx, by, 1.9)]
  }
  return [
    loop(15.6, 12.8, 6.8, 4.8, 1.4),
    loop(14.6, 14.6, 6.8, 4.8, 1.4),
    loop(13.6, 16.4, 6.8, 4.8, 1.4),
    tube(cord, 21.2, 10.6, 22.6, 8, 1.2),
    tube(cord, 8, 18.8, 7, 21.6, 1.2),
    ...plug(22.6, 8, 23.6, 5.8),
    ...plug(7, 21.6, 6.2, 23.8),
  ]
}

/**
 * Meltan Candy: Pokémon GO's candy, tilted, in Meltan's silver with the gold
 * of the nut it carries as its band.
 */
function meltanCandy(): Shape[] {
  const nut: Palette = ['#fff6b0', '#f4d24c', '#cfa52a', '#94721a']
  return [
    (x, y) => {
      const a = -Math.PI / 6
      const ra = 10.5
      const rb = 7.2
      const dx = x - 15
      const dy = y - 15.5
      const u = (dx * Math.cos(a) + dy * Math.sin(a)) / ra
      const v = (-dx * Math.sin(a) + dy * Math.cos(a)) / rb
      const d = u * u + v * v
      if (d > 1) return null
      // The surface's normal, from the ellipse's axes back to the screen's.
      const nu = (u / ra) * 10
      const nv = (v / rb) * 10
      const nx = nu * Math.cos(a) - nv * Math.sin(a)
      const ny = nu * Math.sin(a) + nv * Math.cos(a)
      const z = Math.sqrt(1 - d)
      const m = Math.hypot(nx, ny, z)
      const band = Math.abs(u - 0.18 + 0.32 * v * v) < 0.2
      return tone(band ? nut : silver, lit([nx / m, ny / m, z / m]))
    },
  ]
}

/**
 * The Shelmet Shell: the helmet Shelmet leaves when it becomes Accelgor, a
 * dome with a darker skirt, and the hole it looked out of at the front.
 */
function shelmetShell(): Shape[] {
  const shell: Palette = ['#ffffff', '#e4e7ee', '#b7bdcb', '#838a9c']
  const skirt: Palette = ['#d5dae3', '#a3aaba', '#7d8597', '#5b6274']
  return [
    (x, y) => {
      const r = 10.4
      const dx = x - 15
      const dy = y - 14.5
      const d = Math.hypot(dx, dy)
      if (d > r || dy > 7.2) return null
      const z = Math.sqrt(Math.max(0, 1 - (d / r) ** 2))
      if (dy > 5.4) return tone(skirt, lit([dx / r, 0.2, z]))
      return tone(shell, lit([dx / r, dy / r, z]))
    },
    // Dark inside, with its far rim catching the light.
    (x, y) => {
      const dx = (x - 15) / 4.6
      const dy = (y - 15.2) / 4.2
      const d = dx * dx + dy * dy
      if (d > 1) return null
      if (d > 0.62 && dx > 0.1 && dy > -0.2) return '#6a5862'
      return d < 0.5 ? '#24181f' : '#4a3a44'
    },
  ]
}

const ITEMS: Record<string, Shape[]> = {
  'linking-cord': linkingCord(),
  'meltan-candy': meltanCandy(),
  'shelmet-shell': shelmetShell(),
}

await mkdir(DIR, { recursive: true })
for (const [id, shapes] of Object.entries(ITEMS))
  await writeFile(`${DIR}${id}.png`, png(draw(shapes)))
console.log(`${Object.keys(ITEMS).length} items drawn`)
