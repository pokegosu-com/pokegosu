import { createClient } from '@pokegosu/supabase/client'

type ByProvider = Record<string, number>

/** What the usage function answers with. */
export type Usage = {
  from: string
  to: string
  total: string
  providers: { provider: string; display_name: string; tokens: number }[]
  devices: {
    device_id: string
    /** Null once the machine is deleted: its tokens still count, its name is gone. */
    device_name: string | null
    tokens: number
    providers: ByProvider
  }[]
  hours: { hour_bucket: string; tokens: number; providers: ByProvider }[]
}

export const HOUR = 60 * 60 * 1000

/** The server keeps hours in UTC, so every range has to start on one. */
export function floorHour(at: Date): Date {
  return new Date(Math.floor(at.getTime() / HOUR) * HOUR)
}

/** 00:00 of the day `at` falls on, on the reader's clock. */
export function startOfDay(at: Date): Date {
  return new Date(at.getFullYear(), at.getMonth(), at.getDate())
}

/** Monday 00:00 of this week, on the reader's clock. */
export function startOfWeek(at: Date): Date {
  const day = startOfDay(at)
  day.setDate(day.getDate() - ((day.getDay() + 6) % 7))
  return day
}

export function startOfMonth(at: Date): Date {
  return new Date(at.getFullYear(), at.getMonth(), 1)
}

export function localDate(at: Date): string {
  return `${at.getFullYear()}-${at.getMonth() + 1}-${at.getDate()}`
}

/**
 * The reader's usage from `start` up to the end of the current hour.
 *
 * Days and weeks are the reader's, which the server cannot know, so the range
 * is worked out here. In a zone offset by part of an hour, local midnight
 * falls inside a UTC hour; that hour is counted whole.
 */
export async function loadUsage(start: Date, now: Date): Promise<Usage> {
  const { data, error } = await createClient().rpc('usage', {
    range_start: floorHour(start).toISOString(),
    range_end: new Date(floorHour(now).getTime() + HOUR).toISOString(),
  })
  if (error) throw error
  return data as unknown as Usage
}

/**
 * Each coding agent's colour. Claude Code keeps its own; the next agents take
 * the numbered ones in the order the legend lists them.
 */
export function providerColors(providers: { provider: string }[]): Map<string, string> {
  const colors = new Map<string, string>()
  let next = 2
  for (const { provider } of providers) {
    if (provider === 'claude_code') colors.set(provider, 'var(--provider-claude-code)')
    else colors.set(provider, `var(--provider-${Math.min(next++, 3)})`)
  }
  return colors
}

/** The hours of one day, 0 to 23 on the reader's clock, split by provider. */
export function hoursOf(usage: Usage, day: Date): ByProvider[] {
  const hours: ByProvider[] = Array.from({ length: 24 }, () => ({}))
  const key = localDate(day)
  for (const h of usage.hours) {
    const at = new Date(h.hour_bucket)
    if (localDate(at) !== key) continue
    const slot = hours[at.getHours()]
    for (const [p, t] of Object.entries(h.providers)) slot[p] = (slot[p] ?? 0) + t
  }
  return hours
}

/** The seven days from `monday`, split by provider. */
export function daysOf(usage: Usage, monday: Date): ByProvider[] {
  const days: ByProvider[] = Array.from({ length: 7 }, () => ({}))
  for (const h of usage.hours) {
    const at = startOfDay(new Date(h.hour_bucket))
    const i = Math.round((at.getTime() - monday.getTime()) / (24 * HOUR))
    if (i < 0 || i > 6) continue
    for (const [p, t] of Object.entries(h.providers)) days[i][p] = (days[i][p] ?? 0) + t
  }
  return days
}

export function sum(split: ByProvider): number {
  return Object.values(split).reduce((a, b) => a + b, 0)
}
