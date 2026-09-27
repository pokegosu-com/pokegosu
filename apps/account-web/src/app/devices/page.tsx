import Link from 'next/link'

import { createClient } from '@/lib/supabase/server'

import { DeviceRow } from './device-row'

export default async function DevicesPage() {
  const supabase = await createClient()

  // RLS limits this to the reader's own machines; the key digest is not
  // granted, so it could not be selected even by mistake. A deleted machine
  // is gone for good, so it is not listed; its row stays only so the usage
  // it sent keeps counting.
  const { data: devices, error } = await supabase
    .from('devices')
    .select('id, name, last_sync_at, created_at')
    .is('revoked_at', null)
    .order('created_at')

  return (
    <main className="max-w-wide mx-auto flex w-full flex-1 flex-col gap-6 px-6 py-10">
      <div className="flex items-start justify-between gap-6">
        <div className="space-y-1">
          <h1 className="text-2xl font-semibold tracking-tight">기기</h1>
          <p className="text-muted text-sm">
            CLI 로 로그인한 기기입니다. 새 기기는{' '}
            <code className="text-ink font-mono text-[13px]">pokegosu auth login</code> 을 실행하면
            추가됩니다.
          </p>
        </div>
        <Link href="/devices/add" className="text-accent hover:text-ink flex-none text-sm">
          코드로 추가
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
