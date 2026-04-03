import React from 'react'

interface MetricCardProps {
  title: string
  value: string
  subtitle?: string
  color?: string
  icon?: React.ReactNode
}

export const MetricCard: React.FC<MetricCardProps> = ({ title, value, subtitle, color = '#6366f1', icon }) => (
  <div
    style={{
      background: 'linear-gradient(135deg,#1e293b 0%,#0f172a 100%)',
      border: `1px solid ${color}30`,
      borderRadius: '12px',
      padding: '20px',
      display: 'flex',
      flexDirection: 'column',
      gap: '8px',
      boxShadow: `0 4px 24px ${color}10`,
      transition: 'transform 0.2s ease,box-shadow 0.2s ease',
      cursor: 'default',
    }}
    onMouseEnter={e => {
      const el = e.currentTarget as HTMLElement
      el.style.transform = 'translateY(-2px)'
      el.style.boxShadow = `0 8px 32px ${color}20`
    }}
    onMouseLeave={e => {
      const el = e.currentTarget as HTMLElement
      el.style.transform = 'none'
      el.style.boxShadow = `0 4px 24px ${color}10`
    }}
  >
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
      <span style={{ color: '#94a3b8', fontSize: '11px', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
        {title}
      </span>
      {icon && <span style={{ color, fontSize: '18px' }}>{icon}</span>}
    </div>
    <div style={{ color, fontSize: '26px', fontWeight: 700, fontFamily: "'JetBrains Mono',monospace" }}>
      {value}
    </div>
    {subtitle && <div style={{ color: '#64748b', fontSize: '12px' }}>{subtitle}</div>}
  </div>
)
