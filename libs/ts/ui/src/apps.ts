import { createEnv } from '@t3-oss/env-nextjs'
import * as z from 'zod'

/**
 * Where each PokeGosu app lives, for the app drawer that moves between them.
 * Each app imports this from vite.config.ts, so a missing address fails the
 * build rather than a link.
 *
 * `process.env.NEXT_PUBLIC_*` is spelled out literally: Next inlines those by
 * matching that exact expression.
 */
export const appsEnv = createEnv({
  client: {
    NEXT_PUBLIC_ACCOUNT_URL: z.url(),
    NEXT_PUBLIC_POKEDEX_URL: z.url(),
    NEXT_PUBLIC_CODER_URL: z.url(),
  },
  experimental__runtimeEnv: {
    NEXT_PUBLIC_ACCOUNT_URL: process.env.NEXT_PUBLIC_ACCOUNT_URL,
    NEXT_PUBLIC_POKEDEX_URL: process.env.NEXT_PUBLIC_POKEDEX_URL,
    NEXT_PUBLIC_CODER_URL: process.env.NEXT_PUBLIC_CODER_URL,
  },
  emptyStringAsUndefined: true,
  // For builds that only check the code, such as `moon ci`. A deploy must
  // never set it.
  skipValidation: !!process.env.SKIP_ENV_VALIDATION,
})

export type AppId = 'pokedex' | 'coder'

/** The apps the drawer lists, in its order. */
export const apps: { id: AppId; name: string; note: string; url: string }[] = [
  {
    id: 'pokedex',
    name: 'PokeGosu Pokédex',
    note: '포켓몬 찾아보기',
    url: appsEnv.NEXT_PUBLIC_POKEDEX_URL,
  },
  {
    id: 'coder',
    name: 'PokeGosu Coder',
    note: '코딩 에이전트 토큰으로 포켓몬 키우기',
    url: appsEnv.NEXT_PUBLIC_CODER_URL,
  },
]

export const accountUrl = appsEnv.NEXT_PUBLIC_ACCOUNT_URL
