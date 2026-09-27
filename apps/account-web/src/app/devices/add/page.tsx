import { CodeForm } from './code-form'

export default function AddMachinePage() {
  return (
    <main className="mx-auto flex w-full max-w-task flex-1 flex-col justify-center gap-6 px-6 py-24">
      <div className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">기기 추가</h1>
        <p className="text-muted text-sm">
          기기에서 <code>pokegosu auth login</code> 을 실행하면 코드가 나옵니다. 그 코드를 여기에
          입력하세요.
        </p>
      </div>

      <CodeForm />
    </main>
  )
}
