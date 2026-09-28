'use client'

import { useState } from 'react'

/** A command to run in a terminal, with a button that copies it. */
export function Command({ command }: { command: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <div className="bg-surface-raised flex items-center gap-2 rounded-md py-2 pr-2 pl-3">
      <code className="flex-1 font-mono text-[13px]">{command}</code>
      <button
        type="button"
        onClick={() =>
          navigator.clipboard
            .writeText(command)
            .then(() => setCopied(true))
            .catch(() => {})
        }
        className="border-line-strong hover:border-ink rounded-md border px-3 py-1.5 text-xs font-medium"
      >
        {copied ? '복사함' : '복사'}
      </button>
    </div>
  )
}
