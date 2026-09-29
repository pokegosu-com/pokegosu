import { itemSpriteUrl, ko, type Item } from '@/lib/game'

/** "불꽃의돌 사용" with the stone's sprite before it, for a button. */
export function UseItemLabel({ item }: { item: Item }) {
  const sprite = itemSpriteUrl(item)
  return (
    <span className="flex items-center gap-1.5">
      {sprite && (
        // eslint-disable-next-line @next/next/no-img-element -- served by pokedex-web
        <img src={sprite} alt="" className="-my-2 size-[30px] [image-rendering:pixelated]" />
      )}
      {ko(item)} 사용
    </span>
  )
}
