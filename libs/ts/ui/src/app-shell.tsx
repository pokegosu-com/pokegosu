'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useEffect, useState } from 'react'

import { accountUrl, apps, type AppId } from './apps'
import { PokeGosuIcon } from './icon'

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
  picker = false,
  bareOn = [],
}: {
  /** Which app this is, marked in the drawer; the account is none of them. */
  app: AppId | 'account'
  /** The full name: PokeGosu Coder, PokeGosu Pokédex, PokeGosu 계정. */
  name: string
  sections?: Section[]
  /** Shows the current section alone, the rest in a menu under it, for an app with too many to fit in the bar. */
  picker?: boolean
  /** Paths that show no sections, such as sign-in, where every section would only lead back to it. */
  bareOn?: string[]
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
        <nav className="max-w-wide mx-auto flex w-full items-center gap-6 px-4 sm:px-6 py-3 text-sm">
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
          {bareOn.includes(pathname) ? null : picker ? (
            <SectionPicker sections={sections} pathname={pathname} />
          ) : (
            <>
              {/* More than two sections don't fit beside the name on a phone,
                  so there they fold into the picker. */}
              <span
                className={`items-center gap-6 ${sections.length > 2 ? 'hidden sm:flex' : 'flex'}`}
              >
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
              </span>
              {sections.length > 2 && (
                <span className="sm:hidden">
                  <SectionPicker sections={sections} pathname={pathname} />
                </span>
              )}
            </>
          )}
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

/** The current section as a button, opening a menu of every section below it. */
function SectionPicker({ sections, pathname }: { sections: Section[]; pathname: string }) {
  // Like the drawer, it remembers the page it was opened over, so it is shut
  // on the page a link inside it leads to.
  const [openOn, setOpenOn] = useState<string | null>(null)
  const open = openOn === pathname
  // A page under no section, such as a missing one, still names where home is.
  const current = sections.find((s) => isCurrent(pathname, s.href)) ?? sections[0]

  useEffect(() => {
    if (!open) return
    const close = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpenOn(null)
    }
    window.addEventListener('keydown', close)
    return () => window.removeEventListener('keydown', close)
  }, [open])

  if (!current) return null
  return (
    <span className="relative">
      <button
        type="button"
        aria-haspopup="true"
        aria-expanded={open}
        onClick={() => setOpenOn(open ? null : pathname)}
        className="hover:bg-surface-raised -mx-2 flex items-center gap-1.5 rounded-md px-2 py-1"
      >
        {current.label}
        <span aria-hidden="true">▾</span>
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpenOn(null)} />
          <ul className="bg-surface border-line absolute top-full left-0 z-50 mt-1 -ml-2 grid w-44 gap-0.5 rounded-md border p-1 shadow-sm">
            {sections.map((s, i) => (
              // The first section is home, so it stands apart from the rest.
              <li key={s.href} className={i === 1 ? 'border-line mt-0.5 border-t pt-1' : undefined}>
                <Link
                  href={s.href}
                  aria-current={isCurrent(pathname, s.href) ? 'page' : undefined}
                  className="text-muted hover:text-ink hover:bg-surface-raised aria-[current=page]:text-ink aria-[current=page]:bg-surface-raised block rounded px-2 py-1.5"
                >
                  {s.label}
                </Link>
              </li>
            ))}
          </ul>
        </>
      )}
    </span>
  )
}
