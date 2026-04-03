import React from 'react'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
} from 'recharts'
import { BenchmarkResult } from '../../types/benchmark'
import { getSystemColor, CHART_THEME } from '../../utils/colors'
import { formatRPS, toHumanScenario } from '../../utils/format'

export const ThroughputChart: React.FC<{ results: BenchmarkResult[] }> = ({ results }) => {
  const scenarios = [...new Set(results.map(r => r.scenario))]
  const systems = [...new Set(results.map(r => r.system))]

  const data = scenarios.map(scenario => {
    const row: Record<string, string | number> = { scenario: toHumanScenario(scenario) }
    systems.forEach(system => {
      const r = results.find(x => x.scenario === scenario && x.system === system)
      row[system] = r ? r.throughput_rps : 0
    })
    return row
  })

  return (
    <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155' }}>
      <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600, fontSize: '15px' }}>
        Throughput by Scenario (RPS) — higher is better
      </h3>
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={data} margin={{ top: 5, right: 20, left: 20, bottom: 60 }}>
          <CartesianGrid strokeDasharray="3 3" stroke={CHART_THEME.gridColor} />
          <XAxis dataKey="scenario" tick={{ fill: CHART_THEME.textColor, fontSize: 11 }} angle={-30} textAnchor="end" interval={0} />
          <YAxis tick={{ fill: CHART_THEME.textColor, fontSize: 11 }} tickFormatter={formatRPS} />
          <Tooltip
            contentStyle={{ background: CHART_THEME.tooltipBg, border: `1px solid ${CHART_THEME.tooltipBorder}`, borderRadius: '8px', color: '#f8fafc', fontSize: '12px' }}
            formatter={(v: number) => [formatRPS(v), '']}
          />
          <Legend wrapperStyle={{ color: '#94a3b8', paddingTop: '16px', fontSize: '12px' }} />
          {systems.map(system => (
            <Bar key={system} dataKey={system} fill={getSystemColor(system)} radius={[3, 3, 0, 0]} maxBarSize={40} />
          ))}
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}
