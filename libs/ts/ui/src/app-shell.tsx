'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useEffect, useId, useState } from 'react'

import { accountUrl, apps, type AppId } from './apps'

export type Section = { label: string; href: string }

function MenuIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
      <path
        d="M3 5h12M3 9h12M3 13h12"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        fill="none"
      />
    </svg>
  )
}

const CAP_AT = 'translate(14.5 10.17) rotate(-10) scale(1.2 1.02) translate(-13 -21.5)'

/**
 * PokeGosu's icon, the Poké Ball in a trainer's cap, drawn as in each app's
 * icon.svg but without its white disc: on the page, the page is the ground.
 */
function PokeGosuIcon() {
  // Mask ids are document-wide, so each copy gets its own.
  const id = useId()
  return (
    <svg
      width="20"
      height="20"
      viewBox="-1 -8.3 37.8 37.8"
      aria-hidden="true"
      className="text-accent"
    >
      <defs>
        <g id={`${id}cap`}>
          <ellipse cx="13.2" cy="6.2" rx="1.7" ry="2" />
          <path d="M1.5 23.5C1 14.5 6 7.6 13.5 7.6C20.5 7.6 24.6 12.4 25 19.4Z" />
          <path d="M19.5 20.2C24 18.6 28.6 19 31.4 21C31 23.4 27.4 24.6 22.6 24.4C19 24.2 16 23 12.5 21.6Z" />
        </g>
        <mask
          id={`${id}under-cap`}
          maskUnits="userSpaceOnUse"
          x="-20"
          y="-20"
          width="72"
          height="72"
        >
          <rect x="-20" y="-20" width="72" height="72" fill="#fff" />
          <use
            href={`#${id}cap`}
            transform={CAP_AT}
            stroke="#000"
            strokeWidth="2.04"
            strokeLinejoin="round"
          />
        </mask>
        <mask
          id={`${id}bill-gap`}
          maskUnits="userSpaceOnUse"
          x="-20"
          y="-20"
          width="72"
          height="72"
        >
          <rect x="-20" y="-20" width="72" height="72" fill="#fff" />
          <path
            d="M19.2 19.6C24 18 28.6 18.4 31.6 20.4"
            fill="none"
            stroke="#000"
            strokeWidth="1.2"
          />
        </mask>
      </defs>
      <g fill="none" stroke="currentColor" strokeWidth="2.6" mask={`url(#${id}under-cap)`}>
        <circle cx="16" cy="16" r="10.6" />
        <path d="M5.4 16H12.6M19.4 16H26.6" />
        <circle cx="16" cy="16" r="3.2" />
      </g>
      <use href={`#${id}cap`} transform={CAP_AT} fill="currentColor" mask={`url(#${id}bill-gap)`} />
    </svg>
  )
}

/** A section is current on its own path and below it; the home section only on its own. */
function isCurrent(pathname: string, href: string): boolean {
  return href === '/' ? pathname === '/' : pathname === href || pathname.startsWith(`${href}/`)
}

/**
 * The bar across the top of every app, and the drawer its menu button opens.
 * The drawer is the only way between apps and to the account; the bar itself
 * links to neither.
 */
export function AppHeader({
  app,
  name,
  sections = [],
}: {
  /** Which app this is, marked in the drawer; the account is none of them. */
  app: AppId | 'account'
  /** The full name: PokeGosu Coder, PokeGosu Pokédex, PokeGosu 계정. */
  name: string
  sections?: Section[]
}) {
  const pathname = usePathname()
  // Remembers the page it was opened over, so following a link inside it
  // lands on a new page with the drawer shut.
  const [openOn, setOpenOn] = useState<string | null>(null)
  const open = openOn === pathname
  const setOpen = (value: boolean) => setOpenOn(value ? pathname : null)

  useEffect(() => {
    if (!open) return
    const close = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpenOn(null)
    }
    window.addEventListener('keydown', close)
    return () => window.removeEventListener('keydown', close)
  }, [open])

  return (
    <>
      <header className="border-line bg-surface border-b">
        <nav className="max-w-wide mx-auto flex w-full items-center gap-6 px-6 py-3 text-sm">
          <span className="-ml-2 flex items-center gap-1">
            <button
              type="button"
              aria-label="앱 메뉴"
              aria-expanded={open}
              onClick={() => setOpen(true)}
              className="hover:bg-surface-raised grid size-8 place-items-center rounded-md"
            >
              <MenuIcon />
            </button>
            {/* Not a link: the first section is already the way home. */}
            <span className="font-semibold tracking-tight">{name}</span>
          </span>
          {sections.map((s) => (
            <Link
              key={s.href}
              href={s.href}
              aria-current={isCurrent(pathname, s.href) ? 'page' : undefined}
              className="text-muted hover:text-ink aria-[current=page]:text-ink"
            >
              {s.label}
            </Link>
          ))}
        </nav>
      </header>

      {open && (
        <div className="fixed inset-0 z-50">
          <div className="bg-ink/30 absolute inset-0" onClick={() => setOpen(false)} />
          <aside
            aria-label="앱 메뉴"
            className="bg-surface border-line absolute inset-y-0 left-0 flex w-72 flex-col gap-2 border-r px-3 pt-3 pb-4"
          >
            <div className="flex items-center justify-between pr-2 pb-3 pl-3">
              <span className="flex items-center gap-2 font-semibold tracking-tight">
                <PokeGosuIcon />
                PokeGosu
              </span>
              <button
                type="button"
                aria-label="닫기"
                onClick={() => setOpen(false)}
                className="hover:bg-surface-raised grid size-8 place-items-center rounded-md"
              >
                ✕
              </button>
            </div>
            <p className="text-muted px-3 text-xs font-medium">앱</p>
            <ul className="grid gap-0.5">
              {apps.map((a) => (
                <li key={a.id}>
                  <a
                    href={a.url}
                    aria-current={a.id === app ? 'page' : undefined}
                    className="hover:bg-surface-raised aria-[current=page]:bg-surface-raised aria-[current=page]:ring-line grid gap-0.5 rounded-md px-3 py-2 aria-[current=page]:ring-1"
                  >
                    <span className="text-sm font-medium">{a.name}</span>
                    <span className="text-muted text-xs">{a.note}</span>
                  </a>
                </li>
              ))}
            </ul>
            <a
              href={accountUrl}
              aria-current={app === 'account' ? 'page' : undefined}
              className="border-line hover:bg-surface-raised mt-auto border-t px-3 pt-3 pb-2 text-sm font-medium"
            >
              계정
            </a>
          </aside>
        </div>
      )}
    </>
  )
}
