import manifest from '../../sprites.json'

// What this app serves, drawn from the same manifest the files come from, so a
// sprite that failed to arrive shows up here as a broken image.
export default function Pokedex() {
  return (
    <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-8 px-6 py-12">
      <h1 className="text-2xl font-semibold tracking-tight">pokedex</h1>
      <ol className="grid grid-cols-4 gap-4 sm:grid-cols-6">
        {manifest.species.map((s) => (
          <li key={s.id} className="flex flex-col items-center gap-1 text-xs">
            <span className="flex h-20 items-end gap-1">
              {/* eslint-disable-next-line @next/next/no-img-element -- animated GIFs, served as they are */}
              <img src={`/sprites/pokemon/${s.id}.gif`} alt={s.name} />
              {/* eslint-disable-next-line @next/next/no-img-element -- animated GIFs, served as they are */}
              <img src={`/sprites/pokemon/shiny/${s.id}.gif`} alt={`${s.name} (색이 다른)`} />
            </span>
            <span className="text-muted tabular-nums">No.{String(s.id).padStart(3, '0')}</span>
            <span>{s.name}</span>
          </li>
        ))}
      </ol>
    </main>
  )
}
