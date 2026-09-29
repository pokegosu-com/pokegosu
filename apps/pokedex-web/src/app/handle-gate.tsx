'use client'

import { useEffect } from 'react'

import { createClient } from '@pokegosu/supabase/client'
import { accountUrl } from '@pokegosu/ui/apps'

/**
 * Sends someone signed in without a handle to choose one, as the other apps
 * do on the server. The pages are files built ahead, so it can only happen
 * here, after the page has loaded; a visitor with no session is left alone.
 */
export function HandleGate() {
  useEffect(() => {
    void (async () => {
      const supabase = createClient()
      const {
        data: { session },
      } = await supabase.auth.getSession()
      if (!session) return
      const { data: profile, error } = await supabase
        .from('profiles')
        .select('username')
        .eq('id', session.user.id)
        .single()
      // Unable to tell, the page is left as it is rather than sent away.
      if (error || profile.username) return
      const onboarding = new URL('/onboarding', accountUrl)
      onboarding.searchParams.set('next', window.location.href)
      window.location.replace(onboarding)
    })()
  }, [])
  return null
}
