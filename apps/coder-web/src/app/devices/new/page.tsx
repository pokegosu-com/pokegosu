import { headers } from 'next/headers'

import { AddMachine } from './add-machine'

export default async function AddMachinePage() {
  // The address this page was reached at is the one the CLI should use.
  const requestHeaders = await headers()
  const host = requestHeaders.get('x-forwarded-host') ?? requestHeaders.get('host')
  const proto = requestHeaders.get('x-forwarded-proto') ?? 'http'
  const origin = `${proto}://${host}`

  return (
    <main className="mx-auto flex w-full max-w-xl flex-1 flex-col gap-6 px-6 py-12">
      <div className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">기기 추가</h1>
        <p className="text-muted text-sm">
          기기에서 <code>pokegosu coder login</code> 을 실행하고 아래 코드를 입력하세요. 기기는 이
          코드를 자기만의 키로 바꿔 갖기 때문에, 비밀값을 복사해 붙여넣을 일이 없습니다.
        </p>
      </div>
      <AddMachine origin={origin} />
    </main>
  )
}
