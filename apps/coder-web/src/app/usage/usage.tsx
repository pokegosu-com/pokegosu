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
  startOfWeek,
  sum,
  type Usage,
} from '@/lib/usage'

import { Figure, HourChart, Legend, SplitBar } from '../charts'

const WEEKDAYS = ['월', '화', '수', '목', '금', '토', '일']

/**
 * This month and this week, by hour, day, machine and coding agent. The month
 * is one call for its total; the week is another for everything else, since
 * the month's hours are more than the charts need.
 */
export function UsageView() {
  const [loaded, setLoaded] = useState<{ week: Usage; month: Usage; now: Date } | null>(null)
  const [failure, setFailure] = useState<string | null>(null)
  const [picked, setPicked] = useState<number | null>(null)

  useEffect(() => {
    let cancelled = false
    async function load() {
      const now = new Date()
      try {
        const [week, month] = await Promise.all([
          loadUsage(startOfWeek(now), now),
          loadUsage(startOfMonth(now), now),
        ])
        if (!cancelled) setLoaded({ week, month, now })
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

  const { week, month, now } = loaded
  const monday = startOfWeek(now)
  const today = Math.round((startOfDay(now).getTime() - monday.getTime()) / 86_400_000)
  const day = picked ?? today
  const shownDay = new Date(monday)
  shownDay.setDate(monday.getDate() + day)

  // The month's agents, so one that used nothing this week keeps its colour.
  const colors = providerColors(month.providers)
  const order = month.providers.map((p) => p.provider)
  const days = daysOf(week, monday)
  const busiestDay = Math.max(1, ...days.map(sum))
  const busiestDevice = Math.max(1, ...week.devices.map((d) => d.tokens))

  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-4">
        <h1 className="text-2xl font-semibold tracking-tight">사용량</h1>
        <Legend providers={month.providers} colors={colors} />
      </div>

      <section className="grid gap-4 sm:grid-cols-3">
        <Figure label="오늘" tokens={sum(days[today])} />
        <Figure label="이번 주" tokens={BigInt(week.total)} />
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
            {WEEKDAYS.slice(0, today + 1).map((label, i) => (
              <button
                key={label}
                type="button"
                aria-pressed={day === i}
                onClick={() => setPicked(i)}
                className="text-muted aria-pressed:bg-surface aria-pressed:text-ink aria-pressed:ring-line rounded-md px-3 py-1 text-[13px] font-medium aria-pressed:ring-1"
              >
                {i === today ? '오늘' : label}
              </button>
            ))}
          </div>
        </div>
        <HourChart
          hours={hoursOf(week, shownDay)}
          colors={colors}
          order={order}
          until={day === today ? now.getHours() : 23}
          height={200}
        />
      </section>

      <section className="grid gap-10 sm:grid-cols-2">
        <div className="flex flex-col gap-4">
          <h2 className="text-muted text-sm font-medium">요일별 · 이번 주</h2>
          <ol className="flex flex-col gap-3">
            {days.map((split, i) => (
              <li
                key={WEEKDAYS[i]}
                className="grid grid-cols-[1.5rem_minmax(0,1fr)_3.5rem] items-center gap-3 text-[13px]"
              >
                <span className={i === today ? 'text-ink font-medium' : 'text-muted'}>
                  {WEEKDAYS[i]}
                </span>
                <SplitBar split={split} max={busiestDay} colors={colors} order={order} />
                <span className="text-right font-mono text-xs tabular-nums">
                  {i > today ? '—' : compactTokens(sum(split))}
                </span>
              </li>
            ))}
          </ol>
        </div>
        <div className="flex flex-col gap-4">
          <h2 className="text-muted text-sm font-medium">기기별 · 이번 주</h2>
          {week.devices.length === 0 ? (
            <p className="text-muted text-sm">이번 주에 보낸 기기가 없습니다.</p>
          ) : (
            <ul className="flex flex-col gap-4">
              {week.devices.map((d) => (
                <li key={d.device_id} className="flex flex-col gap-1.5">
                  <p className="flex items-baseline justify-between gap-3 text-[13px]">
                    <span>{d.device_name ?? '이름 없는 기기'}</span>
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
