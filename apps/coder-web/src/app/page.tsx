import { Dashboard } from './dashboard'
import { HomePanel } from './game/home-panel'

export default function DashboardPage() {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-10 px-6 py-12">
      <HomePanel />
      <Dashboard />
    </main>
  )
}
