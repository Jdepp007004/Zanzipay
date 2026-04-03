export const SYSTEM_COLORS: Record<string, string> = {
  'ZanziPay': '#6366f1',
  'SpiceDB': '#f59e0b',
  'OpenFGA': '#10b981',
  'Ory Keto': '#ef4444',
  'Cedar (standalone)': '#8b5cf6',
}

export const getSystemColor = (system: string): string =>
  SYSTEM_COLORS[system] ?? '#64748b'

export const CHART_THEME = {
  background: '#0f172a',
  gridColor: '#1e293b',
  textColor: '#94a3b8',
  tooltipBg: '#1e293b',
  tooltipBorder: '#334155',
}
