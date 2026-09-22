import { NextResponse, type NextRequest } from 'next/server'

import { createClient } from '@pokegosu/supabase/server'

import { env } from '@/env'

/** Reachable without a session: the CLI reads the discovery document. */
const PUBLIC_PREFIXES = ['/.well-known']

export async function proxy(request: NextRequest) {
  // Replaced by setAll below whenever Supabase rotates the session cookies, so
  // the refreshed values reach the browser.
  let response = NextResponse.next({ request })

  const { pathname } = request.nextUrl
  if (PUBLIC_PREFIXES.some((p) => pathname === p || pathname.startsWith(`${p}/`))) {
    return response
  }

  const supabase = createClient({
    getAll: () => request.cookies.getAll(),
    setAll: (cookiesToSet) => {
      for (const { name, value } of cookiesToSet) {
        request.cookies.set(name, value)
      }
      response = NextResponse.next({ request })
      for (const { name, value, options } of cookiesToSet) {
        response.cookies.set(name, value, options)
      }
    },
  })

  // getUser() revalidates against the auth server. getSession() only decodes
  // the cookie and must not be trusted here.
  const {
    data: { user },
  } = await supabase.auth.getUser()

  // Signing in is the account app's job. It sends the person back here once
  // they have a session, which this app shares through the cookie domain.
  if (!user) {
    const login = new URL('/login', env.NEXT_PUBLIC_ACCOUNT_URL)
    login.searchParams.set('next', request.url)
    return NextResponse.redirect(login)
  }

  return response
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)',
  ],
}
