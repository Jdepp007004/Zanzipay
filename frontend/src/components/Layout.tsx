import React from 'react'
import { NavLink } from 'react-router-dom'

const NAV = [
  { path: '/', label: 'Dashboard', icon: '◎' },
  { path: '/latency', label: 'Latency', icon: '⚡' },
  { path: '/throughput', label: 'Throughput', icon: '⇄' },
  { path: '/features', label: 'Features', icon: '✦' },
  { path: '/architecture', label: 'Architecture', icon: '⬡' },
  { path: '/raw-data', label: 'Raw Data', icon: '≡' },
]

export const Layout: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ display: 'flex', minHeight: '100vh', background: '#0f172a', fontFamily: "'Inter', sans-serif" }}>
    <nav style={{
      width: '220px', background: '#0a0f1e', borderRight: '1px solid #1e293b',
      display: 'flex', flexDirection: 'column', padding: '20px 12px', gap: '4px', flexShrink: 0,
    }}>
      <div style={{ padding: '8px 12px 24px', display: 'flex', alignItems: 'center', gap: '10px' }}>
        <div style={{
          width: '32px', height: '32px', borderRadius: '8px',
          background: 'linear-gradient(135deg,#6366f1,#8b5cf6)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <span style={{ color: '#fff', fontWeight: 700, fontSize: '16px' }}>Z</span>
        </div>
        <div>
          <div style={{ color: '#f8fafc', fontWeight: 700, fontSize: '15px' }}>ZanziPay</div>
          <div style={{ color: '#475569', fontSize: '11px' }}>Benchmarks v1.0</div>
        </div>
      </div>
      {NAV.map(item => (
        <NavLink key={item.path} to={item.path} end={item.path === '/'}
          style={({ isActive }) => ({
            display: 'flex', alignItems: 'center', gap: '10px',
            padding: '9px 12px', borderRadius: '8px', textDecoration: 'none',
            fontSize: '13px', fontWeight: 500, transition: 'all 0.15s',
            color: isActive ? '#6366f1' : '#64748b',
            background: isActive ? '#6366f115' : 'transparent',
          })}>
          <span>{item.icon}</span>
          {item.label}
        </NavLink>
      ))}
      <div style={{ marginTop: 'auto', padding: '12px', color: '#334155', fontSize: '11px', textAlign: 'center' }}>
        Apache 2.0 · Open Source
      </div>
    </nav>
    <main style={{ flex: 1, padding: '32px', overflow: 'auto' }}>
      {children}
    </main>
  </div>
)
