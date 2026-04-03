import React from 'react'
import { RadarChart, PolarGrid, PolarAngleAxis, Radar, Legend, ResponsiveContainer } from 'recharts'
import { SYSTEM_COLORS } from '../../utils/colors'

const DATA = [
  { metric: 'Latency', ZanziPay: 95, SpiceDB: 72, OpenFGA: 62 },
  { metric: 'Throughput', ZanziPay: 90, SpiceDB: 68, OpenFGA: 58 },
  { metric: 'Consistency', ZanziPay: 85, SpiceDB: 80, OpenFGA: 75 },
  { metric: 'Compliance', ZanziPay: 100, SpiceDB: 20, OpenFGA: 20 },
  { metric: 'Features', ZanziPay: 100, SpiceDB: 58, OpenFGA: 55 },
  { metric: 'Scalability', ZanziPay: 88, SpiceDB: 62, OpenFGA: 55 },
]

export const RadarComparisonChart: React.FC = () => (
  <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155' }}>
    <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600, fontSize: '15px' }}>
      Overall System Comparison
    </h3>
    <ResponsiveContainer width="100%" height={300}>
      <RadarChart data={DATA}>
        <PolarGrid stroke="#334155" />
        <PolarAngleAxis dataKey="metric" tick={{ fill: '#94a3b8', fontSize: 12 }} />
        {(['ZanziPay', 'SpiceDB', 'OpenFGA'] as const).map(system => (
          <Radar
            key={system} name={system} dataKey={system}
            stroke={SYSTEM_COLORS[system]} fill={SYSTEM_COLORS[system]}
            fillOpacity={0.1} strokeWidth={2}
          />
        ))}
        <Legend wrapperStyle={{ color: '#94a3b8', fontSize: '12px' }} />
      </RadarChart>
    </ResponsiveContainer>
  </div>
)
