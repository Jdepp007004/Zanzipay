import React from 'react'
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts'
import { CHART_THEME, SYSTEM_COLORS } from '../../utils/colors'

const DATA = [
  { concurrency: 1,   ZanziPay: 0.8,  SpiceDB: 1.2, OpenFGA: 1.5, 'Ory Keto': 1.8 },
  { concurrency: 10,  ZanziPay: 1.2,  SpiceDB: 1.8, OpenFGA: 2.5, 'Ory Keto': 3.2 },
  { concurrency: 50,  ZanziPay: 2.1,  SpiceDB: 3.2, OpenFGA: 4.1, 'Ory Keto': 5.5 },
  { concurrency: 100, ZanziPay: 3.5,  SpiceDB: 6.5, OpenFGA: 8.2, 'Ory Keto': 12.1 },
  { concurrency: 250, ZanziPay: 5.8,  SpiceDB: 15.2, OpenFGA: 22.5, 'Ory Keto': 35.0 },
  { concurrency: 500, ZanziPay: 9.2,  SpiceDB: 32.5, OpenFGA: 48.0, 'Ory Keto': 80.0 },
]

export const ScalabilityChart: React.FC = () => (
  <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155' }}>
    <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600, fontSize: '15px' }}>
      Scalability: P95 Latency vs Concurrent Workers
    </h3>
    <ResponsiveContainer width="100%" height={300}>
      <LineChart data={DATA} margin={{ top: 5, right: 20, left: 10, bottom: 20 }}>
        <CartesianGrid strokeDasharray="3 3" stroke={CHART_THEME.gridColor} />
        <XAxis dataKey="concurrency" tick={{ fill: CHART_THEME.textColor, fontSize: 11 }} label={{ value: 'Workers', fill: '#64748b', position: 'insideBottom', offset: -10 }} />
        <YAxis tick={{ fill: CHART_THEME.textColor, fontSize: 11 }} tickFormatter={v => `${v}ms`} />
        <Tooltip
          contentStyle={{ background: CHART_THEME.tooltipBg, border: `1px solid ${CHART_THEME.tooltipBorder}`, borderRadius: '8px', color: '#f8fafc', fontSize: '12px' }}
          formatter={(v: number) => [`${v}ms`, '']}
        />
        <Legend wrapperStyle={{ color: '#94a3b8', fontSize: '12px' }} />
        {Object.keys(SYSTEM_COLORS).slice(0, 4).map(system => (
          <Line key={system} type="monotone" dataKey={system} stroke={SYSTEM_COLORS[system]} strokeWidth={2} dot={{ r: 3 }} />
        ))}
      </LineChart>
    </ResponsiveContainer>
  </div>
)
