import { redirect } from 'next/navigation'

/** Every pokedex has its own address; the national one is where to start. */
export default function Home() {
  redirect('/national')
}
