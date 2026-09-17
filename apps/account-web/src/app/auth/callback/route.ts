import { NextResponse, type NextRequest } from 'next/server'
import type { EmailOtpType } from '@pokegosu/supabase/server'

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

  return NextResponse.redirect(new URL('/', origin))
}
