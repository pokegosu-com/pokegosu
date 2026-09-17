import { NextResponse, type NextRequest } from 'next/server'

import { createClient } from '@pokegosu/supabase/server'

/** Reachable without a session. */
const PUBLIC_PREFIXES = ['/login', '/auth']

export async function proxy(request: NextRequest) {
  // Replaced by setAll below whenever Supabase rotates the session cookies, so
  // the refreshed values reach the browser.
  let response = NextResponse.next({ request })

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

  const { pathname } = request.nextUrl
  const isPublic = PUBLIC_PREFIXES.some((p) => pathname === p || pathname.startsWith(`${p}/`))

  if (!user && !isPublic) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    url.search = ''
    return NextResponse.redirect(url)
  }

  // Lets the landing page link to /login unconditionally: someone who already
  // has a session lands on their account instead of a sign-in form.
  if (user && pathname === '/login') {
    const url = request.nextUrl.clone()
    url.pathname = '/'
    url.search = ''
    return NextResponse.redirect(url)
  }

  return response
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)',
  ],
}
