'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

import { When } from '@/lib/when'

type Device = {
  id: string
  name: string
  last_sync_at: string | null
  revoked_at: string | null
  created_at: string
}

/** The database rejects a name for one reason: the check constraint. */
function messageFor(code: string | undefined, fallback: string) {
  return code === '23514' ? '이름은 공백이 아닌 글자를 포함해 100자 이내로 지어주세요.' : fallback
}

export function DeviceRow({ device }: { device: Device }) {
  const router = useRouter()
  const [editing, setEditing] = useState(false)
  const [name, setName] = useState(device.name)
  const [confirmingRetire, setConfirmingRetire] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const retired = device.revoked_at !== null

  async function update(values: { name?: string; revoked_at?: string }) {
    setBusy(true)
    setError(null)
    const { error: updateError } = await createClient()
      .from('devices')
      .update(values)
      .eq('id', device.id)
    setBusy(false)

    if (updateError) {
      setError(messageFor(updateError.code, updateError.message))
      return false
    }
    router.refresh()
    return true
  }

  return (
    <li className="space-y-2 px-4 py-3 text-sm">
      <div className="flex items-center justify-between gap-4">
        {editing ? (
          <form
            className="flex flex-1 gap-2"
            onSubmit={async (e) => {
              e.preventDefault()
              if (await update({ name: name.trim() })) setEditing(false)
            }}
          >
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              maxLength={100}
              autoFocus
              className="border-muted/40 flex-1 rounded-md border px-2 py-1"
            />
            <button type="submit" disabled={busy} className="text-accent disabled:opacity-50">
              저장
            </button>
            <button
              type="button"
              onClick={() => {
                setName(device.name)
                setEditing(false)
              }}
              className="text-muted"
            >
              취소
            </button>
          </form>
        ) : (
          <span className={retired ? 'text-muted line-through' : 'font-medium'}>{device.name}</span>
        )}

        {!editing && (
          <span className="flex gap-3">
            <button onClick={() => setEditing(true)} className="text-muted hover:text-ink">
              이름 변경
            </button>
            {!retired && (
              <button
                onClick={() => setConfirmingRetire(true)}
                className="text-red-600 hover:text-red-700"
              >
                폐기
              </button>
            )}
          </span>
        )}
      </div>

      <dl className="text-muted flex flex-wrap gap-x-6 gap-y-1 text-xs">
        <div className="flex gap-1">
          <dt>마지막 동기화</dt>
          <dd>
            <When at={device.last_sync_at} />
          </dd>
        </div>
        <div className="flex gap-1">
          <dt>등록</dt>
          <dd>
            <When at={device.created_at} />
          </dd>
        </div>
        {retired && (
          <div className="flex gap-1">
            <dt>폐기</dt>
            <dd>
              <When at={device.revoked_at} />
            </dd>
          </div>
        )}
      </dl>

      {retired && (
        <p className="text-muted text-xs">
          이 기기에서 새 코드로 <code>pokegosu auth login</code> 을 다시 하면 기록을 그대로 둔 채
          되살아납니다.
        </p>
      )}

      {confirmingRetire && (
        <div className="space-y-2 rounded-md bg-red-50 px-3 py-2 text-red-800">
          <p>
            이 기기의 키가 바로 막힙니다. 지금까지의 기록은 남습니다. 폐기는 되돌릴 수 없고, 다시
            쓰려면 그 기기에서 새로 로그인해야 합니다.
          </p>
          <div className="flex gap-3">
            <button
              disabled={busy}
              onClick={async () => {
                // The database stamps its own clock whatever is sent.
                if (await update({ revoked_at: new Date().toISOString() }))
                  setConfirmingRetire(false)
              }}
              className="font-medium disabled:opacity-50"
            >
              폐기
            </button>
            <button onClick={() => setConfirmingRetire(false)}>취소</button>
          </div>
        </div>
      )}

      {error && <p className="text-xs text-red-600">{error}</p>}
    </li>
  )
}
