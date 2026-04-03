export const formatMs = (ms: number): string => {
  if (ms < 1) return `${(ms * 1000).toFixed(0)}us`
  if (ms < 1000) return `${ms.toFixed(1)}ms`
  return `${(ms / 1000).toFixed(2)}s`
}

export const formatRPS = (rps: number): string => {
  if (rps >= 1_000_000) return `${(rps / 1_000_000).toFixed(1)}M/s`
  if (rps >= 1_000) return `${(rps / 1_000).toFixed(0)}K/s`
  return `${rps}/s`
}

export const toHumanScenario = (s: string): string =>
  s.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
