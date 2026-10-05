'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

import { env } from '@/env'
import { points } from '@/lib/format'
import { eggSpriteUrl, itemSpriteUrl, ko, type Item, type Named } from '@/lib/game'

import { ActionToasts } from '../game/action-toasts'
import { useGame } from '../game/use-game'

type ShopItem = {
  id: string
  price: number
  item: Item | null
  egg: ({ id: string } & Named) | null
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
        'id, price, item:pokedex_items(id, ko_name, en_name, sprite), egg:coder_egg_kinds(id, ko_name, en_name)',
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
 * One thing for sale: its sprite, its name, a line about it, the
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
  note: React.ReactNode
  price: number
  disabled: boolean
  onBuy: () => void
}) {
  return (
    <li className="border-line flex flex-col items-center gap-2 rounded-lg border p-4 text-center">
      <span className="grid size-24 place-items-center">
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
        구매
      </button>
    </li>
  )
}

/**
 * "관동 지방의 포켓몬", from an egg named 관동 알, linked to that region's
 * pokedex, which shares the egg's id.
 */
function RegionNote({ egg }: { egg: { id: string } & Named }) {
  return (
    <a href={`${env.NEXT_PUBLIC_POKEDEX_URL}/${egg.id}`} className="text-accent hover:text-ink">
      {ko(egg).replace(/ 알$/, '')} 지방의 포켓몬
    </a>
  )
}

export function ShopView() {
  const game = useGame()
  const { box, busy, act } = game
  const shop = useShop()
  const failure = game.failure ?? shop.failure

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
  const tools = shop.items.filter((s) => s.item)
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
      <ActionToasts
        game={game}
        bought={(id) => {
          const s = shop.items?.find((i) => i.id === id)
          return s?.item ? ko(s.item) : s?.egg ? ko(s.egg) : undefined
        }}
      />

      <section className="space-y-3">
        <h2 className="text-muted text-sm font-medium">진화 도구</h2>
        <ul className="grid grid-cols-2 gap-3 sm:grid-cols-5">
          {tools.map((s) => (
            <Ware
              key={s.id}
              sprite={itemSpriteUrl(s.item!)}
              large={false}
              name={ko(s.item!)}
              note={`${held(s.item!.id)}개 보유`}
              price={s.price}
              disabled={busy || box.points < s.price}
              onBuy={() => act({ fn: 'buy', shop_item_id: s.id })}
            />
          ))}
        </ul>
      </section>

      <section className="space-y-3">
        <h2 className="text-muted text-sm font-medium">알</h2>
        <ul className="grid grid-cols-2 gap-3 sm:grid-cols-5">
          {eggs.map((s) => (
            <Ware
              key={s.id}
              sprite={eggSpriteUrl}
              large
              name={ko(s.egg!)}
              note={<RegionNote egg={s.egg!} />}
              price={s.price}
              disabled={busy || box.points < s.price}
              onBuy={() => act({ fn: 'buy', shop_item_id: s.id })}
            />
          ))}
        </ul>
      </section>
    </>
  )
}
