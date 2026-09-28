'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

import { points } from '@/lib/format'
import { eggSpriteUrl, ko, type Named } from '@/lib/game'

import { say } from '../game/say'
import { useGame } from '../game/use-game'

type ShopItem = {
  id: string
  price: number
  item: ({ id: string } & Named) | null
  egg: Named | null
}

const quiet =
  'border-line-strong hover:border-ink rounded-md border px-4 py-2 text-sm font-medium disabled:opacity-50'

function useShop() {
  const [items, setItems] = useState<ShopItem[] | null>(null)
  const [failure, setFailure] = useState<string | null>(null)
  useEffect(() => {
    createClient()
      .from('coder_shop_items')
      .select(
        'id, price, item:pokedex_items(id, ko_name, en_name), egg:coder_egg_kinds(ko_name, en_name)',
      )
      .order('position')
      .then(({ data, error }) => {
        if (error) setFailure(error.message)
        else setItems(data as unknown as ShopItem[])
      })
  }, [])
  return { items, failure }
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
  const stones = shop.items.filter((s) => s.item)
  const eggs = shop.items.filter((s) => s.egg)

  const row = (s: ShopItem) => (
    <li key={s.id} className="flex items-center gap-4 px-4 py-3">
      {s.egg && (
        // eslint-disable-next-line @next/next/no-img-element -- served by pokedex-web
        <img src={eggSpriteUrl} alt="" className="size-10 [image-rendering:pixelated]" />
      )}
      <span className="flex-1 text-sm font-medium">{ko((s.item ?? s.egg)!)}</span>
      {s.item && (
        <span className="text-muted font-mono text-xs tabular-nums">
          가방에 {held(s.item.id)}개
        </span>
      )}
      <span className="w-24 text-right font-mono text-sm tabular-nums">{points(s.price)}</span>
      <button
        type="button"
        className={quiet}
        disabled={busy || box.points < s.price}
        onClick={() => act({ fn: 'buy', shop_item_id: s.id })}
      >
        사기
      </button>
    </li>
  )

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
        <ul className="border-line divide-line divide-y rounded-lg border">{stones.map(row)}</ul>
        <p className="text-muted text-xs">
          산 돌은 가방에 들어갑니다. 박스에서 포켓몬을 고르면 그 포켓몬에게 쓸 수 있는 돌이
          보입니다.
        </p>
      </section>

      <section className="space-y-3">
        <h2 className="text-muted text-sm font-medium">알</h2>
        <ul className="border-line divide-line divide-y rounded-lg border">{eggs.map(row)}</ul>
        <p className="text-muted text-xs">
          그 지방의 도감에 있는 포켓몬만 나옵니다. 산 알은 박스에 들어갑니다.
        </p>
      </section>

      <p className="text-muted text-xs">
        포인트는{' '}
        <Link href="/work" className="text-accent hover:text-ink">
          업장
        </Link>
        에서 법니다.
      </p>
    </>
  )
}
