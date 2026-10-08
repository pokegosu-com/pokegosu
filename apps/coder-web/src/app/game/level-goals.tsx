import { exactTokens } from '@/lib/format'
import type { Curve } from '@/lib/game'

/** The levels a player aims for past the next one. */
const GOALS = [50, 100]

/** What Lv.50 and Lv.100 are still away, under the bar that shows the next level. */
export function LevelGoals({
  curve,
  growthRate,
  level,
  tokens,
}: {
  curve: Curve
  growthRate: string
  level: number
  tokens: number
}) {
  const starts = curve.get(growthRate) ?? []
  // The next level is already said above the bar, so a goal it reaches is
  // left out rather than said twice.
  const goals = GOALS.filter((goal) => goal > level + 1 && goal <= starts.length)
  if (!goals.length) return null
  return (
    <p className="text-muted flex justify-end gap-3 font-mono text-xs tabular-nums">
      {goals.map((goal) => (
        <span key={goal}>
          Lv.{goal}까지 {exactTokens(Math.ceil(starts[goal - 1] - tokens))} 토큰
        </span>
      ))}
    </p>
  )
}
