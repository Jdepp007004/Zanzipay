import React from 'react'
import { useBenchmarkData } from '../hooks/useBenchmarkData'
import { FeatureMatrix } from '../components/charts/FeatureMatrix'
import { SystemCard } from '../components/cards/SystemCard'

export const Features: React.FC = () => {
  const { features, loading } = useBenchmarkData()
  if (loading) return <div style={{ color: '#94a3b8', padding: '40px' }}>Loading...</div>

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
      <h1 style={{ color: '#f8fafc', fontSize: '26px', fontWeight: 700, margin: 0 }}>Feature Comparison</h1>
      <FeatureMatrix features={features} />
      <h2 style={{ color: '#f8fafc', fontSize: '18px', fontWeight: 600, margin: 0 }}>System Cards</h2>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(280px,1fr))', gap: '16px' }}>
        {features.map(f => <SystemCard key={f.system} features={f} />)}
      </div>
    </div>
  )
}
