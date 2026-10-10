import { exactTokens } from '@/lib/format'
import type { Curve } from '@/lib/game'

/** The levels a player aims for past the next one. */
const GOALS = [50, 100]

/** The tokens left to the next level, then to Lv.50 and Lv.100, beside the level above its bar. */
export function TokensLeft({
  curve,
  growthRate,
  level,
  to,
  tokens,
}: {
  curve: Curve
  growthRate: string
  level: number
  /** Where the next level starts, or null at the top. */
  to: number | null
  tokens: number
}) {
  if (to === null) return <span className="text-muted">최고 레벨</span>
  const starts = curve.get(growthRate) ?? []
  // A goal the next level reaches is said once, as the next level.
  const goals = GOALS.filter((goal) => goal > level + 1 && goal <= starts.length)
  return (
    <span className="text-muted flex flex-col items-end gap-0.5">
      <span>다음 레벨까지 {exactTokens(Math.ceil(to - tokens))} 토큰</span>
      {goals.map((goal) => (
        <span key={goal}>
          Lv.{goal}까지 {exactTokens(Math.ceil(starts[goal - 1] - tokens))} 토큰
        </span>
      ))}
    </span>
  )
}
