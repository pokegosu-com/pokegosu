import type { Pokemon } from '@/lib/game'

const GENDERS = {
  male: { symbol: '♂', label: '수컷' },
  female: { symbol: '♀', label: '암컷' },
} as const

/** ♂ or ♀ after a name, as the games put it, and nothing for a genderless Pokémon. */
export function Gender({ gender }: Pick<Pokemon, 'gender'>) {
  if (!gender) return null
  const { symbol, label } = GENDERS[gender]
  return (
    <span className="text-muted text-lg" title={label}>
      <span aria-hidden>{symbol}</span>
      <span className="sr-only">{label}</span>
    </span>
  )
}
