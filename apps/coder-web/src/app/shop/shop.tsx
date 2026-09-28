'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

import { points } from '@/lib/format'
import { eggSpriteUrl, itemSpriteUrl, ko, type Item, type Named } from '@/lib/game'

import { say } from '../game/say'
import { useGame } from '../game/use-game'

type ShopItem = {
  id: string
  price: number
  item: Item | null
  egg: Named | null
}

const quiet =
  'border-line-strong hover:border-ink rounded-md border px-4 py-1.5 text-sm font-medium disabled:opacity-50'

function useShop() {
  const [items, setItems] = useState<ShopItem[] | null>(null)
  const [failure, setFailure] = useState<string | null>(null)
  useEffect(() => {
    createClient()
      .from('coder_shop_items')
      .select(
        'id, price, item:pokedex_items(id, ko_name, en_name, sprite), egg:coder_egg_kinds(ko_name, en_name)',
      )
      .order('position')
      .then(({ data, error }) => {
        if (error) setFailure(error.message)
        else setItems(data as unknown as ShopItem[])
      })
  }, [])
  return { items, failure }
}

/**
 * One thing for sale: its sprite in a well, its name, a line about it, the
 * price and the button. An item's sprite is 30px and drawn at twice that, a
 * whole number of pixels, so it stays crisp; the egg is 96px, like a
 * Pokémon's.
 */
function Ware({
  sprite,
  large,
  name,
  note,
  price,
  disabled,
  onBuy,
}: {
  sprite: string | undefined
  large: boolean
  name: string
  note: string
  price: number
  disabled: boolean
  onBuy: () => void
}) {
  return (
    <li className="border-line flex flex-col items-center gap-2 rounded-lg border p-4 text-center">
      <span className="bg-surface-raised grid size-24 place-items-center rounded-md">
        {sprite && (
          // eslint-disable-next-line @next/next/no-img-element -- served by pokedex-web
          <img
            src={sprite}
            alt=""
            className={`[image-rendering:pixelated] ${large ? 'size-24' : 'size-[60px]'}`}
          />
        )}
      </span>
      <span className="text-sm font-medium">{name}</span>
      <span className="text-muted text-xs">{note}</span>
      <span className="mt-auto font-mono text-sm tabular-nums">{points(price)}</span>
      <button type="button" className={quiet} disabled={disabled} onClick={onBuy}>
        사기
      </button>
    </li>
  )
}

export function ShopView() {
  const game = useGame()
  const { box, busy, last, act } = game
  const shop = useShop()
  const failure = game.failure ?? shop.failure
  const message = last ? say(box, last.action.fn, last.outcome) : null

  if (!box || !shop.items) {
    return failure ? (
      <p className="bg-danger-surface text-danger rounded-md px-3 py-2 text-sm">{failure}</p>
    ) : (
      <p className="text-muted text-sm">불러오는 중…</p>
    )
  }
  if (!box.started) {
    return (
      <p className="text-muted text-sm">
        아직 알을 받지 않았습니다.{' '}
        <Link href="/" className="text-accent">
          대시보드에서 시작하세요
        </Link>
      </p>
    )
  }

  const held = (id: string) => box.bag.find((b) => b.id === id)?.quantity ?? 0
  // How many in the box a stone would evolve, so it is clear what it is for.
  const takers = (id: string) =>
    box.pokemon.filter((p) => p.item_evolutions.some((e) => e.item.id === id)).length
  const stones = shop.items.filter((s) => s.item)
  const eggs = shop.items.filter((s) => s.egg)

  return (
    <>
      <div className="flex items-baseline justify-between gap-3">
        <h1 className="text-2xl font-semibold tracking-tight">상점</h1>
        <span className="font-mono text-sm tabular-nums">{points(box.points)}</span>
      </div>
      {failure && (
        <p className="bg-danger-surface text-danger rounded-md px-3 py-2 text-sm">{failure}</p>
      )}
      {message && <p className="bg-accent/10 rounded-md px-3 py-2 text-sm">{message}</p>}

      <section className="space-y-3">
        <h2 className="text-muted text-sm font-medium">진화의 돌</h2>
        <ul className="grid grid-cols-2 gap-3 sm:grid-cols-5">
          {stones.map((s) => {
            const n = takers(s.item!.id)
            return (
              <Ware
                key={s.id}
                sprite={itemSpriteUrl(s.item!)}
                large={false}
                name={ko(s.item!)}
                note={`가방에 ${held(s.item!.id)}개${n > 0 ? ` · 쓸 포켓몬 ${n}` : ''}`}
                price={s.price}
                disabled={busy || box.points < s.price}
                onBuy={() => act({ fn: 'buy', shop_item_id: s.id })}
              />
            )
          })}
        </ul>
        <p className="text-muted text-xs">
          산 돌은 가방에 들어갑니다. 박스에서 포켓몬을 고르면 그 포켓몬에게 쓸 수 있는 돌이
          보입니다.
        </p>
      </section>

      <section className="space-y-3">
        <h2 className="text-muted text-sm font-medium">알</h2>
        <ul className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {eggs.map((s) => (
            <Ware
              key={s.id}
              sprite={eggSpriteUrl}
              large
              name={ko(s.egg!)}
              note="그 지방 도감의 포켓몬"
              price={s.price}
              disabled={busy || box.points < s.price}
              onBuy={() => act({ fn: 'buy', shop_item_id: s.id })}
            />
          ))}
        </ul>
        <p className="text-muted text-xs">산 알은 박스에 들어갑니다.</p>
      </section>

      <p className="text-muted text-xs">
        포인트는{' '}
        <Link href="/requests" className="text-accent hover:text-ink">
          의뢰
        </Link>
        로 법니다.
      </p>
    </>
  )
}
