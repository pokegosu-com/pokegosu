'use client'

import { Panel } from './panel'
import { useGame } from './use-game'

/** The main companion above the usage, which opening this page also feeds. */
export function HomePanel() {
  return <Panel game={useGame()} />
}
