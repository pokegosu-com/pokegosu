'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

import { compactTokens, exactTokens } from '@/lib/format'

/** What the usage function answers with. */
type Usage = {
  from: string
  to: string
  total: string
  devices: { device_id: string; device_name: string | null; tokens: number }[]
  hours: { hour_bucket: string; tokens: number }[]
}

const HOUR = 60 * 60 * 1000

/** The server keeps hours in UTC, so every range has to start on one. */
function floorHour(at: Date): Date {
  return new Date(Math.floor(at.getTime() / HOUR) * HOUR)
}

/** Monday 00:00 of this week, on the reader's clock. */
function startOfWeek(now: Date): Date {
  const day = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  day.setDate(day.getDate() - ((day.getDay() + 6) % 7))
  return day
}

function localDate(at: Date): string {
  return `${at.getFullYear()}-${at.getMonth() + 1}-${at.getDate()}`
}

/**
 * Today and this week are the same hourly rows summed over different spans, so
 * the week is fetched once and the day is taken from inside it.
 *
 * "Today" and "this week" are the reader's, which the server cannot know, so
 * this runs in the browser. In a zone offset by part of an hour, local
 * midnight falls inside a UTC hour; that hour is counted whole.
 */
export function Dashboard() {
  const [shown, setShown] = useState<{ usage: Usage; at: Date } | null>(null)
  const [failure, setFailure] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false

    async function load() {
      const at = new Date()
      const { data, error } = await createClient().rpc('usage', {
        range_start: floorHour(startOfWeek(at)).toISOString(),
        range_end: new Date(floorHour(at).getTime() + HOUR).toISOString(),
      })
      if (cancelled) return
      if (error) {
        setFailure(error.message)
        return
      }
      setFailure(null)
      setShown({ usage: data as Usage, at })
    }

    load()
    // A machine syncs every few minutes; a minute is fresh enough to watch.
    const timer = setInterval(load, 60_000)
    return () => {
      cancelled = true
      clearInterval(timer)
    }
  }, [])

  if (failure) {
    return <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{failure}</p>
  }
  if (!shown) {
    return <p className="text-muted text-sm">불러오는 중…</p>
  }

  const { usage, at } = shown
  const midnight = floorHour(new Date(at.getFullYear(), at.getMonth(), at.getDate()))
  const today = usage.hours
    .filter((h) => new Date(h.hour_bucket) >= midnight)
    .reduce((sum, h) => sum + h.tokens, 0)

  const monday = startOfWeek(at)
  const days = Array.from({ length: 7 }, (_, i) => {
    const day = new Date(monday)
    day.setDate(monday.getDate() + i)
    return { day, tokens: 0 }
  })
  const byDate = new Map(days.map((d) => [localDate(d.day), d]))
  for (const h of usage.hours) {
    const entry = byDate.get(localDate(new Date(h.hour_bucket)))
    if (entry) entry.tokens += h.tokens
  }
  const busiest = Math.max(1, ...days.map((d) => d.tokens))

  if (usage.devices.length === 0 && usage.hours.length === 0) {
    return (
      <section className="space-y-3">
        <h1 className="text-2xl font-semibold tracking-tight">아직 기록이 없습니다</h1>
        <p className="text-muted text-sm">
          <Link href="/devices/new" className="text-accent underline">
            기기를 추가
          </Link>
          하고 그 기기에서 <code>pokegosu coder sync</code> 를 실행하세요.
        </p>
      </section>
    )
  }

  return (
    <>
      <section className="grid grid-cols-2 gap-4">
        <Figure label="오늘" tokens={today} />
        <Figure label="이번 주" tokens={Number(usage.total)} exact={usage.total} />
      </section>

      <section className="space-y-3">
        <h2 className="text-muted text-sm font-medium">요일별</h2>
        <ol className="space-y-2">
          {days.map(({ day, tokens }) => (
            <li key={localDate(day)} className="flex items-center gap-3 text-sm">
              <span className="text-muted w-8">
                {day.toLocaleDateString('ko-KR', { weekday: 'short' })}
              </span>
              <span className="bg-muted/15 h-2 flex-1 overflow-hidden rounded-full">
                <span
                  className="bg-accent block h-full rounded-full"
                  style={{ width: `${(tokens / busiest) * 100}%` }}
                />
              </span>
              <span className="w-16 text-right tabular-nums" title={exactTokens(tokens)}>
                {tokens ? compactTokens(tokens) : '—'}
              </span>
            </li>
          ))}
        </ol>
      </section>

      <section className="space-y-3">
        <h2 className="text-muted text-sm font-medium">기기별 (이번 주)</h2>
        <ul className="border-muted/25 divide-muted/25 divide-y rounded-lg border text-sm">
          {usage.devices.map((d) => (
            <li key={d.device_id} className="flex justify-between gap-4 px-4 py-3">
              <span>{d.device_name ?? '이름 없는 기기'}</span>
              <span className="tabular-nums" title={exactTokens(d.tokens)}>
                {compactTokens(d.tokens)}
              </span>
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}

function Figure({ label, tokens, exact }: { label: string; tokens: number; exact?: string }) {
  return (
    <div className="border-muted/25 space-y-1 rounded-lg border px-4 py-3">
      <p className="text-muted text-sm">{label}</p>
      <p className="text-3xl font-semibold tracking-tight tabular-nums">{compactTokens(tokens)}</p>
      <p className="text-muted text-xs tabular-nums">{exactTokens(exact ?? tokens)} 토큰</p>
    </div>
  )
}
