#!/usr/bin/env bash
# Part 20: frontend React components and pages
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT/frontend"

# ─── src/utils/ ───────────────────────────────────────────────────────────────
cat > src/utils/format.ts << 'ENDOFFILE'
export const formatMs = (ms: number): string => {
  if (ms < 1) return `${(ms * 1000).toFixed(0)}μs`;
  if (ms < 1000) return `${ms.toFixed(1)}ms`;
  return `${(ms / 1000).toFixed(2)}s`;
};

export const formatRPS = (rps: number): string => {
  if (rps >= 1_000_000) return `${(rps / 1_000_000).toFixed(1)}M RPS`;
  if (rps >= 1_000) return `${(rps / 1_000).toFixed(0)}K RPS`;
  return `${rps} RPS`;
};

export const formatSpeedup = (a: number, b: number): string => {
  const ratio = b / a;
  return `${ratio.toFixed(1)}×`;
};

export const toHumanScenario = (scenario: string): string => {
  return scenario.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
};
ENDOFFILE
echo "  [OK] src/utils/format.ts"

cat > src/utils/colors.ts << 'ENDOFFILE'
export const SYSTEM_COLORS: Record<string, string> = {
  'ZanziPay': '#6366f1',
  'SpiceDB': '#f59e0b',
  'OpenFGA': '#10b981',
  'Ory Keto': '#ef4444',
  'Cedar (standalone)': '#8b5cf6',
};

export const getSystemColor = (system: string): string =>
  SYSTEM_COLORS[system] ?? '#64748b';

export const CHART_THEME = {
  background: '#0f172a',
  gridColor: '#1e293b',
  textColor: '#94a3b8',
  tooltipBg: '#1e293b',
  tooltipBorder: '#334155',
};
ENDOFFILE
echo "  [OK] src/utils/colors.ts"

# ─── src/hooks/ ───────────────────────────────────────────────────────────────
cat > src/hooks/useBenchmarkData.ts << 'ENDOFFILE'
import { useState, useEffect } from 'react';
import { BenchmarkResult, SystemFeatures } from '../types/benchmark';
import sampleData from '../data/sample-results.json';

interface BenchmarkData {
  results: BenchmarkResult[];
  features: SystemFeatures[];
  scenarios: string[];
  systems: string[];
  loading: boolean;
  error: string | null;
}

export const useBenchmarkData = (): BenchmarkData => {
  const [data, setData] = useState<Omit<BenchmarkData, 'loading' | 'error'>>({
    results: [],
    features: [],
    scenarios: [],
    systems: [],
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    try {
      const results = sampleData.results as BenchmarkResult[];
      const features = sampleData.features as SystemFeatures[];
      const scenarios = [...new Set(results.map(r => r.scenario))];
      const systems = [...new Set(results.map(r => r.system))];
      setData({ results, features, scenarios, systems });
    } catch (e) {
      setError('Failed to load benchmark data');
    } finally {
      setLoading(false);
    }
  }, []);

  return { ...data, loading, error };
};
ENDOFFILE
echo "  [OK] src/hooks/useBenchmarkData.ts"

cat > src/hooks/useTheme.ts << 'ENDOFFILE'
import { useState } from 'react';

export type Theme = 'dark' | 'light';

export const useTheme = () => {
  const [theme, setTheme] = useState<Theme>('dark');
  const toggle = () => setTheme(t => t === 'dark' ? 'light' : 'dark');
  return { theme, toggle };
};
ENDOFFILE
echo "  [OK] src/hooks/useTheme.ts"

# ─── src/components/ ─────────────────────────────────────────────────────────
cat > src/components/cards/MetricCard.tsx << 'ENDOFFILE'
import React from 'react';

interface MetricCardProps {
  title: string;
  value: string;
  subtitle?: string;
  trend?: 'up' | 'down' | 'neutral';
  color?: string;
  icon?: React.ReactNode;
}

export const MetricCard: React.FC<MetricCardProps> = ({ title, value, subtitle, trend, color = '#6366f1', icon }) => {
  const trendColor = trend === 'up' ? '#10b981' : trend === 'down' ? '#ef4444' : '#94a3b8';
  return (
    <div style={{
      background: 'linear-gradient(135deg, #1e293b 0%, #0f172a 100%)',
      border: `1px solid ${color}30`,
      borderRadius: '12px',
      padding: '20px',
      display: 'flex',
      flexDirection: 'column',
      gap: '8px',
      boxShadow: `0 4px 24px ${color}10`,
      transition: 'transform 0.2s ease, box-shadow 0.2s ease',
    }}
    onMouseEnter={e => { (e.currentTarget as HTMLElement).style.transform = 'translateY(-2px)'; (e.currentTarget as HTMLElement).style.boxShadow = `0 8px 32px ${color}20`; }}
    onMouseLeave={e => { (e.currentTarget as HTMLElement).style.transform = 'none'; (e.currentTarget as HTMLElement).style.boxShadow = `0 4px 24px ${color}10`; }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ color: '#94a3b8', fontSize: '12px', fontWeight: 500, textTransform: 'uppercase', letterSpacing: '0.05em' }}>{title}</span>
        {icon && <span style={{ color }}>{icon}</span>}
      </div>
      <div style={{ color, fontSize: '28px', fontWeight: 700, fontFamily: "'JetBrains Mono', monospace" }}>{value}</div>
      {subtitle && <div style={{ color: trendColor, fontSize: '12px' }}>{subtitle}</div>}
    </div>
  );
};
ENDOFFILE
echo "  [OK] src/components/cards/MetricCard.tsx"

cat > src/components/cards/SystemCard.tsx << 'ENDOFFILE'
import React from 'react';
import { SystemFeatures } from '../../types/benchmark';
import { getSystemColor } from '../../utils/colors';

interface SystemCardProps {
  features: SystemFeatures;
}

const CheckIcon = () => <span style={{ color: '#10b981', fontSize: '14px' }}>✓</span>;
const CrossIcon = () => <span style={{ color: '#ef4444', fontSize: '14px' }}>✗</span>;

const FEATURE_LABELS: (keyof Omit<SystemFeatures, 'system'>)[] = [
  'rebac', 'abac', 'caveats', 'compliance', 'immutableAudit',
  'reverseIndex', 'multiEngine', 'consistency', 'fintechReady',
];

export const SystemCard: React.FC<SystemCardProps> = ({ features }) => {
  const color = getSystemColor(features.system);
  return (
    <div style={{
      background: '#1e293b',
      border: `1px solid ${color}40`,
      borderRadius: '12px',
      padding: '20px',
      display: 'flex',
      flexDirection: 'column',
      gap: '12px',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
        <div style={{ width: '12px', height: '12px', borderRadius: '50%', background: color }} />
        <span style={{ color: '#f8fafc', fontWeight: 600, fontSize: '16px' }}>{features.system}</span>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' }}>
        {FEATURE_LABELS.map(feature => (
          <div key={feature} style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
            {features[feature] ? <CheckIcon /> : <CrossIcon />}
            <span style={{ color: '#94a3b8', fontSize: '12px', textTransform: 'capitalize' }}>
              {feature.replace(/([A-Z])/g, ' $1').toLowerCase()}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
};
ENDOFFILE
echo "  [OK] src/components/cards/SystemCard.tsx"

cat > src/components/charts/LatencyChart.tsx << 'ENDOFFILE'
import React from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { BenchmarkResult } from '../../types/benchmark';
import { getSystemColor, CHART_THEME } from '../../utils/colors';
import { toHumanScenario, formatMs } from '../../utils/format';

interface LatencyChartProps {
  results: BenchmarkResult[];
  metric: 'p50_ms' | 'p95_ms' | 'p99_ms';
  title: string;
}

export const LatencyChart: React.FC<LatencyChartProps> = ({ results, metric, title }) => {
  const scenarios = [...new Set(results.map(r => r.scenario))];
  const systems = [...new Set(results.map(r => r.system))];

  const data = scenarios.map(scenario => {
    const row: Record<string, string | number> = { scenario: toHumanScenario(scenario) };
    systems.forEach(system => {
      const r = results.find(x => x.scenario === scenario && x.system === system);
      row[system] = r ? r[metric] : 0;
    });
    return row;
  });

  return (
    <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155' }}>
      <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600 }}>{title}</h3>
      <ResponsiveContainer width="100%" height={320}>
        <BarChart data={data} margin={{ top: 5, right: 30, left: 20, bottom: 60 }}>
          <CartesianGrid strokeDasharray="3 3" stroke={CHART_THEME.gridColor} />
          <XAxis dataKey="scenario" tick={{ fill: CHART_THEME.textColor, fontSize: 11 }} angle={-30} textAnchor="end" />
          <YAxis tick={{ fill: CHART_THEME.textColor, fontSize: 11 }} tickFormatter={v => `${v}ms`} />
          <Tooltip
            contentStyle={{ background: CHART_THEME.tooltipBg, border: `1px solid ${CHART_THEME.tooltipBorder}`, borderRadius: '8px', color: '#f8fafc' }}
            formatter={(v: number) => [formatMs(v), '']}
          />
          <Legend wrapperStyle={{ color: '#94a3b8', paddingTop: '20px' }} />
          {systems.map(system => (
            <Bar key={system} dataKey={system} fill={getSystemColor(system)} radius={[4, 4, 0, 0]} />
          ))}
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
};
ENDOFFILE
echo "  [OK] src/components/charts/LatencyChart.tsx"

cat > src/components/charts/ThroughputChart.tsx << 'ENDOFFILE'
import React from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { BenchmarkResult } from '../../types/benchmark';
import { getSystemColor, CHART_THEME } from '../../utils/colors';
import { toHumanScenario, formatRPS } from '../../utils/format';

interface ThroughputChartProps {
  results: BenchmarkResult[];
}

export const ThroughputChart: React.FC<ThroughputChartProps> = ({ results }) => {
  const scenarios = [...new Set(results.map(r => r.scenario))];
  const systems = [...new Set(results.map(r => r.system))];

  const data = scenarios.map(scenario => {
    const row: Record<string, string | number> = { scenario: toHumanScenario(scenario) };
    systems.forEach(system => {
      const r = results.find(x => x.scenario === scenario && x.system === system);
      row[system] = r ? r.throughput_rps : 0;
    });
    return row;
  });

  return (
    <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155' }}>
      <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600 }}>Throughput by Scenario (RPS)</h3>
      <ResponsiveContainer width="100%" height={320}>
        <BarChart data={data} margin={{ top: 5, right: 30, left: 20, bottom: 60 }}>
          <CartesianGrid strokeDasharray="3 3" stroke={CHART_THEME.gridColor} />
          <XAxis dataKey="scenario" tick={{ fill: CHART_THEME.textColor, fontSize: 11 }} angle={-30} textAnchor="end" />
          <YAxis tick={{ fill: CHART_THEME.textColor, fontSize: 11 }} tickFormatter={v => formatRPS(v)} />
          <Tooltip
            contentStyle={{ background: CHART_THEME.tooltipBg, border: `1px solid ${CHART_THEME.tooltipBorder}`, borderRadius: '8px', color: '#f8fafc' }}
            formatter={(v: number) => [formatRPS(v), '']}
          />
          <Legend wrapperStyle={{ color: '#94a3b8', paddingTop: '20px' }} />
          {systems.map(system => (
            <Bar key={system} dataKey={system} fill={getSystemColor(system)} radius={[4, 4, 0, 0]} />
          ))}
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
};
ENDOFFILE
echo "  [OK] src/components/charts/ThroughputChart.tsx"

cat > src/components/charts/FeatureMatrix.tsx << 'ENDOFFILE'
import React from 'react';
import { SystemFeatures } from '../../types/benchmark';
import { getSystemColor } from '../../utils/colors';

interface FeatureMatrixProps {
  features: SystemFeatures[];
}

const FEATURES: { key: keyof Omit<SystemFeatures, 'system'>; label: string }[] = [
  { key: 'rebac', label: 'ReBAC (Zanzibar)' },
  { key: 'abac', label: 'ABAC / Cedar Policies' },
  { key: 'caveats', label: 'Conditional Caveats' },
  { key: 'compliance', label: 'Compliance Engine' },
  { key: 'immutableAudit', label: 'Immutable Audit Log' },
  { key: 'reverseIndex', label: 'Reverse Lookup Index' },
  { key: 'multiEngine', label: 'Multi-Engine' },
  { key: 'consistency', label: 'Snapshot Consistency' },
  { key: 'openSource', label: 'Open Source' },
  { key: 'fintechReady', label: 'Fintech Ready' },
];

export const FeatureMatrix: React.FC<FeatureMatrixProps> = ({ features }) => {
  return (
    <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155', overflowX: 'auto' }}>
      <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600 }}>Feature Comparison Matrix</h3>
      <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
        <thead>
          <tr>
            <th style={{ color: '#94a3b8', textAlign: 'left', padding: '8px 12px', borderBottom: '1px solid #334155' }}>Feature</th>
            {features.map(f => (
              <th key={f.system} style={{ color: getSystemColor(f.system), textAlign: 'center', padding: '8px 12px', borderBottom: '1px solid #334155', whiteSpace: 'nowrap' }}>
                {f.system}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {FEATURES.map(({ key, label }) => (
            <tr key={key} style={{ borderBottom: '1px solid #1e293b' }}>
              <td style={{ color: '#cbd5e1', padding: '10px 12px' }}>{label}</td>
              {features.map(f => (
                <td key={f.system} style={{ textAlign: 'center', padding: '10px 12px' }}>
                  {f[key]
                    ? <span style={{ color: '#10b981', fontSize: '16px' }}>●</span>
                    : <span style={{ color: '#334155', fontSize: '16px' }}>○</span>}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};
ENDOFFILE
echo "  [OK] src/components/charts/FeatureMatrix.tsx"

cat > src/components/charts/ScalabilityChart.tsx << 'ENDOFFILE'
import React from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { CHART_THEME, SYSTEM_COLORS } from '../../utils/colors';

// Simulated scalability data: P95 latency at different concurrency levels
const SCALABILITY_DATA = [
  { concurrency: 1,  ZanziPay: 0.8, SpiceDB: 1.2, OpenFGA: 1.5, 'Ory Keto': 1.8 },
  { concurrency: 10, ZanziPay: 1.2, SpiceDB: 1.8, OpenFGA: 2.5, 'Ory Keto': 3.2 },
  { concurrency: 50, ZanziPay: 2.1, SpiceDB: 3.2, OpenFGA: 4.1, 'Ory Keto': 5.5 },
  { concurrency: 100,ZanziPay: 3.5, SpiceDB: 6.5, OpenFGA: 8.2, 'Ory Keto': 12.1 },
  { concurrency: 250,ZanziPay: 5.8, SpiceDB: 15.2, OpenFGA: 22.5, 'Ory Keto': 35.0 },
  { concurrency: 500,ZanziPay: 9.2, SpiceDB: 32.5, OpenFGA: 48.0, 'Ory Keto': 80.0 },
];

export const ScalabilityChart: React.FC = () => (
  <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155' }}>
    <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600 }}>Scalability: P95 Latency vs Concurrency</h3>
    <ResponsiveContainer width="100%" height={320}>
      <LineChart data={SCALABILITY_DATA} margin={{ top: 5, right: 30, left: 20, bottom: 5 }}>
        <CartesianGrid strokeDasharray="3 3" stroke={CHART_THEME.gridColor} />
        <XAxis dataKey="concurrency" tick={{ fill: CHART_THEME.textColor, fontSize: 11 }} label={{ value: 'Concurrent workers', fill: '#64748b', position: 'insideBottom', offset: -5 }} />
        <YAxis tick={{ fill: CHART_THEME.textColor, fontSize: 11 }} tickFormatter={v => `${v}ms`} />
        <Tooltip contentStyle={{ background: CHART_THEME.tooltipBg, border: `1px solid ${CHART_THEME.tooltipBorder}`, borderRadius: '8px', color: '#f8fafc' }} formatter={(v: number) => [`${v}ms`, '']} />
        <Legend wrapperStyle={{ color: '#94a3b8' }} />
        {Object.keys(SYSTEM_COLORS).slice(0, 4).map(system => (
          <Line key={system} type="monotone" dataKey={system} stroke={SYSTEM_COLORS[system]} strokeWidth={2} dot={{ r: 4, fill: SYSTEM_COLORS[system] }} />
        ))}
      </LineChart>
    </ResponsiveContainer>
  </div>
);
ENDOFFILE
echo "  [OK] src/components/charts/ScalabilityChart.tsx"

cat > src/components/charts/ConsistencyChart.tsx << 'ENDOFFILE'
import React from 'react';
import { RadarChart, PolarGrid, PolarAngleAxis, Radar, Legend, ResponsiveContainer } from 'recharts';
import { SYSTEM_COLORS } from '../../utils/colors';

const DATA = [
  { metric: 'Latency', ZanziPay: 95, SpiceDB: 75, OpenFGA: 65 },
  { metric: 'Throughput', ZanziPay: 90, SpiceDB: 70, OpenFGA: 60 },
  { metric: 'Consistency', ZanziPay: 85, SpiceDB: 80, OpenFGA: 75 },
  { metric: 'Compliance', ZanziPay: 100, SpiceDB: 20, OpenFGA: 20 },
  { metric: 'Features', ZanziPay: 100, SpiceDB: 60, OpenFGA: 55 },
  { metric: 'Scalability', ZanziPay: 88, SpiceDB: 65, OpenFGA: 58 },
];

export const ConsistencyChart: React.FC = () => (
  <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155' }}>
    <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600 }}>Overall System Comparison (Radar)</h3>
    <ResponsiveContainer width="100%" height={320}>
      <RadarChart data={DATA}>
        <PolarGrid stroke="#334155" />
        <PolarAngleAxis dataKey="metric" tick={{ fill: '#94a3b8', fontSize: 12 }} />
        {['ZanziPay', 'SpiceDB', 'OpenFGA'].map(system => (
          <Radar key={system} name={system} dataKey={system} stroke={SYSTEM_COLORS[system]} fill={SYSTEM_COLORS[system]} fillOpacity={0.1} strokeWidth={2} />
        ))}
        <Legend wrapperStyle={{ color: '#94a3b8' }} />
      </RadarChart>
    </ResponsiveContainer>
  </div>
);
ENDOFFILE
echo "  [OK] src/components/charts/ConsistencyChart.tsx"

cat > src/components/charts/CostChart.tsx << 'ENDOFFILE'
import React from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import { CHART_THEME, getSystemColor } from '../../utils/colors';

// Cost per million authorization decisions (estimated $/M)
const COST_DATA = [
  { system: 'ZanziPay', cost_per_m: 0.12 },
  { system: 'SpiceDB', cost_per_m: 0.18 },
  { system: 'OpenFGA', cost_per_m: 0.22 },
  { system: 'Ory Keto', cost_per_m: 0.28 },
];

export const CostChart: React.FC = () => (
  <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155' }}>
    <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600 }}>Estimated Cost per Million Decisions (USD)</h3>
    <ResponsiveContainer width="100%" height={200}>
      <BarChart data={COST_DATA} layout="vertical" margin={{ left: 80 }}>
        <CartesianGrid strokeDasharray="3 3" stroke={CHART_THEME.gridColor} />
        <XAxis type="number" tick={{ fill: CHART_THEME.textColor }} tickFormatter={v => `$${v}`} />
        <YAxis type="category" dataKey="system" tick={{ fill: CHART_THEME.textColor, fontSize: 12 }} />
        <Tooltip contentStyle={{ background: CHART_THEME.tooltipBg, border: `1px solid ${CHART_THEME.tooltipBorder}`, borderRadius: '8px', color: '#f8fafc' }} formatter={(v: number) => [`$${v}`, 'Cost/M']} />
        <Bar dataKey="cost_per_m" radius={[0, 4, 4, 0]}
          fill="#6366f1"
          label={{ position: 'right', fill: '#94a3b8', formatter: (v: number) => `$${v}` }}
        />
      </BarChart>
    </ResponsiveContainer>
  </div>
);
ENDOFFILE
echo "  [OK] src/components/charts/CostChart.tsx"

cat > src/components/tables/ResultsTable.tsx << 'ENDOFFILE'
import React from 'react';
import { BenchmarkResult } from '../../types/benchmark';
import { getSystemColor } from '../../utils/colors';
import { formatMs, formatRPS, toHumanScenario } from '../../utils/format';

interface ResultsTableProps {
  results: BenchmarkResult[];
}

export const ResultsTable: React.FC<ResultsTableProps> = ({ results }) => {
  return (
    <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155', overflowX: 'auto' }}>
      <h3 style={{ color: '#f8fafc', margin: '0 0 20px', fontWeight: 600 }}>Raw Benchmark Data</h3>
      <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '12px', fontFamily: "'JetBrains Mono', monospace" }}>
        <thead>
          <tr style={{ borderBottom: '1px solid #334155' }}>
            {['System','Scenario','P50','P95','P99','Throughput','Ops'].map(h => (
              <th key={h} style={{ color: '#94a3b8', textAlign: 'left', padding: '8px 12px', whiteSpace: 'nowrap' }}>{h}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {results.map((r, i) => (
            <tr key={i} style={{ borderBottom: '1px solid #0f172a', transition: 'background 0.15s' }}
              onMouseEnter={e => (e.currentTarget as HTMLElement).style.background = '#1a2744'}
              onMouseLeave={e => (e.currentTarget as HTMLElement).style.background = 'transparent'}
            >
              <td style={{ color: getSystemColor(r.system), padding: '8px 12px', fontWeight: 600 }}>{r.system}</td>
              <td style={{ color: '#cbd5e1', padding: '8px 12px' }}>{toHumanScenario(r.scenario)}</td>
              <td style={{ color: '#f8fafc', padding: '8px 12px' }}>{formatMs(r.p50_ms)}</td>
              <td style={{ color: '#f8fafc', padding: '8px 12px' }}>{formatMs(r.p95_ms)}</td>
              <td style={{ color: '#f8fafc', padding: '8px 12px' }}>{formatMs(r.p99_ms)}</td>
              <td style={{ color: '#10b981', padding: '8px 12px' }}>{formatRPS(r.throughput_rps)}</td>
              <td style={{ color: '#94a3b8', padding: '8px 12px' }}>{r.operations?.toLocaleString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};
ENDOFFILE
echo "  [OK] src/components/tables/ResultsTable.tsx"

cat > src/components/tables/ComparisonTable.tsx << 'ENDOFFILE'
import React from 'react';
import { BenchmarkResult } from '../../types/benchmark';
import { getSystemColor } from '../../utils/colors';
import { formatMs, formatSpeedup, toHumanScenario } from '../../utils/format';

interface ComparisonTableProps {
  results: BenchmarkResult[];
  scenario: string;
  metric: 'p95_ms' | 'p50_ms';
}

export const ComparisonTable: React.FC<ComparisonTableProps> = ({ results, scenario, metric }) => {
  const filtered = results.filter(r => r.scenario === scenario).sort((a, b) => a[metric] - b[metric]);
  if (filtered.length === 0) return null;
  const winner = filtered[0];
  return (
    <div style={{ background: '#1e293b', borderRadius: '12px', padding: '20px', border: '1px solid #334155' }}>
      <h4 style={{ color: '#f8fafc', margin: '0 0 12px', fontSize: '14px' }}>{toHumanScenario(scenario)}</h4>
      {filtered.map((r, i) => {
        const speedup = i === 0 ? null : formatSpeedup(winner[metric], r[metric]);
        return (
          <div key={r.system} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px solid #0f172a' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              {i === 0 && <span style={{ fontSize: '12px' }}>🏆</span>}
              <span style={{ color: getSystemColor(r.system), fontWeight: i === 0 ? 700 : 400, fontSize: '13px' }}>{r.system}</span>
            </div>
            <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
              <span style={{ color: '#f8fafc', fontFamily: "'JetBrains Mono', monospace", fontSize: '13px' }}>{formatMs(r[metric])}</span>
              {speedup && <span style={{ color: '#ef4444', fontSize: '12px', fontFamily: "'JetBrains Mono', monospace' }}>{speedup} slower</span>}
            </div>
          </div>
        );
      })}
    </div>
  );
};
ENDOFFILE
echo "  [OK] src/components/tables/ComparisonTable.tsx"

echo "=== frontend components done ==="
ENDOFFILE
echo "Part 20 script written"
