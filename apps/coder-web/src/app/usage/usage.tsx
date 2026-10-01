'use client'

import { useEffect, useState } from 'react'

import { compactTokens } from '@/lib/format'
import {
  daysOf,
  hoursOf,
  loadUsage,
  providerColors,
  startOfDay,
  startOfMonth,
  sum,
  type Usage,
} from '@/lib/usage'

import { Figure, HourChart, Legend, SplitBar } from '../charts'

const WEEKDAYS = ['월', '화', '수', '목', '금', '토', '일']

/** Today and the six days before it, on the reader's clock. */
const DAYS = 7
const TODAY = DAYS - 1

function firstDay(now: Date): Date {
  const day = startOfDay(now)
  day.setDate(day.getDate() - TODAY)
  return day
}

/**
 * This month and the last seven days, by hour, day, machine and coding agent.
 * The month is one call for its total; the seven days are another for
 * everything else, since the month's hours are more than the charts need.
 */
export function UsageView() {
  const [loaded, setLoaded] = useState<{ recent: Usage; month: Usage; now: Date } | null>(null)
  const [failure, setFailure] = useState<string | null>(null)
  const [picked, setPicked] = useState<number | null>(null)

  useEffect(() => {
    let cancelled = false
    async function load() {
      const now = new Date()
      try {
        const [recent, month] = await Promise.all([
          loadUsage(firstDay(now), now),
          loadUsage(startOfMonth(now), now),
        ])
        if (!cancelled) setLoaded({ recent, month, now })
      } catch (error) {
        if (!cancelled) setFailure((error as Error).message)
      }
    }
    load()
    const timer = setInterval(load, 60_000)
    return () => {
      cancelled = true
      clearInterval(timer)
    }
  }, [])

  if (failure) {
    return <p className="bg-danger-surface text-danger rounded-md px-3 py-2 text-sm">{failure}</p>
  }
  if (!loaded) return <p className="text-muted text-sm">불러오는 중…</p>

  const { recent, month, now } = loaded
  const first = firstDay(now)
  const dates = Array.from({ length: DAYS }, (_, i) => {
    const d = new Date(first)
    d.setDate(first.getDate() + i)
    return d
  })
  const weekday = (i: number) => WEEKDAYS[(dates[i].getDay() + 6) % 7]
  const day = picked ?? TODAY

  // The charts draw only the seven days, so their agents are the ones to list.
  // The month's would miss an agent used before the 1st, as on the 1st itself.
  const colors = providerColors(recent.providers)
  const order = recent.providers.map((p) => p.provider)
  const days = daysOf(recent, first)
  const busiestDay = Math.max(1, ...days.map(sum))
  const busiestDevice = Math.max(1, ...recent.devices.map((d) => d.tokens))

  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-semibold tracking-tight">사용량</h1>
        <Legend providers={recent.providers} colors={colors} />
      </div>

      <section className="grid gap-4 sm:grid-cols-3">
        <Figure label="오늘" tokens={sum(days[TODAY])} />
        <Figure label="최근 7일" tokens={BigInt(recent.total)} />
        <Figure label="이번 달" tokens={BigInt(month.total)} />
      </section>

      <section className="flex flex-col gap-4">
        <div className="flex items-center justify-between">
          <h2 className="text-muted text-sm font-medium">시간별</h2>
          <div
            role="group"
            aria-label="날짜"
            className="bg-surface-raised flex gap-0.5 rounded-lg p-0.5"
          >
            {dates.map((_, i) => (
              <button
                key={i}
                type="button"
                aria-pressed={day === i}
                onClick={() => setPicked(i)}
                className="text-muted aria-pressed:bg-surface aria-pressed:text-ink aria-pressed:ring-line rounded-md px-3 py-1 text-[13px] font-medium aria-pressed:ring-1"
              >
                {i === TODAY ? '오늘' : weekday(i)}
              </button>
            ))}
          </div>
        </div>
        <HourChart
          hours={hoursOf(recent, dates[day])}
          colors={colors}
          order={order}
          until={day === TODAY ? now.getHours() : 23}
          height={200}
        />
      </section>

      <section className="grid gap-10 sm:grid-cols-2">
        <div className="flex flex-col gap-4">
          <h2 className="text-muted text-sm font-medium">일별 · 최근 7일</h2>
          <ol className="flex flex-col gap-3">
            {days.map((split, i) => (
              <li
                key={i}
                className="grid grid-cols-[1.5rem_minmax(0,1fr)_3.5rem] items-center gap-3 text-[13px]"
              >
                <span className={i === TODAY ? 'text-ink font-medium' : 'text-muted'}>
                  {weekday(i)}
                </span>
                <SplitBar split={split} max={busiestDay} colors={colors} order={order} />
                <span className="text-right font-mono text-xs tabular-nums">
                  {compactTokens(sum(split))}
                </span>
              </li>
            ))}
          </ol>
        </div>
        <div className="flex flex-col gap-4">
          <h2 className="text-muted text-sm font-medium">기기별 · 최근 7일</h2>
          {recent.devices.length === 0 ? (
            <p className="text-muted text-sm">최근 7일 동안 보낸 기기가 없습니다.</p>
          ) : (
            <ul className="flex flex-col gap-4">
              {recent.devices.map((d) => (
                <li key={d.device_id} className="flex flex-col gap-1.5">
                  <p className="flex items-baseline justify-between gap-3 text-[13px]">
                    <span>{d.device_name ?? '(deleted-device)'}</span>
                    <span className="font-mono text-xs tabular-nums">
                      {compactTokens(d.tokens)}
                    </span>
                  </p>
                  <SplitBar split={d.providers} max={busiestDevice} colors={colors} order={order} />
                </li>
              ))}
            </ul>
          )}
        </div>
      </section>
    </>
  )
}
