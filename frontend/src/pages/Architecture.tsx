import React from 'react'

const LAYERS = [
  {
    num: 1, name: 'ReBAC Engine', color: '#6366f1', perf: '~2ms P95',
    desc: 'Zanzibar relationship graph with union/intersection/exclusion, caveats via CEL, zookie-based snapshot consistency. Recursive check algorithm with userset expansion.',
  },
  {
    num: 2, name: 'Policy Engine (Cedar)', color: '#f59e0b', perf: '~1ms P95',
    desc: 'Cedar-compatible ABAC policies: permit/forbid rules, temporal conditions, KYC tier enforcement, transaction limit checks. Deny-overrides evaluation model.',
  },
  {
    num: 3, name: 'Compliance Engine', color: '#ef4444', perf: '~3ms P95',
    desc: 'OFAC/EU/UN sanctions screening (Jaro-Winkler fuzzy matching), account freezes, regulatory holds, AML blocks. Compliance DENY is an absolute veto — cannot be overridden.',
  },
  {
    num: 4, name: 'Decision Orchestrator', color: '#10b981', perf: '< 10ms total',
    desc: 'Parallel fan-out to all 3 engines with strict AND merge. Any deny from any engine = global DENY. Emits HMAC-signed decision tokens and async audit records.',
  },
  {
    num: 5, name: 'Materialized Index', color: '#8b5cf6', perf: '~1ms P95',
    desc: 'Roaring bitmap-based reverse lookup: "which accounts can user X access?" Updated in real-time via the Watch stream. Powers sub-millisecond LookupResources queries.',
  },
  {
    num: 6, name: 'Immutable Audit Stream', color: '#64748b', perf: '< 1ms overhead',
    desc: 'Append-only PostgreSQL log protected by DDL triggers that block UPDATE/DELETE. Every decision is recorded with full context. SOX/PCI-DSS reports, 7-year retention.',
  },
]

export const Architecture: React.FC = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
    <div>
      <h1 style={{ color: '#f8fafc', fontSize: '26px', fontWeight: 700, margin: '0 0 6px' }}>ZanziPay Architecture</h1>
      <p style={{ color: '#64748b', margin: 0, fontSize: '13px' }}>
        Six-layer hybrid authorization — ReBAC + ABAC + Compliance, all decisions in under 10ms
      </p>
    </div>

    <div style={{ background: '#1e293b', borderRadius: '12px', padding: '24px', border: '1px solid #334155', fontFamily: "'JetBrains Mono',monospace", fontSize: '12px', color: '#94a3b8', lineHeight: 1.7 }}>
      <div style={{ color: '#6366f1' }}>Client Request</div>
      <div>{'  '}<span style={{ color: '#334155' }}>▼</span></div>
      <div><span style={{ color: '#f8fafc' }}>gRPC / REST Server</span> <span style={{ color: '#475569' }}>(port 50053 / 8090)</span></div>
      <div>{'  '}<span style={{ color: '#334155' }}>▼</span></div>
      <div><span style={{ color: '#10b981' }}>Orchestrator</span> <span style={{ color: '#475569' }}>(fan-out, strict AND merge)</span></div>
      <div style={{ display: 'flex', gap: '40px', margin: '8px 0' }}>
        <div>{'  '}├─ <span style={{ color: '#6366f1' }}>ReBAC Engine</span></div>
        <div>├─ <span style={{ color: '#f59e0b' }}>Policy (Cedar)</span></div>
        <div>└─ <span style={{ color: '#ef4444' }}>Compliance</span></div>
      </div>
      <div>{'  '}<span style={{ color: '#334155' }}>▼</span></div>
      <div style={{ display: 'flex', gap: '40px' }}>
        <div><span style={{ color: '#8b5cf6' }}>Bitmap Index</span></div>
        <div><span style={{ color: '#64748b' }}>Audit Log</span></div>
        <div><span style={{ color: '#0ea5e9' }}>Decision Token</span></div>
      </div>
    </div>

    {LAYERS.map(layer => (
      <div key={layer.num} style={{
        background: '#1e293b', borderRadius: '12px', padding: '20px',
        border: `1px solid ${layer.color}25`,
        display: 'flex', alignItems: 'flex-start', gap: '16px',
      }}>
        <div style={{
          width: '40px', height: '40px', borderRadius: '8px',
          background: `${layer.color}15`, display: 'flex', alignItems: 'center',
          justifyContent: 'center', flexShrink: 0,
        }}>
          <span style={{ color: layer.color, fontWeight: 700 }}>{layer.num}</span>
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
            <h3 style={{ color: layer.color, margin: 0, fontSize: '15px', fontWeight: 600 }}>{layer.name}</h3>
            <span style={{
              color: '#10b981', fontSize: '11px',
              fontFamily: "'JetBrains Mono',monospace",
              background: '#10b98115', padding: '2px 8px', borderRadius: '4px',
            }}>{layer.perf}</span>
          </div>
          <p style={{ color: '#94a3b8', margin: 0, fontSize: '13px', lineHeight: '1.6' }}>{layer.desc}</p>
        </div>
      </div>
    ))}
  </div>
)
