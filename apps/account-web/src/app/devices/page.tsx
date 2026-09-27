import Link from 'next/link'

import { createClient } from '@/lib/supabase/server'

import { DeviceRow } from './device-row'

export default async function DevicesPage() {
  const supabase = await createClient()

  // RLS limits this to the reader's own machines; the key digest is not
  // granted, so it could not be selected even by mistake.
  const { data: devices, error } = await supabase
    .from('devices')
    .select('id, name, last_sync_at, revoked_at, created_at')
    .order('created_at')

  return (
    <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-6 px-6 py-12">
      <div className="flex items-baseline justify-between">
        <h1 className="text-2xl font-semibold tracking-tight">기기</h1>
        <Link href="/devices/add" className="text-accent text-sm underline">
          기기 추가
        </Link>
      </div>

      {error && (
        <p className="rounded-md bg-danger-surface px-3 py-2 text-sm text-danger">
          {error.message}
        </p>
      )}

      {devices && devices.length === 0 && (
        <p className="text-muted text-sm">
          아직 등록된 기기가 없습니다. 기기에서 <code>pokegosu auth login</code> 을 실행하면 코드가
          나옵니다.
        </p>
      )}

      {devices && devices.length > 0 && (
        <ul className="border-line divide-line divide-y rounded-lg border">
          {devices.map((device) => (
            <DeviceRow key={device.id} device={device} />
          ))}
        </ul>
      )}
    </main>
  )
}
