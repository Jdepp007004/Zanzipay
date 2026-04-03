import React from 'react'
import { useBenchmarkData } from '../hooks/useBenchmarkData'
import { ResultsTable } from '../components/tables/ResultsTable'

export const RawData: React.FC = () => {
  const { results, loading } = useBenchmarkData()
  if (loading) return <div style={{ color: '#94a3b8', padding: '40px' }}>Loading...</div>
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
      <div>
        <h1 style={{ color: '#f8fafc', fontSize: '26px', fontWeight: 700, margin: '0 0 6px' }}>Raw Benchmark Data</h1>
        <p style={{ color: '#64748b', margin: 0, fontSize: '13px' }}>
          {results.length} benchmark results across {new Set(results.map(r => r.scenario)).size} scenarios
        </p>
      </div>
      <ResultsTable results={results} />
    </div>
  )
}
