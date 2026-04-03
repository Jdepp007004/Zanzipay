import React from 'react'
import { useBenchmarkData } from '../hooks/useBenchmarkData'
import { ThroughputChart } from '../components/charts/ThroughputChart'
import { MetricCard } from '../components/cards/MetricCard'
import { formatRPS, toHumanScenario } from '../utils/format'

export const Throughput: React.FC = () => {
  const { results, loading } = useBenchmarkData()
  if (loading) return <div style={{ color: '#94a3b8', padding: '40px' }}>Loading...</div>

  const zanzi = results.filter(r => r.system === 'ZanziPay').sort((a, b) => b.throughput_rps - a.throughput_rps)

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
      <h1 style={{ color: '#f8fafc', fontSize: '26px', fontWeight: 700, margin: 0 }}>Throughput Analysis</h1>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(200px,1fr))', gap: '16px' }}>
        {zanzi.slice(0, 4).map(r => (
          <MetricCard
            key={r.scenario}
            title={toHumanScenario(r.scenario)}
            value={formatRPS(r.throughput_rps)}
            color="#10b981"
          />
        ))}
      </div>

      <ThroughputChart results={results} />

      <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155' }}>
        <h3 style={{ color: '#f8fafc', margin: '0 0 16px', fontWeight: 600, fontSize: '15px' }}>
          ZanziPay Throughput Advantage
        </h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          {zanzi.map(r => {
            const spicedb = results.find(x => x.scenario === r.scenario && x.system === 'SpiceDB')
            if (!spicedb) return null
            const speedup = (r.throughput_rps / spicedb.throughput_rps).toFixed(1)
            return (
              <div key={r.scenario} style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <span style={{ color: '#94a3b8', fontSize: '12px', minWidth: '140px' }}>{toHumanScenario(r.scenario)}</span>
                <div style={{ flex: 1, background: '#0f172a', borderRadius: '4px', height: '8px', overflow: 'hidden' }}>
                  <div style={{ width: `${Math.min(100, (r.throughput_rps / Math.max(...zanzi.map(x => x.throughput_rps))) * 100)}%`, height: '100%', background: '#6366f1', borderRadius: '4px' }} />
                </div>
                <span style={{ color: '#10b981', fontSize: '12px', fontFamily: "'JetBrains Mono',monospace", minWidth: '60px' }}>{formatRPS(r.throughput_rps)}</span>
                <span style={{ color: '#64748b', fontSize: '11px' }}>{speedup}x vs SpiceDB</span>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
