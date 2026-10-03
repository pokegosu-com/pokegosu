// Draws the bag sprites PokeAPI/sprites has none for into public/drawn: the
// Linking Cord and Meltan Candy, which the Coder game sells, the Shelmet
// Shell, which is the game's own, and the items Generation VIII evolves
// with, Legends: Arceus's and Generation IX's too, which PokeAPI/sprites
// stops short of. The files are not committed: this script is what they
// are, and the same run draws the same bytes.
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
/** A shape paints a colour, clears what is under it with CLEAR, or leaves it with null. */
type Shape = (x: number, y: number) => Colour | null
const CLEAR = 'clear'
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

/**
 * The pixels, painted, then outlined: every empty pixel beside a painted one,
 * inside a hole as well as round the edge.
 */
function draw(shapes: Shape[]): (Colour | null)[][] {
  const painted = Array.from({ length: SIZE }, (_, y) =>
    Array.from({ length: SIZE }, (_, x) => {
      let colour: Colour | null = null
      for (const shape of shapes) {
        const painted = shape(x + 0.5, y + 0.5)
        colour = painted === CLEAR ? null : (painted ?? colour)
      }
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
 * Meltan Candy: a ball in Meltan's silver, with the gold of the nut it
 * carries as a band running round it at a slant.
 */
function meltanCandy(): Shape[] {
  const nut: Palette = ['#fff6b0', '#f4d24c', '#cfa52a', '#94721a']
  // The band is where the ball's surface is near the plane square to this.
  const axis: Vector = (() => {
    const v: Vector = [0.62, -0.78, 0.2]
    const m = Math.hypot(...v)
    return v.map((x) => x / m) as Vector
  })()
  return [
    (x, y) => {
      const r = 8.6
      const nx = (x - 15) / r
      const ny = (y - 15) / r
      const d = nx * nx + ny * ny
      if (d > 1) return null
      const normal: Vector = [nx, ny, Math.sqrt(1 - d)]
      const band = Math.abs(normal[0] * axis[0] + normal[1] * axis[1] + normal[2] * axis[2]) < 0.2
      return tone(band ? nut : silver, lit(normal))
    },
  ]
}

/**
 * The Shelmet Shell: the shell Shelmet leaves when it becomes Accelgor, from
 * the side as Shelmet is seen, the coil behind and the spotted brim over the
 * opening it looked out of, now empty.
 */
function shelmetShell(): Shape[] {
  const ivory: Palette = ['#ffffff', '#efe8d6', '#cfc5a9', '#9d9277']
  const spot: Palette = ['#4f7fd0', '#2a5cb4', '#1f4590', '#163266']
  const ellipse = (x: number, y: number, cx: number, cy: number, rx: number, ry: number, a = 0) => {
    const dx = x - cx
    const dy = y - cy
    const u = (dx * Math.cos(a) + dy * Math.sin(a)) / rx
    const v = (-dx * Math.sin(a) + dy * Math.cos(a)) / ry
    return { u, v, d: u * u + v * v }
  }
  const ball = (palette: Palette, e: { u: number; v: number; d: number }) =>
    tone(palette, lit([e.u, e.v, Math.sqrt(Math.max(0, 1 - e.d))]))
  return [
    // The coil, a ball with its turn and its eye darker.
    (x, y) => {
      const e = ellipse(x, y, 19.4, 12.6, 7.6, 7.6)
      if (e.d > 1) return null
      // Lit a little more than a ball, so its turns show on its dark side.
      const r = Math.sqrt(e.d)
      if (Math.abs(r - 0.66) < 0.09 || Math.abs(r - 0.33) < 0.09) return ivory[3]
      return tone(ivory, lit([e.u, e.v, Math.sqrt(1 - e.d)]) + 0.25)
    },
    // The opening it looked out of, empty, so what is behind shows through.
    (x, y) => (ellipse(x, y, 11.2, 16.4, 6.4, 4.4).d <= 1 ? CLEAR : null),
    // The lower lip.
    (x, y) => {
      const e = ellipse(x, y, 13, 21.2, 6.8, 2.6, 0.12)
      return e.d <= 1 ? ball(ivory, e) : null
    },
    // The brim, tilted up at the front.
    (x, y) => {
      const e = ellipse(x, y, 11.6, 11.2, 8.4, 3.2, -0.22)
      return e.d <= 1 ? ball(ivory, e) : null
    },
    // Its spots.
    (x, y) => {
      for (const [cx, cy] of [
        [9.4, 10.8],
        [14.4, 9.6],
      ]) {
        const e = ellipse(x, y, cx, cy, 1.9, 1.1, -0.22)
        if (e.d <= 1) return tone(spot, lit([e.u * 0.5, -0.4, 0.8]))
      }
      return null
    },
  ]
}

/** A ball, squashed or stretched, lit as a ball is. */
function ball(palette: Palette, cx: number, cy: number, rx: number, ry: number): Shape {
  return (x, y) => {
    const u = (x - cx) / rx
    const v = (y - cy) / ry
    const d = u * u + v * v
    return d > 1 ? null : tone(palette, lit([u, v, Math.sqrt(1 - d)]))
  }
}

const leafGreen: Palette = ['#c8f08a', '#7fc44a', '#4e9a2c', '#2f6a18']

/**
 * An apple, as Applin lives in: round, dimpled at the top, with a stem and a
 * leaf. The Tart and Sweet Apples differ in their skins.
 */
function apple(skin: Palette): Shape[] {
  const stem: Palette = ['#c99a6a', '#9b6b3f', '#6f4823', '#4a2e14']
  return [
    // Two lobes make the dimple.
    ball(skin, 12.6, 17, 8, 8.4),
    ball(skin, 17.4, 17, 8, 8.4),
    tube(stem, 15, 9.6, 15.8, 5.2, 1),
    (x, y) => {
      const a = 0.5
      const dx = x - 19.6
      const dy = y - 6.6
      const u = (dx * Math.cos(a) + dy * Math.sin(a)) / 3.6
      const v = (-dx * Math.sin(a) + dy * Math.cos(a)) / 1.8
      const d = u * u + v * v
      return d > 1 ? null : tone(leafGreen, lit([u * 0.5, v, Math.sqrt(1 - d)]))
    },
  ]
}

/**
 * The Cracked Pot Sinistea comes from: a teapot in its lavender, spout to the
 * left and handle to the right, cracked down its side.
 */
function crackedPot(): Shape[] {
  const china: Palette = ['#ffffff', '#e2d6f2', '#b9a6d6', '#7f6aa3']
  const crack: [number, number][] = [
    [17.5, 12.5],
    [19, 15.5],
    [17.6, 18],
    [19.4, 21.5],
  ]
  return [
    // The handle, a loop out of the right of the body.
    (x, y) => {
      const u = (x - 22.4) / 4.2
      const v = (y - 17) / 4.4
      const r = Math.hypot(u, v)
      return Math.abs(r - 1) < 0.28 && x > 22.4 ? tone(china, lit([u, v, 0.6])) : null
    },
    tube(china, 9, 17.6, 4, 12.6, 1.5),
    ball(china, 15, 17.4, 8, 6.6),
    ball(china, 15, 10.8, 4.8, 1.6),
    ball(china, 15, 8.6, 1.5, 1.5),
    (x, y) =>
      crack.some(
        ([ax, ay], i) => i < crack.length - 1 && toSegment(x, y, ax, ay, ...crack[i + 1]).d < 0.55,
      )
        ? OUTLINE
        : null,
  ]
}

/**
 * Galarica twigs, bent into a Cuff for Galarian Slowpoke's arm or a Wreath for
 * its head: a ring seen at a slant, banded with the twigs' bark, the Wreath
 * wider and set with buds.
 */
function galaricaRing(wreath: boolean): Shape[] {
  const twig: Palette = ['#d9f2ef', '#86c9c2', '#4f9690', '#2c605c']
  const bud: Palette = ['#f6e7ff', '#cba3e6', '#9a6fbf', '#664a85']
  const rx = wreath ? 11.2 : 8.4
  const ry = wreath ? 6.4 : 5.6
  const width = wreath ? 1.7 : 2.3
  const ring: Shape = (x, y) => {
    const dx = (x - 15) / rx
    const dy = (y - 15.5) / ry
    const r = Math.hypot(dx, dy)
    const off = (r - 1) * Math.min(rx, ry)
    if (Math.abs(off) > width) return null
    if (Math.abs(Math.sin(Math.atan2(dy, dx) * (wreath ? 9 : 7))) < 0.18) return twig[3]
    const nr = off / width
    return tone(twig, lit([(dx / (r || 1)) * nr, (dy / (r || 1)) * nr, Math.sqrt(1 - nr * nr)]))
  }
  if (!wreath) return [ring]
  return [
    ring,
    ball(bud, 6.2, 11.4, 2.4, 2.4),
    ball(bud, 15, 8.6, 2.4, 2.4),
    ball(bud, 23.8, 11.4, 2.4, 2.4),
  ]
}

/**
 * A Strawberry Sweet, as Milcery is given to hold: a strawberry of sugar,
 * seeded, under its green cap.
 */
function strawberrySweet(): Shape[] {
  const berry: Palette = ['#ffd2dc', '#f2607d', '#c93556', '#8a1d36']
  return [
    (x, y) => {
      // Widest near the top, coming to a point at the bottom.
      const v = (y - 9) / 15
      if (v < 0 || v > 1) return null
      const half = 8.4 * Math.sqrt(1 - v) * (1 - 0.25 * v)
      const u = (x - 15) / half
      if (Math.abs(u) > 1) return null
      if ((Math.floor(x) * 2 + Math.floor(y) * 3) % 7 === 0 && Math.abs(u) < 0.75 && v > 0.15)
        return '#ffe9a0'
      return tone(berry, lit([u, v - 0.4, Math.sqrt(1 - u * u)]))
    },
    ball(leafGreen, 11, 9, 3.4, 1.8),
    ball(leafGreen, 19, 9, 3.4, 1.8),
    ball(leafGreen, 15, 8, 2.4, 2.2),
  ]
}

/**
 * A scroll of the Master Dojo's towers, as a spell scroll is drawn: a sheet
 * of paper in its tower's colour, open between its two rolls and written on
 * from the top roll to the bottom one.
 */
function scroll(paper: Palette): Shape[] {
  const rod: Palette = ['#d9b38a', '#a87a4f', '#7a522e', '#4f3318']
  // The writing, line by line, the last a short one.
  const lines: [number, number, number][] = [
    [10, 20, 10.5],
    [10, 18, 12.5],
    [10, 19, 14.5],
    [10, 20, 16.5],
    [10, 18, 18.5],
    [10, 15, 20.5],
  ]
  return [
    // The sheet, lit from the left, its right edge in shade.
    (x, y) =>
      x > 8 && x < 22 && y > 6 && y < 24
        ? x > 20.5
          ? paper[2]
          : x < 9.5
            ? paper[0]
            : paper[1]
        : null,
    (x, y) =>
      lines.some(([a, b, ly]) => x > a && x < b && Math.abs(y - ly) < 0.5) ? paper[3] : null,
    // The rolls across the top and the foot, their rod's ends out at the sides.
    tube(rod, 5, 6, 25, 6, 1.3),
    tube(paper, 7, 6, 23, 6, 2.2),
    tube(rod, 5, 24, 25, 24, 1.3),
    tube(paper, 7, 24, 23, 24, 2.2),
  ]
}

/** Whether a point is inside a polygon, by how many of its edges a ray crosses. */
function inside(x: number, y: number, points: [number, number][]): boolean {
  let crossings = 0
  points.forEach(([ax, ay], i) => {
    const [bx, by] = points[(i + 1) % points.length]
    if (ay > y !== by > y && x < ax + ((y - ay) / (by - ay)) * (bx - ax)) crossings += 1
  })
  return crossings % 2 === 1
}

/** A flat face of a solid, in one colour: faces are lit by where they face, not shaded across. */
function face(colour: Colour, points: [number, number][]): Shape {
  return (x, y) => (inside(x, y, points) ? colour : null)
}

/**
 * Black Augurite, the glassy stone Scyther becomes Kleavor with: a chunk of
 * black crystal, cut in facets, the ones to the top left catching the light.
 */
function blackAugurite(): Shape[] {
  const stone: Palette = ['#b4bccb', '#5d6372', '#3a3e48', '#22242a']
  const top: [number, number] = [16, 5]
  const left: [number, number] = [6, 13]
  const right: [number, number] = [24, 11]
  const bottom: [number, number] = [14, 26]
  const middle: [number, number] = [15, 15]
  return [
    face(stone[1], [top, left, middle]),
    face(stone[2], [top, middle, right]),
    face(stone[2], [left, bottom, middle]),
    face(stone[3], [middle, bottom, right]),
    // A glint where the lit facets meet.
    face(stone[0], [
      [14.5, 7.5],
      [11, 11.5],
      [12.5, 12],
    ]),
  ]
}

/**
 * A Peat Block, as Ursaring is given under a full moon: a cube of cut peat,
 * its top lit, its sides in shade, flecked with the roots it is made of.
 */
function peatBlock(): Shape[] {
  const peat: Palette = ['#c49a6c', '#9a7148', '#71502f', '#4b331c']
  const fleck = (x: number, y: number) =>
    (Math.floor(x) * 5 + Math.floor(y) * 3) % 11 === 0 ? peat[3] : null
  return [
    face(peat[1], [
      [15, 4],
      [26, 9.5],
      [15, 15],
      [4, 9.5],
    ]),
    face(peat[2], [
      [4, 9.5],
      [15, 15],
      [15, 27],
      [4, 21.5],
    ]),
    face(peat[3], [
      [15, 15],
      [26, 9.5],
      [26, 21.5],
      [15, 27],
    ]),
    (x, y) =>
      inside(x, y, [
        [15, 4],
        [26, 9.5],
        [15, 15],
        [4, 9.5],
      ])
        ? (Math.floor(x) * 7 + Math.floor(y) * 5) % 13 === 0
          ? peat[0]
          : null
        : inside(x, y, [
              [4, 9.5],
              [15, 15],
              [15, 27],
              [4, 21.5],
            ])
          ? fleck(x, y)
          : null,
  ]
}

/**
 * A Syrupy Apple, as Applin becomes Dipplin with: an apple in the amber of
 * the syrup it is steeped in, a drop of it running down its side.
 */
function syrupyApple(): Shape[] {
  const syrup: Palette = ['#fff1b8', '#f6c445', '#d8901c', '#94570c']
  return [...apple(syrup), tube(syrup, 21.6, 19, 21.8, 23.4, 1.3)]
}

/**
 * Metal Alloy, as Duraludon becomes Archaludon with: an ingot, its top lit,
 * its front and end in shade, with a gleam along the top.
 */
function metalAlloy(): Shape[] {
  return [
    face(metal[1], [
      [9, 9],
      [25, 9],
      [21, 14],
      [5, 14],
    ]),
    face(metal[2], [
      [5, 14],
      [21, 14],
      [20, 22],
      [6, 22],
    ]),
    face(metal[3], [
      [21, 14],
      [25, 9],
      [24, 17],
      [20, 22],
    ]),
    face(metal[0], [
      [10, 10],
      [19, 10],
      [17.5, 11.2],
      [9, 11.2],
    ]),
  ]
}

/**
 * A suit of armour, as Charcadet takes one of two to become Armarouge or
 * Ceruledge: a cuirass seen from the front, a notch for the neck, a
 * pauldron on each shoulder and a belt above the skirt of plates, ridged
 * down the middle and set with a gem on the chest.
 */
function armor(plate: Palette, gem: Palette): Shape[] {
  const body: [number, number][] = [
    [9, 7],
    [12.5, 7],
    [15, 10],
    [17.5, 7],
    [21, 7],
    [22, 12],
    [20.5, 19],
    [22.5, 26],
    [7.5, 26],
    [9.5, 19],
    [8, 12],
  ]
  const shaded = (x: number, y: number) => {
    // Rounded across the chest: lit to the left of the ridge, shaded right.
    const u = (x - 15) / 8
    return tone(plate, lit([u, (y - 15) / 16, Math.sqrt(Math.max(0, 1 - u * u))]))
  }
  return [
    (x, y) => (inside(x, y, body) ? shaded(x, y) : null),
    // The ridge down the chest, and the belt and the skirt's seams below it.
    (x, y) => (inside(x, y, body) && Math.abs(x - 15) < 0.5 && y > 10 && y < 19 ? plate[3] : null),
    (x, y) => (inside(x, y, body) && Math.abs(y - 19.5) < 1 ? plate[3] : null),
    (x, y) =>
      inside(x, y, body) && y > 20.5 && [11.5, 15, 18.5].some((sx) => Math.abs(x - sx) < 0.5)
        ? plate[2]
        : null,
    // The pauldrons, over the shoulders.
    ball(plate, 6.6, 11, 4.2, 3.6),
    ball(plate, 23.4, 11, 4.2, 3.6),
    ball(gem, 15, 14, 2.2, 2.2),
  ]
}

/**
 * The Unremarkable Teacup Poltchageist settles in to become Sinistcha: a bowl
 * of plain glazed clay, matcha green inside its rim.
 */
function unremarkableTeacup(): Shape[] {
  const clay: Palette = ['#f6f1e4', '#d9cfb6', '#b2a483', '#7b6e52']
  const matcha: Palette = ['#d9f0a0', '#9bc25a', '#6f9636', '#4a6a20']
  return [
    // The bowl, narrowing from its rim to its foot.
    (x, y) => {
      const v = (y - 11) / 13
      if (v < 0 || v > 1) return null
      const half = 11 - 5 * v * v
      const u = (x - 15) / half
      if (Math.abs(u) > 1) return null
      return tone(clay, lit([u, v - 0.3, Math.sqrt(1 - u * u)]))
    },
    tube(clay, 11, 24.5, 19, 24.5, 1.2),
    ball(clay, 15, 11, 11, 3.6),
    ball(matcha, 15, 11.4, 9.4, 2.6),
  ]
}

/**
 * The Leader's Crest, the blade Bisharp leading others wear on their heads:
 * a gold axe-head, its edge curved, with the dark steel it is set in below.
 */
function leadersCrest(): Shape[] {
  const steel: Palette = ['#9aa0ad', '#5e6472', '#40444f', '#2a2d35']
  return [
    (x, y) => {
      // A blade between two arcs, widest at the top, meeting at the foot.
      const outer = Math.hypot(x - 28, y - 13.5) < 19
      const inner = Math.hypot(x - 39, y - 13.5) < 19
      if (!outer || inner || y < 4 || y > 22) return null
      return tone(gold, lit([(x - 15) / 8, (y - 13) / 12, 0.75]))
    },
    face(steel[2], [
      [12, 21],
      [19, 21],
      [18, 26],
      [13, 26],
    ]),
    face(steel[1], [
      [12, 21],
      [14.5, 21],
      [14.5, 26],
      [13, 26],
    ]),
  ]
}

/**
 * A Gimmighoul Coin: a gold coin seen at a slant, a raised rim round it and
 * Gimmighoul's mark, a ring, struck in the middle.
 */
function gimmighoulCoin(): Shape[] {
  return [
    ball(gold, 15.6, 15.6, 9.4, 10.4),
    (x, y) => {
      const r = Math.hypot((x - 15) / 9.4, (y - 15) / 10.4)
      if (r > 1) return null
      if (r > 0.82) return tone(gold, lit([(x - 15) / 9.4, (y - 15) / 10.4, 0.5]))
      if (Math.abs(r - 0.42) < 0.1) return gold[3]
      return gold[1]
    },
    face(gold[0], [
      [9.5, 10],
      [12, 7.5],
      [13, 8.5],
      [10.5, 11],
    ]),
  ]
}

const ITEMS: Record<string, Shape[]> = {
  'linking-cord': linkingCord(),
  'meltan-candy': meltanCandy(),
  'shelmet-shell': shelmetShell(),
  'tart-apple': apple(['#fbffc2', '#c7e65a', '#93b92e', '#5c7a18']),
  'sweet-apple': apple(['#ffd8cc', '#f26a52', '#c93c32', '#8a1f1c']),
  'cracked-pot': crackedPot(),
  'galarica-cuff': galaricaRing(false),
  'galarica-wreath': galaricaRing(true),
  'strawberry-sweet': strawberrySweet(),
  'scroll-of-darkness': scroll(['#f4f4f6', '#c9c9d0', '#9a9aa6', '#62626e']),
  'scroll-of-waters': scroll(['#f2fbff', '#bfe6fb', '#8cc6e8', '#5592bd']),
  'black-augurite': blackAugurite(),
  'peat-block': peatBlock(),
  'syrupy-apple': syrupyApple(),
  'metal-alloy': metalAlloy(),
  'auspicious-armor': armor(
    ['#fff3c2', '#f0c64a', '#c9932a', '#8a5c14'],
    ['#ffd0d6', '#e8485e', '#b21f3a', '#701024'],
  ),
  'malicious-armor': armor(
    ['#b8b4d8', '#6c64a6', '#463f7a', '#2a244e'],
    ['#d6f2ff', '#5cc8f2', '#2a8cc4', '#155a88'],
  ),
  'unremarkable-teacup': unremarkableTeacup(),
  'leaders-crest': leadersCrest(),
  'gimmighoul-coin': gimmighoulCoin(),
}

await mkdir(DIR, { recursive: true })
for (const [id, shapes] of Object.entries(ITEMS))
  await writeFile(`${DIR}${id}.png`, png(draw(shapes)))
console.log(`${Object.keys(ITEMS).length} items drawn`)
