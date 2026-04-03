#!/usr/bin/env bash
# Part 19: frontend React app
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT/frontend"

cat > package.json << 'ENDOFFILE'
{
  "name": "zanzipay-dashboard",
  "version": "1.0.0",
  "description": "ZanziPay Authorization Benchmark Dashboard",
  "private": true,
  "scripts": {
    "dev": "vite --host",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "lint": "eslint src --ext ts,tsx"
  },
  "dependencies": {
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "recharts": "^2.12.0",
    "react-router-dom": "^6.23.0",
    "@radix-ui/react-tabs": "^1.1.0",
    "@radix-ui/react-tooltip": "^1.1.0",
    "lucide-react": "^0.400.0",
    "clsx": "^2.1.1"
  },
  "devDependencies": {
    "@types/react": "^18.3.0",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.0",
    "typescript": "^5.4.0",
    "vite": "^5.3.0",
    "eslint": "^8.57.0"
  }
}
ENDOFFILE
echo "  [OK] frontend/package.json"

cat > tsconfig.json << 'ENDOFFILE'
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
ENDOFFILE
echo "  [OK] frontend/tsconfig.json"

cat > tsconfig.node.json << 'ENDOFFILE'
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts"]
}
ENDOFFILE
echo "  [OK] frontend/tsconfig.node.json"

cat > vite.config.ts << 'ENDOFFILE'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    host: true,
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
})
ENDOFFILE
echo "  [OK] frontend/vite.config.ts"

cat > index.html << 'ENDOFFILE'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="description" content="ZanziPay Authorization System — Benchmark Dashboard comparing ReBAC, Cedar, and Compliance-aware authorization systems" />
    <title>ZanziPay — Authorization Benchmark Dashboard</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
ENDOFFILE
echo "  [OK] frontend/index.html"

cat > public/favicon.svg << 'ENDOFFILE'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <defs>
    <linearGradient id="g" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#6366f1"/>
      <stop offset="100%" style="stop-color:#8b5cf6"/>
    </linearGradient>
  </defs>
  <rect width="32" height="32" rx="8" fill="url(#g)"/>
  <text x="16" y="22" font-family="Arial" font-size="18" font-weight="bold" fill="white" text-anchor="middle">Z</text>
</svg>
ENDOFFILE
echo "  [OK] frontend/public/favicon.svg"

# ─── frontend/src/types/ ──────────────────────────────────────────────────────
cat > src/types/benchmark.ts << 'ENDOFFILE'
export interface BenchmarkScenario {
  name: string;
  description: string;
  tuples: number;
  depth: number;
}

export interface BenchmarkResult {
  system: string;
  scenario: string;
  p50_ms: number;
  p95_ms: number;
  p99_ms: number;
  throughput_rps: number;
  error_rate: number;
  operations: number;
  concurrency: number;
}

export interface SystemFeatures {
  system: string;
  rebac: boolean;
  abac: boolean;
  caveats: boolean;
  compliance: boolean;
  immutableAudit: boolean;
  reverseIndex: boolean;
  multiEngine: boolean;
  consistency: boolean;
  openSource: boolean;
  fintechReady: boolean;
}

export interface ScenarioSummary {
  scenario: string;
  systems: BenchmarkResult[];
  winner: string;
  speedupVsRunner: number;
}
ENDOFFILE
echo "  [OK] frontend/src/types/benchmark.ts"

# ─── Sample data ──────────────────────────────────────────────────────────────
cat > src/data/sample-results.json << 'ENDOFFILE'
{
  "results": [
    {"system":"ZanziPay","scenario":"simple_check","p50_ms":1.2,"p95_ms":2.1,"p99_ms":3.5,"throughput_rps":52000,"error_rate":0,"operations":1560000,"concurrency":50},
    {"system":"SpiceDB","scenario":"simple_check","p50_ms":1.8,"p95_ms":3.2,"p99_ms":5.1,"throughput_rps":38000,"error_rate":0,"operations":1140000,"concurrency":50},
    {"system":"OpenFGA","scenario":"simple_check","p50_ms":2.5,"p95_ms":4.1,"p99_ms":7.2,"throughput_rps":28000,"error_rate":0,"operations":840000,"concurrency":50},
    {"system":"Ory Keto","scenario":"simple_check","p50_ms":3.1,"p95_ms":5.5,"p99_ms":8.9,"throughput_rps":22000,"error_rate":0,"operations":660000,"concurrency":50},

    {"system":"ZanziPay","scenario":"deep_nested","p50_ms":2.1,"p95_ms":4.2,"p99_ms":7.0,"throughput_rps":22000,"error_rate":0,"operations":660000,"concurrency":50},
    {"system":"SpiceDB","scenario":"deep_nested","p50_ms":6.5,"p95_ms":12.1,"p99_ms":18.5,"throughput_rps":8000,"error_rate":0,"operations":240000,"concurrency":50},
    {"system":"OpenFGA","scenario":"deep_nested","p50_ms":8.2,"p95_ms":15.3,"p99_ms":22.1,"throughput_rps":6000,"error_rate":0,"operations":180000,"concurrency":50},
    {"system":"Ory Keto","scenario":"deep_nested","p50_ms":10.1,"p95_ms":19.2,"p99_ms":28.5,"throughput_rps":4800,"error_rate":0,"operations":144000,"concurrency":50},

    {"system":"ZanziPay","scenario":"lookup_resources","p50_ms":0.8,"p95_ms":1.5,"p99_ms":2.5,"throughput_rps":82000,"error_rate":0,"operations":2460000,"concurrency":50},
    {"system":"SpiceDB","scenario":"lookup_resources","p50_ms":25.0,"p95_ms":48.5,"p99_ms":72.0,"throughput_rps":2200,"error_rate":0,"operations":66000,"concurrency":50},
    {"system":"OpenFGA","scenario":"lookup_resources","p50_ms":38.0,"p95_ms":72.1,"p99_ms":105.0,"throughput_rps":1400,"error_rate":0,"operations":42000,"concurrency":50},
    {"system":"Ory Keto","scenario":"lookup_resources","p50_ms":42.0,"p95_ms":80.0,"p99_ms":120.0,"throughput_rps":1200,"error_rate":0,"operations":36000,"concurrency":50},

    {"system":"ZanziPay","scenario":"mixed_workload","p50_ms":4.5,"p95_ms":8.2,"p99_ms":12.0,"throughput_rps":15000,"error_rate":0,"operations":450000,"concurrency":50},
    {"system":"SpiceDB","scenario":"mixed_workload","p50_ms":8.1,"p95_ms":15.2,"p99_ms":22.0,"throughput_rps":8500,"error_rate":0,"operations":255000,"concurrency":50},
    {"system":"OpenFGA","scenario":"mixed_workload","p50_ms":11.2,"p95_ms":20.1,"p99_ms":30.5,"throughput_rps":6200,"error_rate":0,"operations":186000,"concurrency":50},

    {"system":"ZanziPay","scenario":"compliance_check","p50_ms":5.2,"p95_ms":9.8,"p99_ms":14.5,"throughput_rps":12000,"error_rate":0,"operations":360000,"concurrency":50}
  ],
  "features": [
    {"system":"ZanziPay","rebac":true,"abac":true,"caveats":true,"compliance":true,"immutableAudit":true,"reverseIndex":true,"multiEngine":true,"consistency":true,"openSource":true,"fintechReady":true},
    {"system":"SpiceDB","rebac":true,"abac":false,"caveats":true,"compliance":false,"immutableAudit":false,"reverseIndex":false,"multiEngine":false,"consistency":true,"openSource":true,"fintechReady":false},
    {"system":"OpenFGA","rebac":true,"abac":false,"caveats":true,"compliance":false,"immutableAudit":false,"reverseIndex":false,"multiEngine":false,"consistency":true,"openSource":true,"fintechReady":false},
    {"system":"Ory Keto","rebac":true,"abac":false,"caveats":false,"compliance":false,"immutableAudit":false,"reverseIndex":false,"multiEngine":false,"consistency":false,"openSource":true,"fintechReady":false},
    {"system":"Cedar (standalone)","rebac":false,"abac":true,"caveats":true,"compliance":false,"immutableAudit":false,"reverseIndex":false,"multiEngine":false,"consistency":false,"openSource":true,"fintechReady":false}
  ]
}
ENDOFFILE
echo "  [OK] frontend/src/data/sample-results.json"

echo "=== frontend package.json + data done ==="
ENDOFFILE
echo "Part 19 script written"
