import React from 'react'
import { SystemFeatures } from '../../types/benchmark'
import { getSystemColor } from '../../utils/colors'

const FEATURES: { key: keyof Omit<SystemFeatures, 'system'>; label: string }[] = [
  { key: 'rebac',         label: 'ReBAC (Zanzibar)' },
  { key: 'abac',          label: 'ABAC / Cedar Policies' },
  { key: 'caveats',       label: 'Conditional Caveats' },
  { key: 'compliance',    label: 'Compliance Engine' },
  { key: 'immutableAudit',label: 'Immutable Audit Log' },
  { key: 'reverseIndex',  label: 'Reverse Lookup Index' },
  { key: 'multiEngine',   label: 'Multi-Engine Fusion' },
  { key: 'consistency',   label: 'Snapshot Consistency' },
  { key: 'openSource',    label: 'Open Source' },
  { key: 'fintechReady',  label: 'Fintech Ready' },
]

export const FeatureMatrix: React.FC<{ features: SystemFeatures[] }> = ({ features }) => (
  <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155', overflowX: 'auto' }}>
    <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600, fontSize: '15px' }}>Feature Comparison Matrix</h3>
    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px', minWidth: '600px' }}>
      <thead>
        <tr>
          <th style={{ color: '#64748b', textAlign: 'left', padding: '8px 12px', borderBottom: '1px solid #334155', fontWeight: 500 }}>
            Feature
          </th>
          {features.map(f => (
            <th key={f.system} style={{ color: getSystemColor(f.system), textAlign: 'center', padding: '8px 12px', borderBottom: '1px solid #334155', whiteSpace: 'nowrap', fontWeight: 600 }}>
              {f.system}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {FEATURES.map(({ key, label }) => (
          <tr key={key} style={{ borderBottom: '1px solid #1e293b' }}
            onMouseEnter={e => (e.currentTarget as HTMLElement).style.background = '#1a2744'}
            onMouseLeave={e => (e.currentTarget as HTMLElement).style.background = 'transparent'}
          >
            <td style={{ color: '#cbd5e1', padding: '10px 12px' }}>{label}</td>
            {features.map(f => (
              <td key={f.system} style={{ textAlign: 'center', padding: '10px 12px' }}>
                {f[key]
                  ? <span style={{ color: '#10b981', fontSize: '16px' }}>●</span>
                  : <span style={{ color: '#334155', fontSize: '16px' }}>○</span>}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  </div>
)
