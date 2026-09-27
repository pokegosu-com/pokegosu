'use client'

import { useState } from 'react'

import { PokemonTile } from '@pokegosu/ui/pokemon'

export type Row = { number: number; name: string; types: string[]; sprite?: string }

/** A pokedex's tiles, narrowed by name or number and by type, all in the browser. */
export function DexGrid({
  dex,
  rows,
  types,
}: {
  dex: string
  rows: Row[]
  /** Every type, [id, Korean name], in the games' order. */
  types: [string, string][]
}) {
  const [query, setQuery] = useState('')
  const [type, setType] = useState<string | null>(null)
  const q = query.trim().replace(/^no\.?\s*/i, '')
  const shown = rows.filter(
    (r) =>
      (!type || r.types.includes(type)) &&
      (!q || r.name.includes(q) || String(r.number) === q.replace(/^0+/, '')),
  )
  return (
    <>
      <div className="flex items-center gap-3">
        <input
          type="search"
          aria-label="이름이나 번호로 찾기"
          placeholder="이름이나 번호로 찾기"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="border-line-strong bg-surface w-60 rounded-md border px-2.5 py-1.5 text-[13px]"
        />
        <span className="text-muted ml-auto font-mono text-xs tabular-nums">
          {shown.length === rows.length ? `${rows.length}마리` : `${shown.length} / ${rows.length}`}
        </span>
      </div>
      <div role="group" aria-label="타입" className="flex flex-wrap gap-1.5">
        {types.map(([id, name]) => (
          <button
            key={id}
            type="button"
            aria-pressed={type === id}
            onClick={() => setType(type === id ? null : id)}
            className="border-line aria-pressed:border-ink aria-pressed:bg-surface-raised inline-flex items-center gap-1.5 rounded border py-1 pr-2 pl-1.5 text-xs"
          >
            <i className="size-2 rounded-full" style={{ background: `var(--type-${id})` }} />
            {name}
          </button>
        ))}
      </div>
      {shown.length > 0 ? (
        <ol className="grid grid-cols-4 gap-2 sm:grid-cols-8">
          {shown.map((r) => (
            <li key={r.number} className="grid">
              <PokemonTile
                href={`/${dex}/${r.number}`}
                name={r.name}
                caption={`No.${String(r.number).padStart(3, '0')}`}
                sprite={r.sprite}
              />
            </li>
          ))}
        </ol>
      ) : (
        <p className="text-muted py-12 text-center">찾는 포켓몬이 없습니다</p>
      )}
    </>
  )
}
