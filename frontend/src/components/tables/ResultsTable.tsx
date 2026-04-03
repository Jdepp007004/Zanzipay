import React from 'react'
import { BenchmarkResult } from '../../types/benchmark'
import { getSystemColor } from '../../utils/colors'
import { formatMs, formatRPS, toHumanScenario } from '../../utils/format'

export const ResultsTable: React.FC<{ results: BenchmarkResult[] }> = ({ results }) => (
  <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155', overflowX: 'auto' }}>
    <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600, fontSize: '15px' }}>Raw Benchmark Results</h3>
    <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '12px', fontFamily: "'JetBrains Mono',monospace", minWidth: '700px' }}>
      <thead>
        <tr style={{ borderBottom: '1px solid #334155' }}>
          {['System', 'Scenario', 'P50', 'P95', 'P99', 'Throughput', 'Operations'].map(h => (
            <th key={h} style={{ color: '#94a3b8', textAlign: 'left', padding: '8px 12px', fontWeight: 500, whiteSpace: 'nowrap' }}>{h}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {results.map((r, i) => (
          <tr key={i}
            style={{ borderBottom: '1px solid #0f172a', transition: 'background 0.15s' }}
            onMouseEnter={e => (e.currentTarget as HTMLElement).style.background = '#1a2744'}
            onMouseLeave={e => (e.currentTarget as HTMLElement).style.background = 'transparent'}
          >
            <td style={{ color: getSystemColor(r.system), padding: '8px 12px', fontWeight: 600 }}>{r.system}</td>
            <td style={{ color: '#cbd5e1', padding: '8px 12px' }}>{toHumanScenario(r.scenario)}</td>
            <td style={{ color: '#f8fafc', padding: '8px 12px' }}>{formatMs(r.p50_ms)}</td>
            <td style={{ color: '#f8fafc', padding: '8px 12px' }}>{formatMs(r.p95_ms)}</td>
            <td style={{ color: '#f8fafc', padding: '8px 12px' }}>{formatMs(r.p99_ms)}</td>
            <td style={{ color: '#10b981', padding: '8px 12px' }}>{formatRPS(r.throughput_rps)}</td>
            <td style={{ color: '#64748b', padding: '8px 12px' }}>{r.operations?.toLocaleString()}</td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
)
