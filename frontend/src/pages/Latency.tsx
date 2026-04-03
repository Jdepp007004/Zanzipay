import React, { useState } from 'react'
import { useBenchmarkData } from '../hooks/useBenchmarkData'
import { LatencyChart } from '../components/charts/LatencyChart'
import { ScalabilityChart } from '../components/charts/ScalabilityChart'
import { toHumanScenario, formatMs } from '../utils/format'
import { getSystemColor } from '../utils/colors'

type Metric = 'p50_ms' | 'p95_ms' | 'p99_ms'

export const Latency: React.FC = () => {
  const { results, scenarios, loading } = useBenchmarkData()
  const [metric, setMetric] = useState<Metric>('p95_ms')
  if (loading) return <div style={{ color: '#94a3b8', padding: '40px' }}>Loading...</div>

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
      <div>
        <h1 style={{ color: '#f8fafc', fontSize: '26px', fontWeight: 700, margin: '0 0 12px' }}>Latency Analysis</h1>
        <div style={{ display: 'flex', gap: '8px' }}>
          {(['p50_ms', 'p95_ms', 'p99_ms'] as Metric[]).map(m => (
            <button key={m} onClick={() => setMetric(m)} style={{
              padding: '6px 16px', borderRadius: '6px', border: 'none', cursor: 'pointer',
              fontSize: '12px', fontWeight: 600, transition: 'all 0.15s',
              background: metric === m ? '#6366f1' : '#1e293b',
              color: metric === m ? '#fff' : '#94a3b8',
            }}>
              {m.replace('_ms', '').toUpperCase()}
            </button>
          ))}
        </div>
      </div>

      <LatencyChart results={results} metric={metric} title={`${metric.replace('_ms','').toUpperCase()} Latency by Scenario`} />
      <ScalabilityChart />

      <h2 style={{ color: '#f8fafc', fontSize: '18px', fontWeight: 600, margin: 0 }}>Per-Scenario Winners</h2>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill,minmax(300px,1fr))', gap: '16px' }}>
        {scenarios.map(scenario => {
          const scenarioResults = results.filter(r => r.scenario === scenario).sort((a, b) => a[metric] - b[metric])
          const winner = scenarioResults[0]
          return (
            <div key={scenario} style={{ background: '#1e293b', borderRadius: '10px', padding: '16px', border: '1px solid #334155' }}>
              <div style={{ color: '#94a3b8', fontSize: '11px', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: '10px' }}>
                {toHumanScenario(scenario)}
              </div>
              {scenarioResults.map((r, i) => (
                <div key={r.system} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '5px 0', borderBottom: i < scenarioResults.length - 1 ? '1px solid #0f172a' : 'none' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                    {i === 0 && <span style={{ fontSize: '12px' }}>🏆</span>}
                    <span style={{ color: getSystemColor(r.system), fontSize: '12px', fontWeight: i === 0 ? 700 : 400 }}>{r.system}</span>
                  </div>
                  <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                    <span style={{ color: '#f8fafc', fontFamily: "'JetBrains Mono',monospace", fontSize: '12px' }}>{formatMs(r[metric])}</span>
                    {i > 0 && winner && (
                      <span style={{ color: '#ef4444', fontSize: '11px' }}>{(r[metric] / winner[metric]).toFixed(1)}x</span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )
        })}
      </div>
    </div>
  )
}
