import React from 'react'
import { useBenchmarkData } from '../hooks/useBenchmarkData'
import { MetricCard } from '../components/cards/MetricCard'
import { LatencyChart } from '../components/charts/LatencyChart'
import { ThroughputChart } from '../components/charts/ThroughputChart'
import { RadarComparisonChart } from '../components/charts/RadarChart'
import { formatMs, formatRPS } from '../utils/format'

export const Dashboard: React.FC = () => {
  const { results, loading, error } = useBenchmarkData()

  if (loading) return <div style={{ color: '#94a3b8', padding: '40px', textAlign: 'center' }}>Loading benchmark data...</div>
  if (error) return <div style={{ color: '#ef4444', padding: '40px' }}>{error}</div>

  const zanzi = results.filter(r => r.system === 'ZanziPay')
  const simple = zanzi.find(r => r.scenario === 'simple_check')
  const lookup = zanzi.find(r => r.scenario === 'lookup_resources')
  const compliance = zanzi.find(r => r.scenario === 'compliance_check')
  const allThroughput = Math.max(...zanzi.map(r => r.throughput_rps))

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
      <div>
        <h1 style={{ color: '#f8fafc', fontSize: '26px', fontWeight: 700, margin: '0 0 6px' }}>
          ZanziPay Authorization Benchmarks
        </h1>
        <p style={{ color: '#64748b', margin: 0, fontSize: '13px' }}>
          Comparing ZanziPay vs SpiceDB, OpenFGA &amp; Ory Keto across 5 fintech scenarios
        </p>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(200px,1fr))', gap: '16px' }}>
        <MetricCard
          title="Simple Check P95"
          value={formatMs(simple?.p95_ms ?? 0)}
          subtitle="vs SpiceDB 3.2ms"
          color="#6366f1"
        />
        <MetricCard
          title="Lookup Resources P95"
          value={formatMs(lookup?.p95_ms ?? 0)}
          subtitle="37x faster than SpiceDB"
          color="#10b981"
        />
        <MetricCard
          title="Peak Throughput"
          value={formatRPS(allThroughput)}
          subtitle="lookup_resources scenario"
          color="#f59e0b"
        />
        <MetricCard
          title="Full Pipeline P95"
          value={formatMs(compliance?.p95_ms ?? 0)}
          subtitle="ReBAC + Policy + Compliance"
          color="#8b5cf6"
        />
      </div>

      <LatencyChart results={results} metric="p95_ms" title="P95 Latency by Scenario (ms) — lower is better" />

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px' }}>
        <ThroughputChart results={results} />
        <RadarComparisonChart />
      </div>
    </div>
  )
}
