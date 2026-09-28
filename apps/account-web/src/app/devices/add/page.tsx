import { Command } from '@pokegosu/ui/command'

import { CodeForm } from './code-form'

const STEPS = [
  {
    title: 'PokeGosu CLI 설치',
    command: 'curl -fsSL https://pokegosu.com/install-cli.sh | sh',
    hint: '~/.local/bin 에 설치되고, sudo 는 필요 없습니다.',
  },
  {
    title: '로그인',
    command: 'pokegosu auth login',
    hint: '코드와 링크가 나옵니다. 링크를 열면 바로 승인 화면으로 갑니다.',
  },
]

export default function AddMachinePage() {
  return (
    <main className="mx-auto flex w-full max-w-task flex-1 flex-col justify-center gap-6 px-6 py-24">
      <div className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">기기 추가</h1>
        <p className="text-muted text-sm">추가할 기기의 터미널에서 차례로 실행하세요.</p>
      </div>

      <ol className="border-line divide-line divide-y rounded-lg border">
        {STEPS.map((s, i) => (
          <li key={s.command} className="grid grid-cols-[2rem_minmax(0,1fr)] gap-3 p-4">
            <span className="text-muted font-mono text-sm leading-6 font-medium">{i + 1}</span>
            <div className="space-y-2">
              <p className="text-sm leading-6 font-medium">{s.title}</p>
              <Command command={s.command} />
              <p className="text-muted text-xs">{s.hint}</p>
            </div>
          </li>
        ))}
        <li className="grid grid-cols-[2rem_minmax(0,1fr)] gap-3 p-4">
          <span className="text-muted font-mono text-sm leading-6 font-medium">
            {STEPS.length + 1}
          </span>
          <div className="space-y-2">
            <p className="text-sm leading-6 font-medium">코드 입력</p>
            <p className="text-muted text-xs">
              링크를 열 수 없는 기기라면, 나온 코드를 여기에 입력하세요.
            </p>
            <CodeForm />
          </div>
        </li>
      </ol>
    </main>
  )
}
