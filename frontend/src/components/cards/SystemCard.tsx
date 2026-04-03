import React from 'react'
import { SystemFeatures } from '../../types/benchmark'
import { getSystemColor } from '../../utils/colors'

const FEATURES: { key: keyof Omit<SystemFeatures, 'system'>; label: string }[] = [
  { key: 'rebac', label: 'ReBAC' },
  { key: 'abac', label: 'ABAC / Cedar' },
  { key: 'caveats', label: 'Caveats' },
  { key: 'compliance', label: 'Compliance' },
  { key: 'immutableAudit', label: 'Immutable Audit' },
  { key: 'reverseIndex', label: 'Reverse Index' },
  { key: 'multiEngine', label: 'Multi-Engine' },
  { key: 'fintechReady', label: 'Fintech Ready' },
]

export const SystemCard: React.FC<{ features: SystemFeatures }> = ({ features }) => {
  const color = getSystemColor(features.system)
  return (
    <div style={{
      background: '#1e293b', border: `1px solid ${color}40`,
      borderRadius: '12px', padding: '20px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '16px' }}>
        <div style={{ width: '10px', height: '10px', borderRadius: '50%', background: color }} />
        <span style={{ color: '#f8fafc', fontWeight: 600, fontSize: '15px' }}>{features.system}</span>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' }}>
        {FEATURES.map(({ key, label }) => (
          <div key={key} style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
            <span style={{ color: features[key] ? '#10b981' : '#334155', fontSize: '14px' }}>
              {features[key] ? '●' : '○'}
            </span>
            <span style={{ color: features[key] ? '#94a3b8' : '#475569', fontSize: '12px' }}>
              {label}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}
