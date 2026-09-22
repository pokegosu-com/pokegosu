import { NextResponse, type NextRequest } from 'next/server'
import type { EmailOtpType } from '@pokegosu/supabase/server'

import { RETURN_TO_COOKIE, safeReturnTo } from '@/lib/return-to'
import { createClient } from '@/lib/supabase/server'

/**
 * Where the emailed link lands. Supabase sends either a PKCE `code` or a
 * `token_hash` + `type` pair depending on the template, so handle both.
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl
  const code = searchParams.get('code')
  const tokenHash = searchParams.get('token_hash')
  const type = searchParams.get('type') as EmailOtpType | null

  const supabase = await createClient()

  let message: string | null
  if (code) {
    message = (await supabase.auth.exchangeCodeForSession(code)).error?.message ?? null
  } else if (tokenHash && type) {
    message =
      (await supabase.auth.verifyOtp({ type, token_hash: tokenHash })).error?.message ?? null
  } else {
    message = searchParams.get('error_description') ?? '유효하지 않은 인증 링크입니다.'
  }

  if (message) {
    const url = new URL('/login', origin)
    url.searchParams.set('error', message)
    return NextResponse.redirect(url)
  }

  // Back to the app that sent them here, if one did. Checked again rather
  // than trusted: the cookie is only as good as whoever could write it.
  const returnTo = safeReturnTo(
    decodeURIComponent(request.cookies.get(RETURN_TO_COOKIE)?.value ?? ''),
  )
  const response = NextResponse.redirect(returnTo ?? new URL('/', origin))
  response.cookies.delete(RETURN_TO_COOKIE)
  return response
}
