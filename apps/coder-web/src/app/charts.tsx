import { compactTokens, exactTokens } from '@/lib/format'
import { sum } from '@/lib/usage'

type Split = Record<string, number>

/** A round number at or above the busiest value, so the axis reads cleanly. */
function niceMax(value: number): number {
  if (value <= 0) return 1
  const step = 10 ** Math.floor(Math.log10(value))
  for (const m of [1, 2, 2.5, 5, 10]) if (m * step >= value) return m * step
  return 10 * step
}

/** The agents in a chart, named beside their colours. */
export function Legend({
  providers,
  colors,
}: {
  providers: { provider: string; display_name: string }[]
  colors: Map<string, string>
}) {
  return (
    <ul className="flex flex-wrap gap-4 text-[13px]">
      {providers.map((p) => (
        <li key={p.provider} className="flex items-center gap-1.5">
          <i className="size-2.5 rounded-sm" style={{ background: colors.get(p.provider) }} />
          {p.display_name}
        </li>
      ))}
    </ul>
  )
}

/**
 * 24 hours as columns, each stacked by agent. Hours after `until` are left
 * empty rather than drawn as zero, since they have not happened.
 */
export function HourChart({
  hours,
  colors,
  order,
  first = 0,
  until = 23,
  height = 180,
}: {
  hours: Split[]
  colors: Map<string, string>
  /** Agents from the bottom of a column up. */
  order: string[]
  /** The clock hour of the first column, for a chart that crosses midnight. */
  first?: number
  until?: number
  height?: number
}) {
  const max = niceMax(Math.max(...hours.map(sum)))
  const clock = (i: number) => `${(first + i) % 24}시`
  return (
    <div className="grid grid-cols-[2.5rem_minmax(0,1fr)] gap-x-2 gap-y-1">
      <div
        className="text-muted flex flex-col justify-between text-right font-mono text-[11px]"
        style={{ height }}
      >
        <span>{compactTokens(max)}</span>
        <span>{compactTokens(max / 2)}</span>
        <span>0</span>
      </div>
      <div className="border-line-strong relative border-b" style={{ height }}>
        <div className="border-line absolute inset-x-0 top-[7px] border-t border-dashed" />
        <div className="border-line absolute inset-x-0 top-1/2 border-t border-dashed" />
        <div className="absolute inset-0 flex items-end gap-1">
          {hours.map((split, i) => (
            <span
              key={i}
              title={i > until ? clock(i) : `${clock(i)} · ${exactTokens(sum(split))} 토큰`}
              className="flex h-full flex-1 flex-col-reverse"
            >
              {i <= until &&
                order.map((p) =>
                  split[p] ? (
                    <span
                      key={p}
                      className="border-surface border-t first:rounded-none last:rounded-t-sm"
                      style={{ height: `${(split[p] / max) * 100}%`, background: colors.get(p) }}
                    />
                  ) : null,
                )}
            </span>
          ))}
        </div>
      </div>
      <span />
      <div className="text-muted flex justify-between font-mono text-[11px]">
        {[0, 6, 12, 18, 23].map((i) => (
          <span key={i}>{clock(i)}</span>
        ))}
      </div>
    </div>
  )
}

/** One row's total as a bar split by agent, against the busiest row's. */
export function SplitBar({
  split,
  max,
  colors,
  order,
}: {
  split: Split
  max: number
  colors: Map<string, string>
  order: string[]
}) {
  return (
    <span className="bg-surface-raised flex h-2.5 overflow-hidden rounded-full">
      {order.map((p) =>
        split[p] ? (
          <span
            key={p}
            className="border-surface border-l first:border-l-0"
            style={{ width: `${(split[p] / Math.max(1, max)) * 100}%`, background: colors.get(p) }}
          />
        ) : null,
      )}
    </span>
  )
}

/** One headline number, its label, and the exact count beneath. */
export function Figure({
  label,
  tokens,
  className = '',
}: {
  label: string
  tokens: number | bigint
  className?: string
}) {
  return (
    <div className={`border-line grid gap-1 rounded-lg border px-4 py-3 ${className}`}>
      <p className="text-muted text-sm">{label}</p>
      <p className="font-mono text-3xl font-medium tracking-tight tabular-nums">
        {compactTokens(tokens)}
      </p>
      <p className="text-muted font-mono text-xs tabular-nums">{exactTokens(tokens)} 토큰</p>
    </div>
  )
}
